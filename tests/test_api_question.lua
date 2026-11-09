-- Tests for leetcode-ui.api.question.

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['api_question'] = new_set()

T['api_question']['clean removes vim.NIL recursively'] = function()
  local question = helpers.mod('api.question')
  local cleaned = question.remove_nil({ a = 'x', nested = { b = vim.NIL, c = 2 } })
  eq(cleaned.a, 'x')
  eq(cleaned.nested.b, nil)
  eq(cleaned.nested.c, 2)
  eq(question.remove_nil({ 'a', vim.NIL, 'b' }), { 'a', 'b' })
end

T['api_question']['normalize defaults and status mapping'] = function()
  local question = helpers.mod('api.question')
  local entry = question.normalize_entry({})
  eq(entry.frontend_id, '')
  eq(entry.ac_rate, 0)
  eq(entry.is_paid_only, false)
  eq(type(entry.topic_tags), 'table')
  eq(question.normalize_entry({ frontend_id = 1 }).frontend_id, '1')

  eq(question.normalize_entry({ status = 'AC' }).status, 'solved')
  eq(question.normalize_entry({ status = 'ac' }).status, 'solved')
  eq(question.normalize_entry({ status = 'notac' }).status, 'attempted')
  eq(question.normalize_entry({ status = 'attempted' }).status, 'attempted')
  eq(question.normalize_entry({ status = 'null' }).status, nil)
  eq(question.normalize_entry({ status = 'unknown' }).status, nil)
end

T['api_question']['normalize copies topic tags'] = function()
  local question = helpers.mod('api.question')
  local entry = question.normalize_entry({ topic_tags = { { name = 'Array', slug = 'array' } } })
  eq(entry.topic_tags[1].name, 'Array')
  eq(entry.topic_tags[1].slug, 'array')
end

T['api_question']['get_list fetches and caches a single page'] = function()
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
end

T['api_question']['get_list paginates until total is reached'] = function()
  local question = helpers.mod('api.question')
  local calls = 0
  local skips = {}
  helpers.with_stub('leetcode-ui.api', 'graphql', function(_query, variables)
    calls = calls + 1
    table.insert(skips, variables.skip)
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
    eq(list.questions[100].title_slug, 'q-100')
    eq(list.questions[101].title_slug, 'q-101')
    eq(list.questions[102].title_slug, 'q-102')
    eq(calls, 2)
    eq(skips, { 0, 100 })
  end)
end

T['api_question']['get_list stops on an exact full page'] = function()
  local question = helpers.mod('api.question')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    local rows = {}
    for index = 1, 100 do
      table.insert(rows, { title_slug = 'q-' .. index })
    end
    return { problemsetQuestionList = { total = 100, questions = rows } }, nil
  end, function()
    local list = question.get_list()
    eq(#list.questions, 100)
    eq(calls, 1)
  end)
end

T['api_question']['get_list reports failures and does not cache them'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = 0,
  })
  helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'network down' end, function()
    local list, err = question.get_list()
    eq(list, nil)
    eq(err, 'network down')
    local cache = storage.read_cache()
    eq(cache.problems[1].title_slug, 'cached')
    eq(cache.total, 1)
    eq(cache.cache_time, 0)
  end)
end

T['api_question']['get_list fetches when the cache total is non-numeric'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 'many',
    cache_time = os.time(),
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil
  end, function()
    local list = question.get_list()
    eq(list.total, 1)
    eq(list.questions[1].title_slug, 'fresh')
    eq(calls, 1)
    local cache = storage.read_cache()
    eq(cache.problems[1].title_slug, 'fresh')
    eq(cache.domain, 'leetcode.com')
    eq(cache.user, 'anonymous')
  end)
end

T['api_question']['get_list fetches when a fresh cache has total zero'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = {},
    total = 0,
    cache_time = os.time(),
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil
  end, function()
    local list = question.get_list()
    eq(list.total, 1)
    eq(list.questions[1].title_slug, 'fresh')
    eq(calls, 1)
  end)
