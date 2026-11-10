-- Tests for leetcode-ui.stats_view.
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

local function texts(lines) return table.concat(helpers.mod('buffer').spans_to_texts(lines), '\n') end

T['meter'] = new_set()

local function meter_percent(label, solved, total)
  local spans = helpers.mod('stats_view').meter(label, solved, total)
  return spans[6].text
end

T['meter']['renders partial progress'] = function()
  local spans = helpers.mod('stats_view').meter('Easy', 5, 10)
  eq(spans[2].text, '   5/  10')
  eq(spans[6].text, '  50%')
  eq(vim.fn.strchars(spans[4].text) + vim.fn.strchars(spans[5].text), 24)
  eq(vim.fn.strchars(spans[4].text), 12)
end

T['meter']['keeps the bar width across progress values'] = function()
  local stats_view = helpers.mod('stats_view')
  local function bar_width(spans) return vim.fn.strchars(spans[4].text) + vim.fn.strchars(spans[5].text) end
  for _, values in ipairs({ { 0, 10 }, { 1, 3 }, { 10, 10 }, { 100, 10 } }) do
    eq(bar_width(stats_view.meter('Easy', values[1], values[2])), 24)
  end
  eq(bar_width(stats_view.meter('Easy', 5, 10, 10)), 10)
end

T['meter']['appears in solved statistics with each difficulty ratio'] = function()
  local lines = helpers.mod('stats_view').lines({
    solved = {
      total = { Easy = 10, Medium = 20, Hard = 30 },
      solved = { Easy = 5, Medium = 5, Hard = 5 },
    },
  })
  local text = texts(lines)
  eq(helpers.contains(text, 'Easy'), true)
  eq(helpers.contains(text, 'Medium'), true)
  eq(helpers.contains(text, 'Hard'), true)
  eq(text:find(' 50%', 1, true) ~= nil, true)
  eq(text:find(' 25%', 1, true) ~= nil, true)
  eq(text:find(' 17%', 1, true) ~= nil, true)
end

T['meter']['handles zero and full progress'] = function()
  eq(meter_percent('Hard', 0, 0), '   0%')
  eq(meter_percent('Medium', 10, 10), ' 100%')
end

T['meter']['clamps invalid progress'] = function()
  eq(meter_percent('Easy', -1, 10), '   0%')
  eq(meter_percent('Easy', 20, 10), ' 100%')
  eq(meter_percent('Easy', 1, -10), '   0%')
  eq(meter_percent('Easy', math.huge, 10), '   0%')
  eq(meter_percent('Easy', -math.huge, 10), '   0%')
  eq(meter_percent('Easy', 0 / 0, 10), '   0%')
  eq(meter_percent('Easy', 1e300, 10), ' 100%')
end

T['language_lines'] = new_set()

T['language_lines']['sorts by solved count without mutating input'] = function()
  local rows = {
    { language_name = 'Go', problems_solved = 5 },
    { language_name = 'Python3', problems_solved = 10 },
  }
  local lines = helpers.mod('stats_view').language_lines(rows)
  local text = texts(lines)
  eq(helpers.contains(text, 'Python3'), true)
  eq(text:find('Python3') < text:find('Go'), true)
  eq(rows[1].language_name, 'Go')

  local long = helpers.mod('stats_view').language_lines({
    { language_name = 'LongLanguageName', problems_solved = 1 },
  })
  eq(helpers.contains(texts(long), 'LongLanguageName 1'), true)
end

T['language_lines']['handles empty input'] = function() eq(helpers.mod('stats_view').language_lines(nil), {}) end

T['skills_lines'] = new_set()

T['skills_lines']['tolerates null sections'] = function()
  local skills_lines = helpers.mod('stats_view').skills_lines
  eq(skills_lines({ advanced = vim.NIL, intermediate = {}, fundamental = vim.NIL }), {})
  eq(skills_lines(vim.NIL), {})
end

