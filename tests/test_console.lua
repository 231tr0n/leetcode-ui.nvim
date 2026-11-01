-- Tests for leetcode-ui.console helpers.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
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

T['add_case'] = new_set()

T['add_case']['appends a case'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:add_case('[0]\n0')
  eq(#c.cases, 2)
  eq(c.cases[2].status, 'unknown')
end

T['case_result'] = new_set()

T['case_result']['marks passed on Accepted'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:open()
  c:case_result(1, { status = 'Accepted', correct = 1, total = 1, runtime_ms = 5 })
  eq(c.cases[1].status, 'passed')
  c:close()
end

T['case_result']['marks failed on wrong answer'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:open()
  c:case_result(1, { status = 'Wrong Answer', correct = 0, total = 1, runtime_ms = 5 })
  eq(c.cases[1].status, 'failed')
  c:close()
end

T['case_result']['marks error on compile error'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:open()
  c:case_result(1, { status = 'Compile Error' })
  eq(c.cases[1].status, 'error')
  c:close()
end

T['open_close'] = new_set()

T['open_close']['open creates bufnr'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:open()
  eq(type(c.bufnr), 'number')
  c:close()
  eq(c.bufnr, nil)
end

T['open_close']['toggle works'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:toggle()
  eq(type(c.bufnr), 'number')
  c:toggle()
  eq(c.bufnr, nil)
end

T['spinner'] = new_set()

T['spinner']['start and stop'] = function()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local c = Console.new(view)
  c:set_cases({ '[1,2]\n3' })
  c:open()
  c:start_spinner()
  eq(type(c.timer), 'userdata')
  c:stop_spinner()
  eq(c.timer, nil)
  c:close()
end

return T