end

T['api_question']['get_list fetches when the cache has no total'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    cache_time = os.time(),
  })

  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil end,
    function()
      local list = question.get_list()
      eq(list.total, 1)
      eq(list.questions[1].title_slug, 'fresh')
      local cache = storage.read_cache()
      eq(cache.problems[1].title_slug, 'fresh')
      eq(cache.domain, 'leetcode.com')
      eq(cache.user, 'anonymous')
    end
  )
end

T['api_question']['get_list refreshes expired contents when the total is unchanged'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = 0,
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil
  end, function()
    local list = question.get_list()
    eq(calls, 1)
    eq(list.total, 1)
    eq(list.questions[1].title_slug, 'fresh')
    local cache = storage.read_cache()
    eq(cache.problems[1].title_slug, 'fresh')
    eq(cache.total, 1)
    eq(cache.domain, 'leetcode.com')
    eq(cache.user, 'anonymous')
    eq(cache.cache_time > 0, true)
  end)
end

T['api_question']['get_list updates cached problems when the total changes'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = 0,
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return {
      problemsetQuestionList = {
        total = 2,
        questions = { { title_slug = 'fresh-a' }, { title_slug = 'fresh-b' } },
      },
    },
      nil
  end, function()
    local list = question.get_list()
    eq(calls, 1)
    eq(list.total, 2)
    eq(list.questions[2].title_slug, 'fresh-b')
    local cache = storage.read_cache()
    eq(cache.total, 2)
    eq(cache.problems[1].title_slug, 'fresh-a')
    eq(cache.problems[2].title_slug, 'fresh-b')
    eq(cache.domain, 'leetcode.com')
    eq(cache.user, 'anonymous')
  end)
end

T['api_question']['get_list rejects future and cross-domain caches'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  for _, cached in ipairs({
    { domain = 'leetcode.com', cache_time = os.time() + 3600 },
    { domain = 'leetcode.cn', cache_time = os.time() },
  }) do
    cached.problems = { { title_slug = 'stale' } }
    cached.total = 1
    storage.write_cache(cached)

    helpers.with_stub(
      'leetcode-ui.api',
      'graphql',
      function() return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil end,
      function()
        local list = question.get_list()
        eq(list.questions[1].title_slug, 'fresh')
      end
    )
  end
end

T['api_question']['get_list preserves status updates written during a fetch'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'two-sum', status = nil } },
    total = 1,
    cache_time = 0,
  })

  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    question.update_list_status('two-sum', 'solved')
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'two-sum' } } } }, nil
  end, function()
    local list = question.get_list()
    eq(list.questions[1].status, 'solved')
    eq(storage.read_cache().problems[1].status, 'solved')
  end)
end

T['api_question']['get_list caches a fresh list after a status update during the fetch'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'two-sum' }, { title_slug = 'old-question' } },
    total = 2,
    cache_time = 0,
  })

  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    question.update_list_status('two-sum', 'attempted')
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'two-sum' } } } }, nil
  end, function()
    local list = question.get_list()
    eq(list.questions[1].status, 'attempted')
    local cache = storage.read_cache()
    eq(#cache.problems, 1)
    eq(cache.problems[1].title_slug, 'two-sum')
    eq(cache.problems[1].status, 'attempted')
    eq(cache.cache_time > 0, true)
    eq(cache.list_revision, 1)
  end)
end