T['skills_lines']['renders sections and limits rows'] = function()
  local rows = {}
  for index = 1, 12 do
    table.insert(rows, { tag_name = 'Tag' .. index, problems_solved = index })
  end
  local lines = helpers.mod('stats_view').skills_lines({
    advanced = rows,
    intermediate = { { tag_name = 'Mid', problems_solved = 1 } },
    fundamental = {},
  })
  local text = texts(lines)
  eq(helpers.contains(text, 'Advanced'), true)
  eq(helpers.contains(text, 'Intermediate'), true)
  eq(helpers.contains(text, 'Tag12'), true)
  eq(helpers.contains(text, 'Tag2'), false)

  local line_texts = helpers.mod('buffer').spans_to_texts(lines)
  local skills_index, advanced_index = nil, nil
  for index, line_text in ipairs(line_texts) do
    if line_text == 'Skills' then skills_index = index end
    if helpers.contains(line_text, 'Advanced') then advanced_index = index end
  end
  eq(advanced_index, skills_index + 1)
end

T['lines'] = new_set()

T['lines']['omits empty sections'] = function()
  local text = texts(helpers.mod('stats_view').lines({ languages = {}, skills = {} }))
  eq(helpers.contains(text, 'Languages'), false)
  eq(helpers.contains(text, 'Skills'), false)
end

T['lines']['renders signed-in progress'] = function()
  local lines = helpers.mod('stats_view').lines({
    solved = { solved = { Easy = 3 }, total = { Easy = 10 } },
    languages = { { language_name = 'Python3', problems_solved = 5 } },
    skills = { fundamental = { { tag_name = 'Array', problems_solved = 2 } } },
    session = { signed_in = true, name = 'user', is_premium = true },
    streak = { streak_count = 4 },
  })
  local text = texts(lines)
  eq(helpers.contains(text, 'user (premium)'), true)
  eq(helpers.contains(text, 'streak: 4'), true)
  eq(helpers.contains(text, 'Languages'), true)
  eq(helpers.contains(text, 'Skills'), true)

  local line_texts = helpers.mod('buffer').spans_to_texts(lines)
  local languages_index, skills_index = nil, nil
  for index, line_text in ipairs(line_texts) do
    if line_text == 'Languages' then languages_index = index end
    if line_text == 'Skills' then skills_index = index end
  end
  eq(languages_index ~= nil, true)
  eq(skills_index ~= nil, true)
  eq(skills_index > languages_index, true)
  eq(line_texts[skills_index - 1], '')
end

T['lines']['uses the configured LeetCode domain'] = function()
  helpers.configure({ url = 'leetcode.cn' })
  local text = texts(helpers.mod('stats_view').lines({}))
  eq(helpers.contains(text, 'leetcode.cn'), true)
  eq(helpers.contains(text, 'leetcode.com'), false)
end

T['lines']['renders anonymous guidance once'] = function()
  local lines = helpers.mod('stats_view').lines({ err = 'Not signed in', session = { signed_in = false } })
  local text = texts(lines)
  eq(helpers.contains(text, 'Not signed in'), true)
  eq(helpers.contains(text, 'Sign-in required'), false)
  eq(helpers.contains(text, 'Easy'), false)
  local guidance = 0
  for _, line_text in ipairs(helpers.mod('buffer').spans_to_texts(lines)) do
    if line_text == 'Not signed in (see :h leetcode-ui-config for cookie options)' then guidance = guidance + 1 end
  end
  eq(guidance, 1)
end

T['lines']['does not show anonymous guidance for network errors'] = function()
  local text = texts(helpers.mod('stats_view').lines({ err = 'network down', session = { signed_in = false } }))
  eq(helpers.contains(text, 'Not signed in (see :h leetcode-ui-config'), false)
  eq(helpers.contains(text, 'Statistics unavailable: network down'), true)
end

