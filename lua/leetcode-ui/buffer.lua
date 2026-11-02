--- *leetcode-ui-buffer* Buffer and span helpers
---
--- Shared plumbing for the central UI and the code editor:
--- scratch buffer creation, window creation, and `{ text, hl }` span rendering
--- via |nvim_buf_set_extmark()|.
---
---@tag LeetCodeBuffer
---@toc_entry Buffer helpers

local LeetCodeBuffer = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeBuffer.ns = vim.api.nvim_create_namespace('leetcode-ui')

-- Helper functionality =============================================================================================

--- Create or reuse a scratch buffer.
---
---@param name string Unique buffer name.
---@param opts table|nil { listed = boolean, ft = string, modifiable = boolean }
---@return number bufnr
LeetCodeBuffer.scratch = function(name, opts)
  opts = opts or {}

  local bufnr = vim.fn.bufnr(name)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(opts.listed == true, true)
    vim.api.nvim_buf_set_name(bufnr, name)
  end

  vim.api.nvim_set_option_value('buflisted', opts.listed == true, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })
  vim.api.nvim_set_option_value('swapfile', false, { buf = bufnr })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = bufnr })
  if opts.ft ~= nil then vim.api.nvim_set_option_value('filetype', opts.ft, { buf = bufnr }) end

  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeBuffer.ns, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { '' })
  vim.api.nvim_set_option_value('modifiable', opts.modifiable ~= false, { buf = bufnr })
  return bufnr
end

--- Open a centered floating window for a buffer.
---
---@param bufnr number
---@param opts table|nil { width = number, height = number, border = string, focus = boolean, title = string }
---@return number winid
LeetCodeBuffer.open_float = function(bufnr, opts)
  opts = opts or {}

  local width = opts.width or config.config.float_width
  local height = opts.height or config.config.float_height
  width = math.max(1, math.min(width, vim.o.columns - 4))
  height = math.max(1, math.min(height, vim.o.lines - 4))

  local win_opts = {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
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

  return vim.api.nvim_open_win(bufnr, opts.focus ~= false, win_opts)
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

  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeBuffer.ns, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, LeetCodeBuffer.spans_to_texts(lines))

  for lnum, line in ipairs(lines) do
    local col = 0
    for _, span in ipairs(line) do
      local width = #span.text
      if span.hl ~= nil and width > 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, LeetCodeBuffer.ns, lnum - 1, col, {
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

--- Delete a buffer if it is still valid.
---
---@param bufnr number|nil
LeetCodeBuffer.maybe_delete = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then return end
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end

return LeetCodeBuffer
