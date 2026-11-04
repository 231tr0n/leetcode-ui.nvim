-- Tests for leetcode-ui.api.runner.

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['api_runner'] = new_set()

T['api_runner']['normalize maps status codes and fields'] = function()
  local runner = helpers.mod('api.runner')
  local result = runner.normalize({
    status_code = 11,
    elapsed_time = 5,
    memory = 1024,
    total_correct = 1,
    total_testcases = 2,
    compare_result = '10',
    std_output_list = { 'a', 'b' },
    pretty_stdout = 'pretty',
    code_answer = { '[0,1]', '[1,0]' },
    expected_code_answer = { '[0,1]', '[1,0]' },
    full_run_error = 'details',
    input_formatted = 'input',
    expected_output = 'expected',
    code_output = 'got',
    lang = 'python3',
  }, false)

  eq(result.status, 'Wrong Answer')
  eq(result.ok, false)
  eq(result.message, 'details')
  eq(result.runtime_ms, 5)
  eq(result.memory_bytes, 1024)
  eq(result.correct, 1)
  eq(result.total, 2)
  eq(result.compare, '10')
  eq(result.stdouts[2], 'b')
  eq(result.pretty_stdout, 'pretty')
  eq(result.answers[1], '[0,1]')
  eq(result.expected_answers[2], '[1,0]')
  eq(result.input, 'input')
  eq(result.expected_output, 'expected')
  eq(result.code_output, 'got')
  eq(result.lang, 'python3')
  eq(result.is_submit, false)
end

T['api_runner']['normalize maps every judge status and prefers the server label'] = function()
  local runner = helpers.mod('api.runner')
  local expected = {
    [10] = 'Accepted',
    [11] = 'Wrong Answer',
    [12] = 'Memory Limit Exceeded',
    [13] = 'Time Limit Exceeded',
    [14] = 'Output Limit Exceeded',
    [15] = 'Runtime Error',
    [16] = 'Internal Error',
    [20] = 'Compile Error',
    [21] = 'Compile Error',
    [50] = 'Rejected',
  }
  for code, status in pairs(expected) do
    eq(runner.normalize({ status_code = code }, false).status, status)
  end
  eq(runner.normalize({ status_code = 10, status_msg = 'Server status' }, false).status, 'Server status')
end

T['api_runner']['normalize handles compile errors and invalid testcases'] = function()
  local runner = helpers.mod('api.runner')
  local compile =
    runner.normalize({ status_code = 20, full_compile_error = 'compile failed', compile_error = 'legacy' }, true)
  eq(compile.status, 'Compile Error')
  eq(compile.message, 'compile failed')
  eq(compile.is_submit, true)

  local messages = {
    {
      { full_compile_error = 'full', full_run_error = 'run', task_compile_error = 'task', compile_error = 'compile' },
      'full',
    },
    { { full_run_error = 'run', task_compile_error = 'task', compile_error = 'compile' }, 'run' },
    { { task_compile_error = 'task', compile_error = 'compile' }, 'task' },
    { { compile_error = 'compile' }, 'compile' },
    { {}, 'Compilation failed' },
  }
  for _, case in ipairs(messages) do
    eq(runner.normalize(vim.tbl_extend('force', { status_code = 20 }, case[1]), true).message, case[2])
  end
  eq(runner.normalize({ status_code = 10, status_msg = '' }, false).status, 'Accepted')
  local rejected = runner.normalize({ status_code = 50, ai_judge_message = 'policy violation' }, true)
  eq(rejected.status, 'Rejected')
  eq(rejected.ok, false)
  eq(rejected.message, 'policy violation')

  local invalid = runner.normalize({ status_code = 10, invalid_testcase = true, compare_result = '10' }, false)
  eq(invalid.status, 'Invalid Testcase')
  eq(invalid.ok, false)
  eq(invalid.compare, nil)

  local null_flag = runner.normalize({ status_code = 10, invalid_testcase = vim.NIL }, false)
  eq(null_flag.status, 'Accepted')
  eq(null_flag.ok, true)

  local unknown = runner.normalize({}, false)
  eq(unknown.status, 'Finished')
  eq(unknown.ok, false)
end

T['api_runner']['interpret starts a run and polls'] = function()
  local runner = helpers.mod('api.runner')
  local calls = 0
  local request, poll_request
  helpers.with_stub('leetcode-ui.api', 'rest', function(method, path, body, _headers, opts)
    calls = calls + 1
    if calls == 1 then
      request = { method = method, path = path, body = vim.json.decode(body), retries = opts.retries }
      return { interpret_id = 'abc' }, nil
    end
    poll_request = { method = method, path = path }
    return { status_code = 10, elapsed_time = 3, memory = 1, total_correct = 1, total_testcases = 1 }, nil
  end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum', lang_slug = 'python3' }, 'code', 'input')
    eq(err, nil)
    eq(result.status, 'Accepted')
    eq(calls, 2)
  end)
  eq(request.method, 'POST')
  eq(request.path, '/problems/two-sum/interpret_solution/')
  eq(request.body.question_id, '1')
  eq(request.body.lang, 'python3')
  eq(request.body.typed_code, 'code')
  eq(request.body.data_input, 'input')
  eq(request.retries, 0)
  assert(poll_request ~= nil)
  eq(poll_request.method, 'GET')
  eq(poll_request.path, '/submissions/detail/abc/v2/check/')
end

