--- *leetcode-ui-solution* Code editor buffer
---
--- Owns the editable solution buffer: starter snippets, draft persistence,
--- formatting, and language switching.
---
---@tag LeetCodeSolution
---@toc_entry Solution buffer

local LeetCodeSolution = {}

local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local storage = require('leetcode-ui.storage')

-- Helper data =======================================================================================================

LeetCodeSolution.cli_formatters = {
  javascript = { 'prettier', '--stdin-filepath', 'x.js' },
  typescript = { 'prettier', '--stdin-filepath', 'x.ts' },
  python3 = { 'black', '-' },
  python = { 'black', '-' },
  cpp = { 'clang-format' },
  c = { 'clang-format' },
  golang = { 'gofmt' },
  go = { 'gofmt' },
  rust = { 'rustfmt', '--emit', 'stdout' },
  java = { 'google-java-format', '-' },
}

-- Helper functionality =============================================================================================

--- Filetype used for a language slug.
---
---@param lang_slug string
---@return string
LeetCodeSolution.filetype = function(lang_slug)
  local info = config.get_lang(lang_slug)
  return info ~= nil and info.ft or lang_slug
end

--- Starter snippet for the view's current language.
---
---@param view table
---@return string
LeetCodeSolution.snippet = function(view)
  local snippet = (view.detail.snippets or {})[view.lang]
  return snippet ~= nil and snippet.code or ''
end

--- Languages available for a question, with the active one first.
---
---@param view table
---@return table slugs
LeetCodeSolution.languages = function(view)
  local preferred = config.config.languages
  local out = {}
  for slug in pairs(view.detail.snippets or {}) do
    if config.lang_enabled(slug) then table.insert(out, slug) end
  end

  local function rank(slug)
    if slug == view.lang then return -1 end
    if preferred == nil then return 0 end
    for index, enabled in ipairs(preferred) do
      local info = config.get_lang(enabled)
      local canonical = info ~= nil and (info.alt or info.slug) or enabled
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
  if view.code_bufnr ~= nil and vim.api.nvim_buf_is_valid(view.code_bufnr) then return end

  local draft = storage.read_draft(view.slug, view.lang)
  local content = draft ~= nil and draft or LeetCodeSolution.snippet(view)
  view.code_bufnr = buffer.scratch(('leetcode-ui://%s'):format(view.slug), {
    ft = LeetCodeSolution.filetype(view.lang),
    listed = true,
  })
  LeetCodeSolution.set_code(view, content)
end

--- Apply buffer options and draft persistence for a view.
---
---@param view table
LeetCodeSolution.open = function(view)
  vim.api.nvim_set_option_value('buflisted', true, { buf = view.code_bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = view.code_bufnr })

  if vim.b[view.code_bufnr].lc_draft_enabled ~= true then
    vim.b[view.code_bufnr].lc_draft_enabled = true
    vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWritePre' }, {
      buffer = view.code_bufnr,
      callback = function() LeetCodeSolution.save_draft(view) end,
    })
  end
end

--- Save the current code buffer as a draft.
---
---@param view table|nil
LeetCodeSolution.save_draft = function(view)
  if view == nil or view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  local code = LeetCodeSolution.code(view)
  storage.write_draft(view.slug, view.lang, code ~= LeetCodeSolution.snippet(view) and code or nil)
end

--- Current code buffer text.
---
---@param view table
---@return string
LeetCodeSolution.code = function(view)
  if view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return '' end
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  if lines[1] == '' then table.remove(lines, 1) end
  return table.concat(lines, '\n')
end

--- Replace the code buffer contents.
---
---@param view table
---@param content string
LeetCodeSolution.set_code = function(view, content)
  local lines = vim.split(content, '\n')
  table.insert(lines, 1, '')
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, lines)
end

--- Format the current code using a local CLI formatter or LSP.
---
--- LeetCode's remote formatting endpoint is intentionally not used.
---
---@param view table
LeetCodeSolution.format = function(view)
  if view == nil or view.busy then return end
  if view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end

  view.busy = true
  log.info('Formatting code…')
  local code = LeetCodeSolution.code(view)
  local formatted = nil

  local command = LeetCodeSolution.cli_formatters[view.lang]
  if command ~= nil and vim.fn.executable(command[1]) == 1 then
    local out = vim.system(command, { text = true, stdin = code }):wait()
    if out.code == 0 and type(out.stdout) == 'string' and out.stdout ~= '' then formatted = out.stdout end
  end

  if type(formatted) == 'string' and formatted ~= '' then
    LeetCodeSolution.set_code(view, formatted)
    LeetCodeSolution.save_draft(view)
    view.busy = false
    log.info('Code formatted')
    return
  end

  ---@type function
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = get_clients({ bufnr = view.code_bufnr, method = 'textDocument/formatting' })
  if #clients > 0 and pcall(vim.lsp.buf.format, { bufnr = view.code_bufnr, async = false }) then
    LeetCodeSolution.set_code(view, LeetCodeSolution.code(view))
    LeetCodeSolution.save_draft(view)
    view.busy = false
    log.info('Code formatted with LSP')
    return
  end

  view.busy = false
  LeetCodeSolution.save_draft(view)
  log.warn('No formatter is available for this language')
end

--- Restore the starter snippet and remove the saved draft.
---
---@param view table
LeetCodeSolution.reset = function(view)
  if view == nil or view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  LeetCodeSolution.set_code(view, LeetCodeSolution.snippet(view))
  storage.write_draft(view.slug, view.lang, nil)
  log.info('Code reset to the starter snippet')
end

--- Switch the view to another language.
---
---@param view table
---@param lang_slug string
LeetCodeSolution.switch_language = function(view, lang_slug)
  if view == nil or lang_slug == view.lang then return end
  if (view.detail.snippets or {})[lang_slug] == nil then
    log.warn(('`%s` is not available for this question'):format(lang_slug))
    return
  end

  local old_code = LeetCodeSolution.code(view)
  local old_snippet = LeetCodeSolution.snippet(view)
  storage.write_draft(view.slug, view.lang, old_code ~= old_snippet and old_code or nil)

  view.lang = lang_slug
  local draft = storage.read_draft(view.slug, view.lang)
  LeetCodeSolution.set_code(view, draft ~= nil and draft or LeetCodeSolution.snippet(view))
  vim.api.nvim_set_option_value('filetype', LeetCodeSolution.filetype(lang_slug), { buf = view.code_bufnr })
  local info = config.get_lang(lang_slug)
  log.info(('Switched to %s'):format(info ~= nil and info.lang or lang_slug))
end

return LeetCodeSolution
