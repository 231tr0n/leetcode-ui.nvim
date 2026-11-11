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

local function mock_render_markdown(state)
  state = state or {}
  state.enabled = state.enabled ~= false
  local original = package.loaded['render-markdown']
  local original_preload = package.preload['render-markdown']
  package.loaded['render-markdown'] = {
    get = function(buf)
      state.get_buf = buf
      return state.enabled
    end,
    render = function(opts) state.rendered = opts.buf end,
    buf_disable = function() state.enabled = false end,
    buf_enable = function() state.enabled = true end,
  }
  MiniTest.finally(function()
    package.loaded['render-markdown'] = original
    package.preload['render-markdown'] = original_preload
  end)
  return state
end

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

T['window']['applies window.config and resizes on setup'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  helpers.configure({ window = { config = { width = 30, height = 8, border = 'rounded' } } })
  local winid = ui.ensure()
  local first = vim.api.nvim_win_get_config(winid)
  eq(first.width, 30)
  eq(first.height, 8)
  eq(type(first.border), 'table')
  eq(first.border[1], '╭')
  local expected = buffer.float_config({})
  eq(first.row, expected.row)
  eq(first.col, expected.col)

  helpers.configure({ window = { config = { width = 40, height = 10 } } })
  local resized = vim.api.nvim_win_get_config(winid)
  eq(resized.width, 40)
  eq(resized.height, 10)
  expected = buffer.float_config({})
  eq(resized.row, expected.row)
  eq(resized.col, expected.col)
end

T['window']['resizes with creation-only window config keys'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  helpers.configure({ window = { config = { width = 30, height = 8, noautocmd = true } } })
  local winid = ui.ensure()
  local cmdheight = vim.o.cmdheight
  MiniTest.finally(function() vim.o.cmdheight = cmdheight end)
  vim.o.cmdheight = 3
  ui.resize()
  local config = vim.api.nvim_win_get_config(winid)
  local expected = buffer.float_config({})
  eq(config.row, expected.row)
  eq(config.col, expected.col)
end

T['window']['does not reposition non-editor relative windows on resize'] = function()
  local ui = helpers.mod('ui')
  helpers.configure({ window = { config = { relative = 'cursor', width = 30, height = 8 } } })
  local winid = ui.ensure()
  local before = vim.api.nvim_win_get_config(winid)
  ui.resize()
  local after = vim.api.nvim_win_get_config(winid)
  eq(after.row, before.row)
  eq(after.col, before.col)
  eq(after.width, before.width)
  eq(after.height, before.height)
end

T['window']['opens with a custom winborder'] = function()
  if vim.fn.exists('+winborder') == 0 then return end
  local original = vim.o.winborder
  MiniTest.finally(function() vim.o.winborder = original end)
  vim.o.winborder = '+,-,+,|,+,-,+,|'
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  eq(vim.api.nvim_win_is_valid(winid), true)
end

T['window']['enables mini.clue triggers once for unlisted buffers'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  local original = rawget(_G, 'MiniClue')
  local seen = {}
  _G.MiniClue = {
    ensure_buf_triggers = function(bufnr) table.insert(seen, bufnr) end,
  }
  MiniTest.finally(function() _G.MiniClue = original end)

  local lines = { { { text = 'content' } } }
  ui.render(lines)
  ui.render(lines)
  eq(#seen, 1)
  eq(seen[1], ui.panel())

  _G.MiniClue.config = {}
  ui.render(lines)
  eq(#seen, 2)

  -- Listed buffers are managed by mini.clue itself.
  local code = buffer.scratch('leetcode-ui://clue-code', { ft = 'lua', listed = true })
  ui.show(code, {})
  eq(vim.tbl_contains(seen, code), false)
end

T['window']['ignores missing or failing mini.clue integrations'] = function()
  local ui = helpers.mod('ui')
  local original = rawget(_G, 'MiniClue')
  MiniTest.finally(function() _G.MiniClue = original end)

  _G.MiniClue = nil
  eq(pcall(ui.render, { { { text = 'content' } } }), true)

  _G.MiniClue = { ensure_buf_triggers = function() error('boom') end }
  ui.close()
  eq(pcall(ui.render, { { { text = 'content' } } }), true)

  local seen = {}
  _G.MiniClue = { ensure_buf_triggers = function(bufnr) table.insert(seen, bufnr) end }
  ui.render({ { { text = 'content' } } })
  eq(vim.tbl_contains(seen, ui.panel()), true)
end

T['window']['re-enables mini.clue triggers after recording'] = function()
  local ui = helpers.mod('ui')
  local original = rawget(_G, 'MiniClue')
  local seen = {}
  _G.MiniClue = {
    config = {},
    ensure_buf_triggers = function(bufnr) table.insert(seen, bufnr) end,
  }
  MiniTest.finally(function() _G.MiniClue = original end)

  ui.render({ { { text = 'content' } } })
  eq(#seen, 1)
  vim.api.nvim_exec_autocmds('RecordingLeave', {})
  eq(helpers.wait_for(function() return #seen == 2 end), true)
  eq(#seen, 2)
end

T['window']['does not cache mini.clue triggers while disabled'] = function()
  local ui = helpers.mod('ui')
  local original = rawget(_G, 'MiniClue')
  local seen = {}
  _G.MiniClue = {
    config = {},
    ensure_buf_triggers = function(bufnr) table.insert(seen, bufnr) end,
  }
  vim.g.miniclue_disable = true
  MiniTest.finally(function()
    _G.MiniClue = original
    vim.g.miniclue_disable = nil
  end)

  ui.render({ { { text = 'content' } } })
  eq(#seen, 0)
  vim.g.miniclue_disable = false
  vim.b[ui.panel()].miniclue_disable = true
  ui.render({ { { text = 'content' } } })
  eq(#seen, 0)
  vim.b[ui.panel()].miniclue_disable = nil
  ui.render({ { { text = 'content' } } })
  eq(#seen, 1)
end

T['window']['resize uses the float tab rather than the current tab'] = function()
  helpers.configure({ float_width = 40, float_height = 9 })
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  local original = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus, cmdheight = vim.o.cmdheight }
  MiniTest.finally(function()
    vim.o.showtabline = original.showtabline
    vim.o.laststatus = original.laststatus
    vim.o.cmdheight = original.cmdheight
    if ui.is_open() then ui.close() end
    vim.cmd('silent! tabonly')
  end)

  vim.o.showtabline = 0
  vim.o.laststatus = 1
  vim.o.cmdheight = 1
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'laststatus' })
  eq(vim.api.nvim_win_get_config(winid).row, 15)

  vim.cmd('tabnew')
  vim.cmd('split')
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'laststatus' })
  eq(vim.api.nvim_win_get_config(winid).row, 15)
end

T['window']['recenters when showtabline or cmdheight changes'] = function()
  helpers.configure({ float_width = 40, float_height = 9 })
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  local original = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus, cmdheight = vim.o.cmdheight }
  MiniTest.finally(function()
    vim.o.showtabline = original.showtabline
    vim.o.laststatus = original.laststatus
    vim.o.cmdheight = original.cmdheight
    if ui.is_open() then ui.close() end
  end)

  vim.o.showtabline = 1
  vim.o.laststatus = 2
  vim.o.cmdheight = 1
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'showtabline' })
  eq(vim.api.nvim_win_get_config(winid).row, 14)

  vim.o.showtabline = 2
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'showtabline' })
  eq(vim.api.nvim_win_get_config(winid).row, 15)

  vim.o.cmdheight = 2
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'cmdheight' })
  eq(vim.api.nvim_win_get_config(winid).row, 14)