T['api_runner']['interpret reports start failures'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return { error = 'nope' }, nil end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum' }, 'code', 'input')
    eq(result, nil)
    eq(err, 'nope')
  end)

  helpers.with_stub('leetcode-ui.api', 'rest', function() return nil, 'network' end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum' }, 'code', 'input')
    eq(result, nil)
    eq(err, 'network')
  end)

  helpers.with_stub('leetcode-ui.api', 'rest', function() return { interpret_id = vim.NIL }, nil end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum' }, 'code', 'input')
    eq(result, nil)
    eq(err, 'Failed to start test run')
  end)
end

T['api_runner']['submit starts a submission and polls'] = function()
  local runner = helpers.mod('api.runner')
  local calls = 0
  local request, poll_request
  helpers.with_stub('leetcode-ui.api', 'rest', function(method, path, body, _headers, opts)
    calls = calls + 1
    if calls == 1 then
      request = { method = method, path = path, body = vim.json.decode(body), retries = opts.retries }
      return { submission_id = 'xyz' }, nil
    end
    poll_request = { method = method, path = path }
    return { status_code = 10, elapsed_time = 1, memory = 2 }, nil
  end, function()
    local result, err = runner.submit({ id = '1', title_slug = 'two-sum', lang_slug = 'python3' }, 'code')
    eq(err, nil)
    eq(result.status, 'Accepted')
    eq(result.is_submit, true)
  end)
  eq(calls, 2)
  eq(request.method, 'POST')
  eq(request.path, '/problems/two-sum/submit/')
  eq(request.body.question_id, '1')
  eq(request.body.lang, 'python3')
  eq(request.body.typed_code, 'code')
  eq(request.retries, 0)
  assert(poll_request ~= nil)
  eq(poll_request.method, 'GET')
  eq(poll_request.path, '/submissions/detail/xyz/v2/check/')
end

T['api_runner']['submit reports start failures'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return {}, nil end, function()
    local result, err = runner.submit({ id = '1', title_slug = 'two-sum' }, 'code')
    eq(result, nil)
    eq(err, 'Failed to submit solution')
  end)
end

T['api_runner']['poll rejects malformed completion responses'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return { status_code = '10' }, nil end, function()
    local result, err = runner.poll('abc', false)
    eq(result, nil)
    eq(err, 'Malformed judging response')
  end)

  helpers.with_stub(
    'leetcode-ui.api',
    'rest',
    function() return { status_code = vim.NIL, state = 'SUCCESS' }, nil end,
    function()
      local result, err = runner.poll('abc', false)
      eq(result, nil)
      eq(err, 'Judging finished without a status')
    end
  )
end

T['api_runner']['poll waits for AI judging to finish'] = function()
  local runner = helpers.mod('api.runner')
  local attempts = 0
  helpers.with_stub('leetcode-ui.async', 'sleep', function() end, function()
    helpers.with_stub('leetcode-ui.api', 'rest', function()
      attempts = attempts + 1
      if attempts == 1 then return { status_code = 10, state = 'SUCCESS', ai_state = 'PENDING' }, nil end
      return { status_code = 10, state = 'SUCCESS', ai_state = 'SUCCESS' }, nil
    end, function()
      local result, err = runner.poll('abc', true)
      eq(err, nil)
      eq(result.status, 'Accepted')
      eq(attempts, 2)
    end)
  end)
end

T['api_runner']['poll waits for pending judging to finish'] = function()
  local runner = helpers.mod('api.runner')
  local attempts, method, path = 0, nil, nil
  helpers.with_stub('leetcode-ui.async', 'sleep', function() end, function()
    helpers.with_stub('leetcode-ui.api', 'rest', function(request_method, request_path)
      method, path = request_method, request_path
      attempts = attempts + 1
      if attempts == 1 then return { state = 'PENDING' }, nil end
      return { status_code = 10, state = 'SUCCESS' }, nil
    end, function()
      local result, err = runner.poll('abc', true)
      eq(err, nil)
      eq(result.status, 'Accepted')
      eq(attempts, 2)
      eq(method, 'GET')
      eq(path, '/submissions/detail/abc/v2/check/')
    end)
  end)
end

T['api_runner']['poll stops before the first request when cancelled'] = function()
  local runner = helpers.mod('api.runner')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'rest', function()
    calls = calls + 1
    return { state = 'PENDING' }, nil
  end, function()
    local result, err = runner.poll('abc', true, function() return true end)
    eq(result, nil)
    eq(err, 'Cancelled')
    eq(calls, 0)
  end)
end

T['api_runner']['poll stops when cancelled'] = function()
  local runner = helpers.mod('api.runner')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'rest', function()
    calls = calls + 1
    return { state = 'PENDING' }, nil
  end, function()
    local result, err = runner.poll('abc', true, function() return calls > 0 end)
    eq(result, nil)
    eq(err, 'Cancelled')
    eq(calls, 1)
  end)
end

T['api_runner']['poll reports polling errors and timeouts'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return nil, 'poll failed' end, function()
    local result, err = runner.poll('abc', false)
    eq(result, nil)
    eq(err, 'poll failed')
  end)

  local now, attempts = 0, 0
  helpers.with_field(vim.uv, 'now', function() return now end, function()
    helpers.with_stub('leetcode-ui.async', 'sleep', function(ms) now = now + ms end, function()
      helpers.with_stub('leetcode-ui.api', 'rest', function()
        attempts = attempts + 1
        return {}, nil
      end, function()
        local result, err = runner.poll('abc', true)
        eq(result, nil)
        eq(err, 'Judging timed out')
        eq(attempts, 334)
        eq(now, 300600)
      end)
    end)
  end)
end

return T
