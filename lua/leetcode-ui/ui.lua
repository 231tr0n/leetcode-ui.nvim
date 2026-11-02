--- *leetcode-ui-ui* Central UI window
---
--- All plugin views (question tabs and statistics) are shown in one central
--- floating window. Read-only views use a shared scratch buffer; the code tab
--- swaps in the editable solution buffer inside the same window.
---
---@tag LeetCodeUI
---@toc_entry Central UI

local LeetCodeUI = {}

local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeUI.state = {
  bufnr = nil,
  hide_cursor = false,
  winid = nil,
}

local saved_guicursor = nil
local cursor_is_hidden = false
local cursor_autocmd = nil

local function restore_cursor()
  if not cursor_is_hidden then return end
  if saved_guicursor ~= nil then vim.o.guicursor = saved_guicursor end
  saved_guicursor = nil
  cursor_is_hidden = false
end

local function hide_cursor()
  if cursor_is_hidden then return end
  saved_guicursor = vim.o.guicursor
  vim.o.guicursor = 'a:LeetCodeCursor'
  cursor_is_hidden = true
end

local function update_cursor()
  local in_central = LeetCodeUI.is_open() and vim.api.nvim_get_current_win() == LeetCodeUI.state.winid
  if in_central and LeetCodeUI.state.hide_cursor then
    hide_cursor()
  else
    restore_cursor()
  end
end

local function ensure_cursor_autocmd()
  if cursor_autocmd ~= nil then return end
  cursor_autocmd = vim.api.nvim_create_autocmd('WinEnter', { callback = update_cursor })
end

local function apply_folds(winid, folds)
  vim.api.nvim_win_call(winid, function()
    vim.cmd('silent! normal! zE')
    for _, fold in ipairs(folds or {}) do
      if fold.start_line <= fold.end_line then vim.cmd(('%d,%dfold'):format(fold.start_line, fold.end_line)) end
    end
  end)
end

local function window_highlight(cursorline_hl)
  local groups = {
    'Normal:LeetCodeNormalFloat',
    'FloatBorder:LeetCodeFloatBorder',
    'WinBar:LeetCodeWinBar',
    'WinBarNC:LeetCodeWinBarNC',
  }
  if cursorline_hl ~= nil then table.insert(groups, 'CursorLine:' .. cursorline_hl) end
  return table.concat(groups, ',')
end

-- Helper functionality =============================================================================================

--- Whether the central window is currently open.
---
---@return boolean
LeetCodeUI.is_open = function()
  return LeetCodeUI.state.winid ~= nil and vim.api.nvim_win_is_valid(LeetCodeUI.state.winid)
end

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
---@return number winid
LeetCodeUI.ensure = function()
  if LeetCodeUI.is_open() then return LeetCodeUI.state.winid end

  local winid = buffer.open_float(LeetCodeUI.panel(), {
    width = config.config.float_width,
    height = config.config.float_height,
    border = config.config.float_border,
    focus = true,
  })

  LeetCodeUI.state.winid = winid
  ensure_cursor_autocmd()
  return winid
end

--- Show a buffer in the central window.
---
---@param bufnr number
---@param opts table|nil Options: `number`, `wrap`, `cursorline`,
--- `cursorline_hl`, `hide_cursor`, `foldmethod`, `foldcolumn`,
--- `statuscolumn`, and `folds`.
---@return number winid
LeetCodeUI.show = function(bufnr, opts)
  opts = opts or {}
  local winid = LeetCodeUI.ensure()

  if vim.api.nvim_win_get_buf(winid) ~= bufnr then vim.api.nvim_win_set_buf(winid, bufnr) end
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_set_option_value('number', opts.number == true, { win = winid })
  vim.api.nvim_set_option_value('wrap', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('cursorline', opts.cursorline == true, { win = winid })
  vim.api.nvim_set_option_value('winhighlight', window_highlight(opts.cursorline_hl), { win = winid })
  vim.api.nvim_set_option_value('foldmethod', opts.foldmethod or vim.go.foldmethod, { win = winid })
  vim.api.nvim_set_option_value('foldcolumn', tostring(opts.foldcolumn or 0), { win = winid })
  vim.api.nvim_set_option_value('statuscolumn', opts.statuscolumn or '', { win = winid })
  apply_folds(winid, opts.folds)

  LeetCodeUI.state.hide_cursor = opts.hide_cursor == true
  update_cursor()
  return winid
end

--- Render read-only span lines in the central window.
---
---@param lines table Array of lines, each an array of `{ text, hl }` spans.
---@param opts table|nil { number = boolean, wrap = boolean, pad_top = boolean,
--- folds = table }
---@return number winid
LeetCodeUI.render = function(lines, opts)
  opts = opts or {}
  if opts.pad_top == true then
    table.insert(lines, 1, {})
    for _, fold in ipairs(opts.folds or {}) do
      fold.start_line = fold.start_line + 1
      fold.end_line = fold.end_line + 1
    end
  end

  local render_opts = vim.tbl_extend('force', {
    cursorline = true,
    cursorline_hl = 'LeetCodeCursorLine',
    hide_cursor = true,
  }, opts)

  local bufnr = LeetCodeUI.panel()
  buffer.spans_write(bufnr, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  local winid = LeetCodeUI.show(bufnr, render_opts)

  local first_content = render_opts.pad_top == true and 2 or 1
  if vim.api.nvim_buf_line_count(bufnr) >= first_content then
    pcall(vim.api.nvim_win_set_cursor, winid, { first_content, 0 })
  end
  return winid
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
  if LeetCodeUI.is_open() then pcall(vim.api.nvim_win_close, LeetCodeUI.state.winid, false) end
  LeetCodeUI.state.hide_cursor = false
  LeetCodeUI.state.winid = nil
  restore_cursor()
end

return LeetCodeUI
