-- Tests for leetcode-ui.net and the API layer.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

local function json(body) return vim.json.encode(body) end

T['net'] = new_set()

T['net']['curl_args includes method, headers, body, and cookie file'] = function()
  local net = helpers.mod('net')
  local args = net.curl_args({
    method = 'POST',
    url = 'https://example.com',
    body = 'x',
    headers = { 'A: b' },
    cookie_file = '/tmp/jar',
    timeout = 10,
  }, '/tmp/h', '/tmp/b')
  eq(args[1], 'curl')
  eq(args[#args], 'https://example.com')
  eq(vim.tbl_contains(args, '--data-binary'), true)
  eq(vim.tbl_contains(args, '-b'), true)
  eq(vim.tbl_contains(args, 'A: b'), true)
  eq(vim.tbl_contains(args, '-D'), true)
  eq(vim.tbl_contains(args, '-o'), true)
end

T['net']['curl_args omits an empty body'] = function()
  local net = helpers.mod('net')
  local args = net.curl_args({ url = 'https://example.com', body = '' }, '/tmp/h', '/tmp/b')
  eq(vim.tbl_contains(args, '--data-binary'), false)
end

T['net']['parse_headers parses status and lowercase headers'] = function()
  local net = helpers.mod('net')
  local status, headers = net.parse_headers('HTTP/2 200 \r\nContent-Type: application/json\r\nX-Foo: bar\r\n\r\n')
  eq(status, 200)
  eq(headers['content-type'], 'application/json')
  eq(headers['x-foo'], 'bar')
end

T['net']['parse_headers uses the last HTTP block'] = function()
  local net = helpers.mod('net')
  local status, headers =
    net.parse_headers('HTTP/1.1 302 Found\r\nLocation: /x\r\n\r\nHTTP/2 200 \r\nContent-Type: text/plain\r\n\r\n')
  eq(status, 200)
  eq(headers['content-type'], 'text/plain')
  eq(headers['location'], nil)
end

T['net']['parse_headers returns zero without an HTTP line'] = function()
  local net = helpers.mod('net')
  local status, headers = net.parse_headers('garbage')
  eq(status, 0)
  eq(headers, {})
end

T['net']['read_response reads and deletes temporary files'] = function()
  local net = helpers.mod('net')
  local headers = vim.fn.tempname()
  local body = vim.fn.tempname()
  vim.fn.writefile({ 'HTTP/1.1 200 OK', 'Content-Type: text/plain', '', 'hello' }, headers)
  vim.fn.writefile({ 'hello' }, body)
  local response = net.read_response(headers, body)
  eq(response.status, 200)
  eq(response.body, 'hello')
  eq(vim.fn.filereadable(headers), 0)
  eq(vim.fn.filereadable(body), 0)
end

T['net']['read_response returns nil for missing headers'] = function()
  local net = helpers.mod('net')
  eq(net.read_response('/definitely/missing', '/definitely/missing'), nil)
end

T['net']['should_retry covers transient statuses'] = function()
  local net = helpers.mod('net')
  eq(net.should_retry(403), true)
  eq(net.should_retry(429), true)
  eq(net.should_retry(500), true)
  eq(net.should_retry(200), false)
  eq(net.should_retry(404), false)
end

T['net']['request uses sync path on the main thread'] = function()
  local net = helpers.mod('net')
  local calls = { sync = 0, async = 0 }
  helpers.with_stub('leetcode-ui.net', 'request_sync', function()
    calls.sync = calls.sync + 1
    return { status = 200, headers = {}, body = '{}' }, nil
  end, function()
    helpers.with_stub('leetcode-ui.net', 'request_async', function()
      calls.async = calls.async + 1
      return nil, 'should not run'
    end, function()
      local response, err = net.request({ url = 'https://example.com' })
      assert(response ~= nil)
      eq(err, nil)
      eq(response.status, 200)
      eq(calls.sync, 1)
      eq(calls.async, 0)
    end)
  end)
end

T['net']['request uses async path inside a coroutine'] = function()
  local net = helpers.mod('net')
  ---@type any
  local result = nil
  helpers.with_stub(
    'leetcode-ui.net',
    'request_async',
    function() return { status = 201, headers = {}, body = '' }, nil end,
    function()
      local thread = coroutine.create(function() result = net.request({ url = 'https://example.com' }) end)
      coroutine.resume(thread)
    end
  )
  eq(type(result), 'table')
  eq(result.status, 201)
end

T['net']['request_sync retries transient failures'] = function()
  local net = helpers.mod('net')
  local attempts = 0
  helpers.with_stub('leetcode-ui.net', 'request_once', function()
    attempts = attempts + 1
    if attempts < 3 then return { status = 500, headers = {}, body = '' } end
    return { status = 200, headers = {}, body = 'ok' }
  end, function()
    local response, err = net.request_sync({ url = 'https://example.com', retries = 3 })
    eq(err, nil)
    eq(response.status, 200)
    eq(attempts, 3)
  end)
end

T['api'] = new_set()

T['api']['base_url and problems_url reflect the configured domain'] = function()
  local api = helpers.mod('api')
  eq(api.base_url(), 'https://leetcode.com')
  eq(api.problems_url('two-sum'), 'https://leetcode.com/problems/two-sum/')
end

T['api']['is_nillish understands vim.NIL'] = function()
  local api = helpers.mod('api')
  eq(api.is_nillish(nil), true)
  eq(api.is_nillish(vim.NIL), true)
  eq(api.is_nillish({}), false)
  eq(api.is_nillish(0), false)
end

T['api']['graphql returns decoded data'] = function()
  local api = helpers.mod('api')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = json({ data = { answer = 42 } }) }, nil end,
    function()
      local data, err = api.graphql('query { answer }')
      eq(err, nil)
      eq(data.answer, 42)
    end
  )