T['lines']['reports sign-in errors for signed-in sessions'] = function()
  local lines =
    helpers.mod('stats_view').lines({ err = 'Not signed in', session = { signed_in = true, name = 'user' } })
  local text = texts(lines)
  eq(helpers.contains(text, 'Session expired'), true)
  eq(helpers.contains(text, 'Signed in'), false)
  eq(helpers.contains(text, 'Sign-in required'), false)
  eq(helpers.contains(text, 'Not signed in (see :h leetcode-ui-config'), false)
end

T['lines']['reports expired sessions instead of signed-in state'] = function()
  local lines = helpers.mod('stats_view').lines({
    err = 'Authentication failed or session expired (check cookies)',
    session = { signed_in = true, name = 'user' },
  })
  local text = texts(lines)
  eq(helpers.contains(text, 'Session expired'), true)
  eq(helpers.contains(text, 'Signed in'), false)
  eq(helpers.contains(text, 'Statistics unavailable'), false)
end

T['lines']['splits multi-line errors into separate lines'] = function()
  local lines = helpers.mod('stats_view').lines({ err = 'first\nsecond', session = { signed_in = true } })
  local text = table.concat(helpers.mod('buffer').spans_to_texts(lines), '\n')
  eq(helpers.contains(text, 'Statistics unavailable: first'), true)
  eq(helpers.contains(text, 'second'), true)
end

T['lines']['does not label server errors as authentication failures'] = function()
  local lines = helpers.mod('stats_view').lines({ err = 'HTTP 500', session = { signed_in = true } })
  local text = texts(lines)
  eq(helpers.contains(text, 'Statistics unavailable'), true)
  eq(helpers.contains(text, 'Sign-in required'), false)
end

T['open'] = new_set()

T['open']['loads and renders statistics'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub(
        'leetcode-ui.api.stats',
        'solved',
        function() return { solved = { Easy = 1 }, total = { Easy = 2 } }, nil end,
        function()
          helpers.with_stub(
            'leetcode-ui.api.stats',
            'languages',
            function() return { { language_name = 'Python3', problems_solved = 1 } }, nil end,
            function()
              helpers.with_stub(
                'leetcode-ui.api.stats',
                'skills',
                function() return { fundamental = { { tag_name = 'Array', problems_solved = 1 } } }, nil end,
                function()
                  helpers.with_stub(
                    'leetcode-ui.api.stats',
                    'streak',
                    function() return { streak_count = 2 }, nil end,
                    function()
                      stats_view.open()
                      local rendered = vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false)
                      local text = table.concat(rendered, '\n')
                      eq(rendered[1], '')
                      eq(helpers.contains(text, 'user'), true)
                      eq(helpers.contains(text, 'Languages'), true)
                      eq(helpers.contains(text, 'streak: 2'), true)
                      eq(vim.api.nvim_get_option_value('winbar', { win = ui.state.winid }), ' LeetCode Statistics ')
                    end
                  )
                end
              )
            end
          )
        end
      )
    end
  )
end

T['open']['renders sign-in guidance when statistics fail'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub(
        'leetcode-ui.api.stats',
        'solved',
        function() return nil, 'Not signed in (check cookies)' end,
        function()
          stats_view.open()
          local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
          eq(helpers.contains(text, 'Session expired'), true)
          eq(helpers.contains(text, 'Signed in'), false)
          eq(helpers.contains(text, 'Sign-in required'), false)
          eq(helpers.contains(text, 'Not signed in (see :h leetcode-ui-config'), false)
        end
      )
    end
  )
end

