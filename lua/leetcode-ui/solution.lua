--- *leetcode-ui-solution* Code editor buffer
---
--- Owns the editable solution buffer: starter snippets, draft persistence,
--- formatting, and language switching.
---@tag LeetCodeSolution
---@toc_entry Solution buffer

local LeetCodeSolution = {}

local auth = require('leetcode-ui.auth')
local format = require('leetcode-ui.format')
local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local net = require('leetcode-ui.net')
local storage = require('leetcode-ui.storage')

-- Helper data =======================================================================================================

-- LeetCode's formatter endpoints are lsp-<name>.<domain>/format. The names
-- below are the ones LeetCode currently exposes: c, cpp, go, java, py3, swift.
LeetCodeSolution.remote_formatters = {
  c = 'c',
  cpp = 'cpp',
  golang = 'go',
  java = 'java',
  python3 = 'py3',
  swift = 'swift',
}

LeetCodeSolution.padding_namespace = vim.api.nvim_create_namespace('leetcode-ui-code-padding')

-- Helper functionality =============================================================================================

local indent_options = { 'shiftwidth', 'tabstop', 'softtabstop', 'expandtab' }

local function inherit_indent_options(bufnr)
  for _, name in ipairs(indent_options) do
    vim.api.nvim_set_option_value(name, vim.go[name], { buf = bufnr })
  end
end

local function snippets(view)
  local value = view.detail.snippets
  return type(value) == 'table' and value or {}
end

--- Whether the view is open and has a valid, loaded code buffer.
---
---@param view table|nil
---@return boolean
LeetCodeSolution.has_code_buffer = function(view)
  return view ~= nil
    and view.closed ~= true
    and view.code_bufnr ~= nil
    and vim.api.nvim_buf_is_valid(view.code_bufnr)
    and vim.api.nvim_buf_is_loaded(view.code_bufnr)
end

local has_code_buffer = LeetCodeSolution.has_code_buffer

local function response_content_type(response)
  for key, value in pairs(response.headers or {}) do
    if type(key) == 'string' and key:lower() == 'content-type' and type(value) == 'string' then return value end
  end
  return ''
end

local function remote_formatted(lang_slug, code, bufnr)
  local canonical = config.canonical_lang(lang_slug)
  local name = LeetCodeSolution.remote_formatters[canonical]
  if name == nil then return nil, 'unsupported' end

  local shiftwidth = 0
  local tabstop = 0
  local softtabstop = 0
  local expandtab = true
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    shiftwidth = vim.api.nvim_buf_call(bufnr, vim.fn.shiftwidth)
    tabstop = vim.api.nvim_get_option_value('tabstop', { buf = bufnr })
    softtabstop = vim.api.nvim_get_option_value('softtabstop', { buf = bufnr })
    expandtab = vim.api.nvim_get_option_value('expandtab', { buf = bufnr })
  end
  if shiftwidth <= 0 then shiftwidth = 4 end
  if tabstop <= 0 then tabstop = shiftwidth end
  local tab_size = shiftwidth
  if softtabstop > 0 then
    expandtab = true
    tab_size = softtabstop
  elseif not expandtab then
    tab_size = tabstop
  end
  local domain = config.config.url:lower():gsub('^www%.', '')
  local response, err = net.request({
    url = ('https://lsp-%s.%s/format'):format(name, domain),
    method = 'POST',
    headers = auth.headers(),
    body = vim.json.encode({ code = code, tabSize = tab_size, insertSpaces = expandtab }),
    cookie_file = auth.cookie_file(),
    timeout = 15,
    retries = 0,
  })
  if err ~= nil or response == nil or response.status ~= 200 or type(response.body) ~= 'string' then
    return nil, 'failed'
  end
  if response.body:match('^%s*<') then return nil, 'failed' end

  local ok, decoded = pcall(vim.json.decode, response.body)
  local formatted = nil
  if ok and type(decoded) == 'table' then
    formatted = decoded.code or decoded.formattedCode or decoded.formatted_code or decoded.data
  end
  local content_type = response_content_type(response):lower()
  if type(formatted) ~= 'string' and content_type:find('text/plain', 1, true) ~= nil then formatted = response.body end
  if type(formatted) ~= 'string' then return nil, 'failed' end
  local normalized = format.normalize(formatted)
  return normalized, normalized ~= nil and 'ok' or 'failed'
end

--- Filetype used for a language slug.
---
---@param lang_slug string
---@return string
LeetCodeSolution.filetype = function(lang_slug)
  local info = config.get_lang(lang_slug)
  return info ~= nil and info.ft or lang_slug
end

--- Display label for a language slug.
---
---@param lang_slug string
---@return string
LeetCodeSolution.label = function(lang_slug)
  local info = config.get_lang(lang_slug)
  return info ~= nil and info.lang or lang_slug
end

--- Starter snippet for the view's current language.
---
---@param view table
---@return string
LeetCodeSolution.snippet = function(view)
  local snippet = snippets(view)[view.lang]
  if type(snippet) ~= 'table' or type(snippet.code) ~= 'string' then return '' end
  return snippet.code
