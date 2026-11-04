-- Tests for leetcode-ui.ui central window.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
    post_case = function() helpers.reset_ui() end,
  },
})

T['window'] = new_set()

T['window']['ensure opens one reusable window'] = function()
  local ui = helpers.mod('ui')
  eq(ui.is_open(), false)
  local first = ui.ensure()
  local second = ui.ensure()
  eq(first, second)
  eq(ui.is_open(), true)
  eq(vim.api.nvim_win_get_buf(first), ui.panel())
  eq(vim.api.nvim_win_get_config(first).title, nil)
end

T['window']['panel is a read-only scratch buffer'] = function()
  local ui = helpers.mod('ui')
  local panel = ui.panel()
  eq(vim.api.nvim_get_option_value('buftype', { buf = panel }), 'nofile')
  eq(vim.api.nvim_get_option_value('modifiable', { buf = panel }), false)
  eq(vim.api.nvim_get_option_value('buflisted', { buf = panel }), false)
end

T['render'] = new_set()

T['render']['renders spans and keeps the panel read-only'] = function()
  local ui = helpers.mod('ui')
  local winid = ui.render({
    { { text = 'Title', hl = 'LeetCodeTitle' } },
    { { text = 'body', hl = 'LeetCodeDim' } },
  }, { number = false, wrap = true })
  local panel = ui.panel()
  local lines = vim.api.nvim_buf_get_lines(panel, 0, -1, false)
  eq(lines[1], 'Title')
  eq(lines[2], 'body')
  eq(vim.api.nvim_win_get_buf(winid), panel)
  eq(vim.api.nvim_get_option_value('modifiable', { buf = panel }), false)
  eq(vim.api.nvim_get_option_value('wrap', { win = winid }), true)
  eq(vim.api.nvim_get_option_value('number', { win = winid }), false)
end

T['render']['pad_top adds one empty line before the content'] = function()
  local ui = helpers.mod('ui')
  local winid = ui.render({ { { text = 'content' } } }, { pad_top = true })
  local lines = vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false)
  eq(vim.api.nvim_win_get_buf(winid), ui.panel())
  eq(lines[1], '')
  eq(lines[2], 'content')
end

T['render']['padding does not mutate lines or fold positions'] = function()
  local ui = helpers.mod('ui')
  local lines = {
    { { text = 'header' } },
    { { text = 'body' } },
  }
  local folds = { { start_line = 1, end_line = 2 } }
  local winid = ui.render(lines, {
    pad_top = true,
    folds = folds,
    foldenable = true,
    foldmethod = 'manual',
  })

  eq(#lines, 2)
  eq(folds, { { start_line = 1, end_line = 2 } })
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), { '', 'header', 'body' })
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(2) end), 2)
end

T['render']['applies closed folds with a status column'] = function()
  local ui = helpers.mod('ui')
  local winid = ui.render({
    { { text = 'header' } },
    { { text = 'body one' } },
    { { text = 'body two' } },
  }, {
    folds = { { start_line = 2, end_line = 3 } },
    foldenable = true,
    foldmethod = 'manual',
    foldcolumn = 1,
    statuscolumn = '%C ',
  })

  eq(vim.api.nvim_get_option_value('foldmethod', { win = winid }), 'manual')
  eq(vim.api.nvim_get_option_value('statuscolumn', { win = winid }), '%C ')
  eq(vim.api.nvim_get_option_value('foldcolumn', { win = winid }), '1')
  eq(vim.fn.foldclosed(2), 2)
  eq(vim.fn.foldclosedend(2), 3)
end

T['render']['does not pad by default'] = function()
  local ui = helpers.mod('ui')
  ui.render({ { { text = 'content' } } })
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false)[1], 'content')
end