T['open']['keeps independent sections when solved fails'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub('leetcode-ui.api.stats', 'solved', function() return nil, 'HTTP 500' end, function()
        helpers.with_stub(
          'leetcode-ui.api.stats',
          'languages',
          function() return { { language_name = 'Python3', problems_solved = 3 } }, nil end,
          function()
            helpers.with_stub(
              'leetcode-ui.api.stats',
              'skills',
              function() return { fundamental = { { tag_name = 'Array', problems_solved = 2 } } }, nil end,
              function()
                helpers.with_stub(
                  'leetcode-ui.api.stats',
                  'streak',
                  function() return { streak_count = 1 }, nil end,
                  function() stats_view.open() end
                )
              end
            )
          end
        )
      end)
    end
  )

  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'Languages'), true)
  eq(helpers.contains(text, 'Skills'), true)
  eq(helpers.contains(text, 'streak: 1'), true)
  eq(helpers.contains(text, 'Statistics unavailable: HTTP 500'), true)
end

T['open']['renders non-auth errors alongside session errors'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub('leetcode-ui.api.stats', 'solved', function() return nil, 'HTTP 500' end, function()
        helpers.with_stub(
          'leetcode-ui.api.stats',
          'languages',
          function() return nil, 'Authentication failed or session expired (check cookies)' end,
          function()
            helpers.with_stub('leetcode-ui.api.stats', 'skills', function() return {}, nil end, function()
              helpers.with_stub(
                'leetcode-ui.api.stats',
                'streak',
                function() return {}, nil end,
                function() stats_view.open() end
              )
            end)
          end
        )
      end)
    end
  )

  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'Session expired'), true)
  eq(helpers.contains(text, 'Statistics unavailable: HTTP 500'), true)
end

T['open']['discards results after a credential change during the request'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local key = 'old-user'
  helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return key end, function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = true, name = 'user' }, nil end,
      function()
        helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
          key = 'new-user'
          return { total = {}, solved = {} }, nil
        end, function()
          helpers.with_stub('leetcode-ui.api.stats', 'languages', function() return {}, nil end, function()
            helpers.with_stub('leetcode-ui.api.stats', 'skills', function() return {}, nil end, function()
              helpers.with_stub(
                'leetcode-ui.api.stats',
                'streak',
                function() return {}, nil end,
                function() stats_view.open() end
              )
            end)
          end)
        end)
      end
    )
  end)
  eq(ui.is_open(), false)
end

T['open']['discards results after a domain change during the request'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local config = helpers.mod('config')
  local epoch = config.url_epoch
  MiniTest.finally(function() config.url_epoch = epoch end)

  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
        config.url_epoch = epoch + 1
        return { total = {}, solved = {} }, nil
      end, function()
        helpers.with_stub('leetcode-ui.api.stats', 'languages', function() return {}, nil end, function()
          helpers.with_stub('leetcode-ui.api.stats', 'skills', function() return {}, nil end, function()
            helpers.with_stub(
              'leetcode-ui.api.stats',
              'streak',
              function() return {}, nil end,
              function() stats_view.open() end
            )
          end)
        end)
      end)
    end
  )

  eq(ui.is_open(), false)
end

T['open']['renders authentication errors even when the credential state resets'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local key = 'old-user'
  helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return key end, function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = true, name = 'user' }, nil end,
      function()
        helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
          key = 'new-user'
          return nil, 'Authentication failed or session expired (check cookies)'
        end, function() stats_view.open() end)
      end
    )
  end)
  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'Session expired'), true)
  eq(ui.is_open(), true)
end

T['open']['discards old payloads when credentials change alongside an auth error'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local key = 'old-user'

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return key end, function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = true, name = 'user' }, nil end,
      function()
        helpers.with_stub(
          'leetcode-ui.api.stats',
          'solved',
          function() return { total = { Easy = 10 }, solved = { Easy = 5 } }, nil end,
          function()
            helpers.with_stub('leetcode-ui.api.stats', 'languages', function()
              key = 'new-user'
              return nil, 'Authentication failed or session expired (check cookies)'
            end, function()
              helpers.with_stub('leetcode-ui.api.stats', 'skills', function() return {}, nil end, function()
                helpers.with_stub(
                  'leetcode-ui.api.stats',
                  'streak',
                  function() return {}, nil end,
                  function() stats_view.open() end
                )
              end)
            end)
          end
        )
      end
    )
  end)

  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'Session expired'), true)
  eq(helpers.contains(text, 'Easy'), false)
