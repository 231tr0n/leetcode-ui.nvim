-- Tests for leetcode-ui.api.stats.

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['api_stats'] = new_set()

T['api_stats']['username requires a verified signed-in session'] = function()
  local stats = helpers.mod('api.stats')

  helpers.with_stub('leetcode-ui.auth', 'verify', function() return nil, 'no session' end, function()
    local name, err = stats.username()
    eq(name, nil)
    eq(err, 'no session')
  end)

  helpers.with_stub('leetcode-ui.auth', 'verify', function() return nil, nil end, function()
    local name, err = stats.username()
    eq(name, nil)
    eq(err, 'No session')
  end)

  helpers.with_stub('leetcode-ui.auth', 'verify', function() return { signed_in = false }, nil end, function()
    local name, err = stats.username()
    eq(name, nil)
    eq(err, 'Not signed in (check cookies)')
  end)

  helpers.with_stub('leetcode-ui.auth', 'verify', function() return { signed_in = true }, nil end, function()
    local name, err = stats.username()
    eq(name, nil)
    eq(err, 'Not signed in (check cookies)')
  end)

  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function() eq(stats.username(), 'user') end
  )
end

T['api_stats']['solved returns totals and counts'] = function()
  local stats = helpers.mod('api.stats')
  helpers.with_stub('leetcode-ui.api.stats', 'username', function() return 'user', nil end, function()
    helpers.with_stub('leetcode-ui.api', 'graphql', function(_, variables)
      eq(variables.username, 'user')
      return {
        allQuestionsCount = { { difficulty = 'Easy', count = 10 } },
        matchedUser = { solved_counts = { acSubmissionNum = { { difficulty = 'Easy', count = 3 } } } },
      },
        nil
    end, function()
      local solved, err = stats.solved()
      eq(err, nil)
      eq(solved.total.Easy, 10)
      eq(solved.solved.Easy, 3)
    end)
  end)
end

T['api_stats']['query errors propagate'] = function()
  local stats = helpers.mod('api.stats')
  helpers.with_stub('leetcode-ui.api.stats', 'username', function() return 'user', nil end, function()
    helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'query failed' end, function()
      local result, err = stats.solved()
      eq(result, nil)
      eq(err, 'query failed')
      eq(select(2, stats.skills()), 'query failed')
      eq(select(2, stats.languages()), 'query failed')
    end)
  end)
end

T['api_stats']['skills and languages return their sections'] = function()
  local stats = helpers.mod('api.stats')
  helpers.with_stub('leetcode-ui.api.stats', 'username', function() return 'user', nil end, function()
    local response = { matchedUser = { tag_problems_counts = { fundamental = { { tag_name = 'Array' } } } } }
    helpers.with_stub('leetcode-ui.api', 'graphql', function(_, variables)
      eq(variables.username, 'user')
      return response, nil
    end, function()
      local skills, err = stats.skills()
      eq(err, nil)
      eq(skills.fundamental[1].tag_name, 'Array')
    end)

    helpers.with_stub('leetcode-ui.api', 'graphql', function(_, variables)
      eq(variables.username, 'user')
      return { matchedUser = { language_problem_count = { { language_name = 'Python3' } } } }, nil
    end, function()
      local languages, err = stats.languages()
      eq(err, nil)
      eq(languages[1].language_name, 'Python3')
    end)

    helpers.with_stub('leetcode-ui.api', 'graphql', function() return { matchedUser = vim.NIL }, nil end, function()
      local skills, skills_err = stats.skills()
      eq(skills, {})
      eq(skills_err, nil)
      local languages, languages_err = stats.languages()
      eq(languages, {})
      eq(languages_err, nil)
    end)
  end)
end

T['api_stats']['streak returns the counter and errors'] = function()
  local stats = helpers.mod('api.stats')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { streakCounter = { streak_count = 7 } }, nil end,
    function()
      local streak, err = stats.streak()
      eq(err, nil)
      eq(streak.streak_count, 7)
    end
  )

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return { streakCounter = nil }, nil end, function()
    local streak, err = stats.streak()
    eq(streak, nil)
    eq(err, 'Streak counter is not available')
  end)
end

return T
