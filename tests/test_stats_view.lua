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

return T