end

T['open']['renders a failure instead of staying on the loading screen'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub('leetcode-ui.api.stats', 'solved', function() error('boom') end, function()
        stats_view.open()
        local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
        eq(helpers.contains(text, 'Failed to load statistics'), true)
        eq(helpers.contains(text, 'Loading statistics'), false)
      end)
    end
  )
end

T['open']['reports authentication failures without querying statistics'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub('leetcode-ui.auth', 'verify', function() return nil, 'network down' end, function()
    helpers.with_stub('leetcode-ui.api.stats', 'solved', function() error('statistics should not load') end, function()
      helpers.with_stub(
        'leetcode-ui.api.stats',
        'languages',
        function() error('sections should not load') end,
        function()
          helpers.with_stub(
            'leetcode-ui.api.stats',
            'skills',
            function() error('sections should not load') end,
            function()
              helpers.with_stub(
                'leetcode-ui.api.stats',
                'streak',
                function() error('sections should not load') end,
                function()
                  stats_view.open()
                  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
                  eq(helpers.contains(text, 'network down'), true)
                end
              )
            end
          )
        end
      )
    end)
  end)
end

T['open']['renders partial statistics with aggregated errors'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub(
        'leetcode-ui.api.stats',
        'solved',
        function() return { solved = { Easy = 1 }, total = { Easy = 2 } }, nil end,
        function()
          helpers.with_stub(
            'leetcode-ui.api.stats',
            'languages',
            function() return nil, 'language failed' end,
            function()
              helpers.with_stub(
                'leetcode-ui.api.stats',
                'skills',
                function() return { fundamental = { { tag_name = 'Array', problems_solved = 1 } } }, nil end,
                function()
                  helpers.with_stub(
                    'leetcode-ui.api.stats',
                    'streak',
                    function() return nil, 'streak failed' end,
                    function()
                      stats_view.open()
                      local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
                      eq(helpers.contains(text, 'Skills'), true)
                      eq(helpers.contains(text, 'language failed'), true)
                      eq(helpers.contains(text, 'streak failed'), true)
                    end
                  )
                end
              )
            end
          )
        end
      )
    end
  )
end

T['open']['ignores a superseded statistics request'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local calls, thread = 0, nil
  local sections = { languages = 0, skills = 0, streak = 0 }

  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
        calls = calls + 1
        if calls == 1 then
          thread = coroutine.running()
          coroutine.yield()
          return nil, 'stale response'
        end
        return { solved = { Easy = 1 }, total = { Easy = 2 } }, nil
      end, function()
        helpers.with_stub('leetcode-ui.api.stats', 'languages', function()
          sections.languages = sections.languages + 1
          return {}, nil
        end, function()
          helpers.with_stub('leetcode-ui.api.stats', 'skills', function()
            sections.skills = sections.skills + 1
            return {}, nil
          end, function()
            helpers.with_stub('leetcode-ui.api.stats', 'streak', function()
              sections.streak = sections.streak + 1
              return nil, nil
            end, function()
              stats_view.open()
              stats_view.open()
              eq(helpers.mod('async').resume(thread), true)
            end)
          end)
        end)
      end)
    end
  )

  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'stale response'), false)
  eq(helpers.contains(text, 'Easy'), true)
  eq(sections, { languages = 1, skills = 1, streak = 1 })
end

