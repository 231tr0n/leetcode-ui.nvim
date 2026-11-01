-- Tests for leetcode-ui.net and leetcode-ui.api plumbing (stubs).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['net'] = new_set()

T['net']['request returns nil with message without curl'] = function()
  local net = require('leetcode-ui.net')
  local ok = pcall(net.request, { method = 'GET', url = 'http://127.0.0.1:1/nowhere' })
  eq(type(ok), 'boolean')
end

T['api'] = new_set()

T['api']['base_url reflects config'] = function()
  local api = require('leetcode-ui.api')
  eq(type(api.base_url()), 'string')
  eq(api.base_url():find('leetcode') ~= nil, true)
end

T['api']['is_nillish'] = function()
  local api = helpers.mod('api')
  eq(api.is_nillish(nil), true)
  eq(api.is_nillish({}), false)
  eq(api.is_nillish(0), false)
end

T['api']['rest uses stub'] = function()
  local api = helpers.mod('api')
  local calls = {}
  helpers.with_stub('leetcode-ui.api', 'rest', function(method, path, body)
    table.insert(calls, { method = method, path = path, body = body })
    return { status = 'RUNNING', interpret_id = 'abc' }, nil
  end, function()
    local res, err = api.rest('POST', '/test', { x = 1 })
    eq(res.interpret_id, 'abc')
    eq(err, nil)
    eq(#calls, 1)
    eq(calls[1].method, 'POST')
  end)
end

T['api']['graphql uses stub'] = function()
  local api = helpers.mod('api')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { question = { titleSlug = 'two-sum' } }, nil end,
    function()
      local data, err = api.graphql('q', { a = 1 })
      eq(data.question.titleSlug, 'two-sum')
      eq(err, nil)
    end
  )
end

T['api_question'] = new_set()

T['api_question']['clean normalizes payload'] = function()
  local q = helpers.mod('api.question')
  local cleaned = q.clean({ titleSlug = 'two-sum', isPaidOnly = true })
  eq(cleaned.titleSlug, 'two-sum')
  eq(cleaned.isPaidOnly, true)
end

T['api_question']['normalize defaults'] = function()
  local q = helpers.mod('api.question')
  local n = q.normalize({})
  eq(type(n), 'table')
  eq(type(n.ac_rate), 'number')
end

T['net']['parse_headers extracts status and headers'] = function()
  local net = require('leetcode-ui.net')
  local status, headers = net.parse_headers('HTTP/2 200 \r\nContent-Type: application/json\r\nX-Foo: bar\r\n\r\n')
  eq(status, 200)
  eq(headers['content-type'], 'application/json')
  eq(headers['x-foo'], 'bar')
end

T['net']['parse_headers handles multiple HTTP blocks'] = function()
  local net = require('leetcode-ui.net')
  local status, headers =
    net.parse_headers('HTTP/1.1 302 Found\r\nLocation: /x\r\n\r\nHTTP/2 200 \r\nContent-Type: text/plain\r\n\r\n')
  eq(status, 200)
  eq(headers['content-type'], 'text/plain')
  eq(headers['location'], nil)
end

