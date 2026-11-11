--- *leetcode-ui-ui* Central UI window
---
--- All plugin views (question tabs, statistics, and command help) are shown
--- in one central floating window. Read-only views use a shared scratch
--- buffer; the code tab swaps in the editable solution buffer inside the same
--- window.
---@tag LeetCodeUI
---@toc_entry Central UI

local LeetCodeUI = {}

local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')
local format = require('leetcode-ui.format')
local log = require('leetcode-ui.log')

-- Helper data =======================================================================================================

LeetCodeUI.state = {
  bufnr = nil,
  close_autocmd = nil,
  cursor_hidden = false,
  fold_bufnr = nil,
  fold_signature = nil,
  fold_winid = nil,
  owner = nil,
  owner_serial = 0,
  winid = nil,
}

local saved_guicursor = nil
local cursor_is_hidden = false
local cursor_autocmd = nil
local resize_autocmd = nil
local layout_autocmd = nil
local clue_cleanup_autocmd = nil
local clue_ensured = {}
local markdown_disabled_buffer = nil
local ui_augroup = vim.api.nvim_create_augroup('LeetCodeUi', { clear = true })

local function ensure_clue_triggers(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  -- mini.clue manages listed buffers itself; the panel is an unlisted scratch
  -- buffer and needs explicit trigger creation.
  if vim.fn.buflisted(bufnr) == 1 then return end

  local clue = rawget(_G, 'MiniClue')
  if type(clue) ~= 'table' or type(clue.ensure_buf_triggers) ~= 'function' then return end
  if vim.g.miniclue_disable == true or vim.b[bufnr].miniclue_disable == true then return end

  local config_id = clue.config or true
  if clue_ensured[bufnr] == config_id then return end

  local ok = pcall(clue.ensure_buf_triggers, bufnr)
  if not ok then return end
  clue_ensured[bufnr] = config_id
  if clue_cleanup_autocmd == nil then
    clue_cleanup_autocmd = vim.api.nvim_create_autocmd({ 'BufUnload', 'RecordingLeave' }, {
      group = ui_augroup,
      callback = function(args)
        if args.event == 'RecordingLeave' then
          clue_ensured = {}
          vim.schedule(function()
            if LeetCodeUI.is_open() and vim.api.nvim_get_current_win() == LeetCodeUI.state.winid then
              ensure_clue_triggers(vim.api.nvim_get_current_buf())
            end
          end)
        else
          clue_ensured[args.buf] = nil
        end
      end,
    })
  end
end

local function fold_signature(folds)
  local parts = {}
  for _, fold in ipairs(folds or {}) do
    table.insert(parts, ('%d:%d'):format(fold.start_line, fold.end_line))
  end
  return table.concat(parts, ',')
end

local function restore_cursor()
  if not cursor_is_hidden then return end
  if saved_guicursor ~= nil then vim.o.guicursor = saved_guicursor end
  saved_guicursor = nil
  cursor_is_hidden = false
end

local function hide_cursor()
  if cursor_is_hidden then return end
  saved_guicursor = vim.o.guicursor
  local hidden = 'n-v-ve-o-i-r-sm:LeetCodeCursor'
  -- Leave command-line modes untouched so the visible cmdline cursor is kept.
  if saved_guicursor == '' then
    vim.o.guicursor = hidden
  else
    local sep = saved_guicursor:sub(-1) == ',' and '' or ','
    vim.o.guicursor = saved_guicursor .. sep .. hidden
  end
  cursor_is_hidden = true
end

local function update_cursor()
  local in_central = LeetCodeUI.is_open() and vim.api.nvim_get_current_win() == LeetCodeUI.state.winid
  if in_central then ensure_clue_triggers(vim.api.nvim_get_current_buf()) end
  if in_central and LeetCodeUI.state.cursor_hidden then
    hide_cursor()
  else
    restore_cursor()
  end
end

local function ensure_cursor_autocmd()
  if cursor_autocmd ~= nil then return end
  cursor_autocmd = vim.api.nvim_create_autocmd(
    { 'WinEnter', 'BufEnter' },
    { group = ui_augroup, callback = update_cursor }
  )
end

local function apply_folds(winid, folds)
  vim.api.nvim_win_call(winid, function()
    vim.cmd('silent! normal! zE')
    for _, fold in ipairs(folds or {}) do
      if fold.start_line <= fold.end_line then vim.cmd(('%d,%dfold'):format(fold.start_line, fold.end_line)) end
    end
  end)
end

local function resize_window()
  if not LeetCodeUI.is_open() then return end
  local float = buffer.float_config({ tabpage = vim.api.nvim_win_get_tabpage(LeetCodeUI.state.winid) })
  local resize
  if float.relative == 'editor' then
    resize = float
    resize.noautocmd, resize.external, resize.split, resize.vertical = nil, nil, nil, nil
  else
    resize = { width = float.width, height = float.height }
  end
  local ok, err = pcall(vim.api.nvim_win_set_config, LeetCodeUI.state.winid, resize)
  if not ok then log.warn('Failed to resize the central window: ' .. tostring(err)) end
end

local function ensure_layout_autocmds()
  if layout_autocmd ~= nil then return end
  layout_autocmd = vim.api.nvim_create_autocmd({ 'OptionSet', 'TabNew', 'TabClosed', 'WinNew', 'WinClosed' }, {
    group = ui_augroup,
    callback = function(args)
      if
        args.event == 'OptionSet'
        and not vim.tbl_contains({ 'laststatus', 'showtabline', 'cmdheight' }, args.match)
      then
        return
      end
      -- WinClosed fires before the closing window leaves the layout, and tab
      -- events fire before the tab set is fully updated. Defer to recompute
      -- tabline/statusline rows from the new layout.
      if args.event == 'WinClosed' or args.event == 'TabNew' or args.event == 'TabClosed' then
        vim.schedule(resize_window)
      else
        resize_window()
      end
    end,
  })
end

local function winhighlight(cursorline_hl, normal_hl)
  local normal = normal_hl or 'LeetCodeNormalFloat'
  local groups = {
    'Normal:' .. normal,
    'NormalNC:' .. normal,
    'FloatBorder:LeetCodeFloatBorder',
    'WinBar:LeetCodeWinBar',
    'WinBarNC:LeetCodeWinBarNC',
  }
  if cursorline_hl ~= nil then
    table.insert(groups, 'CursorLine:' .. cursorline_hl)
    table.insert(groups, 'CursorLineNC:' .. cursorline_hl)
  end
  return table.concat(groups, ',')
end

-- Helper functionality =============================================================================================

--- Whether the central window is currently open.
---
---@return boolean
LeetCodeUI.is_open = function()
  return LeetCodeUI.state.winid ~= nil and vim.api.nvim_win_is_valid(LeetCodeUI.state.winid)
end

--- Mark the start of a new central-window view.
---
--- In-flight question loads compare the serial captured when they start, so a
--- newer statistics or help view is not replaced by older results.
---
---@param owner string
LeetCodeUI.claim = function(owner)
  LeetCodeUI.state.owner = owner
  LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1
end

--- Record a navigation without changing view ownership.
---
--- Used by actions that fetch before rendering so earlier in-flight requests
--- can detect that newer navigation happened.
LeetCodeUI.bump = function() LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1 end

--- Get the shared read-only scratch buffer, creating it if needed.
---
---@return number bufnr
LeetCodeUI.panel = function()
  local bufnr = LeetCodeUI.state.bufnr
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = buffer.scratch('leetcode-ui://panel', { ft = 'txt', modifiable = false })
    LeetCodeUI.state.bufnr = bufnr
  end
  return bufnr
end

--- Ensure the central window is open and return its id.
---
---@param focus boolean|nil Whether to focus a newly opened window.
---@return number winid
LeetCodeUI.ensure = function(focus)
  if LeetCodeUI.is_open() then return LeetCodeUI.state.winid end

  local winid = buffer.open_float(LeetCodeUI.panel(), { focus = focus ~= false })

  LeetCodeUI.state.winid = winid
  LeetCodeUI.state.close_autocmd = vim.api.nvim_create_autocmd('WinClosed', {
    group = ui_augroup,
    pattern = tostring(winid),
    once = true,
    callback = function()
      local owner = LeetCodeUI.state.owner
      LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1
      LeetCodeUI.state.close_autocmd = nil
      LeetCodeUI.state.winid = nil
      LeetCodeUI.state.cursor_hidden = false
      LeetCodeUI.state.owner = nil
      LeetCodeUI.state.fold_winid, LeetCodeUI.state.fold_bufnr, LeetCodeUI.state.fold_signature = nil, nil, nil
      restore_cursor()

      if owner == 'question' then
        local question = require('leetcode-ui.question')
        local view = question.active
        if view ~= nil then question.close(view, true) end
      end
    end,
  })
  ensure_cursor_autocmd()
  if resize_autocmd == nil then
    resize_autocmd = vim.api.nvim_create_autocmd('VimResized', { group = ui_augroup, callback = resize_window })
  end
  ensure_layout_autocmds()
  ensure_clue_triggers(LeetCodeUI.panel())
  return winid
end

--- Reapply the configured window geometry.
LeetCodeUI.resize = resize_window

--- Show a buffer in the central window.
---
---@param bufnr number
---@param opts table|nil Options: `number`, `wrap`, `cursorline`,
--- `cursorline_hl`, `normal_hl`, `topfill`, `hide_cursor`, `signcolumn`,
--- `foldenable`, `foldmethod`, `foldcolumn`, `statuscolumn`, `folds`,
--- `focus`, and `owner` (logical view name stored for stale-render checks).
---@return number winid
LeetCodeUI.show = function(bufnr, opts)
  opts = opts or {}
  local winid = LeetCodeUI.ensure(opts.focus ~= false)

  local previous_buf = vim.api.nvim_win_get_buf(winid)
  local current_foldmethod = vim.api.nvim_get_option_value('foldmethod', { win = winid })
  if previous_buf ~= bufnr then
    vim.b[previous_buf].leetcode_ui_foldmethod = current_foldmethod
    vim.api.nvim_win_set_buf(winid, bufnr)
  end
  if opts.focus ~= false then vim.api.nvim_set_current_win(winid) end
  if opts.owner ~= nil then LeetCodeUI.state.owner = opts.owner end

  vim.api.nvim_set_option_value('number', opts.number == true, { win = winid })
  vim.api.nvim_set_option_value('wrap', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('linebreak', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('breakindent', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('cursorline', opts.cursorline == true, { win = winid })
  vim.api.nvim_set_option_value('winhighlight', winhighlight(opts.cursorline_hl, opts.normal_hl), { win = winid })
  vim.api.nvim_set_option_value('signcolumn', opts.signcolumn or 'no', { win = winid })
  vim.api.nvim_set_option_value('foldenable', opts.foldenable == true, { win = winid })
  local foldmethod = opts.foldmethod
  if opts.folds ~= nil and #opts.folds > 0 then foldmethod = 'manual' end
  if foldmethod == nil and previous_buf ~= bufnr then
    foldmethod = vim.b[bufnr].leetcode_ui_foldmethod or vim.go.foldmethod
  end
  if foldmethod ~= nil and foldmethod ~= current_foldmethod then
    vim.api.nvim_set_option_value('foldmethod', foldmethod, { win = winid })
    vim.b[bufnr].leetcode_ui_foldmethod = foldmethod
  end
  vim.api.nvim_set_option_value('foldcolumn', tostring(opts.foldcolumn or 0), { win = winid })
  vim.api.nvim_set_option_value('statuscolumn', opts.statuscolumn or '', { win = winid })
  if opts.folds ~= nil then
    local signature = ('%d|%s'):format(vim.api.nvim_buf_line_count(bufnr), fold_signature(opts.folds))
    local state = LeetCodeUI.state
    if state.fold_winid ~= winid or state.fold_bufnr ~= bufnr or state.fold_signature ~= signature then
      apply_folds(winid, opts.folds)
      state.fold_winid, state.fold_bufnr, state.fold_signature = winid, bufnr, signature
    end
  else
    LeetCodeUI.state.fold_winid, LeetCodeUI.state.fold_bufnr, LeetCodeUI.state.fold_signature = nil, nil, nil
  end

  vim.api.nvim_win_call(winid, function()
    local view = vim.fn.winsaveview()
    if view.topfill ~= (opts.topfill or 0) then
      view.topfill = opts.topfill or 0
      vim.fn.winrestview(view)
    end
  end)

  if vim.api.nvim_get_option_value('filetype', { buf = bufnr }) ~= 'markdown' then
    vim.api.nvim_set_option_value('conceallevel', 0, { win = winid })
    vim.api.nvim_set_option_value('concealcursor', '', { win = winid })
  end

  LeetCodeUI.state.cursor_hidden = opts.hide_cursor == true
  update_cursor()
  return winid
end

local function finish_render(bufnr, render_opts, previous_buf, previous_view, first_content)
  local winid = LeetCodeUI.show(bufnr, render_opts)
  LeetCodeUI.set_winbar('')

  if render_opts.focus == false and previous_view ~= nil and previous_buf == bufnr then
    pcall(vim.api.nvim_win_call, winid, function() vim.fn.winrestview(previous_view) end)
  elseif vim.api.nvim_buf_line_count(bufnr) >= first_content then
    pcall(vim.api.nvim_win_set_cursor, winid, { first_content, 0 })
  end
  return winid
end

local function previous_view()
  if not LeetCodeUI.is_open() then return nil, nil end
  local winid = LeetCodeUI.state.winid
  return vim.api.nvim_win_get_buf(winid), vim.api.nvim_win_call(winid, vim.fn.winsaveview)
end

--- Whether Markdown rendering is available.
---
---@return boolean
LeetCodeUI.markdown_enabled = function()
  if config.config.markdown == false then return false end
  local ok, render_markdown = pcall(require, 'render-markdown')
  if not ok then return false end
  if type(render_markdown.get) == 'function' then
    local got, enabled = pcall(render_markdown.get)
    if not got or enabled ~= true then return false end
  end
  return true
end

--- Render Markdown text in the central window.
---
--- When `render-markdown.nvim` is loaded, its renderer is applied to the
--- markdown buffer.
---
--- The configured `formatter` is applied to `text` with filetype `markdown`;
--- a nil result keeps `text` unchanged.
---
--- `pad_top` defaults to `true`. Supplied `folds` are shifted down by one line
--- when top padding is enabled.
---
---@param text string Markdown source.
---@param opts table|nil All |LeetCodeUI.show()| options plus `pad_top`.
---@return number winid
LeetCodeUI.render_markdown = function(text, opts)
  opts = opts or {}
  text = format.format(text, 'markdown') or text
  local lines = vim.split(text, '\n', { plain = true })
  -- Give render-markdown a line after the final block so table/list bottom
  -- borders are not clipped at the bottom of the buffer.
  if lines[#lines] ~= '' then table.insert(lines, '') end
  local pad = opts.pad_top ~= false
  if pad then table.insert(lines, 1, '') end
  if pad and opts.folds ~= nil then
    local folds = {}
    for _, fold in ipairs(opts.folds) do
      table.insert(folds, { start_line = fold.start_line + 1, end_line = fold.end_line + 1 })
    end
    opts = vim.tbl_extend('force', {}, opts, { folds = folds })
  end

  local previous_buf, saved_view = previous_view()
  local render_opts = vim.tbl_extend('force', {
    cursorline = true,
    cursorline_hl = 'LeetCodeCursorLine',
    hide_cursor = true,
    folds = {},
    pad_top = pad,
  }, opts)

  local bufnr = LeetCodeUI.panel()
  local was_markdown = vim.api.nvim_get_option_value('filetype', { buf = bufnr }) == 'markdown'
  buffer.lines_write(bufnr, lines)
  if vim.api.nvim_get_option_value('filetype', { buf = bufnr }) ~= 'markdown' then
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
  end
  local render_ns = vim.api.nvim_get_namespaces()['render-markdown.nvim']
  if was_markdown and render_ns ~= nil then pcall(vim.api.nvim_buf_clear_namespace, bufnr, render_ns, 0, -1) end
  local ok_renderer, renderer = pcall(require, 'render-markdown')
  if ok_renderer and type(renderer.buf_enable) == 'function' then
    local needs_enable = markdown_disabled_buffer == bufnr
    if not needs_enable and type(renderer.get) == 'function' then
      local got, enabled = pcall(renderer.get, bufnr)
      needs_enable = got and enabled ~= true
    end
    if needs_enable then
      vim.api.nvim_buf_call(bufnr, function() pcall(renderer.buf_enable) end)
      markdown_disabled_buffer = nil
    end
  end
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  local first_content = 1
  local winid = finish_render(bufnr, render_opts, previous_buf, saved_view, first_content)

  local ok, render_markdown = pcall(require, 'render-markdown')
  if ok and type(render_markdown.render) == 'function' then
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if vim.api.nvim_get_option_value('filetype', { buf = bufnr }) ~= 'markdown' then return end
      if not LeetCodeUI.is_open() or vim.api.nvim_win_get_buf(LeetCodeUI.state.winid) ~= bufnr then return end
      pcall(render_markdown.render, { buf = bufnr })
    end)
  end
  return winid
end

--- Render read-only span lines in the central window.
---
--- When `pad_top` is true, one empty line is prepended and any supplied
--- `folds` are shifted down by one line.
---
---@param lines table Array of lines, each an array of `{ text, hl }` spans.
---@param opts table|nil All |LeetCodeUI.show()| options plus `pad_top`.
---@return number winid
LeetCodeUI.render = function(lines, opts)
  opts = opts or {}
  if opts.pad_top == true then
    lines = vim.list_extend({ {} }, lines)

    local folds = {}
    for _, fold in ipairs(opts.folds or {}) do
      table.insert(folds, { start_line = fold.start_line + 1, end_line = fold.end_line + 1 })
    end
    opts = vim.tbl_extend('force', {}, opts, { folds = folds })
  end

  local previous_buf, saved_view = previous_view()
  local render_opts = vim.tbl_extend('force', {
    cursorline = true,
    cursorline_hl = 'LeetCodeCursorLine',
    hide_cursor = true,
    folds = {},
  }, opts)

  local bufnr = LeetCodeUI.panel()
  local was_markdown = vim.api.nvim_get_option_value('filetype', { buf = bufnr }) == 'markdown'
  if was_markdown then
    local ok, renderer = pcall(require, 'render-markdown')
    if ok and type(renderer.buf_disable) == 'function' then
      vim.api.nvim_buf_call(bufnr, function() pcall(renderer.buf_disable) end)
      markdown_disabled_buffer = bufnr
    end
  end
  if vim.api.nvim_get_option_value('filetype', { buf = bufnr }) ~= 'txt' then
    vim.api.nvim_set_option_value('filetype', 'txt', { buf = bufnr })
  end
  local render_ns = vim.api.nvim_get_namespaces()['render-markdown.nvim']
  if render_ns ~= nil then pcall(vim.api.nvim_buf_clear_namespace, bufnr, render_ns, 0, -1) end
  buffer.spans_write(bufnr, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  local first_content = render_opts.pad_top == true and 2 or 1
  return finish_render(bufnr, render_opts, previous_buf, saved_view, first_content)
end

--- Set the central window's winbar.
---
---@param text string
LeetCodeUI.set_winbar = function(text)
  if not LeetCodeUI.is_open() then return end
  vim.api.nvim_set_option_value('winbar', text or '', { win = LeetCodeUI.state.winid })
end

--- Close the central window.
LeetCodeUI.close = function()
  LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1
  if LeetCodeUI.state.close_autocmd ~= nil then
    pcall(vim.api.nvim_del_autocmd, LeetCodeUI.state.close_autocmd)
    LeetCodeUI.state.close_autocmd = nil
  end
  if LeetCodeUI.is_open() then pcall(vim.api.nvim_win_close, LeetCodeUI.state.winid, false) end
  LeetCodeUI.state.cursor_hidden = false
  LeetCodeUI.state.owner = nil
  LeetCodeUI.state.fold_winid, LeetCodeUI.state.fold_bufnr, LeetCodeUI.state.fold_signature = nil, nil, nil
  LeetCodeUI.state.winid = nil
  restore_cursor()
end

return LeetCodeUI