T['open']['ignores a request superseded during the final credential check'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local solved_calls, thread = 0, nil
  local yield_next, yielded = false, false

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function()
    if yield_next and not yielded then
      yielded = true
      thread = coroutine.running()
      coroutine.yield()
    end
    return 'user'
  end, function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = true, name = 'user' }, nil end,
      function()
        helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
          solved_calls = solved_calls + 1
          if solved_calls == 1 then
            yield_next = true
            return { solved = { Easy = 1 }, total = { Easy = 2 } }, nil
          end
          return { solved = { Easy = 2 }, total = { Easy = 2 } }, nil
        end, function()
          helpers.with_stub('leetcode-ui.api.stats', 'languages', function() return {}, nil end, function()
            helpers.with_stub('leetcode-ui.api.stats', 'skills', function() return {}, nil end, function()
              helpers.with_stub('leetcode-ui.api.stats', 'streak', function() return nil, nil end, function()
                stats_view.open()
                stats_view.open()
                eq(helpers.mod('async').resume(thread), true)
              end)
            end)
          end)
        end)
      end
    )
  end)

  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, '   2/'), true)
  eq(helpers.contains(text, '   1/'), false)
end

T['open']['does not verify twice for a signed-out session'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local verifies, solved_calls = 0, 0

  helpers.with_stub('leetcode-ui.auth', 'verify', function()
    verifies = verifies + 1
    return { checked = true, signed_in = false }, nil
  end, function()
    helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
      solved_calls = solved_calls + 1
      return {}, nil
    end, function() stats_view.open() end)
  end)

  eq(verifies, 1)
  eq(solved_calls, 0)
  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'Not signed in'), true)
end

T['open']['does not reopen a closed view when a request finishes'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  local thread
  local sections = { languages = 0, skills = 0, streak = 0 }
  helpers.with_stub(
    'leetcode-ui.auth',
    'verify',
    function() return { signed_in = true, name = 'user' }, nil end,
    function()
      helpers.with_stub('leetcode-ui.api.stats', 'solved', function()
        thread = coroutine.running()
        coroutine.yield()
        return nil, 'late response'
      end, function()
        helpers.with_stub('leetcode-ui.api.stats', 'languages', function()
          sections.languages = sections.languages + 1
          return {}, nil
        end, function()
          helpers.with_stub('leetcode-ui.api.stats', 'skills', function()
            sections.skills = sections.skills + 1
            return {}, nil
          end, function()
            helpers.with_stub('leetcode-ui.api.stats', 'streak', function()
              sections.streak = sections.streak + 1
              return nil, nil
            end, function()
              stats_view.open()
              ui.close()
              eq(helpers.mod('async').resume(thread), true)
              eq(ui.is_open(), false)
            end)
          end)
        end)
      end)
    end
  )
  eq(sections, { languages = 0, skills = 0, streak = 0 })
end

T['session'] = new_set()

T['session']['reports a signed-in session'] = function()
  local stats_view = helpers.mod('stats_view')
  helpers.configure({ notifications = true })
  local messages = helpers.capture_notify(function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = true, name = 'user', is_premium = true }, nil end,
      function()
        helpers.with_stub(
          'leetcode-ui.api.stats',
          'streak',
          function() return { streak_count = 3 }, nil end,
          function() stats_view.session() end
        )
      end
    )
  end)
  local last = messages[#messages].message
  eq(helpers.contains(last, 'user'), true)
  eq(helpers.contains(last, 'premium'), true)
  eq(helpers.contains(last, 'streak: 3'), true)
end

T['session']['reports expired sessions'] = function()
  local stats_view = helpers.mod('stats_view')
  helpers.configure({ notifications = true })
  local messages = helpers.capture_notify(function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = true, name = 'user' }, nil end,
      function()
        helpers.with_stub(
          'leetcode-ui.api.stats',
          'streak',
          function() return nil, 'Authentication failed or session expired (check cookies)' end,
          function() stats_view.session() end
        )
      end
    )
  end)
  local last = messages[#messages].message
  eq(helpers.contains(last, 'Session expired'), true)
  eq(helpers.contains(last, 'user'), false)
end

T['session']['discards notifications after a credential change'] = function()
  local stats_view = helpers.mod('stats_view')
  helpers.configure({ notifications = true })
  local key, verified, streaked = 'old-user', false, false
  local messages = helpers.capture_notify(function()
    helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return key end, function()
      helpers.with_stub('leetcode-ui.auth', 'verify', function()
        verified = true
        return { signed_in = true, name = 'user' }, nil
      end, function()
        helpers.with_stub('leetcode-ui.api.stats', 'streak', function()
          streaked = true
          key = 'new-user'
          return { streak_count = 3 }, nil
        end, function() stats_view.session() end)
      end)
    end)
  end)
  eq(verified, true)
  eq(streaked, true)
  eq(#messages, 1)
  for _, message in ipairs(messages) do
    eq(helpers.contains(message.message, 'user'), false)
    eq(helpers.contains(message.message, 'streak: 3'), false)
  end
end

T['session']['reports errors and anonymous sessions'] = function()
  local stats_view = helpers.mod('stats_view')
  helpers.configure({ notifications = true })
  local messages = helpers.capture_notify(function()
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return nil, 'failed' end,
      function() stats_view.session() end
    )
    helpers.with_stub(
      'leetcode-ui.auth',
      'verify',
      function() return { signed_in = false }, nil end,
      function() stats_view.session() end
    )
  end)

  local failed, anonymous = false, false
  for _, message in ipairs(messages) do
    if helpers.contains(message.message, 'failed') then failed = true end
    if helpers.contains(message.message, 'anonymous') then anonymous = true end
  end
  eq(failed, true)
  eq(anonymous, true)