end

T['api']['graphql rejects null data'] = function()
  local api = helpers.mod('api')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = '{"data":null}' }, nil end,
    function()
      local data, err = api.graphql('query')
      eq(data, nil)
      eq(err, 'Empty response')
    end
  )
end

T['api']['graphql reports GraphQL errors'] = function()
  local api = helpers.mod('api')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function()
      return { status = 200, body = json({ errors = { { message = 'bad query' }, { message = 'bad field' } } }) }, nil
    end,
    function()
      local data, err = api.graphql('query')
      eq(data, nil)
      eq(err, 'bad query\nbad field')
    end
  )
end

T['api']['graphql handles transport and decoding failures'] = function()
  local api = helpers.mod('api')

  helpers.with_stub('leetcode-ui.net', 'request', function() return nil, 'curl failed' end, function()
    local data, err = api.graphql('query')
    eq(data, nil)
    eq(err, 'curl failed')
  end)

  helpers.with_stub('leetcode-ui.net', 'request', function() return nil, nil end, function()
    local data, err = api.graphql('query')
    eq(data, nil)
    eq(err, 'Network request failed')
  end)

  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 200, body = 'nope' }, nil end, function()
    local data, err = api.graphql('query')
    eq(data, nil)
    eq(type(err), 'string')
  end)
end

T['api']['rest returns decoded JSON'] = function()
  local api = helpers.mod('api')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = json({ interpret_id = 'abc' }) }, nil end,
    function()
      local data, err = api.rest('POST', '/test', '{}')
      eq(err, nil)
      eq(data.interpret_id, 'abc')
    end
  )
end

T['api']['graphql reports throttling'] = function()
  local api = helpers.mod('api')
  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 429, body = '' }, nil end, function()
    local data, err = api.graphql('query')
    eq(data, nil)
    eq(helpers.contains(err, 'Too many requests'), true)
  end)
end

T['api']['rest reports throttling'] = function()
  local api = helpers.mod('api')
  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 429, body = '' }, nil end, function()
    local data, err = api.rest('POST', '/test', '{}')
    eq(data, nil)
    eq(helpers.contains(err, 'Too many requests'), true)
  end)
end

T['api']['rest rejects null bodies'] = function()
  local api = helpers.mod('api')
  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 200, body = 'null' }, nil end, function()
    local data, err = api.rest('GET', '/test')
    eq(data, nil)
    eq(err, 'Empty response')
  end)
end

