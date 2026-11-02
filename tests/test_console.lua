-- Tests for leetcode-ui.console.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

local function make_console(testcases)
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  local console = Console.new(view)
  view.console = console
  console:set_cases(testcases or { '[1,2]\n3' })
  return console, view
end

T['new'] = new_set()

T['new']['creates an empty console'] = function()
  local view = helpers.fake_view()
  local console = helpers.mod('console').new(view)
  eq(console.view, view)
  eq(type(console.cases), 'table')
  eq(console.selected, 1)
  eq(console.timer, nil)
end

T['set_cases'] = new_set()

T['set_cases']['builds case objects'] = function()
  local console = make_console({ '[1,2]\n3', '[0]\n0' })
  eq(#console.cases, 2)
  eq(console.cases[1].input, '[1,2]\n3')
  eq(console.cases[1].status, 'unknown')
  eq(console.selected, 1)
end

T['set_cases']['always leaves one case'] = function()
  local console = make_console({})
  eq(#console.cases, 1)
  eq(console.cases[1].input, '')

  console:set_cases(nil)
  eq(#console.cases, 1)
end

T['input'] = new_set()

T['input']['normalizes literal backslash-n'] = function()
  local console = helpers.mod('console')
  eq(console.normalize_input('a\\nb'), 'a\nb')
  eq(console.normalize_input(nil), '')
end

T['lines'] = new_set()

T['lines']['renders header, inputs, and results'] = function()
  local console = make_console({ '[1,2]\n3' })
  console.cases[1].status = 'failed'
  console.cases[1].result = {
    status = 'Wrong Answer',
    runtime_ms = 5,
    message = 'bad\nworse',
    stdout = 'out',
    answer = '[0,1]',
    expected_answer = '[1,0]',
  }
  local texts = helpers.mod('buffer').spans_to_texts(console:lines())
  local joined = table.concat(texts, '\n')
  eq(helpers.contains(joined, 'Testcases'), true)
  eq(helpers.contains(joined, 'Use \\n for multi-line testcase input'), true)
  eq(helpers.contains(joined, 'in:  [1,2]'), true)
  eq(helpers.contains(joined, 'ran: 5 ms'), true)
  eq(helpers.contains(joined, 'bad'), true)
  eq(helpers.contains(joined, 'stdout: out'), true)
  eq(helpers.contains(joined, 'return: [0,1]'), true)
  eq(helpers.contains(joined, 'expected: [1,0]'), true)
end

T['lines']['renders a highlighted submission block before testcases'] = function()
  local console = make_console()
  console.submission_result = { ok = true, status = 'Accepted', runtime_ms = 5, memory_mb = 1024 * 1024 }
  local lines = console:lines()
  local texts = helpers.mod('buffer').spans_to_texts(lines)
  local joined = table.concat(texts, '\n')

  eq(texts[1], 'Submission')
  eq(helpers.contains(texts[2], 'Accepted'), true)
  eq(helpers.contains(joined, 'Memory: 1.00 MB'), true)

  local submission_index, testcases_index = nil, nil
  for index, text in ipairs(texts) do
    if text == 'Submission' then submission_index = index end
    if text == 'Testcases' then testcases_index = index end
  end
  eq(submission_index < testcases_index, true)

  local highlighted = false
  for _, line in ipairs(lines) do
    for _, span in ipairs(line) do
      if span.hl == 'LeetCodeOk' and helpers.contains(span.text, 'Accepted') then highlighted = true end
    end
  end
  eq(highlighted, true)
end

T['lines']['renders all case labels uniformly'] = function()
  local console = make_console({ 'a', 'b', 'c' })
  console.selected = 2
  local lines = console:lines()

  for _, line in ipairs(lines) do
    local label = line[3]
    if label ~= nil and helpers.contains(label.text, 'Case ') then eq(label.hl, nil) end
  end
end

T['lines']['uses a spinner for running cases'] = function()
  local console = make_console()
  console.cases[1].running = true
  console.frame = 1
  local joined = table.concat(helpers.mod('buffer').spans_to_texts(console:lines()), '\n')
  eq(helpers.contains(joined, console.spinner[1]), true)
end

T['case_icon'] = new_set()

T['case_icon']['maps every status'] = function()
  local console = make_console()
  local cases = {
    { status = 'passed' },
    { status = 'failed' },
    { status = 'error' },
    { status = 'ran' },
    { status = 'unknown' },
  }
  eq(console:case_icon(cases[1]) ~= console:case_icon(cases[5]), true)
  for _, case in ipairs(cases) do
    local icon, hl = console:case_icon(case)
    eq(type(icon), 'string')
    eq(type(hl), 'string')
  end
end

T['add_edit_delete'] = new_set()

T['add_edit_delete']['adds, edits, and deletes cases'] = function()
  local console = make_console({ '[1,2]\n3' })
  console:add_case('[0]\\n0')
  eq(#console.cases, 2)
  eq(console.cases[2].input, '[0]\n0')
  eq(console.selected, 2)

  console:edit_case(2, 'new')
  eq(console.cases[2].input, 'new')
  eq(console.cases[2].status, 'unknown')

  console:delete_case(1)
  eq(#console.cases, 1)
  eq(console.cases[1].input, 'new')

  console:delete_case(1)
  eq(#console.cases, 1)
  console:delete_case(99)
  eq(#console.cases, 1)
end

T['add_edit_delete']['ignores edits while busy'] = function()
  local console, view = make_console()
  view.busy = true
  console:add_case('x')
  console:edit_case(1, 'y')
  console:delete_case(1)
  console:select_next()
  console:select_prev()
  eq(#console.cases, 1)
  eq(console.cases[1].input, '[1,2]\n3')
end

T['selection'] = new_set()

T['selection']['wraps in both directions'] = function()
  local console = make_console({ 'a', 'b', 'c' })
  console:select_next()
  eq(console.selected, 2)
  console:select_next()
  console:select_next()
  eq(console.selected, 1)
  console:select_prev()
  eq(console.selected, 3)
end

T['case_result'] = new_set()

T['case_result']['marks passed on Accepted'] = function()
  local console = make_console()
  console:case_result(1, { status = 'Accepted', correct = 1, total = 1, runtime_ms = 5 })
  eq(console.cases[1].status, 'passed')
end

T['case_result']['marks failed on wrong answers'] = function()
  local console = make_console()
  console:case_result(1, { status = 'Wrong Answer', correct = 0, total = 1 })
  eq(console.cases[1].status, 'failed')
end

T['case_result']['marks compile errors'] = function()
  local console = make_console()
  console:case_result(1, { status = 'Compile Error' })
  eq(console.cases[1].status, 'error')
end

T['case_result']['marks local runs'] = function()
  local console = make_console()
  console:case_result(1, { status = 'Ran', local_run = true, message = 'output' })
  eq(console.cases[1].status, 'ran')
end

T['case_result']['uses compare bits for submissions'] = function()
  local console = make_console()
  console:case_result(1, { status = 'Accepted', is_submit = true })
  eq(console.cases[1].status, 'passed')

  console:case_result(1, { status = 'Wrong Answer', is_submit = true })
  eq(console.cases[1].status, 'failed')

  console:case_result(1, { status = 'Wrong Answer', compare = '0' })
  eq(console.cases[1].status, 'failed')

  console:case_result(1, { status = 'Accepted', compare = '1' })
  eq(console.cases[1].status, 'passed')
end

T['case_result']['ignores unknown case indexes'] = function()
  local console = make_console()
  local ok = pcall(console.case_result, console, 99, { status = 'Accepted' })
  eq(ok, true)
end

T['refresh'] = new_set()

T['refresh']['asks the question view to refresh'] = function()
  local console, view = make_console()
  local refreshed = 0
  helpers.with_stub('leetcode-ui.question', 'refresh', function(target)
    eq(target, view)
    refreshed = refreshed + 1
  end, function() console:refresh() end)
  eq(refreshed, 1)
end

T['refresh']['does nothing without a view'] = function()
  local console = helpers.mod('console').new(nil)
  eq(pcall(console.refresh, console), true)
end

T['spinner'] = new_set()

T['spinner']['starts and stops'] = function()
  local console = make_console()
  console:start_spinner()
  eq(type(console.timer), 'userdata')
  console:stop_spinner()
  eq(console.timer, nil)
  eq(pcall(console.stop_spinner, console), true)
end

T['spinner']['stops when no case is running'] = function()
  local console = make_console()
  console:start_spinner()
  eq(helpers.wait_for(function() return console.timer == nil end, 1000), true)
end

return T