end

local add_padding
local clear_undo

-- Keep the virtual top padding visible when the first line is at the top.
-- Neovim does not draw `virt_lines_above` on the first buffer line until the
-- window has a top fill. Re-apply it after cursor movement and when the code
-- tab is shown.
local function sync_topfill(view)
  if view == nil or view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  local winid = vim.fn.bufwinid(view.code_bufnr)
  if winid == -1 then return end

  local changed = false
  vim.api.nvim_win_call(winid, function()
    local state = vim.fn.winsaveview()
    local target = vim.fn.line('w0') == 1 and 1 or 0
    if state.topfill ~= target then
      changed = true
      state.topfill = target
      vim.fn.winrestview(state)
    end
  end)
  if changed then add_padding(view) end
end

-- Add non-editable visual padding above the first code line.
add_padding = function(view)
  if view == nil or view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  local bufnr = view.code_bufnr
  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeSolution.padding_namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(bufnr, LeetCodeSolution.padding_namespace, 0, 0, {
    virt_lines = { { { ' ', 'LeetCodeCodeNormal' } } },
    virt_lines_above = true,
    virt_lines_leftcol = true,
  })
end

--- Languages available for a question, with the active one first.
---
---@param view table
---@return table slugs
LeetCodeSolution.languages = function(view)
  local preferred = config.config.languages
  local out = {}
  for slug in pairs(snippets(view)) do
    if config.lang_enabled(slug) then table.insert(out, slug) end
  end

  local function rank(slug)
    if slug == view.lang then return -1 end
    if preferred == nil then return 0 end
    for index, enabled in ipairs(preferred) do
      local canonical = config.canonical_lang(enabled)
      if canonical == slug then return index end
    end
    return math.huge
  end

  table.sort(out, function(a, b)
    local rank_a, rank_b = rank(a), rank(b)
    if rank_a ~= rank_b then return rank_a < rank_b end
    return a < b
  end)
  return out
end

--- Create the solution buffer for a view when needed.
---
---@param view table
LeetCodeSolution.prepare = function(view)
  if view.code_bufnr ~= nil and vim.api.nvim_buf_is_valid(view.code_bufnr) then
    if vim.api.nvim_buf_is_loaded(view.code_bufnr) then return end
    vim.api.nvim_buf_delete(view.code_bufnr, { force = true })
  end

  local draft = storage.read_draft(view.slug, view.lang)
  local content = draft or LeetCodeSolution.snippet(view)
  view.code_bufnr = buffer.scratch(('leetcode-ui://question/%s'):format(view.slug), {
    buftype = '',
    ft = LeetCodeSolution.filetype(view.lang),
    listed = true,
  })
  inherit_indent_options(view.code_bufnr)
  LeetCodeSolution.set_code(view, content)
  clear_undo(view.code_bufnr)
end

--- Apply buffer options and draft persistence for a view.
---
---@param view table
LeetCodeSolution.open = function(view)
  vim.api.nvim_set_option_value('buflisted', true, { buf = view.code_bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = view.code_bufnr })

  if vim.b[view.code_bufnr].leetcode_ui_draft_enabled ~= true then
    vim.b[view.code_bufnr].leetcode_ui_draft_enabled = true
    vim.api.nvim_create_autocmd('BufLeave', {
      buffer = view.code_bufnr,
      callback = function()
        if view.closed then return end
        if LeetCodeSolution.save_draft(view) then
          vim.api.nvim_set_option_value('modified', false, { buf = view.code_bufnr })
        end
      end,
    })
    vim.api.nvim_create_autocmd('BufWriteCmd', {
      buffer = view.code_bufnr,
      callback = function(args)
        if args.file ~= '' and args.file ~= vim.api.nvim_buf_get_name(view.code_bufnr) then
          log.error('Writing the solution buffer to a file is not supported')
          vim.api.nvim_err_writeln('leetcode-ui: writing the solution buffer to a file is not supported')
          return
        end
        if LeetCodeSolution.save_draft(view) then
          vim.api.nvim_set_option_value('modified', false, { buf = view.code_bufnr })
        else
          log.error('Failed to save the solution draft')
          vim.api.nvim_err_writeln('leetcode-ui: failed to save the solution draft')
        end
      end,
    })
    vim.api.nvim_create_autocmd({ 'QuitPre', 'VimLeavePre' }, {
      buffer = view.code_bufnr,
      callback = function()
        if LeetCodeSolution.save_draft(view) then
          vim.api.nvim_set_option_value('modified', false, { buf = view.code_bufnr })
        end
      end,
    })
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      buffer = view.code_bufnr,
      callback = function() sync_topfill(view) end,
    })
  end

  add_padding(view)
end

--- Save the current code buffer as a draft.
---
---@param view table|nil
---@return boolean saved
LeetCodeSolution.save_draft = function(view)
  if view == nil or view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return true end
  if not vim.api.nvim_buf_is_loaded(view.code_bufnr) then return true end
  local code = LeetCodeSolution.code(view)
  return storage.write_draft(view.slug, view.lang, code ~= LeetCodeSolution.snippet(view) and code or nil)