T['api']['rest reports malformed responses'] = function()
  local api = helpers.mod('api')
  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 200, body = 'html' }, nil end, function()
    local data, err = api.rest('GET', '/test')
    eq(data, nil)
    eq(type(err), 'string')
  end)
end

T['api_question'] = new_set()

T['api_question']['clean removes vim.NIL recursively'] = function()
  local question = helpers.mod('api.question')
  local cleaned = question.clean({ a = 'x', nested = { b = vim.NIL, c = 2 } })
  eq(cleaned.a, 'x')
  eq(cleaned.nested.b, nil)
  eq(cleaned.nested.c, 2)
end

T['api_question']['decode_meta handles valid and invalid JSON'] = function()
  local question = helpers.mod('api.question')
  eq(question.decode_meta('{"x":1}').x, 1)
  eq(question.decode_meta('nope'), nil)
  eq(question.decode_meta(nil), nil)
  eq(question.decode_meta(''), nil)
end

T['api_question']['normalize defaults and status mapping'] = function()
  local question = helpers.mod('api.question')
  local entry = question.normalize({})
  eq(entry.frontend_id, '')
  eq(entry.ac_rate, 0)
  eq(entry.is_paid_only, false)
  eq(type(entry.topic_tags), 'table')

  eq(question.normalize({ status = 'AC' }).status, 'solved')
  eq(question.normalize({ status = 'null' }).status, nil)
  eq(question.normalize({ status = 'notac' }).status, 'notac')
end

T['api_question']['normalize copies topic tags'] = function()
  local question = helpers.mod('api.question')
  local entry = question.normalize({ topic_tags = { { name = 'Array', slug = 'array' } } })
  eq(entry.topic_tags[1].name, 'Array')
  eq(entry.topic_tags[1].slug, 'array')
end

T['api_question']['get_list fetches and caches a single page'] = function()
  local api = require('leetcode-ui.api')
  local question = helpers.mod('api.question')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return {
      problemsetQuestionList = {
        total = 2,
        questions = {
          { title = 'A', title_slug = 'a', frontend_id = 1, difficulty = 'Easy' },
          { title = 'B', title_slug = 'b', frontend_id = 2, difficulty = 'Hard' },
        },
      },
    },
      nil
  end, function()
    local list, err = question.get_list()
    eq(err, nil)
    eq(list.total, 2)
    eq(#list.questions, 2)

    local cached = question.get_list()
    eq(cached.total, 2)
    eq(calls, 1)
  end)
  eq(calls, 1)
  eq(api.is_nillish(nil), true)
end

T['api_question']['get_list paginates until total is reached'] = function()
  local question = helpers.mod('api.question')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    local rows = {}
    for index = 1, 100 do
      local id = (calls - 1) * 100 + index
      table.insert(rows, { title = 'Q' .. id, title_slug = 'q-' .. id, frontend_id = id, difficulty = 'Easy' })
    end
    if calls == 2 then rows = { rows[1], rows[2] } end
    return { problemsetQuestionList = { total = 102, questions = rows } }, nil
  end, function()
    local list = question.get_list()
    eq(#list.questions, 102)
    eq(calls, 2)
  end)
end

T['api_question']['get_list reports failures and does not cache them'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'network down' end, function()
    local list, err = question.get_list()
    eq(list, nil)
    eq(err, 'network down')
  end)
end

T['api_question']['get_list ignores a non-numeric cache total'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'cached' } }, total = 'many', cache_time = os.time() })

  local list = question.get_list()
  eq(list.total, 1)
end

T['api_question']['get_list uses a complete cache without a total field'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'cached' } }, cache_time = os.time() })

  local list = question.get_list()
  eq(list.total, 1)
  eq(list.questions[1].title_slug, 'cached')
end

T['api_question']['find_in_list uses the cache then falls back'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'cached' } }, total = 1, cache_time = os.time() })

  eq(question.find_in_list('cached').title_slug, 'cached')

  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_list',
    function() return { total = 1, questions = { { title_slug = 'fetched' } } }, nil end,
    function()
      eq(question.find_in_list('fetched').title_slug, 'fetched')
      eq(question.find_in_list('missing'), nil)
    end
  )
end

