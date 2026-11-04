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
  local view = helpers.fake_view()
  local console = helpers.fake_console(view, testcases or { '[1,2]\n3' })
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
  local text = table.concat(helpers.mod('buffer').spans_to_texts(console:lines()), '\n')
  eq(helpers.contains(text, 'in:  <empty>'), true)

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
  local lines = console:lines()
  local texts = helpers.mod('buffer').spans_to_texts(lines)
  local joined = table.concat(texts, '\n')
  eq(helpers.contains(joined, 'Testcases'), true)
  eq(helpers.contains(joined, ':LeetCode help lists testcase commands'), true)
  eq(helpers.contains(joined, 'Use \\n for multi-line testcase input'), true)
  eq(helpers.contains(joined, 'in:  [1,2]'), true)
  eq(helpers.contains(joined, 'ran: 5 ms'), true)
  eq(helpers.contains(joined, 'stdout: out'), true)
  eq(helpers.contains(joined, 'return: [0,1]'), true)
  eq(helpers.contains(joined, 'expected: [1,0]'), true)

  local message_lines = vim.tbl_filter(function(line)
    local text = helpers.mod('buffer').spans_to_texts({ line })[1]
    return helpers.contains(text, 'bad') or helpers.contains(text, 'worse')
  end, lines)
  eq(#message_lines, 2)
  eq(message_lines[1][1].text, '    bad')
  eq(message_lines[1][1].hl, 'LeetCodeErr')
  eq(message_lines[2][1].text, '    worse')
  eq(message_lines[2][1].hl, 'LeetCodeErr')
end

T['lines']['formats multiline values with one label'] = function()
  local console = make_console({ 'input' })
  console.cases[1].status = 'failed'
  console.cases[1].result = {
    status = 'Wrong Answer',
    answer = 'a\nb',
    expected_answer = 'c\nd',
    stdout = 'one\ntwo',
  }

  local texts = helpers.mod('buffer').spans_to_texts(console:lines())
  local labels = { ['return'] = 0, expected = 0, stdout = 0 }
  for _, text in ipairs(texts) do
    if helpers.contains(text, 'return:') then labels['return'] = labels['return'] + 1 end
    if helpers.contains(text, 'expected:') then labels.expected = labels.expected + 1 end
    if helpers.contains(text, 'stdout:') then labels.stdout = labels.stdout + 1 end
  end
  eq(labels['return'], 1)
  eq(labels.expected, 1)
  eq(labels.stdout, 1)
  eq(helpers.contains(table.concat(texts, '\n'), 'b'), true)
  eq(helpers.contains(table.concat(texts, '\n'), 'd'), true)
  eq(helpers.contains(table.concat(texts, '\n'), '            one'), true)
  eq(helpers.contains(table.concat(texts, '\n'), '            two'), true)
end

T['lines']['indents multiline testcase input'] = function()
  local console = make_console({ 'first\nsecond' })
  local texts = helpers.mod('buffer').spans_to_texts(console:lines())
  local joined = table.concat(texts, '\n')
  eq(helpers.contains(joined, '    in:  first'), true)
  eq(helpers.contains(joined, '         second'), true)
  local labels = 0
  for _, text in ipairs(texts) do
    if helpers.contains(text, 'in:') then labels = labels + 1 end
  end
  eq(labels, 1)
end

T['lines']['renders a highlighted submission block before testcases'] = function()
  local console = make_console()
  console.submission_result = { ok = true, status = 'Accepted', runtime_ms = 5, memory_bytes = 1024 * 1024 }
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

  console.submission_result = {
    ok = false,
    status = 'Wrong Answer',
    message = 'wrong',
    input = 'in',
    expected_output = 'expected',
    code_output = 'actual',
  }
  local failure = table.concat(helpers.mod('buffer').spans_to_texts(console:lines()), '\n')
  eq(helpers.contains(failure, 'error: wrong'), true)
  eq(helpers.contains(failure, 'input: in'), true)
  eq(helpers.contains(failure, 'expected: expected'), true)
  eq(helpers.contains(failure, 'got: actual'), true)
end

T['lines']['renders all case labels uniformly'] = function()
  local console = make_console({ 'a', 'b', 'c' })
  console.selected = 2
  local lines = console:lines()
  local labels = 0

  for _, line in ipairs(lines) do
    local label = line[3]
    if label ~= nil and helpers.contains(label.text, 'Case ') then
      labels = labels + 1
      eq(label.hl, nil)
    end
  end
  eq(labels, 3)
end

T['lines']['folds large stdout and places it after the return value'] = function()
  local console = make_console({ 'input' })
  local output = {}
  for index = 1, 6 do
    table.insert(output, 'line' .. index)
  end
  console.cases[1].status = 'passed'
  console.cases[1].result = {
    status = 'Accepted',
    runtime_ms = 1,
    answer = '42',
    stdout = table.concat(output, '\n'),
  }

  local lines, folds = console:lines()
  eq(#folds, 1)
  local fold = folds[1]
  local texts = helpers.mod('buffer').spans_to_texts(lines)
  eq(texts[fold.start_line], '    stdout:')
  eq(texts[fold.start_line + 1], '            line1')
  eq(texts[fold.end_line], '            line' .. #output)
  eq(fold.end_line, fold.start_line + #output)

  local return_line = nil
  for index, text in ipairs(texts) do
    if helpers.contains(text, 'return: 42') then return_line = index end
  end
  eq(return_line < fold.start_line, true)
end

T['lines']['does not fold stdout at the threshold'] = function()
  local console = make_console({ 'input' })
  local output = {}
  for index = 1, console.stdout_fold_threshold do
    table.insert(output, 'line' .. index)
  end
  console.cases[1].status = 'passed'
  console.cases[1].result = { status = 'Accepted', stdout = table.concat(output, '\n') }

  local lines, folds = console:lines()
  local text = table.concat(helpers.mod('buffer').spans_to_texts(lines), '\n')
  eq(#folds, 0)
  eq(helpers.contains(text, 'stdout:'), true)
  eq(helpers.contains(text, 'line5'), true)
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
  local icons = require('leetcode-ui.config').config.icons.case
  for status, expected in pairs({
    passed = { icons.passed, 'LeetCodeOk' },
    failed = { icons.failed, 'LeetCodeErr' },
    error = { icons.err, 'LeetCodeErr' },
    unknown = { icons.unknown, 'LeetCodeDim' },
  }) do
    local icon, hl = console:case_icon({ status = status })
    eq(icon, expected[1])
    eq(hl, expected[2])
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

  console:edit_case(1.5, 'invalid')
  eq(console.cases[1].input, '[1,2]\n3')
  console:delete_case(1.5)
  eq(#console.cases, 2)

  console:delete_case(1)
  eq(#console.cases, 1)
  eq(console.cases[1].input, 'new')

  console:delete_case(1)
  eq(#console.cases, 1)
  console:delete_case(99)
  eq(#console.cases, 1)
end

T['add_edit_delete']['edits and deletes the selected case by default'] = function()
  local console = make_console({ 'a', 'b' })
  console.selected = 2
  console:edit_case(nil, 'new b')
  eq(console.cases[2].input, 'new b')

  console:delete_case(nil)
  eq(#console.cases, 1)
  eq(console.cases[1].input, 'a')
end

T['add_edit_delete']['deleting an earlier case preserves the selected case'] = function()
  local console = make_console({ 'a', 'b', 'c' })
  console.selected = 3
  console:delete_case(1)
  eq(console.selected, 2)
  eq(console.cases[console.selected].input, 'c')
end

T['add_edit_delete']['keeps cases unchanged when saving fails'] = function()
  local console = make_console({ 'a', 'b' })
  helpers.with_stub('leetcode-ui.storage', 'write_testcases', function() return false end, function()
    console:add_case('c')
    eq(#console.cases, 2)
    eq(console.selected, 1)

    console:edit_case(2, 'changed')
    eq(console.cases[2].input, 'b')

    console:delete_case(1)
    eq(#console.cases, 2)

    console:reset_cases()
    eq(#console.cases, 2)
    eq(console.cases[1].input, 'a')
  end)
end

T['set_cases']['ignores non-string inputs'] = function()
  local console = make_console()
  console:set_cases({ 'a', 1, vim.NIL, 'b' })
  eq(#console.cases, 2)
  eq(console.cases[1].input, 'a')
  eq(console.cases[2].input, 'b')
end

T['add_edit_delete']['ignores edits while busy'] = function()
  local console, view = make_console({ 'a', 'b' })
  view.busy = true
  console:add_case('x')
  console:edit_case(1, 'y')
  console:delete_case(1)
  console:reset_cases()
  console:select_next()
  console:select_prev()
  eq(#console.cases, 2)
  eq(console.selected, 1)
  eq(console.cases[1].input, 'a')
end

T['reset_cases'] = new_set()

T['reset_cases']['restores the question testcases'] = function()
  local console = make_console({ 'custom' })
  console:reset_cases()
  eq(#console.cases, 2)
  eq(console.cases[1].input, '[2,7,11,15]\n9')
  eq(console.selected, 1)
end

T['persistence'] = new_set()

T['persistence']['mutations persist and reset removes saved testcases'] = function()
  local console = make_console({ 'first' })
  local storage = helpers.mod('storage')

  console:add_case('second')
  eq(storage.read_testcases('two-sum')[2], 'second')

  console:edit_case(1, 'changed')
  eq(storage.read_testcases('two-sum')[1], 'changed')

  console:delete_case(2)
  eq(#storage.read_testcases('two-sum'), 1)

  console:reset_cases()
  eq(storage.read_testcases('two-sum'), nil)
  eq(console.cases[1].input, '[2,7,11,15]\n9')
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

T['set_case_result'] = new_set()

T['set_case_result']['marks passed on Accepted'] = function()
  local console = make_console()
  console:set_case_result(1, { status = 'Accepted', correct = 1, total = 1, runtime_ms = 5 })
  eq(console.cases[1].status, 'passed')
end

T['set_case_result']['marks failed on wrong answers'] = function()
  local console = make_console()
  console:set_case_result(1, { status = 'Wrong Answer', correct = 0, total = 1 })
  eq(console.cases[1].status, 'failed')
end

T['set_case_result']['marks compile and input errors'] = function()
  local console = make_console()
  console:set_case_result(1, { status = 'Compile Error' })
  eq(console.cases[1].status, 'error')

  console:set_case_result(1, { status = 'Invalid Testcase' })
  eq(console.cases[1].status, 'error')
end

T['set_case_result']['uses compare bits for submissions'] = function()
  local console = make_console()
  console:set_case_result(1, { status = 'Accepted', is_submit = true })
  eq(console.cases[1].status, 'passed')

  console:set_case_result(1, { status = 'Wrong Answer', is_submit = true })
  eq(console.cases[1].status, 'failed')

  console:set_case_result(1, { status = 'Wrong Answer', compare = '0' })
  eq(console.cases[1].status, 'failed')

  console:set_case_result(1, { status = 'Accepted', compare = '0' })
  eq(console.cases[1].status, 'failed')

  console:set_case_result(1, { status = 'Wrong Answer', compare = '1' })
  eq(console.cases[1].status, 'passed')

  console:set_case_result(1, { status = 'Accepted', compare = '1' })
  eq(console.cases[1].status, 'passed')

  console:set_case_result(1, { status = 'Accepted', compare = 1 })
  eq(console.cases[1].status, 'passed')

  console:set_case_result(1, { status = 'Accepted', correct = '1', total = '1' })
  eq(console.cases[1].status, 'passed')

  console:set_case_result(1, { status = 'Finished', correct = '0', total = '0' })
  eq(console.cases[1].status, 'failed')
end

T['set_case_result']['uses count fallbacks and marks non-accepted statuses failed'] = function()
  local console = make_console()
  console:set_case_result(1, { status = 'Finished', correct = 1, total = 1 })
  eq(console.cases[1].status, 'passed')

  console:set_case_result(1, { status = 'Time Limit Exceeded' })
  eq(console.cases[1].status, 'failed')
end

T['set_case_result']['ignores unknown case indexes and invalid results'] = function()
  local console = make_console()
  eq(pcall(console.set_case_result, console, 99, { status = 'Accepted' }), true)
  eq(pcall(console.set_case_result, console, 1, nil), true)
  eq(console.cases[1].status, 'unknown')
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
  local calls = 0
  helpers.with_stub(
    'leetcode-ui.question',
    'refresh',
    function() calls = calls + 1 end,
    function() console:refresh() end
  )
  eq(calls, 0)
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

T['spinner']['only refreshes while the console tab is active'] = function()
  local console, view = make_console()
  console.cases[1].running = true
  view.active = 'info'
  local refreshed = 0
  MiniTest.finally(function() console:stop_spinner() end)
  helpers.with_stub('leetcode-ui.question', 'refresh', function() refreshed = refreshed + 1 end, function()
    console:start_spinner()
    eq(helpers.wait_for(function() return console.frame > 1 end, 1000), true)
    eq(refreshed, 0)

    view.active = 'console'
    eq(helpers.wait_for(function() return refreshed > 0 end, 1000), true)
    console:stop_spinner()
  end)
end

T['spinner']['stops when no case is running'] = function()
  local console = make_console()
  console:start_spinner()
  eq(helpers.wait_for(function() return console.timer == nil end, 1000), true)
end

return T
