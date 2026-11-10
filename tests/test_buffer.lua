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

T['scratch']['does not reuse a prefix-matched buffer name'] = function()
  local buffer = helpers.mod('buffer')
  local longer = buffer.scratch('leetcode-ui://question/two-sum-ii', { modifiable = true })
  vim.api.nvim_buf_set_lines(longer, 0, -1, true, { 'longer' })
  local shorter = buffer.scratch('leetcode-ui://question/two-sum', { modifiable = true })

  eq(longer ~= shorter, true)
  eq(vim.api.nvim_buf_get_name(longer), 'leetcode-ui://question/two-sum-ii')
  eq(vim.api.nvim_buf_get_name(shorter), 'leetcode-ui://question/two-sum')
  eq(vim.api.nvim_buf_get_lines(longer, 0, -1, false), { 'longer' })
end

T['scratch']['finds exact names regardless of listed prefix matches'] = function()
  local buffer = helpers.mod('buffer')
  local exact = buffer.scratch('leetcode-ui://x', { listed = false })
  buffer.scratch('leetcode-ui://x-long', { listed = true })
  eq(buffer.scratch('leetcode-ui://x', { listed = false }), exact)
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
  helpers.preserve_layout()
  vim.o.showtabline = 1
  vim.o.laststatus = 2
  vim.o.cmdheight = 1

  local config = buffer.float_config({ width = 10000, height = 10000 })
  eq(config.width, 96)
  eq(config.height, 34)
  eq(config.row, 2)
  eq(config.col, 2)
end