T['api_question']['update_list_status updates cached entries'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'two-sum', status = nil } }, total = 1 })
  question.update_list_status('two-sum', 'solved')
  eq(storage.read_cache().problems[1].status, 'solved')
end

T['api_question']['clear_cache empties cached problems'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'x' } }, total = 1, cache_time = os.time() })
  question.clear_cache()
  eq(#storage.read_cache().problems, 0)
  eq(storage.read_cache().cache_time, 0)
end

T['api_question']['get_daily handles success and missing records'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { todayRecord = { question = { title_slug = 'daily' } } }, nil end,
    function() eq(question.get_daily(), 'daily') end
  )

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return { todayRecord = {} }, nil end, function()
    local slug, err = question.get_daily()
    eq(slug, nil)
    eq(err, 'No daily question found')
  end)

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'failed' end, function()
    local slug, err = question.get_daily()
    eq(slug, nil)
    eq(err, 'failed')
  end)
end

T['api_question']['get_random handles success and missing records'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub('leetcode-ui.api', 'graphql', function(_query, variables)
    eq(variables.filters.difficulty, 'Hard')
    return { randomQuestion = { title_slug = 'random' } }, nil
  end, function() eq(question.get_random({ difficulty = 'Hard' }), 'random') end)

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return { randomQuestion = {} }, nil end, function()
    local slug, err = question.get_random()
    eq(slug, nil)
    eq(err, 'No random question found')
  end)

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'failed' end, function()
    local slug, err = question.get_random()
    eq(slug, nil)
    eq(err, 'failed')
  end)
end

T['api_question']['get_detail normalizes snippets, metadata, and testcases'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function()
      return {
        question = {
          id = '1',
          frontend_id = '1',
          title = 'Two Sum',
          title_slug = 'two-sum',
          content = '<p>x</p>',
          code_snippets = {
            { lang = 'Python3', lang_slug = 'python3', code = 'pass' },
          },
          testcase_list = { '[1]\n1' },
          meta_data = '{"name":"twoSum"}',
          stats = '{"totalAccepted":"1"}',
        },
      },
        nil
    end,
    function()
      local detail, err = question.get_detail('two-sum')
      eq(err, nil)
      eq(detail.snippets.python3.code, 'pass')
      eq(detail.testcases[1], '[1]\n1')
      eq(detail.meta.name, 'twoSum')
      eq(detail.stats.totalAccepted, '1')
    end
  )
end

