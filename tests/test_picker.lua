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
  eq(helpers.contains(line, 'Easy'), true)
  eq(helpers.contains(line, '1'), true)
  eq(helpers.contains(line, '✔'), true)
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
      local lines, entries = picker.problem_source({})
      eq(#lines, 2)
      eq(#entries, 2)
      eq(entries[1].title_slug, 'two-sum')
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
      local lines = picker.problem_source({ difficulty = 'Easy', hide_premium = true })
      eq(#lines, 1)

      local hard = picker.problem_source({ difficulty = 'Hard', hide_premium = true })
      eq(#hard, 0)
    end
  )
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
  local config = require('leetcode-ui.config')
  config.setup({ picker = 'builtin' })
  local picker = helpers.mod('picker')
  local original = vim.ui.select
  ---@type any
  local called = nil
  vim.ui.select = function(items, opts, on_choice)
    called = { items = items, prompt = opts.prompt }
    on_choice('b', 2)
  end
  local choice, index = nil, nil
  picker.select({ 'a', 'b' }, 'Title', function(item, idx)
    choice, index = item, idx
  end)
  vim.ui.select = original
  eq(choice, 'b')
  eq(index, 2)
  eq(called.prompt, 'Title')
end

T['select']['uses mini.pick when available'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ picker = 'mini' })
  local mini_ok = pcall(require, 'mini.pick')
  if not mini_ok then return end

  local picker = helpers.mod('picker')
  helpers.with_stub('mini.pick', 'start', function() return 'b' end, function()
    local choice, index = nil, nil
    picker.select({ 'a', 'b' }, 'Title', function(item, idx)
      choice, index = item, idx
    end)
    eq(choice, 'b')
    eq(index, 2)
  end)
end

T['select']['handles cancellation'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ picker = 'mini' })
  local mini_ok = pcall(require, 'mini.pick')
  if not mini_ok then return end

  local picker = helpers.mod('picker')
  helpers.with_stub('mini.pick', 'start', function() return nil end, function()
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
  local config = require('leetcode-ui.config')
  config.setup({ picker = 'mini' })
  local picker = helpers.mod('picker')

  local original_select = vim.ui.select
  local original_loaded = package.loaded['mini.pick']
  local original_preload = package.preload['mini.pick']
  local selected = false
  vim.ui.select = function(_, _, _on_choice) selected = true end
  package.loaded['mini.pick'] = nil
  package.preload['mini.pick'] = function() error('missing') end
  picker.select({ 'a' }, 'Title', function() end)
  package.loaded['mini.pick'] = original_loaded
  package.preload['mini.pick'] = original_preload
  vim.ui.select = original_select
  eq(selected, true)
end

T['problem'] = new_set()

T['problem']['launches the selected entry'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 2, questions = sample_entries() }, nil end,
    function()
      helpers.with_stub(
        'leetcode-ui.picker',
        'select',
        function(_lines, _title, on_choice) on_choice('selected', 2) end,
        function()
          ---@type any
          local launched = nil
          helpers.with_stub('leetcode-ui.picker', 'launch', function(entry) launched = entry end, function()
            picker.problem({})
            eq(helpers.wait_for(function() return launched ~= nil end), true)
            eq(launched.title_slug, 'hard-one')
          end)
        end
      )
    end
  )
end

T['problem']['warns when filters match nothing'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 0, questions = {} }, nil end,
    function()
      local ok = pcall(picker.problem, { difficulty = 'Hard' })
      eq(ok, true)
    end
  )
end

T['daily'] = new_set()

T['daily']['opens the returned slug'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function() return 'daily', nil end, function()
    helpers.with_stub(
      'leetcode-ui.question',
      'open',
      function(slug) eq(slug, 'daily') end,
      function() picker.daily() end
    )
  end)
end

T['daily']['reports errors'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function() return nil, 'failed' end, function()
    local ok = pcall(picker.daily)
    eq(ok, true)
  end)
end

T['random'] = new_set()

T['random']['opens the returned slug'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function() return 'random', nil end, function()
    helpers.with_stub(
      'leetcode-ui.question',
      'open',
      function(slug) eq(slug, 'random') end,
      function() picker.random({ difficulty = 'Easy' }) end
    )
  end)
end

T['random']['reports errors'] = function()
  local picker = helpers.mod('picker')
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function() return nil, 'failed' end, function()
    local ok = pcall(picker.random)
    eq(ok, true)
  end)
end

return T