T['api_question']['get_list does not let fetched statuses downgrade newer local ones'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  for _, case in ipairs({
    { cached = 'solved', fetched = 'attempted', expected = 'solved' },
    { cached = 'solved', fetched = nil, expected = 'solved' },
    { cached = 'attempted', fetched = 'solved', expected = 'solved' },
    { cached = 'attempted', fetched = nil, expected = 'attempted' },
    { cached = 'attempted', fetched = 'attempted', expected = 'attempted' },
  }) do
    storage.write_cache({
      domain = 'leetcode.com',
      problems = { { title_slug = 'two-sum', status = case.cached } },
      total = 1,
      cache_time = 0,
    })

    helpers.with_stub(
      'leetcode-ui.api',
      'graphql',
      function()
        return {
          problemsetQuestionList = { total = 1, questions = { { title_slug = 'two-sum', status = case.fetched } } },
        },
          nil
      end,
      function()
        local list = question.get_list()
        eq(list.questions[1].status, case.expected)
        eq(storage.read_cache().problems[1].status, case.expected)
      end
    )
  end
end

T['api_question']['get_list refetches fresh but incomplete caches'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 2,
    cache_time = os.time(),
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return {
      problemsetQuestionList = {
        total = 2,
        questions = { { title_slug = 'fresh-a' }, { title_slug = 'fresh-b' } },
      },
    },
      nil
  end, function()
    local list = question.get_list()
    eq(calls, 1)
    eq(list.questions[2].title_slug, 'fresh-b')
    local cache = storage.read_cache()
    eq(cache.total, 2)
    eq(cache.problems[1].title_slug, 'fresh-a')
    eq(cache.problems[2].title_slug, 'fresh-b')
    eq(cache.list_revision, 1)
  end)
end

T['api_question']['get_list preserves the previous cache after incomplete responses'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = 0,
  })

  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { problemsetQuestionList = { total = 2, questions = { { title_slug = 'partial' } } } }, nil end,
    function()
      local list, err = question.get_list()
      eq(list, nil)
      eq(err, 'Incomplete problem-list response')
      local cache = storage.read_cache()
      eq(cache.problems[1].title_slug, 'cached')
      eq(cache.total, 1)
      eq(cache.cache_time, 0)
    end
  )
end

T['api_question']['get_list stops when the server returns an empty page'] = function()
  local question = helpers.mod('api.question')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return { problemsetQuestionList = { total = 2, questions = {} } }, nil
  end, function()
    local list, err = question.get_list()
    eq(list, nil)
    eq(err, 'Incomplete problem-list response')
    eq(calls, 1)
  end)
end

T['api_question']['get_list rejects malformed page metadata'] = function()
  local question = helpers.mod('api.question')
  for _, page in ipairs({
    { total = 0, questions = {} },
    { total = -1, questions = {} },
    { total = 1.5, questions = {} },
    { total = 1, questions = 'nope' },
  }) do
    helpers.with_stub(
      'leetcode-ui.api',
      'graphql',
      function() return { problemsetQuestionList = page }, nil end,
      function()
        local list, err = question.get_list()
        eq(list, nil)
        eq(err, 'Malformed problem-list response')
      end
    )
  end
end

T['api_question']['find_in_list only reads the current domain cache'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = os.time(),
  })

  eq(question.find_in_list('cached').title_slug, 'cached')
  eq(question.find_in_list('missing'), nil)

  helpers.configure({ url = 'leetcode.cn' })
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = os.time(),
  })
  eq(question.find_in_list('cached'), nil)
end

T['api_question']['list lookups ignore caches for other credentials'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    user = 'old-user',
    problems = { { title_slug = 'two-sum' } },
    total = 1,
  })

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return 'new-user' end, function()
    eq(question.find_in_list('two-sum'), nil)
    question.update_list_status('two-sum', 'solved')
    eq(storage.read_cache().problems[1].status, nil)
    eq(storage.read_cache().revision, nil)
  end)
end