T['api_question']['get_detail rejects missing questions'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub('leetcode-ui.api', 'graphql', function() return { question = {} }, nil end, function()
    local detail, err = question.get_detail('missing')
    eq(detail, nil)
    eq(helpers.contains(err, 'was not found'), true)
  end)
end

T['api_stats'] = new_set()

T['api_stats']['username requires a verified signed-in session'] = function()
  local stats = helpers.mod('api.stats')

  helpers.with_stub('leetcode-ui.auth', 'verify', function() return nil, 'no session' end, function()
    local name, err = stats.username()
    eq(name, nil)
    eq(err, 'no session')
  end)

  helpers.with_stub('leetcode-ui.auth', 'verify', function() return { signed_in = false }, nil end, function()
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
    helpers.with_stub(
      'leetcode-ui.api',
      'graphql',
      function()
        return {
          allQuestionsCount = { { difficulty = 'Easy', count = 10 } },
          matchedUser = { solved_counts = { acSubmissionNum = { { difficulty = 'Easy', count = 3 } } } },
        },
          nil
      end,
      function()
        local solved, err = stats.solved()
        eq(err, nil)
        eq(solved.total.Easy, 10)
        eq(solved.solved.Easy, 3)
      end
    )
  end)
end

T['api_stats']['skills and languages return their sections'] = function()
  local stats = helpers.mod('api.stats')
  helpers.with_stub('leetcode-ui.api.stats', 'username', function() return 'user', nil end, function()
    local response = { matchedUser = { tag_problems_counts = { fundamental = { { tag_name = 'Array' } } } } }
    helpers.with_stub('leetcode-ui.api', 'graphql', function() return response, nil end, function()
      local skills, err = stats.skills()
      eq(err, nil)
      eq(skills.fundamental[1].tag_name, 'Array')
    end)

    helpers.with_stub(
      'leetcode-ui.api',
      'graphql',
      function() return { matchedUser = { language_problem_count = { { language_name = 'Python3' } } } }, nil end,
      function()
        local languages, err = stats.languages()
        eq(err, nil)
        eq(languages[1].language_name, 'Python3')
      end
    )
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
    eq(type(err), 'string')
  end)
end

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
  eq(result.memory_mb, 1024)
  eq(result.correct, 1)
  eq(result.total, 2)
  eq(result.compare, '10')
  eq(result.stdouts[2], 'b')
  eq(result.pretty_stdout, 'pretty')
  eq(result.input, 'input')
  eq(result.expected_output, 'expected')
  eq(result.code_output, 'got')
  eq(result.lang, 'python3')
  eq(result.is_submit, false)
end

T['api_runner']['normalize handles compile errors and invalid testcases'] = function()
  local runner = helpers.mod('api.runner')
  local compile = runner.normalize({ status_code = 20, task_compile_error = 'compile failed' }, true)
  eq(compile.status, 'Compile Error')
  eq(compile.message, 'compile failed')
  eq(compile.is_submit, true)

  local invalid = runner.normalize({ status_code = 10, invalid_testcase = true }, false)
  eq(invalid.status, 'Invalid Testcase')
  eq(invalid.ok, false)
end

T['api_runner']['interpret starts a run and polls'] = function()
  local runner = helpers.mod('api.runner')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'rest', function()
    calls = calls + 1
    if calls == 1 then return { interpret_id = 'abc' }, nil end
    return { status_code = 10, elapsed_time = 3, memory = 1, total_correct = 1, total_testcases = 1 }, nil
  end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum', lang_slug = 'python3' }, 'code', 'input')
    eq(err, nil)
    eq(result.status, 'Accepted')
    eq(calls, 2)
  end)
end

T['api_runner']['interpret reports start failures'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return { error = 'nope' }, nil end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum' }, 'code', 'input')
    eq(result, nil)
    eq(err, 'Failed to start test run')
  end)

  helpers.with_stub('leetcode-ui.api', 'rest', function() return nil, 'network' end, function()
    local result, err = runner.interpret({ id = '1', title_slug = 'two-sum' }, 'code', 'input')
    eq(result, nil)
    eq(err, 'network')
  end)
end

T['api_runner']['submit starts a submission and polls'] = function()
  local runner = helpers.mod('api.runner')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'rest', function()
    calls = calls + 1
    if calls == 1 then return { submission_id = 'xyz' }, nil end
    return { status_code = 10, elapsed_time = 1, memory = 2 }, nil
  end, function()
    local result, err = runner.submit({ id = '1', title_slug = 'two-sum', lang_slug = 'python3' }, 'code')
    eq(err, nil)
    eq(result.status, 'Accepted')
    eq(result.is_submit, true)
  end)
end

T['api_runner']['submit reports start failures'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return {}, nil end, function()
    local result, err = runner.submit({ id = '1', title_slug = 'two-sum' }, 'code')
    eq(result, nil)
    eq(err, 'Failed to submit solution')
  end)
end

T['api_runner']['listen reports polling errors and timeouts'] = function()
  local runner = helpers.mod('api.runner')
  helpers.with_stub('leetcode-ui.api', 'rest', function() return nil, 'poll failed' end, function()
    local result, err = runner.listen('abc', false)
    eq(result, nil)
    eq(err, 'poll failed')
  end)

  local original_now = vim.uv.now
  local original_sleep = runner.sleep
  local now = 0
  vim.uv.now = function() return now end
  runner.sleep = function(ms) now = now + ms end
  helpers.with_stub('leetcode-ui.api', 'rest', function() return {}, nil end, function()
    local result, err = runner.listen('abc', true)
    eq(result, nil)
    eq(err, 'Judging timed out')
  end)
  vim.uv.now = original_now
  runner.sleep = original_sleep
end

T['api_runner']['sleep waits on the main thread'] = function()
  local runner = helpers.mod('api.runner')
  local started = vim.uv.now()
  runner.sleep(1)
  eq(vim.uv.now() >= started, true)
end

return T
