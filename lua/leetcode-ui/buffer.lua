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

-- Resolve `window.config` into a table. `window.config` may be a table or a
-- function returning a table, mirroring `mini.pick`. Invalid values are ignored.
local function normalize_border(value)
  if type(value) == 'string' and value:find(',', 1, true) then
    local parts = vim.split(value, ',', { plain = true })
    if #parts == 8 then return parts end
  end
  return value
end

local function window_override()
  local window = config.config.window or {}
  local value = window.config
  if type(value) == 'function' then
    local ok, result = pcall(value)
    if not ok or type(result) ~= 'table' then return {} end
    value = result
  end
  if type(value) ~= 'table' then return {} end
  return vim.deepcopy(value)
end

--- Build a centered, editor-bounded floating-window configuration.
---
--- The window is centered in the editor text area: tabline, statusline, and
--- command-line rows are excluded. Width and height are clamped to the
--- available text area (the outer border is not counted). When `float_width`
--- or `float_height` is unset, the default is 61.8% of the available area,
--- like `mini.pick`.
---
--- `window.config` is merged over the centered default. It may be a table or a
--- function returning a table and accepts a subset of |nvim_open_win()| keys:
--- `width`, `height`, `row`, `col`, `relative`, `anchor`, `border`, `style`,
--- `zindex`, `title`, `title_pos`, `focusable`, `noautocmd`, `win`, and
--- `bufpos`.
---
---@param opts table|nil Geometry, border, title, and `tabpage` overrides.
---@return table config
LeetCodeBuffer.float_config = function(opts)
  opts = opts or {}
  local user = window_override()
  local user_width = tonumber(user.width)
  local user_height = tonumber(user.height)
  local user_row = tonumber(user.row)
  local user_col = tonumber(user.col)
  user.width, user.height, user.row, user.col = nil, nil, nil, nil

  -- Only center inside the editor text area. The tabline, statusline, and
  -- command line are part of the `editor` grid, so counting them would push
  -- the float down over the statusline.
  local top = tabline_rows()
  local bottom = (vim.o.cmdheight or 0) + statusline_rows(opts.tabpage)
  local available = math.max(1, vim.o.lines - top - bottom)

  local width = user_width or tonumber(opts.width) or tonumber(config.config.float_width)
  local height = user_height or tonumber(opts.height) or tonumber(config.config.float_height)
  if width == nil then width = math.floor(0.618 * vim.o.columns) end
  if height == nil then height = math.floor(0.618 * available) end
  width = math.floor(width)
  height = math.floor(height)
  width = math.max(1, math.min(width, vim.o.columns - 4))
  height = math.max(1, math.min(height, available - 4))

  local border = user.border
  if border == nil then border = opts.border end
  if border == nil then border = config.config.float_border end
  if border == nil then
    local winborder = vim.fn.exists('+winborder') == 1 and vim.o.winborder or ''
    if winborder ~= '' then
      border = nil
    else
      border = 'single'
    end
  end
  border = normalize_border(border)

  local relative = user.relative or 'editor'
  local anchor = type(user.anchor) == 'string' and user.anchor:upper() or 'NW'
  local row = user_row
  local col = user_col
  if row == nil and relative == 'editor' then
    row = top + math.max(0, math.floor((available - height) / 2))
    if anchor:sub(1, 1) == 'S' then row = row + height end
  end
  if col == nil and relative == 'editor' then
    col = math.max(0, math.floor((vim.o.columns - width) / 2))
    if anchor:sub(2, 2) == 'E' then col = col + width end
  end
  if row == nil and user.bufpos == nil then row = 0 end
  if col == nil and user.bufpos == nil then col = 0 end

  local win_opts = {
    relative = relative,
    anchor = anchor,
    width = width,
    height = height,
    style = 'minimal',
    focusable = true,
    border = border,
  }
  if row ~= nil then win_opts.row = row end
  if col ~= nil then win_opts.col = col end
  if opts.title ~= nil then win_opts.title = opts.title end

  win_opts = vim.tbl_deep_extend('force', win_opts, user)
  win_opts.border = normalize_border(win_opts.border)
  if win_opts.title == nil then
    win_opts.title_pos = nil
  elseif win_opts.title_pos == nil then
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