end

T['window']['markdown_enabled respects config and renderer state'] = function()
  local ui = helpers.mod('ui')
  local original = package.loaded['render-markdown']
  local original_preload = package.preload['render-markdown']
  MiniTest.finally(function()
    package.loaded['render-markdown'] = original
    package.preload['render-markdown'] = original_preload
  end)

  helpers.configure({ markdown = false })
  eq(ui.markdown_enabled(), false)

  helpers.configure({ markdown = true })
  package.loaded['render-markdown'] = nil
  package.preload['render-markdown'] = function() error('not installed') end
  eq(ui.markdown_enabled(), false)

  package.preload['render-markdown'] = original_preload
  package.loaded['render-markdown'] = { get = function() return true end }
  eq(ui.markdown_enabled(), true)

  package.loaded['render-markdown'] = { get = function() return false end }
  eq(ui.markdown_enabled(), false)

  package.loaded['render-markdown'] = { get = function() return nil end }
  eq(ui.markdown_enabled(), false)

  package.loaded['render-markdown'] = {}
  eq(ui.markdown_enabled(), true)

  package.loaded['render-markdown'] = { get = function() error('boom') end }
  eq(ui.markdown_enabled(), false)
end

T['window']['recenters after closing a split with laststatus=1'] = function()
  helpers.configure({ float_width = 40, float_height = 9 })
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  local normal
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(window).relative == '' then
      normal = window
      break
    end
  end
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if window ~= winid and window ~= normal then pcall(vim.api.nvim_win_close, window, true) end
  end
  local original = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus, cmdheight = vim.o.cmdheight }
  MiniTest.finally(function()
    vim.o.showtabline = original.showtabline
    vim.o.laststatus = original.laststatus
    vim.o.cmdheight = original.cmdheight
    if ui.is_open() then ui.close() end
    vim.cmd('silent! only')
  end)

  vim.o.showtabline = 0
  vim.o.laststatus = 1
  vim.o.cmdheight = 1
  vim.api.nvim_set_current_win(normal)
  vim.cmd('split')
  local split_win = vim.api.nvim_get_current_win()
  local before = vim.api.nvim_win_get_config(winid).row
  vim.api.nvim_win_close(split_win, true)

  eq(helpers.wait_for(function() return vim.api.nvim_win_get_config(winid).row == 15 end), true)
  eq(vim.api.nvim_win_get_config(winid).row, 15)
  eq(before, 14)
