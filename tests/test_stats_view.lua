-- Tests for leetcode-ui.stats_view helpers (offline).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['module'] = new_set()

T['module']['loads'] = function()
  local sv = helpers.mod('stats_view')
  eq(type(sv), 'table')
  eq(type(sv.open), 'function')
  eq(type(sv.meter), 'function')
end

T['meter'] = new_set()

T['meter']['returns spans'] = function()
  local sv = helpers.mod('stats_view')
  local spans = sv.meter('Easy', 5, 10)
  eq(type(spans), 'table')
  eq(#spans > 0, true)
end

T['meter']['zero total safe'] = function()
  local sv = helpers.mod('stats_view')
  local spans = sv.meter('Hard', 0, 0)
  eq(type(spans), 'table')
end

T['meter']['full progress'] = function()
  local sv = helpers.mod('stats_view')
  local spans = sv.meter('Medium', 10, 10)
  eq(type(spans), 'table')
end

T['language_lines'] = new_set()

T['language_lines']['renders rows'] = function()
  local sv = helpers.mod('stats_view')
  local lines = sv.language_lines({ { language_name = 'Python3', problems_solved = 5 } })
  eq(type(lines), 'table')
  eq(#lines >= 1, true)
end

T['language_lines']['empty input'] = function()
  local sv = helpers.mod('stats_view')
  local lines = sv.language_lines({})
  eq(type(lines), 'table')
end

T['skills_lines'] = new_set()

T['skills_lines']['renders sections'] = function()
  local sv = helpers.mod('stats_view')
  local tags = {
    advanced = { { tag_name = 'DP', problems_solved = 3 } },
    intermediate = {},
    fundamental = {},
  }
  local lines = sv.skills_lines(tags)
  eq(type(lines), 'table')
  eq(#lines >= 1, true)
end

T['open_close'] = new_set()

T['open_close']['opens'] = function()
  local sv = helpers.mod('stats_view')
  local ok = pcall(sv.open)
  eq(ok, true)
end

T['open_close']['closes'] = function()
  local sv = helpers.mod('stats_view')
  sv.open()
  local ok = pcall(sv.close)
  eq(ok, true)
end

return T