T['api_question']['update_list_status updates cached entries'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({ domain = 'leetcode.com', problems = { { title_slug = 'two-sum', status = nil } }, total = 1 })
  question.update_list_status('two-sum', 'solved')
  eq(storage.read_cache().problems[1].status, 'solved')
  eq(storage.read_cache().revision, 1)

  question.update_list_status('two-sum', 'solved')
  eq(storage.read_cache().revision, 1)

  question.update_list_status('two-sum', 'attempted')
  eq(storage.read_cache().problems[1].status, 'solved')

  helpers.configure({ url = 'leetcode.cn' })
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'two-sum' } },
    total = 1,
  })
  question.update_list_status('two-sum', 'solved')
  eq(storage.read_cache().problems[1].status, nil)
  eq(storage.read_cache().revision, nil)
end

T['api_question']['get_list refetches when the credential identity changes'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    user = 'old-user',
    problems = { { title_slug = 'cached' } },
    total = 1,
    cache_time = os.time(),
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return 'new-user' end, function()
    helpers.with_stub('leetcode-ui.api', 'graphql', function()
      calls = calls + 1
      return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil
    end, function()
      local list = question.get_list()
      eq(calls, 1)
      eq(list.questions[1].title_slug, 'fresh')
      eq(storage.read_cache().user, 'new-user')
    end)
  end)
end

T['api_question']['get_list aborts when credentials change during fetch'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'sentinel' } },
    total = 1,
    cache_time = 12345,
  })
  local calls = 0
  local list, err
  helpers.with_stub('leetcode-ui.auth', 'cache_key', function()
    calls = calls + 1
    return calls == 1 and 'old-user' or 'new-user'
  end, function()
    helpers.with_stub(
      'leetcode-ui.api',
      'graphql',
      function() return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'two-sum' } } } }, nil end,
      function()
        list, err = question.get_list()
      end
    )
  end)
  eq(list, nil)
  eq(err, 'Authentication state changed during fetch')
  eq(storage.read_cache().problems[1].title_slug, 'sentinel')
  eq(storage.read_cache().cache_time, 12345)
end

T['api_question']['get_list aborts when the domain changes during pagination'] = function()
  local question = helpers.mod('api.question')
  local config = helpers.mod('config')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'sentinel' } },
    total = 1,
    cache_time = 12345,
  })
  local list, err
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    coroutine.yield()
    local rows = {}
    for index = 1, 100 do
      table.insert(rows, { title_slug = 'q-' .. index })
    end
    return { problemsetQuestionList = { total = 200, questions = rows } }, nil
  end, function()
    local worker = coroutine.create(function()
      list, err = question.get_list()
    end)
    eq(coroutine.resume(worker), true)
    config.config.url = 'leetcode.cn'
    eq(coroutine.resume(worker), true)
  end)
  eq(list, nil)
  eq(err, 'LeetCode domain changed during fetch')
  eq(storage.read_cache().problems[1].title_slug, 'sentinel')
  eq(storage.read_cache().cache_time, 12345)
end

T['api_question']['forced refresh merges status updates written during the fetch'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'two-sum' } },
    total = 1,
    cache_time = os.time(),
  })

  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    question.update_list_status('two-sum', 'solved')
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'two-sum' } } } }, nil
  end, function()
    local list = question.get_list({ force = true })
    eq(list.questions[1].status, 'solved')
    eq(storage.read_cache().problems[1].status, 'solved')
  end)
end

T['api_question']['get_list does not let an older fetch overwrite a newer cache'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  local threads, calls = {}, 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    local call = calls
    local thread = coroutine.running()
    table.insert(threads, thread)
    coroutine.yield()
    return {
      problemsetQuestionList = { total = 1, questions = { { title_slug = 'question-' .. call } } },
    },
      nil
  end, function()
    local first = coroutine.create(function() question.get_list() end)
    local second = coroutine.create(function() question.get_list() end)
    eq(coroutine.resume(first), true)
    eq(coroutine.resume(second), true)
    eq(#threads, 2)
    eq(coroutine.resume(threads[2]), true)
    eq(coroutine.resume(threads[1]), true)
  end)

  eq(storage.read_cache().problems[1].title_slug, 'question-2')
end

T['api_question']['get_list force bypasses a fresh cache'] = function()
  local question = helpers.mod('api.question')
  local storage = helpers.mod('storage')
  storage.write_cache({
    domain = 'leetcode.com',
    problems = { { title_slug = 'cached', status = 'solved' } },
    total = 1,
    cache_time = os.time(),
  })

  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return { problemsetQuestionList = { total = 1, questions = { { title_slug = 'fresh' } } } }, nil
  end, function()
    eq(question.get_list().questions[1].title_slug, 'cached')
    eq(calls, 0)

    local list = question.get_list({ force = true })
    eq(calls, 1)
    eq(list.questions[1].title_slug, 'fresh')
    eq(list.questions[1].status, nil)
    eq(storage.read_cache().problems[1].title_slug, 'fresh')
    eq(storage.read_cache().problems[1].status, nil)
  end)