T['render']['read-only views hide the cursor and highlight the active line'] = function()
  local ui = helpers.mod('ui')
  local original_guicursor = vim.o.guicursor
  local test_guicursor = 'a:block,c:ver50,ci:ver50,cr:ver50'
  vim.o.guicursor = test_guicursor
  MiniTest.finally(function()
    vim.o.guicursor = original_guicursor
    ui.close()
  end)
  local winid = ui.render({ { { text = 'content' } } }, { pad_top = true })

  eq(helpers.contains(vim.o.guicursor, 'a:LeetCodeCursor'), true)
  eq(helpers.contains(vim.o.guicursor, 'c:ver50'), true)
  eq(vim.api.nvim_get_option_value('cursorline', { win = winid }), true)
  local winhl = vim.api.nvim_get_option_value('winhighlight', { win = winid })
  eq(helpers.contains(winhl, 'CursorLine:LeetCodeCursorLine'), true)

  local code = helpers.mod('buffer').scratch('leetcode-ui://cursor-code', { ft = 'python' })
  ui.show(code, { cursorline = true })
  eq(vim.o.guicursor, test_guicursor)
  eq(vim.api.nvim_get_option_value('cursorline', { win = winid }), true)
  winhl = vim.api.nvim_get_option_value('winhighlight', { win = winid })
  eq(helpers.contains(winhl, 'CursorLine:LeetCodeCursorLine'), false)

  ui.close()
  eq(vim.o.guicursor, test_guicursor)
end

T['render']['shows another buffer in the same window'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  local code = buffer.scratch('leetcode-ui://ui-code', { ft = 'python' })
  local window = ui.show(code, { number = true, wrap = false })
  eq(vim.api.nvim_win_get_buf(window), code)
  eq(vim.api.nvim_win_get_buf(ui.ensure()), code)
  eq(vim.api.nvim_get_option_value('number', { win = window }), true)
  eq(vim.api.nvim_get_option_value('wrap', { win = window }), false)
  local winhl = vim.api.nvim_get_option_value('winhighlight', { win = window })
  eq(helpers.contains(winhl, 'Normal:LeetCodeNormalFloat'), true)
end

T['render']['accepts a normal background highlight'] = function()
  local ui = helpers.mod('ui')
  local code = helpers.mod('buffer').scratch('leetcode-ui://ui-code-normal', { ft = 'python' })
  local window = ui.show(code, { normal_hl = 'LeetCodeCodeNormal' })
  local winhl = vim.api.nvim_get_option_value('winhighlight', { win = window })
  eq(helpers.contains(winhl, 'Normal:LeetCodeCodeNormal'), true)
end

T['render']['applies topfill for virtual padding'] = function()
  local ui = helpers.mod('ui')
  local code = helpers.mod('buffer').scratch('leetcode-ui://ui-code-topfill', { ft = 'python' })
  local window = ui.show(code, { topfill = 1 })
  eq(vim.api.nvim_win_call(window, function() return vim.fn.winsaveview() end).topfill, 1)
  ui.show(code, {})
  eq(vim.api.nvim_win_call(window, function() return vim.fn.winsaveview() end).topfill, 0)
end

T['render']['preserves code folds when no fold list is supplied'] = function()
  local ui = helpers.mod('ui')
  local code = helpers.mod('buffer').scratch('leetcode-ui://folds', { ft = 'lua' })
  vim.api.nvim_buf_set_lines(code, 0, -1, false, { 'one', 'two', 'three' })
  local winid = ui.show(code, { foldenable = true, foldmethod = 'manual' })
  vim.api.nvim_win_call(winid, function() vim.cmd('1,2fold') end)
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(1) end), 1)

  ui.show(code, { foldenable = true })
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(1) end), 1)
end

