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

T['meter']['renders partial progress'] = function()
  local view = helpers.mod('stats_view')
  local spans = view.meter('Easy', 5, 10)
  eq(type(spans), 'table')
  local text = ''
  for _, span in ipairs(spans) do
    text = text .. span.text
  end
  eq(helpers.contains(text, '5'), true)
  eq(helpers.contains(text, '10'), true)
  eq(helpers.contains(text, '50%'), true)
end

T['meter']['handles zero totals'] = function()
  local view = helpers.mod('stats_view')
  local spans = view.meter('Hard', 0, 0)
  eq(type(spans), 'table')
end

T['meter']['handles full progress'] = function()
  local view = helpers.mod('stats_view')
  local spans = view.meter('Medium', 10, 10)
  eq(type(spans), 'table')
end

T['language_lines'] = new_set()

T['language_lines']['sorts by solved count'] = function()
  local lines = helpers.mod('stats_view').language_lines({
    { language_name = 'Go', problems_solved = 5 },
    { language_name = 'Python3', problems_solved = 10 },
  })
  local text = texts(lines)
  eq(helpers.contains(text, 'Python3'), true)
  eq(text:find('Python3') < text:find('Go'), true)
end

T['language_lines']['handles empty input'] = function()
  local lines = helpers.mod('stats_view').language_lines(nil)
  eq(type(lines), 'table')
end

T['skills_lines'] = new_set()

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

T['build_lines'] = new_set()

T['build_lines']['renders signed-in progress'] = function()
  local lines = helpers.mod('stats_view').build_lines(
    { solved = { Easy = 3 }, total = { Easy = 10 } },
    { { language_name = 'Python3', problems_solved = 5 } },
    { fundamental = { { tag_name = 'Array', problems_solved = 2 } } },
    nil,
    { signed_in = true, name = 'user' },
    { streak_count = 4 }
  )
  local text = texts(lines)
  eq(helpers.contains(text, 'user'), true)
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

T['build_lines']['renders anonymous guidance and errors'] = function()
  local lines = helpers.mod('stats_view').build_lines(nil, nil, nil, 'Not signed in', { signed_in = false }, nil)
  local text = texts(lines)
  eq(helpers.contains(text, 'Not signed in'), true)
  eq(helpers.contains(text, 'Sign-in required'), true)
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
                      local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
                      eq(helpers.contains(text, 'user'), true)
                      eq(helpers.contains(text, 'Languages'), true)
                      eq(helpers.contains(text, 'streak: 2'), true)
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
  helpers.with_stub('leetcode-ui.auth', 'verify', function() return { signed_in = false }, nil end, function()
    helpers.with_stub('leetcode-ui.api.stats', 'solved', function() return nil, 'Not signed in' end, function()
      stats_view.open()
      local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
      eq(helpers.contains(text, 'Sign-in required'), true)
    end)
  end)
end

T['session'] = new_set()

T['session']['reports a signed-in session'] = function()
  local stats_view = helpers.mod('stats_view')
  local config = require('leetcode-ui.config')
  config.setup({ notifications = true })
  local original = vim.notify
  local messages = {}
  vim.notify = function(message) table.insert(messages, message) end
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
  vim.notify = original
  local last = messages[#messages]
  eq(helpers.contains(last, 'user'), true)
  eq(helpers.contains(last, 'premium'), true)
  eq(helpers.contains(last, 'streak: 3'), true)
end

T['session']['reports errors and anonymous sessions'] = function()
  local stats_view = helpers.mod('stats_view')
  local config = require('leetcode-ui.config')
  config.setup({ notifications = true })
  local original = vim.notify
  local messages = {}
  vim.notify = function(message) table.insert(messages, message) end

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

  vim.notify = original
  local failed, anonymous = false, false
  for _, message in ipairs(messages) do
    if helpers.contains(message, 'failed') then failed = true end
    if helpers.contains(message, 'anonymous') then anonymous = true end
  end
  eq(failed, true)
  eq(anonymous, true)
end

T['close'] = new_set()

T['close']['closes the central window'] = function()
  local stats_view = helpers.mod('stats_view')
  local ui = helpers.mod('ui')
  ui.ensure()
  stats_view.close()
  eq(ui.is_open(), false)
end

return T