end

T['api_question']['get_daily handles success and missing records'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { todayRecord = { question = { title_slug = 'daily' } } }, nil end,
    function() eq(question.get_daily(), 'daily') end
  )

  for _, response in ipairs({
    { todayRecord = {} },
    { todayRecord = { question = { title_slug = '' } } },
    { todayRecord = vim.NIL },
  }) do
    helpers.with_stub('leetcode-ui.api', 'graphql', function() return response, nil end, function()
      local slug, err = question.get_daily()
      eq(slug, nil)
      eq(err, 'No daily question found')
    end)
  end

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'failed' end, function()
    local slug, err = question.get_daily()
    eq(slug, nil)
    eq(err, 'failed')
  end)
end

T['api_question']['get_random excludes premium questions when configured'] = function()
  helpers.configure({ hide_premium = true })
  local question = helpers.mod('api.question')
  helpers.with_stub('leetcode-ui.api', 'graphql', function(_query, variables)
    eq(variables.filters.premiumOnly, false)
    return { randomQuestion = { title_slug = 'free' } }, nil
  end, function() eq(question.get_random(), 'free') end)
end

T['api_question']['get_random retries paid-only questions'] = function()
  helpers.configure({ hide_premium = true })
  local question = helpers.mod('api.question')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    if calls == 1 then return { randomQuestion = { title_slug = 'paid', is_paid_only = true } }, nil end
    return { randomQuestion = { title_slug = 'free' } }, nil
  end, function()
    eq(question.get_random(), 'free')
    eq(calls, 2)
  end)
end

T['api_question']['get_random returns paid questions when premium is not hidden'] = function()
  helpers.configure({ hide_premium = false })
  local question = helpers.mod('api.question')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { randomQuestion = { title_slug = 'paid', is_paid_only = true } }, nil end,
    function() eq(question.get_random(), 'paid') end
  )
end

T['api_question']['get_random reports when every premium retry is paid-only'] = function()
  helpers.configure({ hide_premium = true })
  local question = helpers.mod('api.question')
  local calls = 0
  helpers.with_stub('leetcode-ui.api', 'graphql', function()
    calls = calls + 1
    return { randomQuestion = { title_slug = 'paid', is_paid_only = true } }, nil
  end, function()
    local slug, err = question.get_random()
    eq(slug, nil)
    eq(err, 'No free random question found')
    eq(calls, 5)
  end)
end

