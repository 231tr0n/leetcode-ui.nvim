-- Tests for leetcode-ui.commands.
---@diagnostic disable: duplicate-set-field
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
    post_case = function() helpers.reset_ui() end,
  },
})

local function make_view()
  local view = helpers.fake_view()
  view.code_bufnr = helpers.mod('buffer').scratch(('leetcode-ui://commands-%s'):format(view.slug), { ft = 'text' })
  helpers.fake_console(view, { 'a', 'b' })
  return view
end

local function stub_current(view)
  local question = require('leetcode-ui.question')
  local original = question.current
  question.current = function() return view end
  MiniTest.finally(function() question.current = original end)
  return function() question.current = original end
end

T['dispatch'] = new_set()

T['dispatch']['defaults to list'] = function()
  ---@type any
  local called = nil
  helpers.with_stub(
    'leetcode-ui.picker',
    'problem',
    function(opts) called = opts end,
    function() helpers.mod('commands').run({}) end
  )
  eq(type(called), 'table')
  eq(called.difficulty, nil)
end

T['dispatch']['reports unknown commands including question actions'] = function()
  helpers.configure({ notifications = true })
  for _, name in ipairs({ 'run', 'wat' }) do
    local messages = helpers.capture_notify(function() helpers.mod('commands').run({ name }) end)
    eq(#messages, 1)
    eq(helpers.contains(messages[1].message, 'Unknown command'), true)
  end

  local messages = helpers.capture_notify(function() helpers.mod('commands').run({ 'question', 'bogus' }) end)
  eq(#messages, 1)
  eq(helpers.contains(messages[1].message, 'Usage: :LeetCode question <subcommand>'), true)
end

T['dispatch']['rejects extra arguments for fixed-arity commands'] = function()
  local calls = {}
  helpers.with_stub('leetcode-ui.picker', 'daily', function() table.insert(calls, 'daily') end, function()
    helpers.with_stub('leetcode-ui.picker', 'problem', function() table.insert(calls, 'list') end, function()
      helpers.mod('commands').run({ 'daily', 'extra' })
      helpers.mod('commands').run({ 'list', 'Easy', 'extra' })
    end)
  end)
  eq(#calls, 0)
end

T['dispatch']['validates argument counts'] = function()
  local commands = helpers.mod('commands')
  eq(commands.validate_args({}, 0, 0, 'usage'), true)
  eq(commands.validate_args({ 'extra' }, 0, 0, 'usage'), false)
  eq(commands.validate_args({}, 1, 1, 'usage'), false)
  eq(commands.validate_args({ 'one' }, 0, 1, 'usage'), true)
  eq(commands.validate_args({ 'one', 'two' }, 0, 1, 'usage'), false)
  eq(commands.validate_args({ 'one', 'two' }, 2, nil, 'usage'), true)
end

T['list'] = new_set()

T['list']['passes a normalized difficulty'] = function()
  ---@type any
  local called = nil
  helpers.with_stub(
    'leetcode-ui.picker',
    'problem',
    function(opts) called = opts end,
    function() helpers.mod('commands').run({ 'list', 'hard' }) end
  )
  eq(called.difficulty, 'Hard')
end

T['list']['rejects invalid difficulties'] = function()
  helpers.configure({ notifications = true })
  local called = false
  helpers.with_stub('leetcode-ui.picker', 'problem', function() called = true end, function()
    local messages = helpers.capture_notify(function() helpers.mod('commands').run({ 'list', 'impossible' }) end)
    eq(#messages, 1)
    eq(helpers.contains(messages[1].message, 'Unknown difficulty'), true)
  end)
  eq(called, false)
end

T['random'] = new_set()

T['random']['passes a normalized difficulty'] = function()
  ---@type any
  local called = nil
  helpers.with_stub(
    'leetcode-ui.picker',
    'random',
    function(opts) called = opts end,
    function() helpers.mod('commands').run({ 'random', 'medium' }) end
  )
  eq(called.difficulty, 'Medium')
end

T['open'] = new_set()

T['open']['requires and passes a slug'] = function()
  local slug = nil
  helpers.with_stub(
    'leetcode-ui.question',
    'open',
    function(value) slug = value end,
    function() helpers.mod('commands').run({ 'open', 'two-sum' }) end
  )
  eq(slug, 'two-sum')
end

T['open']['rejects a missing slug'] = function()
  helpers.configure({ notifications = true })
  local called = false
  helpers.with_stub('leetcode-ui.question', 'open', function() called = true end, function()
    local messages = helpers.capture_notify(function() helpers.mod('commands').run({ 'open' }) end)
    eq(#messages, 1)
    eq(helpers.contains(messages[1].message, 'Usage: :LeetCode open <slug>'), true)
  end)
  eq(called, false)
end

T['views'] = new_set()

T['views']['opens stats and session'] = function()
  local stats, session = 0, 0
  helpers.with_stub('leetcode-ui.stats_view', 'open', function() stats = stats + 1 end, function()
    helpers.with_stub('leetcode-ui.stats_view', 'session', function() session = session + 1 end, function()
      helpers.mod('commands').run({ 'stats' })
      helpers.mod('commands').run({ 'session' })
    end)
  end)
  eq(stats, 1)
  eq(session, 1)
end

T['views']['closes the current question'] = function()
  local close_count = 0
  helpers.with_stub(
    'leetcode-ui.question',
    'close',
    function() close_count = close_count + 1 end,
    function() helpers.mod('commands').run({ 'question', 'close' }) end
  )
  eq(close_count, 1)
end

T['tabs'] = new_set()

T['tabs']['shows each tab and cycles'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local shown = {}

  helpers.with_stub('leetcode-ui.question', 'show_tab', function(target, name)
    eq(target, view)
    table.insert(shown, name)
  end, function()
    helpers.with_stub('leetcode-ui.question', 'cycle_tab', function(target, delta)
      eq(target, view)
      table.insert(shown, 'cycle:' .. tostring(delta))
    end, function()
      for _, tab in ipairs({ 'description', 'code', 'console', 'info', 'next', 'prev' }) do
        helpers.mod('commands').run({ 'question', tab })
      end
    end)
  end)

  eq(table.concat(shown, ','), 'description,code,console,info,cycle:1,cycle:-1')
  restore()
end

T['tabs']['does nothing without an open question'] = function()
  local restore = stub_current(nil)
  local calls = 0
  helpers.with_stub('leetcode-ui.question', 'show_tab', function() calls = calls + 1 end, function()
    helpers.with_stub('leetcode-ui.question', 'cycle_tab', function() calls = calls + 1 end, function()
      for _, tab in ipairs({ 'description', 'code', 'console', 'info', 'next', 'prev' }) do
        eq(pcall(helpers.mod('commands').run, { 'question', tab }), true)
      end
    end)
  end)
  eq(calls, 0)
  restore()
end

T['question_actions'] = new_set()

T['question_actions']['rejects format while another action is running'] = function()
  local view = make_view()
  local restore = stub_current(view)
  view.busy = true
  local formatted = false
  helpers.with_stub(
    'leetcode-ui.solution',
    'format',
    function() formatted = true end,
    function() helpers.mod('commands').run({ 'question', 'format' }) end
  )
  eq(formatted, false)
  eq(view.busy, true)
  restore()
end

T['question_actions']['rejects unloaded code buffers'] = function()
  for _, args in ipairs({
    { 'question', 'format' },
    { 'question', 'language', 'golang' },
  }) do
    local view = make_view()
    vim.cmd(('silent! bunload! %d'):format(view.code_bufnr))
    local restore = stub_current(view)
    local called = false
    helpers.with_stub('leetcode-ui.solution', 'format', function() called = true end, function()
      helpers.with_stub('leetcode-ui.solution', 'languages', function()
        called = true
        return { 'python3', 'golang' }
      end, function() helpers.mod('commands').run(args) end)
    end)
    eq(called, false)
    restore()
  end
end

T['question_actions']['format guards missing buffers and refreshes after success'] = function()
  helpers.configure({ notifications = true })
  local view = make_view()
  view.code_bufnr = nil
  local restore = stub_current(view)
  local formatted = false
  helpers.with_stub('leetcode-ui.solution', 'format', function() formatted = true end, function()
    local messages = helpers.capture_notify(function() helpers.mod('commands').run({ 'question', 'format' }) end)
    eq(formatted, false)
    eq(helpers.contains(messages[1].message, 'Solution buffer is missing'), true)
  end)
  restore()

  view = make_view()
  restore = stub_current(view)
  local refreshed = 0
  local ui = helpers.mod('ui')
  ui.ensure()
  helpers.with_stub('leetcode-ui.solution', 'format', function(target)
    eq(target, view)
    formatted = true
  end, function()
    helpers.with_stub('leetcode-ui.question', 'refresh', function(target)
      eq(target, view)
      refreshed = refreshed + 1
    end, function() helpers.mod('commands').run({ 'question', 'format' }) end)
  end)
  eq(formatted, true)
  eq(refreshed, 1)
  ui.close()
  restore()
end

T['question_actions']['delegates run, submit, reset, and format'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local calls = {}

  helpers.with_stub('leetcode-ui.question', 'run', function(target, index)
    eq(target, view)
    table.insert(calls, 'run:' .. tostring(index))
  end, function()
    helpers.with_stub('leetcode-ui.question', 'submit', function(target)
      eq(target, view)
      table.insert(calls, 'submit')
    end, function()
      helpers.with_stub('leetcode-ui.question', 'reset_code', function(target)
        eq(target, view)
        table.insert(calls, 'reset')
      end, function()
        helpers.with_stub('leetcode-ui.solution', 'format', function(target)
          eq(target, view)
          table.insert(calls, 'format')
        end, function()
          helpers.mod('commands').run({ 'question', 'run', '2' })
          helpers.mod('commands').run({ 'question', 'submit' })
          helpers.mod('commands').run({ 'question', 'reset' })
          helpers.mod('commands').run({ 'question', 'format' })
        end)
      end)
    end)
  end)

  eq(table.concat(calls, ','), 'run:2,submit,reset,format')
  restore()
end

T['language'] = new_set()

T['language']['opens the picker without an argument'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local called = 0
  helpers.with_stub('leetcode-ui.question', 'switch_language', function(target)
    eq(target, view)
    called = called + 1
  end, function() helpers.mod('commands').run({ 'question', 'language' }) end)
  eq(called, 1)
  restore()
end

T['language']['switches directly to an available slug'] = function()
  local view = make_view()
  view.console.submission_result = { status = 'Accepted' }
  view.console.cases[1].status = 'passed'
  local restore = stub_current(view)
  local switched, refreshed = nil, 0

  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3', 'golang' } end, function()
    helpers.with_stub('leetcode-ui.solution', 'switch_language', function(target, slug)
      eq(target, view)
      switched = slug
      return true
    end, function()
      helpers.with_stub(
        'leetcode-ui.question',
        'refresh',
        function() refreshed = refreshed + 1 end,
        function() helpers.mod('commands').run({ 'question', 'language', 'golang' }) end
      )
    end)
  end)

  eq(switched, 'golang')
  eq(refreshed, 1)
  eq(view.console.submission_result, nil)
  eq(view.console.cases[1].status, 'unknown')
  restore()
end

T['language']['normalizes language aliases'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local switched = nil
  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3' } end, function()
    helpers.with_stub('leetcode-ui.solution', 'switch_language', function(_target, slug)
      switched = slug
      return true
    end, function()
      helpers.with_stub(
        'leetcode-ui.question',
        'refresh',
        function() end,
        function() helpers.mod('commands').run({ 'question', 'language', 'python' }) end
      )
    end)
  end)
  eq(switched, 'python3')
  restore()
end

T['language']['rejects changes while another action is running'] = function()
  local view = make_view()
  view.busy = true
  local restore = stub_current(view)
  local switched = false
  helpers.with_stub(
    'leetcode-ui.solution',
    'switch_language',
    function() switched = true end,
    function() helpers.mod('commands').run({ 'question', 'language', 'golang' }) end
  )
  eq(switched, false)
  restore()
end

T['language']['rejects a missing code buffer'] = function()
  helpers.configure({ notifications = true })
  local view = make_view()
  view.code_bufnr = nil
  local restore = stub_current(view)
  local called = false
  helpers.with_stub('leetcode-ui.solution', 'languages', function()
    called = true
    return { 'python3', 'golang' }
  end, function()
    local messages = helpers.capture_notify(
      function() helpers.mod('commands').run({ 'question', 'language', 'golang' }) end
    )
    eq(helpers.contains(messages[1].message, 'Solution buffer is missing'), true)
  end)
  eq(called, false)
  restore()
end

T['language']['rejects unavailable slugs'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local switched = false
  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3' } end, function()
    helpers.with_stub(
      'leetcode-ui.solution',
      'switch_language',
      function() switched = true end,
      function() helpers.mod('commands').run({ 'question', 'language', 'java' }) end
    )
  end)
  eq(switched, false)
  restore()
end

T['hints'] = new_set()

T['hints']['delegates show and hide'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local calls = {}

  helpers.with_stub('leetcode-ui.question', 'set_hints', function(target, show)
    eq(target, view)
    table.insert(calls, tostring(show))
  end, function()
    for _, args in ipairs({
      { 'question', 'hints' },
      { 'question', 'hints', 'show' },
      { 'question', 'hints', 'hide' },
    }) do
      helpers.mod('commands').run(args)
    end
  end)

  eq(table.concat(calls, ','), 'nil,true,false')
  restore()
end

T['hints']['reports invalid actions'] = function()
  helpers.configure({ notifications = true })
  local view = make_view()
  local restore = stub_current(view)
  local calls = 0
  helpers.with_stub('leetcode-ui.question', 'set_hints', function() calls = calls + 1 end, function()
    for _, action in ipairs({ 'on', 'off', 'toggle', 'bogus' }) do
      local messages = helpers.capture_notify(
        function() helpers.mod('commands').run({ 'question', 'hints', action }) end
      )
      eq(#messages, 1)
      eq(helpers.contains(messages[1].message, 'Usage: :LeetCode question hints [show|hide]'), true)
    end
  end)
  eq(calls, 0)
  restore()
end

T['hints']['does nothing without an open question'] = function()
  local restore = stub_current(nil)
  local calls = 0
  helpers.with_stub(
    'leetcode-ui.question',
    'set_hints',
    function() calls = calls + 1 end,
    function() eq(pcall(helpers.mod('commands').run, { 'question', 'hints' }), true) end
  )
  eq(calls, 0)
  restore()
end

T['case'] = new_set()

T['case']['adds, edits, deletes, and selects testcases'] = function()
  local view = make_view()
  local restore = stub_current(view)

  helpers.mod('commands').run({ 'question', 'case', 'add', '[0]', '\\n', '0' })
  eq(#view.console.cases, 3)
  eq(view.console.cases[3].input, '[0] \n 0')

  helpers.mod('commands').run({ 'question', 'case', 'edit', '1', 'new', 'input' })
  eq(view.console.cases[1].input, 'new input')

  helpers.mod('commands').run({ 'question', 'case', 'edit', '2', 'second' })
  eq(view.console.cases[2].input, 'second')

  local selected = view.console.selected
  local count = #view.console.cases
  helpers.mod('commands').run({ 'question', 'case', 'next' })
  eq(view.console.selected, (selected % count) + 1)
  helpers.mod('commands').run({ 'question', 'case', 'prev' })
  eq(view.console.selected, selected)

  helpers.mod('commands').run({ 'question', 'case', 'delete', '1' })
  eq(#view.console.cases, 2)

  restore()
end

T['case']['adds multi-line input from one argument'] = function()
  local view = make_view()
  local restore = stub_current(view)
  helpers.mod('commands').run({ 'question', 'case', 'add', '[0]\\n0' })
  eq(#view.console.cases, 3)
  eq(view.console.cases[3].input, '[0]\n0')
  restore()
end

T['case']['requires explicit index and input arguments'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local original_cases = #view.console.cases

  helpers.mod('commands').run({ 'question', 'case', 'add' })
  helpers.mod('commands').run({ 'question', 'case', 'edit' })
  helpers.mod('commands').run({ 'question', 'case', 'edit', '1' })
  helpers.mod('commands').run({ 'question', 'case', 'edit', '9', 'changed' })
  helpers.mod('commands').run({ 'question', 'case', 'edit', '1', '' })
  helpers.mod('commands').run({ 'question', 'case', 'delete' })
  helpers.mod('commands').run({ 'question', 'case', 'delete', '9' })

  eq(#view.console.cases, original_cases)
  eq(view.console.cases[1].input, 'a')
  restore()
end

T['case']['resets to the original testcases'] = function()
  local view = make_view()
  local restore = stub_current(view)

  helpers.mod('commands').run({ 'question', 'case', 'add', 'custom' })
  helpers.mod('commands').run({ 'question', 'case', 'edit', '1', 'changed' })
  helpers.mod('commands').run({ 'question', 'case', 'delete', '2' })
  eq(#view.console.cases, 2)

  helpers.mod('commands').run({ 'question', 'case', 'reset' })
  eq(#view.console.cases, 2)
  eq(view.console.cases[1].input, '[2,7,11,15]\n9')
  eq(view.console.cases[2].input, '[3,2,4]\n6')
  eq(view.console.selected, 1)

  restore()
end

T['case']['rejects extra arguments'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local selected = view.console.selected

  helpers.mod('commands').run({ 'question', 'case', 'next', 'extra' })
  helpers.mod('commands').run({ 'question', 'case', 'delete', '1', 'extra' })

  eq(view.console.selected, selected)
  eq(#view.console.cases, 2)
  restore()
end

T['case']['rejects changes while an action is running'] = function()
  local view = make_view()
  view.busy = true
  local restore = stub_current(view)
  local selected = view.console.selected

  helpers.mod('commands').run({ 'question', 'case', 'add', 'new' })
  helpers.mod('commands').run({ 'question', 'case', 'edit', '1', 'new' })
  helpers.mod('commands').run({ 'question', 'case', 'delete', '1' })
  helpers.mod('commands').run({ 'question', 'case', 'reset' })
  helpers.mod('commands').run({ 'question', 'case', 'next' })
  helpers.mod('commands').run({ 'question', 'case', 'prev' })

  eq(#view.console.cases, 2)
  eq(view.console.cases[1].input, 'a')
  eq(view.console.selected, selected)
  restore()
end

T['case']['refuses to delete the only testcase'] = function()
  helpers.configure({ notifications = true })
  local view = make_view()
  view.console:set_cases({ 'only' })
  local restore = stub_current(view)
  local deletes = 0
  helpers.with_stub('leetcode-ui.console', 'delete_case', function() deletes = deletes + 1 end, function()
    local messages = helpers.capture_notify(
      function() helpers.mod('commands').run({ 'question', 'case', 'delete', '1' }) end
    )
    eq(helpers.contains(messages[1].message, 'Cannot delete the only testcase'), true)
  end)
  eq(deletes, 0)
  eq(#view.console.cases, 1)
  restore()
end

T['case']['requires explicit subcommands'] = function()
  helpers.configure({ notifications = true })
  local view = make_view()
  local restore = stub_current(view)
  for _, args in ipairs({ { 'question', 'case', 'bogus' }, { 'question', 'case' } }) do
    local messages = helpers.capture_notify(function() helpers.mod('commands').run(args) end)
    eq(#messages, 1)
    eq(helpers.contains(messages[1].message, 'Usage: :LeetCode question case <subcommand>'), true)
  end
  restore()
end

T['refresh'] = new_set()

T['refresh']['reopens the list with a forced difficulty'] = function()
  ---@type table|nil
  local opts = nil
  helpers.with_stub(
    'leetcode-ui.picker',
    'problem',
    function(value) opts = value end,
    function() helpers.mod('commands').run({ 'refresh', 'easy' }) end
  )
  opts = opts or {}
  eq(opts.difficulty, 'Easy')
  eq(opts.force, true)
end

T['refresh']['rejects invalid difficulties'] = function()
  helpers.configure({ notifications = true })
  local called = false
  helpers.with_stub('leetcode-ui.picker', 'problem', function() called = true end, function()
    local messages = helpers.capture_notify(function() helpers.mod('commands').run({ 'refresh', 'impossible' }) end)
    eq(#messages, 1)
    eq(helpers.contains(messages[1].message, 'Unknown difficulty'), true)
  end)
  eq(called, false)
end

T['help'] = new_set()

T['help']['wraps long summaries at the shared column'] = function()
  local commands = helpers.mod('commands')
  local rows = {
    {
      'question case edit <index> <input>',
      'A long summary that should wrap across multiple lines in narrow windows',
    },
  }
  local width = commands.help_width(rows)
  local lines = commands.help_lines(rows, width)
  local indent = string.rep(' ', 12 + width + 2)
  eq(#lines > 1, true)
  for _, line in ipairs(lines) do
    local text = helpers.mod('buffer').spans_to_texts({ line })[1]
    eq(#text <= 78, true)
  end
  for index = 2, #lines do
    local text = helpers.mod('buffer').spans_to_texts({ lines[index] })[1]
    eq(text:sub(1, #indent), indent)
  end
end

T['help']['renders command help in the central window'] = function()
  helpers.mod('commands').run({ 'help' })
  local ui = helpers.mod('ui')
  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  local flat = text:gsub('%s+', ' ')
  eq(helpers.contains(text, ':LeetCode question run'), true)
  eq(helpers.contains(text, ':LeetCode question case add'), true)
  eq(helpers.contains(text, ':LeetCode question hints'), true)
  eq(helpers.contains(flat, 'Run all testcases or one testcase'), true)
  eq(helpers.contains(text, 'Add a testcase'), true)
  eq(helpers.contains(flat, 'Browse problems (same as list)'), true)
  eq(helpers.contains(text, ':LeetCode question case add <input>'), true)
  eq(helpers.contains(text, ':LeetCode question case <subcommand>'), false)
  eq(helpers.contains(text, 'case add|edit|delete'), false)
  eq(vim.api.nvim_get_option_value('winbar', { win = ui.state.winid }), ' LeetCode Help ')
end

T['completion'] = new_set()

local function complete(lead, line) return helpers.mod('commands').complete(lead, line, #line) end

T['completion']['completes top-level commands'] = function()
  local all = complete('', 'LeetCode ')
  eq(vim.tbl_contains(all, 'list'), true)
  eq(vim.tbl_contains(all, 'question'), true)
  eq(vim.tbl_contains(all, 'case'), false)
  eq(complete('st', 'LeetCode st'), { 'stats' })
end

T['completion']['completes difficulties'] = function()
  eq(complete('E', 'LeetCode list E'), { 'Easy' })
  eq(complete('e', 'LeetCode list e'), { 'Easy' })
  eq(complete('', 'LeetCode random '), { 'Easy', 'Medium', 'Hard' })
  eq(complete('', 'LeetCode refresh '), { 'Easy', 'Medium', 'Hard' })
end

T['completion']['completes question subcommands'] = function()
  local all = complete('', 'LeetCode question ')
  eq(vim.tbl_contains(all, 'run'), true)
  eq(vim.tbl_contains(all, 'submit'), true)
  eq(vim.tbl_contains(all, 'case'), true)
  eq(complete('su', 'LeetCode question su'), { 'submit' })
end

T['completion']['completes case actions and indices'] = function()
  local view = make_view()
  local restore = stub_current(view)

  local actions = complete('', 'LeetCode question case ')
  eq(vim.tbl_contains(actions, 'add'), true)
  eq(vim.tbl_contains(actions, 'edit'), true)
  eq(vim.tbl_contains(actions, 'reset'), true)
  eq(vim.tbl_contains(complete('e', 'LeetCode question case e'), 'edit'), true)
  eq(complete('', 'LeetCode question case edit '), { '1', '2' })
  eq(complete('2', 'LeetCode question case delete 2'), { '2' })
  eq(complete('', 'LeetCode question case edit 1 '), {})
  eq(complete('', 'LeetCode question case add '), {})
  eq(complete('', 'LeetCode question case next '), {})
  eq(complete('', 'LeetCode question case reset '), {})

  restore()
end

T['completion']['completes languages, cached slugs, and case indexes'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local storage = helpers.mod('storage')
  storage.write_cache({ domain = 'leetcode.com', problems = { { title_slug = 'two-sum' } }, total = 1 })

  eq(complete('', 'LeetCode question language '), { 'python3', 'golang' })
  eq(complete('two', 'LeetCode open two'), { 'two-sum' })
  eq(complete('', 'LeetCode question run '), { '1', '2' })

  restore()
end

T['completion']['hides premium slugs when configured'] = function()
  helpers.configure({ hide_premium = true })
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'free', is_paid_only = false }, { title_slug = 'premium', is_paid_only = true } },
    total = 2,
  })
  eq(complete('', 'LeetCode open '), { 'free' })
end

T['completion']['ignores cached slugs from another domain'] = function()
  local storage = helpers.mod('storage')
  storage.write_cache({ domain = 'leetcode.cn', problems = { { title_slug = 'two-sum' } }, total = 1 })
  eq(complete('', 'LeetCode open '), {})
end

T['completion']['completes hint actions'] = function()
  eq(complete('', 'LeetCode question hints '), { 'show', 'hide' })
  eq(complete('s', 'LeetCode question hints s'), { 'show' })
end

T['completion']['stops after completed optional arguments'] = function()
  local view = make_view()
  local restore = stub_current(view)

  eq(complete('', 'LeetCode list Easy '), {})
  eq(complete('', 'LeetCode question run 1 '), {})
  eq(complete('', 'LeetCode question language golang '), {})
  eq(complete('', 'LeetCode question hints show '), {})

  restore()
end

T['completion']['returns nothing for unsupported positions'] = function()
  eq(complete('x', 'LeetCode question submit x'), {})
  eq(complete('x', 'LeetCode open two x'), {})
end

T['completion']['completes cached slugs without an open question'] = function()
  local restore = stub_current(nil)
  local storage = helpers.mod('storage')
  storage.write_cache({ domain = 'leetcode.com', problems = { { title_slug = 'two-sum' } }, total = 1 })
  eq(complete('', 'LeetCode open '), { 'two-sum' })
  eq(complete('', 'LeetCode question language '), {})
  eq(complete('', 'LeetCode question run '), {})
  eq(complete('', 'LeetCode question case edit '), {})
  restore()
end

return T