end

T['window']['recenters when layout options change'] = function()
  helpers.configure({ float_width = 40, float_height = 9 })
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  local original = { laststatus = vim.o.laststatus, number = vim.o.number }
  MiniTest.finally(function()
    vim.o.laststatus = original.laststatus
    vim.o.number = original.number
  end)

  local before = vim.api.nvim_win_get_config(winid).row
  vim.o.laststatus = original.laststatus == 0 and 2 or 0
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'laststatus' })
  eq(vim.api.nvim_win_get_config(winid).row, 15)
  eq(before, 14)

  local row = vim.api.nvim_win_get_config(winid).row
  local buffer = helpers.mod('buffer')
  local real_float_config = buffer.float_config
  local calls = 0
  helpers.with_stub('leetcode-ui.buffer', 'float_config', function(opts)
    calls = calls + 1
    return real_float_config(opts)
  end, function()
    vim.o.number = not vim.o.number
    vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'number' })
  end)
  eq(vim.api.nvim_win_get_config(winid).row, row)
  eq(calls, 0)
end

T['window']['recenters when tabs are opened and closed'] = function()
  helpers.configure({ float_width = 40, float_height = 8 })
  local ui = helpers.mod('ui')
  local winid = ui.ensure()
  local original = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus, cmdheight = vim.o.cmdheight }
  MiniTest.finally(function()
    vim.o.showtabline = original.showtabline
    vim.o.laststatus = original.laststatus
    vim.o.cmdheight = original.cmdheight
    if ui.is_open() then ui.close() end
    vim.cmd('silent! tabonly')
  end)

  vim.o.showtabline = 1
  vim.o.laststatus = 0
  vim.o.cmdheight = 1
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'laststatus' })
  eq(vim.api.nvim_win_get_config(winid).row, 15)

  vim.cmd('tabnew')
  eq(helpers.wait_for(function() return vim.api.nvim_win_get_config(winid).row == 16 end), true)
  vim.cmd('tabclose')
  eq(helpers.wait_for(function() return vim.api.nvim_win_get_config(winid).row == 15 end), true)
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
  local test_guicursor = 'n-v-c-sm:block,c:ver50-iCursor-blinkon50,ci:ver50,cr:ver50'
  vim.o.guicursor = test_guicursor
  MiniTest.finally(function()
    vim.o.guicursor = original_guicursor
    ui.close()
  end)
  local winid = ui.render({ { { text = 'content' } } }, { pad_top = true })

  eq(helpers.contains(vim.o.guicursor, 'n-v-ve-o-i-r-sm:LeetCodeCursor'), true)
  eq(helpers.contains(vim.o.guicursor, 'c:ver50-iCursor-blinkon50'), true)
  eq(helpers.contains(vim.o.guicursor, 'ci:ver50'), true)
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