end

T['markdown'] = new_set()

T['markdown']['builds statistics tables'] = function()
  local md = helpers.mod('stats_view').markdown({
    session = { signed_in = true, name = 'user' },
    solved = { solved = { Easy = 1 }, total = { Easy = 2 } },
    languages = { { language_name = 'Python3', problems_solved = 3 } },
    skills = { fundamental = { { tag_name = 'Array', problems_solved = 2 } } },
    streak = { streak_count = 4 },
  })
  eq(helpers.contains(md, '# Progress'), true)
  eq(helpers.contains(md, '| Easy | 1 | 2 | 50.0% |'), true)
  eq(helpers.contains(md, '| Python3 | 3 |'), true)
  eq(helpers.contains(md, '### Fundamental'), true)
  eq(helpers.contains(md, 'streak: 4'), true)
end

T['markdown']['open routes through the markdown renderer'] = function()
  local stats_view = helpers.mod('stats_view')
  local rendered = {}
  local span_rendered = false
  helpers.with_stub('leetcode-ui.ui', 'markdown_enabled', function() return true end, function()
    helpers.with_stub(
      'leetcode-ui.ui',
      'render_markdown',
      function(text, opts) table.insert(rendered, { text = text, opts = opts }) end,
      function()
        helpers.with_stub(
          'leetcode-ui.auth',
          'verify',
          function() return { signed_in = true, name = 'user' }, nil end,
          function()
            helpers.with_stub(
              'leetcode-ui.api.stats',
              'solved',
              function() return { solved = { Easy = 1 }, total = { Easy = 2 } }, nil end,
              function()
                helpers.with_stub('leetcode-ui.api.stats', 'languages', function() return {}, nil end, function()
                  helpers.with_stub('leetcode-ui.api.stats', 'skills', function() return {}, nil end, function()
                    helpers.with_stub(
                      'leetcode-ui.api.stats',
                      'streak',
                      function() return { streak_count = 1 }, nil end,
                      function()
                        helpers.with_stub(
                          'leetcode-ui.ui',
                          'render',
                          function() span_rendered = true end,
                          function() stats_view.open() end
                        )
                      end
                    )
                  end)
                end)
              end
            )
          end
        )
      end
    )
  end)

  eq(#rendered >= 2, true)
  local last = rendered[#rendered]
  eq(helpers.contains(last.text, '# Progress'), true)
  eq(last.opts.owner, 'stats')
  eq(span_rendered, false)
end

return T