end

--- Current code buffer text.
---
---@param view table
---@return string
LeetCodeSolution.code = function(view)
  if view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return '' end
  if not vim.api.nvim_buf_is_loaded(view.code_bufnr) then return '' end
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  return table.concat(lines, '\n')
end

clear_undo = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local levels = vim.api.nvim_get_option_value('undolevels', { buf = bufnr })
  local modifiable = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  vim.api.nvim_set_option_value('undolevels', -1, { buf = bufnr })
  if not modifiable then vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr }) end
  vim.api.nvim_buf_call(bufnr, function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.cmd('execute "normal! A \\<BS>\\<Esc>"')
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end)
  if not modifiable then vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr }) end
  vim.api.nvim_set_option_value('undolevels', levels, { buf = bufnr })
  vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
end

--- Replace the code buffer contents.
---
---@param view table
---@param content string
LeetCodeSolution.set_code = function(view, content)
  local lines = vim.split(content, '\n', { plain = true })
  local bufnr = view.code_bufnr
  local modifiable = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  if not modifiable then vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr }) end
  local ok, err = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, true, lines)
  if not modifiable then vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr }) end
  if not ok then error(err, 0) end
  vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
  add_padding(view)
end

--- Format the current code with the user formatter, then the LeetCode API.
---
---@param view table
LeetCodeSolution.format = function(view)
  if view == nil or view.busy or not has_code_buffer(view) then return end

  view.busy = true
  log.info('Formatting code…')

  local bufnr = view.code_bufnr
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local code = LeetCodeSolution.code(view)
  if not code:match('%S') then
    view.busy = false
    log.info('Nothing to format')
    return
  end
  local function still_usable() return has_code_buffer(view) and view.code_bufnr == bufnr end
  local filetype = LeetCodeSolution.filetype(view.lang)
  local formatted = format.format(code, filetype)
  if not still_usable() then
    view.busy = false
    return
  end
  local reason = nil
  if formatted == nil then
    formatted, reason = remote_formatted(view.lang, code, bufnr)
  end

  if not still_usable() then
    view.busy = false
    return
  end
  if vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
    view.busy = false
    log.warn('Code changed during formatting; result discarded')
    return
  end

  local message, level = 'No formatter is available for this language', vim.log.levels.WARN
  if reason == 'failed' then message = 'Formatting failed; the LeetCode API did not return formatted code' end
  local changed = false
  if formatted ~= nil then
    if formatted ~= code then
      LeetCodeSolution.set_code(view, formatted)
      changed = true
    end
    message, level = 'Code formatted', vim.log.levels.INFO
  end

  local saved = true
  if changed then saved = LeetCodeSolution.save_draft(view) end
  view.busy = false
  if not saved then
    if changed and still_usable() then vim.api.nvim_set_option_value('modified', true, { buf = bufnr }) end
    log.notify('Failed to save the formatted code', vim.log.levels.ERROR)
    return
  end
  log.notify(message, level)
end

--- Restore the starter snippet and remove the saved draft.
---
---@param view table
---@return boolean reset
LeetCodeSolution.reset = function(view)
  if not has_code_buffer(view) then return false end
  if not storage.write_draft(view.slug, view.lang, nil) then return false end
  LeetCodeSolution.set_code(view, LeetCodeSolution.snippet(view))
  clear_undo(view.code_bufnr)
  log.info('Code reset to the starter snippet')
  return true
end

--- Switch the view to another language.
---
---@param view table
---@param lang_slug string
---@return boolean switched
LeetCodeSolution.switch_language = function(view, lang_slug)
  if view == nil or view.busy or not has_code_buffer(view) then return false end
  local target = config.canonical_lang(lang_slug)
  if target == view.lang then return false end
  if type(snippets(view)[target]) ~= 'table' then
    log.warn(('`%s` is not available for this question'):format(lang_slug))
    return false
  end

  local old_code = LeetCodeSolution.code(view)
  local old_snippet = LeetCodeSolution.snippet(view)
  local draft_to_save = old_code ~= old_snippet and old_code or nil
  if not storage.write_draft(view.slug, view.lang, draft_to_save) then return false end

  local saved_draft = storage.read_draft(view.slug, target)
  local target_snippet = snippets(view)[target]
  local content = saved_draft
  if content == nil then content = type(target_snippet) == 'table' and target_snippet.code or '' end
  LeetCodeSolution.set_code(view, content)
  clear_undo(view.code_bufnr)
  view.lang = target
  vim.api.nvim_set_option_value('filetype', LeetCodeSolution.filetype(target), { buf = view.code_bufnr })
  inherit_indent_options(view.code_bufnr)
  local target_info = config.get_lang(target)
  log.info(('Switched to %s'):format(target_info ~= nil and target_info.lang or target))
  return true
end

return LeetCodeSolution
