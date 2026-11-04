-- Tests for leetcode-ui.picker.
---@diagnostic disable: duplicate-set-field
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

local function sample_entries()
  return {
    {
      title = 'Two Sum',
      title_slug = 'two-sum',
      frontend_id = '1',
      difficulty = 'Easy',
      is_paid_only = false,
      status = 'solved',
    },
    {
      title = 'Hard One',
      title_slug = 'hard-one',
      frontend_id = '2',
      difficulty = 'Hard',
      is_paid_only = true,
      status = nil,
    },
  }
end

T['format_entry'] = new_set()

T['format_entry']['includes id, difficulty, status, and title'] = function()
  local picker = helpers.mod('picker')
  local line = picker.format_entry(sample_entries()[1])
  eq(helpers.contains(line, 'Two Sum'), true)
  eq(helpers.contains(line, '✔'), true)
  eq(line:match('^1%s+Easy%s') ~= nil, true)
end

T['format_entry']['marks premium and attempted problems'] = function()
  local picker = helpers.mod('picker')
  local line = picker.format_entry({
    frontend_id = '2',
    title = 'X',
    difficulty = 'Hard',
    is_paid_only = true,
    status = 'attempted',
  })
  eq(helpers.contains(line, '[premium]'), true)
  eq(helpers.contains(line, '✘'), true)
end

T['pick_entry'] = new_set()

T['pick_entry']['finds entries by line and handles misses'] = function()
  local picker = helpers.mod('picker')
  local entries = sample_entries()
  local lines = { 'first', 'second' }
  eq(picker.pick_entry(lines, entries, 'second'), entries[2])
  eq(picker.pick_entry(lines, entries, 'missing'), nil)
  eq(picker.pick_entry(lines, entries, nil), nil)
end

T['problem_source'] = new_set()

T['problem_source']['returns formatted lines and entries'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 2, questions = sample_entries() }, nil end,
    function()
      local filter = {}
      local lines, entries = picker.problem_source(filter)
      eq(#lines, 2)
      eq(#entries, 2)
      eq(entries[1].title_slug, 'two-sum')
      eq(filter, {})
    end
  )
end

T['problem_source']['filters by difficulty and premium'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 2, questions = sample_entries() }, nil end,
    function()
      local lines, entries = picker.problem_source({ difficulty = 'Easy', hide_premium = true })
      eq(#lines, 1)
      eq(entries[1].title_slug, 'two-sum')

      local hard_lines, hard_entries = picker.problem_source({ difficulty = 'Hard', hide_premium = false })
      eq(#hard_lines, 1)
      eq(hard_entries[1].title_slug, 'hard-one')

      local hidden_lines, hidden_entries = picker.problem_source({ difficulty = 'Hard', hide_premium = true })
      eq(hidden_lines, {})
      eq(hidden_entries, {})
    end
  )
end

T['problem_source']['uses the configured premium filter'] = function()
  helpers.configure({ hide_premium = true })
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 2, questions = sample_entries() }, nil end,
    function()
      local lines, entries = picker.problem_source({ difficulty = 'Hard' })
      eq(lines, {})
      eq(entries, {})
    end
  )
end

T['problem_source']['forwards force refresh'] = function()
  local picker = helpers.mod('picker')
  ---@type table|nil
  local options = nil
  helpers.with_stub('leetcode-ui.api.question', 'get_list', function(opts)
    options = opts
    return { total = 2, questions = sample_entries() }, nil
  end, function() picker.problem_source({ force = true }) end)
  assert(options ~= nil)
  eq(options.force, true)
end