T['render']['restores the cursor when leaving the central window'] = function()
  local ui = helpers.mod('ui')
  local original_guicursor = vim.o.guicursor
  local test_guicursor = 'a:block,c:ver50,ci:ver50,cr:ver50'
  vim.o.guicursor = test_guicursor
  MiniTest.finally(function()
    vim.o.guicursor = original_guicursor
    ui.close()
  end)

  ui.render({ { { text = 'content' } } })
  eq(helpers.contains(vim.o.guicursor, 'n-v-ve-o-i-r-sm:LeetCodeCursor'), true)

  vim.cmd('new')
  local other_win = vim.api.nvim_get_current_win()
  local other_buf = vim.api.nvim_get_current_buf()
  MiniTest.finally(function()
    if vim.api.nvim_win_is_valid(other_win) then pcall(vim.api.nvim_win_close, other_win, true) end
    pcall(vim.api.nvim_buf_delete, other_buf, { force = true })
  end)
  eq(vim.o.guicursor, test_guicursor)

  vim.api.nvim_set_current_win(ui.state.winid)
  eq(helpers.contains(vim.o.guicursor, 'n-v-ve-o-i-r-sm:LeetCodeCursor'), true)
end

T['render']['handles an empty guicursor'] = function()
  local ui = helpers.mod('ui')
  local original_guicursor = vim.o.guicursor
  vim.o.guicursor = ''
  MiniTest.finally(function()
    vim.o.guicursor = original_guicursor
    ui.close()
  end)

  ui.render({ { { text = 'content' } } })
  eq(helpers.contains(vim.o.guicursor, 'n-v-ve-o-i-r-sm:LeetCodeCursor'), true)
  ui.close()
  eq(vim.o.guicursor, '')
end

T['render']['applies render-markdown to markdown views'] = function()
  local ui = helpers.mod('ui')
  local original = package.loaded['render-markdown']
  local rendered = nil
  local enabled = true
  local get_buf = nil
  package.loaded['render-markdown'] = {
    get = function(buf)
      get_buf = buf
      return enabled
    end,
    render = function(opts) rendered = opts.buf end,
    buf_disable = function() enabled = false end,
    buf_enable = function() enabled = true end,
  }
  MiniTest.finally(function()
    package.loaded['render-markdown'] = original
    ui.close()
  end)

  ui.render_markdown('# Title')
  eq(helpers.wait_for(function() return rendered ~= nil end), true)
  eq(rendered, ui.panel())
  eq(get_buf, ui.panel())

  enabled = false
  rendered = nil
  ui.render_markdown('# External re-enable')
  eq(enabled, true)
  eq(helpers.wait_for(function() return rendered ~= nil end), true)

  ui.render({ { { text = 'plain' } } })
  eq(enabled, false)
  rendered = nil
  ui.render_markdown('# Title again')
  eq(enabled, true)
  eq(helpers.wait_for(function() return rendered ~= nil end), true)
  eq(rendered, ui.panel())
end