T['render']['rerendering with the same folds preserves user fold state'] = function()
  local ui = helpers.mod('ui')
  local lines = {}
  for index = 1, 6 do
    table.insert(lines, { { text = 'line ' .. index } })
  end
  local folds = { { start_line = 2, end_line = 4 } }
  local winid = ui.render(lines, { folds = folds, foldenable = true, foldmethod = 'manual' })
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(2) end), 2)

  vim.api.nvim_win_call(winid, function() vim.cmd('normal! zR') end)
  ui.render(lines, { folds = folds, foldenable = true, foldmethod = 'manual' })
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(2) end), -1)

  ui.render(lines, { folds = { { start_line = 1, end_line = 2 } }, foldenable = true, foldmethod = 'manual' })
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(1) end), 1)
end

T['render']['focus=false does not take focus when opening'] = function()
  local ui = helpers.mod('ui')
  local other = vim.api.nvim_get_current_win()
  ui.render({ { { text = 'content' } } }, { focus = false })
  eq(ui.is_open(), true)
  eq(vim.api.nvim_get_current_win(), other)
end

T['render']['automatic rerenders preserve viewport and focus'] = function()
  local ui = helpers.mod('ui')
  local lines = {}
  for index = 1, 100 do
    table.insert(lines, { { text = 'line ' .. index } })
  end

  local winid = ui.render(lines, { pad_top = true })
  vim.api.nvim_win_call(winid, function() vim.fn.winrestview({ lnum = 50, topline = 40 }) end)
  local other = vim.api.nvim_get_current_win()
  vim.cmd('new')
  local expected = vim.api.nvim_get_current_win()
  local expected_buf = vim.api.nvim_get_current_buf()
  MiniTest.finally(function()
    if vim.api.nvim_win_is_valid(expected) then vim.api.nvim_win_close(expected, true) end
    if vim.api.nvim_buf_is_valid(expected_buf) then vim.api.nvim_buf_delete(expected_buf, { force = true }) end
    if vim.api.nvim_win_is_valid(other) then vim.api.nvim_set_current_win(other) end
  end)
  ui.render(lines, { pad_top = true, focus = false })

  eq(vim.api.nvim_get_current_win(), expected)
  local view = vim.api.nvim_win_call(winid, vim.fn.winsaveview)
  eq(view.lnum, 50)
  eq(view.topline, 40)
end

T['render']['read-only wrapping uses word boundaries'] = function()
  local ui = helpers.mod('ui')
  local winid = ui.render({ { { text = 'a long line' } } }, { wrap = true })
  eq(vim.api.nvim_get_option_value('linebreak', { win = winid }), true)
  eq(vim.api.nvim_get_option_value('breakindent', { win = winid }), true)
end

T['window']['recenters and clamps the float on editor resize'] = function()
  helpers.configure({ float_width = 40, float_height = 10 })
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  local columns = vim.o.columns
  MiniTest.finally(function() vim.o.columns = columns end)
  vim.o.columns = 30
  vim.api.nvim_exec_autocmds('VimResized', {})
  eq(vim.api.nvim_win_get_width(winid), 26)
  eq(vim.api.nvim_win_get_config(winid).col, 2)
end

T['winbar'] = new_set()

T['winbar']['render clears a stale winbar'] = function()
  local ui = helpers.mod('ui')
  ui.ensure()
  ui.set_winbar(' Question tabs ')
  ui.render({ { { text = 'statistics' } } })
  eq(vim.api.nvim_get_option_value('winbar', { win = ui.state.winid }), '')
end

T['winbar']['sets the winbar while open'] = function()
  local ui = helpers.mod('ui')
  ui.set_winbar(' no window ')
  eq(pcall(ui.set_winbar, 'ignored'), true)
  ui.ensure()
  ui.set_winbar(' LeetCode ')
  eq(vim.api.nvim_get_option_value('winbar', { win = ui.state.winid }), ' LeetCode ')
end

T['close'] = new_set()

T['close']['closes and can reopen'] = function()
  local ui = helpers.mod('ui')
  local first = ui.ensure()
  ui.close()
  eq(ui.is_open(), false)
  eq(vim.api.nvim_win_is_valid(first), false)

  local second = ui.ensure()
  eq(ui.is_open(), true)
  eq(second ~= first, true)
end

return T
