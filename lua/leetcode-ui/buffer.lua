--- *leetcode-ui-buffer* Buffer and span helpers
---
--- Shared plumbing for the central UI and the code editor:
--- scratch buffer creation, window creation, and `{ text, hl }` span
--- rendering via |nvim_buf_set_extmark()|.
---@tag LeetCodeBuffer
---@toc_entry Buffer helpers

local LeetCodeBuffer = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeBuffer.namespace = vim.api.nvim_create_namespace('leetcode-ui')

-- Helper functionality =============================================================================================

-- Number of rows occupied by the tabline.
-- @return integer
local function tabline_rows()
  local showtabline = vim.o.showtabline
  if showtabline == 0 then return 0 end

  -- GUIs that advertise `ext_tabline` draw the tabline themselves, so the
  -- editor grid has no tabline row reserved.
  local uis = vim.api.nvim_list_uis()
  if #uis > 0 then
    local external = true
    for _, ui in ipairs(uis) do
      if not ui.ext_tabline then
        external = false
        break
      end
    end
    if external then return 0 end
  end

  if showtabline == 1 and #vim.api.nvim_list_tabpages() <= 1 then return 0 end
  return 1
end

-- Number of rows occupied by the statusline at the bottom of the editor.
-- @param tabpage integer|nil Tabpage to inspect (default: current).
-- @return integer
local function statusline_rows(tabpage)
  local laststatus = vim.o.laststatus
  if laststatus == 2 or laststatus == 3 then return 1 end
  if laststatus ~= 1 then return 0 end

  -- With 'laststatus' 1 the statusline is only shown for real windows, not
  -- floating ones (including the central window itself).
  local windows = 0
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage or 0)) do
    if vim.api.nvim_win_get_config(winid).relative == '' then windows = windows + 1 end
  end
  return windows > 1 and 1 or 0
end

--- Create or reuse a scratch buffer.
---
---@param name string Unique buffer name.
---@param opts table|nil { listed, ft, modifiable, buftype }
---@return number bufnr
LeetCodeBuffer.scratch = function(name, opts)
  opts = opts or {}

  local bufnr = -1
  for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(candidate) == name then
      bufnr = candidate
      break
    end
  end
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(opts.listed == true, true)
    vim.api.nvim_buf_set_name(bufnr, name)
  end

  vim.api.nvim_set_option_value('buflisted', opts.listed == true, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', opts.buftype or 'nofile', { buf = bufnr })
  vim.api.nvim_set_option_value('swapfile', false, { buf = bufnr })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = bufnr })
  if opts.ft ~= nil then vim.api.nvim_set_option_value('filetype', opts.ft, { buf = bufnr }) end

  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeBuffer.namespace, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { '' })
  vim.api.nvim_set_option_value('modifiable', opts.modifiable ~= false, { buf = bufnr })
  return bufnr
end

--- Build a centered, editor-bounded floating-window configuration.
---
--- The window is centered in the editor text area: tabline, statusline, and
--- command-line rows are excluded. Width and height are clamped to the
--- available text area (the outer border is not counted). Pass `tabpage` to
--- compute statusline rows for a specific tabpage.
---
---@param opts table|nil Geometry, border, title, and `tabpage` overrides.
---@return table config
LeetCodeBuffer.float_config = function(opts)
  opts = opts or {}
  -- Only center inside the editor text area. The tabline, statusline, and
  -- command line are part of the `editor` grid, so counting them would push
  -- the float down over the statusline.
  local top = tabline_rows()
  local bottom = (vim.o.cmdheight or 0) + statusline_rows(opts.tabpage)
  local available = math.max(1, vim.o.lines - top - bottom)

  local width = math.floor(opts.width or config.config.float_width)
  local height = math.floor(opts.height or config.config.float_height)
  width = math.max(1, math.min(width, vim.o.columns - 4))
  height = math.max(1, math.min(height, available - 4))

  local win_opts = {
    relative = 'editor',
    row = top + math.max(0, math.floor((available - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = 'minimal',
    focusable = true,
  }

  local border = opts.border
  if border == nil then border = config.config.float_border end
  if border ~= nil then win_opts.border = border end
  if opts.title ~= nil then
    win_opts.title = opts.title
    win_opts.title_pos = 'center'
  end
  return win_opts
end

--- Open a centered floating window for a buffer.
---
---@param bufnr number
---@param opts table|nil Options accepted by |LeetCodeBuffer.float_config()|,
--- plus `focus` for initial window focus.
---@return number winid
LeetCodeBuffer.open_float = function(bufnr, opts)
  opts = opts or {}
  return vim.api.nvim_open_win(bufnr, opts.focus ~= false, LeetCodeBuffer.float_config(opts))
end

--- Write `{ text, hl }` spans into a buffer.
---
--- The buffer is temporarily made modifiable and its previous state is
--- restored afterwards, so read-only buffers stay read-only.
---
---@param bufnr number
---@param lines table Array of lines, each an array of `{ text, hl }` spans.
LeetCodeBuffer.spans_write = function(bufnr, lines)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local was_modifiable = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  if not was_modifiable then vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr }) end

  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeBuffer.namespace, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, LeetCodeBuffer.spans_to_texts(lines))

  for lnum, line in ipairs(lines) do
    local col = 0
    for _, span in ipairs(line) do
      local width = #span.text
      if span.hl ~= nil and width > 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, LeetCodeBuffer.namespace, lnum - 1, col, {
          end_col = col + width,
          hl_group = span.hl,
          priority = 80,
        })
      end
      col = col + width
    end
  end

  if not was_modifiable then vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr }) end
end

--- Convert span lines into plain text lines.
---
---@param lines table Array of lines, each an array of `{ text, hl }` spans.
---@return table texts
LeetCodeBuffer.spans_to_texts = function(lines)
  local texts = {}
  for _, spans in ipairs(lines) do
    local parts = {}
    for _, span in ipairs(spans) do
      table.insert(parts, span.text)
    end
    table.insert(texts, table.concat(parts))
  end
  return texts
end

--- Write plain text lines into a buffer.
---
---@param bufnr number
---@param lines table
LeetCodeBuffer.lines_write = function(bufnr, lines)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local was_modifiable = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  if not was_modifiable then vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr }) end
  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeBuffer.namespace, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  if not was_modifiable then vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr }) end
end

--- Delete a buffer if it is still valid.
---
---@param bufnr number|nil
LeetCodeBuffer.maybe_delete = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then return end
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end

return LeetCodeBuffer