T['render']['resets conceal options when leaving markdown'] = function()
  local ui = helpers.mod('ui')
  mock_render_markdown()
  local winid = ui.render_markdown('# Title')
  vim.api.nvim_set_option_value('conceallevel', 3, { win = winid })
  vim.api.nvim_set_option_value('concealcursor', 'n', { win = winid })
  ui.render({ { { text = 'plain' } } })
  eq(vim.api.nvim_get_option_value('conceallevel', { win = winid }), 0)
  eq(vim.api.nvim_get_option_value('concealcursor', { win = winid }), '')
end

T['render']['skips a scheduled markdown render after switching views'] = function()
  local ui = helpers.mod('ui')
  local state = mock_render_markdown()

  ui.render_markdown('# Title')
  ui.render({ { { text = 'plain' } } })
  local first_done = false
  vim.schedule(function() first_done = true end)
  eq(vim.wait(1000, function() return first_done end), true)
  eq(state.rendered, nil)

  local other = helpers.mod('buffer').scratch('leetcode-ui://markdown-other', { ft = 'markdown' })
  ui.render_markdown('# Title again')
  ui.show(other, {})
  local second_done = false
  vim.schedule(function() second_done = true end)
  eq(vim.wait(1000, function() return second_done end), true)
  eq(state.rendered, nil)
end

T['render']['resets conceal when showing a code buffer'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  mock_render_markdown()
  local winid = ui.render_markdown('# Title')
  vim.api.nvim_set_option_value('conceallevel', 3, { win = winid })
  vim.api.nvim_set_option_value('concealcursor', 'n', { win = winid })
  local code = buffer.scratch('leetcode-ui://conceal-code', { ft = 'lua' })
  ui.show(code, {})
  eq(vim.api.nvim_get_option_value('conceallevel', { win = winid }), 0)
  eq(vim.api.nvim_get_option_value('concealcursor', { win = winid }), '')
end

T['render']['shifts markdown folds for top padding'] = function()
  local ui = helpers.mod('ui')
  mock_render_markdown()
  local winid = ui.render_markdown('one\ntwo', {
    folds = { { start_line = 1, end_line = 2 } },
    foldenable = true,
    foldmethod = 'manual',
  })
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(2) end), 2)
end

T['render']['skips fold shifting without top padding'] = function()
  local ui = helpers.mod('ui')
  mock_render_markdown()
  local winid = ui.render_markdown('one\ntwo', {
    pad_top = false,
    folds = { { start_line = 1, end_line = 2 } },
    foldenable = true,
    foldmethod = 'manual',
  })
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false)[1], 'one')
  eq(vim.api.nvim_win_call(winid, function() return vim.fn.foldclosed(1) end), 1)
end

T['render']['renders markdown and resets the panel filetype'] = function()
  local ui = helpers.mod('ui')
  mock_render_markdown()
  local winid = ui.render_markdown('# Title\n\nbody', { pad_top = true })
  eq(vim.api.nvim_get_option_value('filetype', { buf = ui.panel() }), 'markdown')
  eq(vim.api.nvim_win_get_buf(winid), ui.panel())
  eq(vim.api.nvim_win_get_cursor(winid)[1], 1)
  local lines = vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false)
  eq(lines[1], '')
  eq(lines[2], '# Title')
  eq(lines[4], 'body')
  eq(lines[5], '')

  ui.render({ { { text = 'plain' } } })
  eq(vim.api.nvim_get_option_value('filetype', { buf = ui.panel() }), 'txt')
end

T['render']['formats markdown through the configured formatter'] = function()
  local ui = helpers.mod('ui')
  mock_render_markdown()
  local seen = nil
  helpers.configure({
    formatter = function(text, filetype)
      seen = { text = text, filetype = filetype }
      if filetype == 'markdown' then return '# formatted' end
      return nil
    end,
  })
  ui.render_markdown('# raw', { pad_top = false })
  assert(seen ~= nil)
  eq(seen.filetype, 'markdown')
  eq(seen.text, '# raw')
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false)[1], '# formatted')
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
