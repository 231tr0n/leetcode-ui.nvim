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
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  view.console = Console.new(view)
  view.console:set_cases({ 'a', 'b' })
  return view
end

local function stub_current(view)
  local original = require('leetcode-ui.question').current
  require('leetcode-ui.question').current = function() return view end
  return function() require('leetcode-ui.question').current = original end
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
end

T['dispatch']['reports unknown commands'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ notifications = true })
  local original = vim.notify
  local messages = {}
  vim.notify = function(message) table.insert(messages, message) end
  helpers.mod('commands').run({ 'wat' })
  vim.notify = original
  eq(#messages, 1)
  eq(helpers.contains(messages[1], 'Unknown command'), true)
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
  local called = false
  helpers.with_stub(
    'leetcode-ui.picker',
    'problem',
    function() called = true end,
    function() helpers.mod('commands').run({ 'list', 'impossible' }) end
  )
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
  local called = false
  helpers.with_stub(
    'leetcode-ui.question',
    'open',
    function() called = true end,
    function() helpers.mod('commands').run({ 'open' }) end
  )
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
    function() helpers.mod('commands').run({ 'close' }) end
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
        helpers.mod('commands').run({ tab })
      end
    end)
  end)

  eq(table.concat(shown, ','), 'description,code,console,info,cycle:1,cycle:-1')
  restore()
end

T['tabs']['does nothing without an open question'] = function()
  local restore = stub_current(nil)
  for _, tab in ipairs({ 'description', 'code', 'console', 'info', 'next', 'prev' }) do
    eq(pcall(helpers.mod('commands').run, { tab }), true)
  end
  restore()
end

T['question_actions'] = new_set()

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
          helpers.mod('commands').run({ 'run', '2' })
          helpers.mod('commands').run({ 'submit' })
          helpers.mod('commands').run({ 'reset' })
          helpers.mod('commands').run({ 'format' })
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
  end, function() helpers.mod('commands').run({ 'language' }) end)
  eq(called, 1)
  restore()
end

T['language']['switches directly to an available slug'] = function()
  local view = make_view()
  local restore = stub_current(view)
  local switched, refreshed = nil, 0

  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3', 'golang' } end, function()
    helpers.with_stub('leetcode-ui.solution', 'switch_language', function(target, slug)
      eq(target, view)
      switched = slug
    end, function()
      helpers.with_stub(
        'leetcode-ui.question',
        'refresh',
        function() refreshed = refreshed + 1 end,
        function() helpers.mod('commands').run({ 'language', 'golang' }) end
      )
    end)
  end)

  eq(switched, 'golang')
  eq(refreshed, 1)
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
    function() helpers.mod('commands').run({ 'language', 'golang' }) end
  )
  eq(switched, false)
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
      function() helpers.mod('commands').run({ 'language', 'java' }) end
    )
  end)
  eq(switched, false)
  restore()
end

T['case'] = new_set()

T['case']['adds, edits, deletes, and selects testcases'] = function()
  local view = make_view()
  local restore = stub_current(view)

  helpers.mod('commands').run({ 'case', 'add', '[0]', '\\n', '0' })
  eq(#view.console.cases, 3)
  eq(view.console.cases[3].input, '[0] \n 0')

  helpers.mod('commands').run({ 'case', 'edit', '1', 'new', 'input' })
  eq(view.console.cases[1].input, 'new input')

  helpers.mod('commands').run({ 'case', 'edit', 'second' })
  eq(view.console.cases[view.console.selected].input, 'second')

  local selected = view.console.selected
  helpers.mod('commands').run({ 'case', 'next' })
  helpers.mod('commands').run({ 'case', 'prev' })
  eq(view.console.selected, selected)

  helpers.mod('commands').run({ 'case', 'delete', '1' })
  eq(#view.console.cases, 2)

  restore()
end

T['case']['reports invalid subcommands'] = function()
  local view = make_view()
  local restore = stub_current(view)
  eq(pcall(helpers.mod('commands').run, { 'case', 'bogus' }), true)
  eq(pcall(helpers.mod('commands').run, { 'case' }), true)
  restore()
end

T['refresh'] = new_set()

T['refresh']['clears the cache and reopens the list'] = function()
  local cleared, called = false, false
  helpers.with_stub('leetcode-ui.api.question', 'clear_cache', function() cleared = true end, function()
    helpers.with_stub(
      'leetcode-ui.picker',
      'problem',
      function() called = true end,
      function() helpers.mod('commands').run({ 'refresh', 'easy' }) end
    )
  end)
  eq(cleared, true)
  eq(called, true)
end

T['help'] = new_set()

T['help']['renders command help in the central window'] = function()
  helpers.mod('commands').run({ 'help' })
  local ui = helpers.mod('ui')
  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, ':LeetCode run'), true)
  eq(helpers.contains(text, ':LeetCode case add'), true)
end

T['completion'] = new_set()

T['completion']['completes top-level commands'] = function()
  local commands = helpers.mod('commands')
  local all = commands.complete('', 'LeetCode ', 9)
  eq(vim.tbl_contains(all, 'list'), true)
  eq(vim.tbl_contains(all, 'case'), true)
  local filtered = commands.complete('st', 'LeetCode st', 11)
  eq(filtered, { 'stats' })
end

T['completion']['completes difficulties'] = function()
  local commands = helpers.mod('commands')
  eq(commands.complete('E', 'LeetCode list E', 15), { 'Easy' })
  eq(commands.complete('', 'LeetCode random ', 16), { 'Easy', 'Medium', 'Hard' })
end

T['completion']['completes case actions and indices'] = function()
  local commands = helpers.mod('commands')
  local view = make_view()
  local restore = stub_current(view)

  local actions = commands.complete('', 'LeetCode case ', 14)
  eq(vim.tbl_contains(actions, 'add'), true)
  eq(vim.tbl_contains(actions, 'edit'), true)

  local filtered = commands.complete('e', 'LeetCode case e', 15)
  eq(vim.tbl_contains(filtered, 'edit'), true)

  eq(commands.complete('', 'LeetCode case edit ', 19), { '1', '2' })
  eq(commands.complete('2', 'LeetCode case delete 2', 22), { '2' })

  restore()
end

T['completion']['completes languages, cached slugs, and case indexes'] = function()
  local commands = helpers.mod('commands')
  local view = make_view()
  local restore = stub_current(view)
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'two-sum' } }, total = 1 })

  eq(commands.complete('', 'LeetCode language ', 18), { 'python3', 'golang' })
  eq(commands.complete('two', 'LeetCode open two', 17), { 'two-sum' })
  eq(commands.complete('', 'LeetCode run ', 13), { '1', '2' })

  restore()
end

T['completion']['returns nothing for unsupported positions'] = function()
  local commands = helpers.mod('commands')
  eq(commands.complete('x', 'LeetCode submit x', 17), {})
  eq(commands.complete('x', 'LeetCode open x', 15), {})
end

return T