T['windows']['float_config uses a mini.pick-like centered default'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1

  local config = buffer.float_config({})
  eq(config.width, 61)
  eq(config.height, 22)
  eq(config.row, 8)
  eq(config.col, 19)
  eq(config.relative, 'editor')
  eq(config.anchor, 'NW')
end

T['windows']['float_config merges window.config overrides'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  helpers.configure({ window = { config = { width = 20, height = 10, border = 'rounded' } } })

  local config = buffer.float_config({})
  eq(config.width, 20)
  eq(config.height, 10)
  eq(config.row, 14)
  eq(config.col, 40)
  eq(config.border, 'rounded')
end

T['windows']['float_config accepts a callable window.config'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  helpers.configure({
    window = {
      config = function() return { width = 20, height = 10, row = 3, col = 4, style = 'minimal' } end,
    },
  })

  local config = buffer.float_config({})
  eq(config.width, 20)
  eq(config.height, 10)
  eq(config.row, 3)
  eq(config.col, 4)
end

T['windows']['float_config honors anchor when centering'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  helpers.configure({ window = { config = { width = 20, height = 10, anchor = 'SW' } } })
  local sw = buffer.float_config({})
  eq(sw.row, 24)
  eq(sw.col, 40)

  helpers.configure({ window = { config = { width = 20, height = 10, anchor = 'NE' } } })
  local ne = buffer.float_config({})
  eq(ne.row, 14)
  eq(ne.col, 60)

  helpers.configure({ window = { config = { width = 20, height = 10, anchor = 'se' } } })
  local se = buffer.float_config({})
  eq(se.row, 24)
  eq(se.col, 60)
end

T['windows']['float_config ignores invalid callable configs'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  helpers.configure({ window = { config = function() error('boom') end } })
  eq(buffer.float_config({}).width, 61)
  helpers.configure({ window = { config = function() return 'bad' end } })
  eq(buffer.float_config({}).width, 61)
end

T['windows']['window.config overrides legacy geometry'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  helpers.configure({
    float_width = 10,
    float_height = 5,
    float_border = 'none',
    window = { config = { width = 20, height = 8, border = 'rounded' } },
  })
  local config = buffer.float_config({})
  eq(config.width, 20)
  eq(config.height, 8)
  eq(config.border, 'rounded')
end

T['windows']['float_config clamps oversized window.config'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  helpers.configure({ window = { config = { width = 10000, height = 10000 } } })
  local config = buffer.float_config({})
  eq(config.width, vim.o.columns - 4)
end

T['windows']['float_config honors winborder and custom border lists'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()
  if vim.fn.exists('+winborder') == 0 then return end
  local original = vim.o.winborder
  MiniTest.finally(function() vim.o.winborder = original end)
  vim.o.winborder = '+,-,+,|,+,-,+,|'
  eq(buffer.float_config({}).border, nil)
  vim.o.winborder = ''
  eq(buffer.float_config({ border = '+,-,+,|,+,-,+,|' }).border, { '+', '-', '+', '|', '+', '-', '+', '|' })
end

T['windows']['window.config normalizes comma borders'] = function()
  local buffer = helpers.mod('buffer')
  helpers.configure({ window = { config = { border = '+,-,+,|,+,-,+,|' } } })
  eq(buffer.float_config({}).border, { '+', '-', '+', '|', '+', '-', '+', '|' })
end

T['windows']['float_config drops title_pos without a title'] = function()
  local buffer = helpers.mod('buffer')
  helpers.configure({ window = { config = { title_pos = 'left' } } })
  eq(buffer.float_config({}).title_pos, nil)
end

T['windows']['float_config reserves a statusline for multiple real windows'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()

  vim.o.showtabline = 1
  vim.o.laststatus = 1
  vim.o.cmdheight = 1
  vim.cmd('split')
  MiniTest.finally(function() vim.cmd('silent! only') end)

  local config = buffer.float_config({ width = 10, height = 5 })
  eq(config.row, 16)
end

T['windows']['float_config centers between the tabline and statusline'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()

  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1

  local config = buffer.float_config({ width = 10, height = 5 })
  eq(config.row, 17)
end

T['windows']['float_config ignores floating windows for laststatus=1'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()

  vim.o.showtabline = 1
  vim.o.laststatus = 1
  vim.o.cmdheight = 1

  local winid = buffer.open_float(buffer.scratch('leetcode-ui://float-laststatus'), { width = 10, height = 5 })
  MiniTest.finally(function() pcall(vim.api.nvim_win_close, winid, true) end)

  -- The open float must not be treated as a second window needing a statusline.
  local config = buffer.float_config({ width = 10, height = 5 })
  eq(config.row, 17)
end

T['windows']['float_config handles laststatus=3 and cmdheight=0'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()

  vim.o.showtabline = 1
  vim.o.cmdheight = 1
  vim.o.laststatus = 3
  eq(buffer.float_config({ width = 10, height = 5 }).row, 16)

  vim.o.cmdheight = 0
  vim.o.laststatus = 2
  eq(buffer.float_config({ width = 10, height = 5 }).row, 17)
end

T['windows']['float_config reserves a tabline when any UI is internal'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()

  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  helpers.with_field(
    vim.api,
    'nvim_list_uis',
    function() return { { ext_tabline = true }, { ext_tabline = false } } end,
    function() eq(buffer.float_config({ width = 10, height = 5 }).row, 17) end
  )
end

T['windows']['float_config uses the requested tabpage window count'] = function()
  local buffer = helpers.mod('buffer')
  local original = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus, cmdheight = vim.o.cmdheight }
  MiniTest.finally(function()
    vim.o.showtabline = original.showtabline
    vim.o.laststatus = original.laststatus
    vim.o.cmdheight = original.cmdheight
    vim.cmd('silent! tabonly')
  end)

  vim.o.showtabline = 1
  vim.o.laststatus = 1
  vim.o.cmdheight = 1
  local first = vim.api.nvim_get_current_tabpage()
  vim.cmd('split')
  vim.cmd('tabnew')
  local second = vim.api.nvim_get_current_tabpage()

  eq(buffer.float_config({ width = 10, height = 4, tabpage = first }).row, 17)
  eq(buffer.float_config({ width = 10, height = 4, tabpage = second }).row, 18)
end

T['windows']['float_config ignores externalized tablines'] = function()
  local buffer = helpers.mod('buffer')
  helpers.preserve_layout()

  vim.o.showtabline = 2
  vim.o.laststatus = 2
  vim.o.cmdheight = 1

  helpers.with_field(vim.api, 'nvim_list_uis', function() return { { ext_tabline = true } } end, function()
    local config = buffer.float_config({ width = 10, height = 5 })
    eq(config.row, 16)
  end)
end

T['windows']['float_config checks external tablines before showtabline=1'] = function()
  local buffer = helpers.mod('buffer')
  local original = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus, cmdheight = vim.o.cmdheight }
  MiniTest.finally(function()
    vim.o.showtabline = original.showtabline
    vim.o.laststatus = original.laststatus
    vim.o.cmdheight = original.cmdheight
    vim.cmd('silent! tabonly')
  end)

  vim.o.showtabline = 1
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  vim.cmd('tabnew')

  helpers.with_field(vim.api, 'nvim_list_uis', function() return { { ext_tabline = true } } end, function()
    local config = buffer.float_config({ width = 10, height = 5 })
    eq(config.row, 16)
  end)
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