T['problem_source']['reports list errors'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_list', function() return nil, 'network' end, function()
    local lines, entries, err = picker.problem_source({})
    eq(#lines, 0)
    eq(#entries, 0)
    eq(err, 'network')
  end)
end

T['select'] = new_set()

T['select']['uses vim.ui.select with the builtin backend'] = function()
  helpers.configure({ picker = 'builtin' })
  local picker = helpers.mod('picker')
  ---@type any
  local called = nil
  helpers.with_field(vim.ui, 'select', function(items, opts, on_choice)
    called = { items = items, prompt = opts.prompt }
    on_choice('b', 2)
  end, function()
    local choice, index = nil, nil
    picker.select({ 'a', 'b' }, 'Title', function(item, idx)
      choice, index = item, idx
    end)
    eq(choice, 'b')
    eq(index, 2)
    eq(called.items, { 'a', 'b' })
    eq(called.prompt, 'Title')
  end)
end

T['select']['uses mini.pick when available'] = function()
  helpers.configure({ picker = 'mini' })
  local picker = helpers.mod('picker')
  ---@type any
  local called = nil
  helpers.with_stub('mini.pick', 'ui_select', function(items, opts, on_choice)
    called = { items = items, prompt = opts.prompt }
    on_choice(items[2], 2)
  end, function()
    local choice, index = nil, nil
    picker.select({ 'a', 'b' }, 'Title', function(item, idx)
      choice, index = item, idx
    end)
    eq(choice, 'b')
    eq(index, 2)
    eq(called.items, { 'a', 'b' })
    eq(called.prompt, 'Title')
  end)
end

T['select']['auto uses mini.pick only when it is already set up'] = function()
  helpers.configure({ picker = 'auto' })
  local picker = helpers.mod('picker')
  ---@type any
  local called = nil
  helpers.with_field(_G, 'MiniPick', {}, function()
    helpers.with_stub(
      'mini.pick',
      'ui_select',
      function(items, opts) called = { items = items, prompt = opts.prompt } end,
      function()
        picker.select({ 'a' }, 'Title', function() end)
      end
    )
  end)
  assert(called ~= nil)
  eq(called.items, { 'a' })
  eq(called.prompt, 'Title')
end

T['select']['auto falls back when MiniPick is not set up'] = function()
  helpers.configure({ picker = 'auto' })
  local picker = helpers.mod('picker')
  ---@type any
  local called = nil
  helpers.with_field(_G, 'MiniPick', nil, function()
    helpers.with_field(
      vim.ui,
      'select',
      function(items, opts) called = { items = items, prompt = opts.prompt } end,
      function()
        picker.select({ 'a' }, 'Title', function() end)
      end
    )
  end)
  assert(called ~= nil)
  eq(called.items, { 'a' })
  eq(called.prompt, 'Title')
end

T['select']['handles cancellation'] = function()
  helpers.configure({ picker = 'mini' })
  local picker = helpers.mod('picker')
  helpers.with_stub('mini.pick', 'ui_select', function(_items, _opts, on_choice) on_choice(nil, nil) end, function()
    local called = false
    picker.select({ 'a' }, 'Title', function(item, index)
      called = true
      eq(item, nil)
      eq(index, nil)
    end)
    eq(called, true)
  end)
end

T['select']['warns and falls back when mini.pick is missing'] = function()
  helpers.configure({ picker = 'mini', notifications = true })
  local picker = helpers.mod('picker')

  local original_select = vim.ui.select
  local original_loaded = package.loaded['mini.pick']
  local original_preload = package.preload['mini.pick']
  MiniTest.finally(function()
    vim.ui.select = original_select
    package.loaded['mini.pick'] = original_loaded
    package.preload['mini.pick'] = original_preload
  end)

  local selected = false
  vim.ui.select = function(_, _, _on_choice) selected = true end
  package.loaded['mini.pick'] = nil
  package.preload['mini.pick'] = function() error('missing') end
  local messages = helpers.capture_notify(function()
    picker.select({ 'a' }, 'Title', function() end)
  end)
  eq(selected, true)
  eq(#messages, 1)
  eq(helpers.contains(messages[1].message, 'mini.pick is not available'), true)
end

T['problem'] = new_set()

local function select_and_launch(choose)
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 2, questions = sample_entries() }, nil end,
    function()
      helpers.with_stub('leetcode-ui.picker', 'select', choose, function()
        local launches = {}
        helpers.with_stub('leetcode-ui.picker', 'launch', function(entry) table.insert(launches, entry) end, function()
          picker.problem({})
          eq(helpers.wait_for(function() return #launches == 1 end), true)
          eq(launches[1].title_slug, 'hard-one')
        end)
      end)
    end
  )
end

T['problem']['launches the selected entry by index'] = function()
  select_and_launch(function(_lines, _title, on_choice) on_choice('selected', 2) end)
end

T['problem']['launches the selected entry by line fallback'] = function()
  select_and_launch(function(lines, _title, on_choice) on_choice(lines[2], nil) end)
end

T['problem']['does not select after the domain changes'] = function()
  local picker = helpers.mod('picker')
  local async = helpers.mod('async')
  local thread, selected = nil, false
  helpers.with_stub('leetcode-ui.api.question', 'get_list', function()
    thread = coroutine.running()
    coroutine.yield()
    return { total = 2, questions = sample_entries() }, nil
  end, function()
    helpers.with_stub('leetcode-ui.picker', 'select', function() selected = true end, function()
      picker.problem({})
      helpers.configure({ url = 'leetcode.cn' })
      eq(async.resume(thread), true)
    end)
  end)
  eq(selected, false)
end

T['problem']['drops a scheduled picker after newer navigation'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, scheduled, selected = nil, nil, false
  helpers.with_stub('leetcode-ui.api.question', 'get_list', function()
    thread = coroutine.running()
    coroutine.yield()
    return { total = 2, questions = sample_entries() }, nil
  end, function()
    helpers.with_stub('leetcode-ui.picker', 'select', function() selected = true end, function()
      helpers.with_field(vim, 'schedule', function(fn) scheduled = fn end, function()
        picker.problem({})
        eq(async.resume(thread), true)
      end)
      assert(scheduled ~= nil)
      ui.bump()
      scheduled()
    end)
  end)
  eq(selected, false)
end

T['problem']['drops results after newer navigation'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, selected = nil, false
  helpers.with_stub('leetcode-ui.api.question', 'get_list', function()
    thread = coroutine.running()
    coroutine.yield()
    return { total = 2, questions = sample_entries() }, nil
  end, function()
    helpers.with_stub('leetcode-ui.picker', 'select', function() selected = true end, function()
      helpers.with_field(vim, 'schedule', function(fn) fn() end, function()
        picker.problem({})
        ui.bump()
        eq(async.resume(thread), true)
      end)
    end)
  end)
  eq(selected, false)
end

T['problem']['warns when filters match nothing'] = function()
  helpers.configure({ notifications = true })
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 0, questions = {} }, nil end,
    function()
      local messages = helpers.capture_notify(function() picker.problem({ difficulty = 'Hard' }) end)
      eq(#messages, 1)
      eq(helpers.contains(messages[1].message, 'No questions matched'), true)
    end
  )
end

T['daily'] = new_set()

T['daily']['opens the returned slug'] = function()
  local picker = helpers.mod('picker')
  local opened = nil
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function() return 'daily', nil end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function(slug) opened = slug end, function() picker.daily() end)
  end)
  eq(opened, 'daily')
end

T['daily']['ignores a superseded request'] = function()
  local picker = helpers.mod('picker')
  local async = helpers.mod('async')
  local opened, thread = {}, nil
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'daily', nil
  end, function()
    helpers.with_stub('leetcode-ui.api.question', 'get_random', function() return 'random', nil end, function()
      helpers.with_stub('leetcode-ui.question', 'open', function(slug) table.insert(opened, slug) end, function()
        picker.daily()
        picker.random()
        eq(async.resume(thread), true)
      end)
    end)
  end)
  eq(opened, { 'random' })
end

T['daily']['does not replace a statistics view opened while fetching'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'daily', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.daily()
      ui.claim('stats')
      ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
  eq(ui.state.owner, 'stats')
  ui.close()
end

T['daily']['does not replace newer navigation'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'daily', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.daily()
      ui.bump()
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['daily']['does not open after the window closes'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'daily', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.daily()
      ui.close()
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['daily']['does not open after the domain changes'] = function()
  local picker = helpers.mod('picker')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'daily', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.daily()
      helpers.configure({ url = 'leetcode.cn' })
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['daily']['does not open after a credential change'] = function()
  local picker = helpers.mod('picker')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'daily', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.daily()
      helpers.configure({ cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['daily']['reports errors'] = function()
  helpers.configure({ notifications = true })
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function() return nil, 'failed' end, function()
    local messages = helpers.capture_notify(function() picker.daily() end)
    eq(helpers.contains(messages[#messages].message, 'failed'), true)
    eq(messages[#messages].level, vim.log.levels.ERROR)
  end)
end

T['random'] = new_set()

T['random']['opens the returned slug'] = function()
  local picker = helpers.mod('picker')
  ---@type table|nil
  local options = nil
  local opened = nil
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function(opts)
    options = opts
    return 'random', nil
  end, function()
    helpers.with_stub(
      'leetcode-ui.question',
      'open',
      function(slug) opened = slug end,
      function() picker.random({ difficulty = 'Easy' }) end
    )
  end)
  assert(options ~= nil)
  eq(options.difficulty, 'Easy')
  eq(opened, 'random')
end

T['random']['does not open after the domain changes'] = function()
  local picker = helpers.mod('picker')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'random', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.random()
      helpers.configure({ url = 'leetcode.cn' })
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['random']['does not open after the window closes'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'random', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.random()
      ui.close()
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['random']['does not replace a statistics view'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'random', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.random()
      ui.claim('stats')
      ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
  ui.close()
end

T['random']['drops results after newer navigation'] = function()
  local picker = helpers.mod('picker')
  local ui = helpers.mod('ui')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'random', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.random()
      ui.bump()
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['random']['does not open after a credential change'] = function()
  local picker = helpers.mod('picker')
  local async = helpers.mod('async')
  local thread, opened = nil, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function()
    thread = coroutine.running()
    coroutine.yield()
    return 'random', nil
  end, function()
    helpers.with_stub('leetcode-ui.question', 'open', function() opened = opened + 1 end, function()
      picker.random()
      helpers.configure({ cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
      eq(async.resume(thread), true)
    end)
  end)
  eq(opened, 0)
end

T['random']['reports errors'] = function()
  helpers.configure({ notifications = true })
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function() return nil, 'failed' end, function()
    local messages = helpers.capture_notify(function() picker.random() end)
    eq(helpers.contains(messages[#messages].message, 'failed'), true)
    eq(messages[#messages].level, vim.log.levels.ERROR)
  end)
end

return T
