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
  winid = nil,
}

local padding_ns = vim.api.nvim_create_namespace('leetcode-ui-padding')

local function pad_top(bufnr)
  if vim.b[bufnr].lc_ui_top_padding == true then return end
  local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, padding_ns, 0, 0, {
    virt_lines = { { { ' ' } } },
    virt_lines_above = true,
  })
  if ok then vim.b[bufnr].lc_ui_top_padding = true end
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
    title = ' LeetCode ',
  })

  LeetCodeUI.state.winid = winid
  return winid
end

--- Show a buffer in the central window.
---
---@param bufnr number
---@param opts table|nil { number = boolean, wrap = boolean, pad_top = boolean }
---@return number winid
LeetCodeUI.show = function(bufnr, opts)
  opts = opts or {}
  local winid = LeetCodeUI.ensure()

  if vim.api.nvim_win_get_buf(winid) ~= bufnr then vim.api.nvim_win_set_buf(winid, bufnr) end
  if opts.pad_top == true then pad_top(bufnr) end
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_set_option_value('number', opts.number == true, { win = winid })
  vim.api.nvim_set_option_value('wrap', opts.wrap ~= false, { win = winid })

  return winid
end

--- Render read-only span lines in the central window.
---
---@param lines table Array of lines, each an array of `{ text, hl }` spans.
---@param opts table|nil { number = boolean, wrap = boolean, pad_top = boolean }
---@return number winid
LeetCodeUI.render = function(lines, opts)
  local bufnr = LeetCodeUI.panel()
  buffer.spans_write(bufnr, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  return LeetCodeUI.show(bufnr, opts)
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
  LeetCodeUI.state.winid = nil
end

return LeetCodeUI
