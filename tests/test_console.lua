-- Tests for leetcode-ui.console helpers.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      helpers.setup()
    end,
  },
})

T['new'] = new_set()

T['new']['creates console for view'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  eq(type(c), 'table')
  eq(c.view, view)
  eq(type(c.cases), 'table')
end

T['cases'] = new_set()

T['cases']['set_cases builds case objects'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3', '[0]\n0' })
  eq(#c.cases, 2)
  eq(type(c.cases[1].input), 'string')
  eq(c.selected, 1)
end

T['cases']['empty testcases allowed'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({})
  eq(type(c.cases), 'table')
end

return T
