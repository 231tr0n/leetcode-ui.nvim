--- *LeetCodeBuffer*
---
---@tag LeetCodeBuffer

-- |leetcode-ui-buffer| Buffer lifecycle, window, and rendering helpers.
-- Shared plumbing for the UI modules:
--   - scratch `nofile` buffer creation with sane defaults,
--   - split window management,
--   - `{ text, hl }` span rendering via |nvim_buf_set_extmark()|,
--   - buffer-local keymaps honoring |leetcode-ui-opt.keys|.

-- Module design:
local LeetCodeBuffer = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeBuffer.ns = vim.api.nvim_create_namespace('leetcode-ui')

-- Helper functionality =============================================================================================

LeetCodeBuffer.scratch = function(name, opts)
  opts = opts or {}

  local bufnr = vim.fn.bufnr(('%s'):format(name))
  if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_set_name(bufnr, name)
  else
    bufnr = vim.api.nvim_create_buf(opts.listed ~= false, false)
  end

  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_set_option_value('buflisted', false, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })
  vim.api.nvim_set_option_value('swapfile', false, { buf = bufnr })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = bufnr })
  if opts.ft ~= nil then vim.api.nvim_set_option_value('filetype', opts.ft, { buf = bufnr }) end

  vim.api.nvim_buf_clear_namespace(bufnr, LeetCodeBuffer.ns, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { '' })
  return bufnr
end

LeetCodeBuffer.open_split = function(bufnr, opts)
  opts = opts or {}

  local current = vim.api.nvim_get_current_win()
  local winid = vim.api.nvim_open_win(bufnr, false, {
    split = opts.pos == 'right' and 'right'
      or (opts.pos == 'below' and 'below' or (opts.pos == 'above' and 'above' or 'left')),
    win = current,
    width = opts.width or config.config.description_width,
    height = opts.height or 12,
  })

  if opts.focus == false then vim.api.nvim_set_current_win(current) end
  return winid
end

LeetCodeBuffer.close = function(winid)
  if winid == nil or not vim.api.nvim_win_is_valid(winid) then return end
  local bufnr = vim.api.nvim_win_get_buf(winid)
  pcall(vim.api.nvim_win_close, winid, false)
  if vim.api.nvim_get_option_value('buftype', { buf = bufnr }) == 'nofile' then
    pcall(vim.api.nvim_buf_delete, bufnr, { unload = false })
  end
end

LeetCodeBuffer.spans_write = function(bufnr, lines, modifiable)
  local was_ro = not vim.api.nvim_get_option_value('modifiable', { buf = bufnr })

  if modifiable ~= false or was_ro then vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr }) end

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

  if was_ro then vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr }) end
end

LeetCodeBuffer.spans_to_texts = function(lines)
  local res = {}
  for _, spans in ipairs(lines) do
    local texts = {}
    for _, span in ipairs(spans) do
      table.insert(texts, span.text)
    end
    table.insert(res, table.concat(texts))
  end
  return res
end

LeetCodeBuffer.keymap = function(bufnr, lhs, rhs, desc)
  return vim.keymap.set('n', lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
end

LeetCodeBuffer.keymaps = function(bufnr, mappings)
  local keys = config.config.keys
  for keys_name, spec in pairs(mappings) do
    local lhs = keys[keys_name]
    if lhs ~= nil then LeetCodeBuffer.keymap(bufnr, lhs, spec.rhs, spec.desc) end
  end
end

LeetCodeBuffer.maybe_delete = function(bufnr)
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { unload = false })
  end
end

return LeetCodeBuffer