T['api_question']['get_random handles success and missing records'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub('leetcode-ui.api', 'graphql', function(_query, variables)
    eq(variables.filters.difficulty, 'HARD')
    return { randomQuestion = { title_slug = 'random' } }, nil
  end, function() eq(question.get_random({ difficulty = 'Hard' }), 'random') end)

  for _, response in ipairs({
    { randomQuestion = {} },
    { randomQuestion = { title_slug = '' } },
    { randomQuestion = vim.NIL },
  }) do
    helpers.with_stub('leetcode-ui.api', 'graphql', function() return response, nil end, function()
      local slug, err = question.get_random()
      eq(slug, nil)
      eq(err, 'No random question found')
    end)
  end

  helpers.with_stub('leetcode-ui.api', 'graphql', function() return nil, 'failed' end, function()
    local slug, err = question.get_random()
    eq(slug, nil)
    eq(err, 'failed')
  end)

  helpers.with_stub('leetcode-ui.api', 'graphql', function(_query, variables)
    eq(next(variables.filters), nil)
    return { randomQuestion = { title_slug = 'random' } }, nil
  end, function() eq(question.get_random(), 'random') end)
end

T['api_question']['get_detail normalizes snippets and testcases'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub('leetcode-ui.api', 'graphql', function(_, variables)
    eq(variables.titleSlug, 'two-sum')
    return {
      question = {
        id = '1',
        frontend_id = '1',
        title = 'Two Sum',
        title_slug = 'two-sum',
        status = 'ac',
        content = '<p>x</p>',
        code_snippets = {
          { lang = 'Python3', lang_slug = 'python3', code = 'pass' },
        },
        testcase_list = { '[1]\n1' },
      },
    },
      nil
  end, function()
    local detail, err = question.get_detail('two-sum')
    eq(err, nil)
    eq(detail.status, 'solved')
    eq(detail.snippets.python3.code, 'pass')
    eq(detail.testcases[1], '[1]\n1')
  end)
end

T['api_question']['get_detail canonicalizes alias snippets'] = function()
  local question = helpers.mod('api.question')
  local snippets = {
    { lang = 'Python', lang_slug = 'python', code = 'legacy' },
    { lang = 'Python3', lang_slug = 'python3', code = 'modern' },
  }
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { question = { id = '1', title_slug = 'two-sum', code_snippets = snippets } }, nil end,
    function()
      local detail = question.get_detail('two-sum')
      eq(vim.tbl_keys(detail.snippets), { 'python3' })
      eq(detail.snippets.python3.code, 'modern')
    end
  )

  snippets = { { lang = 'Python', lang_slug = 'python', code = 'legacy' } }
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { question = { id = '1', title_slug = 'two-sum', code_snippets = snippets } }, nil end,
    function()
      local detail = question.get_detail('two-sum')
      eq(vim.tbl_keys(detail.snippets), { 'python3' })
      eq(detail.snippets.python3.code, 'legacy')
    end
  )
end

T['api_question']['get_detail filters malformed snippets and testcases'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function()
      return {
        question = {
          id = '1',
          title_slug = 'two-sum',
          code_snippets = {
            { lang = 'Python3', lang_slug = 'python3', code = 'pass' },
            { lang = 'Broken', lang_slug = '', code = 'x' },
            { lang = 'Broken' },
            'not a snippet',
          },
          testcase_list = { '[1]\n1', 1, vim.NIL, '[2]\n2' },
        },
      },
        nil
    end,
    function()
      local detail = question.get_detail('two-sum')
      eq(vim.tbl_keys(detail.snippets), { 'python3' })
      eq(detail.testcases, { '[1]\n1', '[2]\n2' })
    end
  )
end

T['api_question']['get_detail defaults optional fields'] = function()
  local question = helpers.mod('api.question')
  helpers.with_stub(
    'leetcode-ui.api',
    'graphql',
    function() return { question = { id = '1', title_slug = 'two-sum' } }, nil end,
    function()
      local detail, err = question.get_detail('two-sum')
      eq(err, nil)
      eq(detail.snippets, {})
      eq(detail.testcases, {})
      eq(detail.hints, {})
    end
  )
end

T['api_question']['get_detail rejects missing questions'] = function()
  local question = helpers.mod('api.question')
  for _, response in ipairs({ { question = {} }, { question = vim.NIL } }) do
    helpers.with_stub('leetcode-ui.api', 'graphql', function() return response, nil end, function()
      local detail, err = question.get_detail('missing')
      eq(detail, nil)
      eq(helpers.contains(err, 'was not found'), true)
    end)
  end
end

return T