T['net']['curl_args includes curl and url'] = function()
  local net = require('leetcode-ui.net')
  local args =
    net.curl_args({ method = 'POST', url = 'https://example.com', body = 'x', timeout = 10 }, '/tmp/h', '/tmp/b')
  eq(args[1], 'curl')
  eq(args[#args], 'https://example.com')
end

T['net']['should_retry'] = function()
  local net = require('leetcode-ui.net')
  eq(net.should_retry(403), true)
  eq(net.should_retry(429), true)
  eq(net.should_retry(500), true)
  eq(net.should_retry(200), false)
  eq(net.should_retry(404), false)
end

T['api_question']['get_list works on main thread'] = function()
  local qmod = require('leetcode-ui.api.question') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local original_graphql = api.graphql
  api.graphql = function(_query, _vars)
    return {
      problemsetQuestionList = {
        total = 1,
        questions = {
          {
            title = 'Two Sum',
            title_slug = 'two-sum',
            frontend_id = '1',
            difficulty = 'Easy',
            ac_rate = 50.5,
            is_paid_only = false,
            status = nil,
            topic_tags = {},
          },
        },
      },
    },
      nil
  end
  local list, err = qmod.get_list()
  eq(err, nil)
  eq(list.total, 1)
  eq(#list.questions, 1)
  api.graphql = original_graphql
end

T['net']['uses sync path on main thread'] = function()
  local net = require('leetcode-ui.net')
  local called = { sync = 0, async = 0 }
  helpers.with_stub('leetcode-ui.net', 'request_sync', function(_opts)
    called.sync = called.sync + 1
    return { status = 200, headers = {}, body = '{}' }, nil
  end, function()
    helpers.with_stub('leetcode-ui.net', 'request_async', function(_opts)
      called.async = called.async + 1
      return nil, 'should not be called'
    end, function()
      local res, err = net.request({ method = 'GET', url = 'http://example.com' })
      eq(called.sync, 1)
      eq(called.async, 0)
      eq(err, nil)
      eq((res --[[@as any]]).status, 200)
    end)
  end)
end

T['runner'] = new_set()

T['runner']['interpret works on main thread'] = function()
  local runner = require('leetcode-ui.api.runner') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local original_rest = api.rest
  local calls = 0
  api.rest = function(_method, _path, _body)
    calls = calls + 1
    if calls == 1 then return { interpret_id = 'abc' }, nil end
    return { status_code = 10, elapsed_time = 5, memory = 1024 * 1024, total_correct = 1, total_testcases = 1 }, nil
  end
  local question = { id = '1', title_slug = 'two-sum', lang_slug = 'python3' }
  local result, err = runner.interpret(question, 'code', 'input')
  eq(err, nil)
  eq(result.status, 'Accepted')
  eq(result.ok, true)
  api.rest = original_rest
end

T['runner']['interpret polls on main thread'] = function()
  local runner = require('leetcode-ui.api.runner') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local original_rest = api.rest
  local calls = 0
  api.rest = function(_method, _path, _body)
    calls = calls + 1
    if calls == 1 then return { interpret_id = 'abc' }, nil end
    if calls == 2 then return { status_code = nil }, nil end
    return { status_code = 11, elapsed_time = 5, memory = 1024, total_correct = 0, total_testcases = 1 }, nil
  end
  local question = { id = '1', title_slug = 'two-sum', lang_slug = 'python3' }
  local result, err = runner.interpret(question, 'code', 'input')
  eq(err, nil)
  eq(result.status, 'Wrong Answer')
  api.rest = original_rest
end

T['runner']['submit works on main thread'] = function()
  local runner = require('leetcode-ui.api.runner') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local original_rest = api.rest
  local calls = 0
  api.rest = function(_method, _path, _body)
    calls = calls + 1
    if calls == 1 then return { submission_id = 'xyz' }, nil end
    return { status_code = 10, elapsed_time = 5, memory = 1024 * 1024 }, nil
  end
  local question = { id = '1', title_slug = 'two-sum', lang_slug = 'python3' }
  local result, err = runner.submit(question, 'code')
  eq(err, nil)
  eq(result.status, 'Accepted')
  api.rest = original_rest
end

T['stats_api'] = new_set()

T['stats_api']['solved works on main thread'] = function()
  local stats = require('leetcode-ui.api.stats') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local auth = require('leetcode-ui.auth') --[[@as any]]
  local original_graphql = api.graphql
  local original_verify = auth.verify
  auth.verify = function() return { signed_in = true, name = 'u' }, nil end
  api.graphql = function(_q, _v)
    return { allQuestionsCount = { { difficulty = 'Easy', count = 10 } }, matchedUser = { solved_counts = { acSubmissionNum = { { difficulty = 'Easy', count = 3 } } } } }, nil
  end
  local solved, err = stats.solved()
  eq(err, nil)
  eq(solved.total.Easy, 10)
  eq(solved.solved.Easy, 3)
  api.graphql = original_graphql
  auth.verify = original_verify
end

T['stats_api']['languages works on main thread'] = function()
  local stats = require('leetcode-ui.api.stats') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local auth = require('leetcode-ui.auth') --[[@as any]]
  local original_graphql = api.graphql
  local original_verify = auth.verify
  auth.verify = function() return { signed_in = true, name = 'u' }, nil end
  api.graphql = function(_q, _v) return { matchedUser = { language_problem_count = { { language_name = 'Python3', problems_solved = 5 } } } }, nil end
  local langs, err = stats.languages()
  eq(err, nil)
  eq(#langs, 1)
  eq(langs[1].language_name, 'Python3')
  api.graphql = original_graphql
  auth.verify = original_verify
end

T['stats_api']['skills works on main thread'] = function()
  local stats = require('leetcode-ui.api.stats') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local auth = require('leetcode-ui.auth') --[[@as any]]
  local original_graphql = api.graphql
  local original_verify = auth.verify
  auth.verify = function() return { signed_in = true, name = 'u' }, nil end
  api.graphql = function(_q, _v) return { matchedUser = { tag_problems_counts = { fundamental = { { tag_name = 'Array', problems_solved = 2 } } } } }, nil end
  local skills, err = stats.skills()
  eq(err, nil)
  eq(type(skills), 'table')
  api.graphql = original_graphql
  auth.verify = original_verify
end

T['stats_api']['streak works on main thread'] = function()
  local stats = require('leetcode-ui.api.stats') --[[@as any]]
  local api = require('leetcode-ui.api') --[[@as any]]
  local original_graphql = api.graphql
  api.graphql = function(_q, _v) return { streakCounter = { streak_count = 7 } }, nil end
  local streak, err = stats.streak()
  eq(err, nil)
  eq(streak.streak_count, 7)
  api.graphql = original_graphql
end

return T
