-- Tests for leetcode-ui.api.

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

local function json(body) return vim.json.encode(body) end

T['api'] = new_set()

T['api']['base_url and problems_url reflect the configured domain'] = function()
  local api = helpers.mod('api')
  eq(api.base_url(), 'https://leetcode.com')
  eq(api.problems_url('two-sum'), 'https://leetcode.com/problems/two-sum/')

  helpers.configure({ url = 'leetcode.cn' })
  eq(api.base_url(), 'https://leetcode.cn')
  eq(api.problems_url('two-sum'), 'https://leetcode.cn/problems/two-sum/')
end

T['api']['is_null understands vim.NIL'] = function()
  local api = helpers.mod('api')
  eq(api.is_null(nil), true)
  eq(api.is_null(vim.NIL), true)
  eq(api.is_null({}), false)
  eq(api.is_null(0), false)
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

T['api']['graphql encodes nil variables as an object'] = function()
  local api = helpers.mod('api')
  local body = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    body = opts.body
    return { status = 200, body = json({ data = { ok = true } }) }, nil
  end, function() api.graphql('query { ok }') end)
  eq(helpers.contains(body or '', '"variables":{}'), true)
end

T['api']['graphql forwards non-empty variables'] = function()
  local api = helpers.mod('api')
  local body = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    body = opts.body
    return { status = 200, body = json({ data = { ok = true } }) }, nil
  end, function() api.graphql('query($username: String!) { ok }', { username = 'user' }) end)
  assert(body ~= nil)
  eq(vim.json.decode(body).variables.username, 'user')
end

T['api']['graphql forwards credentials and cookie jars'] = function()
  local api = helpers.mod('api')
  helpers.configure({ cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  ---@type table|nil
  local request = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    request = opts
    return { status = 200, body = json({ data = { ok = true } }) }, nil
  end, function() api.graphql('query { ok }') end)
  assert(request ~= nil)
  eq(vim.tbl_contains(request.headers, 'Cookie: LEETCODE_SESSION=s; csrftoken=c'), true)
  eq(vim.tbl_contains(request.headers, 'X-CSRFToken: c'), true)
  eq(request.cookie_file, nil)

  local path = helpers.tmpdir() .. '/cookies.txt'
  vim.fn.writefile({ '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tjar-csrf' }, path)
  helpers.configure({ cookies = {}, cookie_file = path })
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    request = opts
    return { status = 200, body = json({ data = { ok = true } }) }, nil
  end, function() api.graphql('query { ok }') end)
  assert(request ~= nil)
  eq(request.cookie_file, vim.fs.normalize(path))
  eq(vim.tbl_contains(request.headers, 'X-CSRFToken: jar-csrf'), true)
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

T['api']['graphql handles malformed error and data shapes'] = function()
  local api = helpers.mod('api')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = '{"errors":[1]}' }, nil end,
    function()
      local data, err = api.graphql('query')
      eq(data, nil)
      eq(err, 'unknown error')
    end
  )

  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = '{"data":1}' }, nil end,
    function()
      local data, err = api.graphql('query')
      eq(data, nil)
      eq(helpers.contains(err, 'Malformed response'), true)
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
    eq(err, 'Malformed response (HTTP 200)')
  end)

  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 200, body = '1' }, nil end, function()
    local data, err = api.graphql('query')
    eq(data, nil)
    eq(helpers.contains(err, 'Malformed response'), true)
  end)
end

T['api']['graphql rejects non-success HTTP responses'] = function()
  local api = helpers.mod('api')
  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 500, body = '{}' }, nil end, function()
    local data, err = api.graphql('query')
    eq(data, nil)
    eq(err, 'Request failed (HTTP 500)')
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

T['api']['rest forwards method, path, body, headers, and request options'] = function()
  local api = helpers.mod('api')
  ---@type table|nil
  local request = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    request = opts
    return { status = 200, body = '{}' }, nil
  end, function() api.rest('POST', '/test', '{"x":1}', { 'X-Extra: yes' }, { timeout = 5 }) end)
  assert(request ~= nil)
  eq(request.method, 'POST')
  eq(request.url, 'https://leetcode.com/test')
  eq(request.body, '{"x":1}')
  eq(request.timeout, 5)
  eq(vim.tbl_contains(request.headers, 'X-Extra: yes'), true)
end

T['api']['rest rejects non-success HTTP responses'] = function()
  local api = helpers.mod('api')
  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 404, body = '{}' }, nil end, function()
    local data, err = api.rest('GET', '/test')
    eq(data, nil)
    eq(err, 'Request failed (HTTP 404)')
  end)
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
  for _, body in ipairs({ 'html', '1' }) do
    helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 200, body = body }, nil end, function()
      local data, err = api.rest('GET', '/test')
      eq(data, nil)
      eq(helpers.contains(err, 'Malformed response'), true)
    end)
  end
end

return T
