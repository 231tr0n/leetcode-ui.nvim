-- Tests for leetcode-ui.buffer.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['scratch'] = new_set()

T['scratch']['creates and reuses a buffer'] = function()
  local buffer = helpers.mod('buffer')
  local first = buffer.scratch('leetcode-ui://scratch', { ft = 'txt' })
  local second = buffer.scratch('leetcode-ui://scratch', { ft = 'txt' })
  eq(first, second)
  eq(vim.api.nvim_buf_is_valid(first), true)
  eq(vim.api.nvim_get_option_value('buftype', { buf = first }), 'nofile')
  eq(vim.api.nvim_get_option_value('swapfile', { buf = first }), false)
  eq(vim.api.nvim_get_option_value('filetype', { buf = first }), 'txt')
end

T['scratch']['respects listed and modifiable options'] = function()
  local buffer = helpers.mod('buffer')
  local listed = buffer.scratch('leetcode-ui://listed', { listed = true })
  eq(vim.api.nvim_get_option_value('buflisted', { buf = listed }), true)

  local readonly = buffer.scratch('leetcode-ui://readonly', { modifiable = false })
  eq(vim.api.nvim_get_option_value('modifiable', { buf = readonly }), false)
end

T['spans'] = new_set()

T['spans']['spans_to_texts concatenates spans'] = function()
  local buffer = helpers.mod('buffer')
  local lines = {
    { { text = 'a' }, { text = 'b' } },
    { { text = 'cd' } },
  }
  eq(buffer.spans_to_texts(lines)[1], 'ab')
  eq(buffer.spans_to_texts(lines)[2], 'cd')
end

T['spans']['spans_to_texts preserves empty lines'] = function()
  local buffer = helpers.mod('buffer')
  local texts = buffer.spans_to_texts({ { { text = 'x' } }, {} })
  eq(texts[1], 'x')
  eq(texts[2], '')
end

T['spans']['spans_write renders text and keeps read-only buffers read-only'] = function()
  local buffer = helpers.mod('buffer')
  local bufnr = buffer.scratch('leetcode-ui://write', { modifiable = false })
  buffer.spans_write(bufnr, {
    { { text = 'hello ', hl = 'LeetCodeTitle' }, { text = 'world' } },
    {},
    { { text = 'last', hl = 'LeetCodeCode' } },
  })
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  eq(lines[1], 'hello world')
  eq(lines[2], '')
  eq(lines[3], 'last')
  eq(vim.api.nvim_get_option_value('modifiable', { buf = bufnr }), false)

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, buffer.namespace, 0, -1, { details = true })
  eq(#marks, 2)
  eq(marks[1][4].hl_group, 'LeetCodeTitle')
end

T['spans']['spans_write ignores invalid buffers'] = function()
  local buffer = helpers.mod('buffer')
  local ok = pcall(buffer.spans_write, 999999, { { { text = 'x' } } })
  eq(ok, true)
end

T['windows'] = new_set()

T['windows']['float_config clamps geometry to the editor'] = function()
  local buffer = helpers.mod('buffer')
  local config = buffer.float_config({ width = 10000, height = 10000 })
  eq(config.width, math.max(1, vim.o.columns - 4))
  eq(config.height, math.max(1, vim.o.lines - 4))
  eq(config.row >= 0, true)
  eq(config.col >= 0, true)
end

T['windows']['float_config sets a centered title'] = function()
  local buffer = helpers.mod('buffer')
  local config = buffer.float_config({ title = ' Test ' })
  eq(config.title, ' Test ')
  eq(config.title_pos, 'center')
end

T['windows']['open_float creates a window'] = function()
  local buffer = helpers.mod('buffer')
  local bufnr = buffer.scratch('leetcode-ui://float')
  local winid = buffer.open_float(bufnr, { width = 20, height = 5, title = ' Test ' })
  eq(vim.api.nvim_win_is_valid(winid), true)
  eq(vim.api.nvim_win_get_buf(winid), bufnr)
  eq(vim.api.nvim_win_get_width(winid) <= vim.o.columns, true)
  eq(vim.api.nvim_win_get_config(winid).height, 5)
  vim.api.nvim_win_close(winid, true)
end

T['delete'] = new_set()

T['delete']['maybe_delete deletes valid buffers only'] = function()
  local buffer = helpers.mod('buffer')
  local bufnr = buffer.scratch('leetcode-ui://delete')
  buffer.maybe_delete(bufnr)
  eq(vim.api.nvim_buf_is_valid(bufnr), false)
  eq(pcall(buffer.maybe_delete, nil), true)
  eq(pcall(buffer.maybe_delete, bufnr), true)
end

return T
