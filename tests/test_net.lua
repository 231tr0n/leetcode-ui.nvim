-- Tests for leetcode-ui.net.

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

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
  eq(vim.tbl_contains(args, '-X'), true)
  eq(vim.tbl_contains(args, '--max-time'), true)
  for index, value in ipairs(args) do
    if value == '-X' then eq(args[index + 1], 'POST') end
    if value == '--max-time' then eq(args[index + 1], '10') end
    if value == '--data-binary' then eq(args[index + 1], '@-') end
    if value == '-b' then eq(args[index + 1], '/tmp/jar') end
    if value == '-D' then eq(args[index + 1], '/tmp/h') end
    if value == '-o' then eq(args[index + 1], '/tmp/b') end
  end
  eq(vim.tbl_contains(args, 'x'), false)
end

T['net']['curl_args omits an empty body and terminates options before the URL'] = function()
  local net = helpers.mod('net')
  local args = net.curl_args({ url = '-https://example.com', body = '' }, '/tmp/h', '/tmp/b')
  eq(vim.tbl_contains(args, '--data-binary'), false)
  eq(args[#args], '-https://example.com')
  eq(args[#args - 1], '--')
end

T['net']['request_once keeps sensitive headers out of process arguments'] = function()
  local net = helpers.mod('net')
  local exposed, body_exposed, contents, headers_file, stdin = false, false, nil, nil, nil
  helpers.with_stub('leetcode-ui.async', 'system', function(args, opts)
    stdin = opts.stdin
    for index, value in ipairs(args) do
      if value:find('secret', 1, true) or value:find('token', 1, true) then exposed = true end
      if value == 'payload' then body_exposed = true end
      if value == '-H' and args[index + 1]:sub(1, 1) == '@' then
        headers_file = args[index + 1]:sub(2)
        contents = table.concat(vim.fn.readfile(headers_file), '\n')
      end
    end
    return { code = 1, stdout = '', stderr = 'offline' }
  end, function()
    local response, err = net.request_once({
      url = 'https://example.com',
      headers = { 'Cookie: secret', 'X-CSRFToken: token' },
      body = 'payload',
    })
    eq(response, nil)
    eq(err, 'offline')
  end)

  eq(exposed, false)
  eq(body_exposed, false)
  eq(stdin, 'payload')
  eq(contents, 'Cookie: secret\nX-CSRFToken: token')
  eq(vim.fn.filereadable(headers_file), 0)
  eq(vim.fn.isdirectory(vim.fs.dirname(headers_file)), 0)
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
  local dir = helpers.tmpdir()
  local headers = dir .. '/headers'
  local body = dir .. '/body'
  vim.fn.writefile({ 'HTTP/1.1 200 OK', 'Content-Type: text/plain', '', 'hello' }, headers)
  vim.fn.writefile({ 'hello' }, body)
  local response = net.read_response(headers, body)
  eq(response.status, 200)
  eq(response.body, 'hello\n')
  eq(vim.fn.filereadable(headers), 0)
  eq(vim.fn.filereadable(body), 0)
end

T['net']['read_response removes the body when headers are missing'] = function()
  local net = helpers.mod('net')
  local body = vim.fn.tempname()
  vim.fn.writefile({ 'body' }, body)
  eq(net.read_response('/definitely/missing', body), nil)
  eq(vim.fn.filereadable(body), 0)
end

T['net']['should_retry covers transient statuses'] = function()
  local net = helpers.mod('net')
  eq(net.should_retry(403), true)
  eq(net.should_retry(429), true)
  eq(net.should_retry(499), false)
  eq(net.should_retry(500), true)
  eq(net.should_retry(501), true)
  eq(net.should_retry(200), false)
  eq(net.should_retry(404), false)
end

T['net']['request works on the main thread and inside a coroutine'] = function()
  local net = helpers.mod('net')
  local calls = 0
  helpers.with_stub('leetcode-ui.net', 'request_once', function()
    calls = calls + 1
    local thread, is_main = coroutine.running()
    if thread ~= nil and not is_main then coroutine.yield() end
    return { status = 200 + calls - 1, headers = {}, body = '{}' }, nil
  end, function()
    local response = net.request({ url = 'https://example.com', retries = 0 })
    eq(response.status, 200)

    local result
    local thread = coroutine.create(function() result = net.request({ url = 'https://example.com', retries = 0 }) end)
    coroutine.resume(thread)
    eq(result, nil)
    eq(calls, 2)
    coroutine.resume(thread)
    eq(result.status, 201)
    eq(calls, 2)
  end)
end

T['net']['request retries transient failures with backoff'] = function()
  local net = helpers.mod('net')
  local attempts, delays = 0, {}
  helpers.with_stub('leetcode-ui.async', 'sleep', function(ms) table.insert(delays, ms) end, function()
    helpers.with_stub('leetcode-ui.net', 'request_once', function()
      attempts = attempts + 1
      if attempts < 3 then return { status = 500, headers = {}, body = '' } end
      return { status = 200, headers = {}, body = 'ok' }
    end, function()
      local response, err = net.request({ url = 'https://example.com', retries = 3 })
      eq(err, nil)
      eq(response.status, 200)
      eq(attempts, 3)
      eq(delays, { 200, 400 })
    end)
  end)
end

T['net']['request retries transport failures'] = function()
  local net = helpers.mod('net')
  local attempts = 0
  helpers.with_stub('leetcode-ui.async', 'sleep', function() end, function()
    helpers.with_stub('leetcode-ui.net', 'request_once', function()
      attempts = attempts + 1
      if attempts == 1 then return nil, 'offline' end
      return { status = 200, headers = {}, body = 'ok' }, nil
    end, function()
      local response, err = net.request({ url = 'https://example.com', retries = 1 })
      eq(err, nil)
      eq(response.status, 200)
      eq(attempts, 2)
    end)
  end)
end

T['net']['request returns the last retryable response'] = function()
  local net = helpers.mod('net')
  local attempts = 0
  helpers.with_stub('leetcode-ui.async', 'sleep', function() end, function()
    helpers.with_stub('leetcode-ui.net', 'request_once', function()
      attempts = attempts + 1
      return { status = 503, headers = {}, body = 'busy' }, nil
    end, function()
      local response, err = net.request({ url = 'https://example.com', retries = 2 })
      eq(err, nil)
      eq(response.status, 503)
      eq(attempts, 3)
    end)
  end)
end

T['net']['request returns the last transport error'] = function()
  local net = helpers.mod('net')
  helpers.with_stub('leetcode-ui.async', 'sleep', function() end, function()
    helpers.with_stub('leetcode-ui.net', 'request_once', function() return nil, 'offline' end, function()
      local response, err = net.request({ url = 'https://example.com', retries = 1 })
      eq(response, nil)
      eq(err, 'offline')
    end)
  end)
end

T['net']['request does not sleep when retries are disabled'] = function()
  local net = helpers.mod('net')
  local slept, attempts = false, 0
  ---@type table|nil
  local response = nil
  helpers.with_stub('leetcode-ui.async', 'sleep', function() slept = true end, function()
    helpers.with_stub('leetcode-ui.net', 'request_once', function()
      attempts = attempts + 1
      return { status = 500, headers = {}, body = '' }, nil
    end, function() response = net.request({ url = 'https://example.com', retries = 0 }) end)
  end)
  eq(slept, false)
  eq(attempts, 1)
  assert(response ~= nil)
  eq(response.status, 500)
end

T['net']['read_response tolerates a missing body file'] = function()
  local net = helpers.mod('net')
  local dir = helpers.tmpdir()
  local headers = dir .. '/headers'
  local body = dir .. '/body'
  vim.fn.writefile({ 'HTTP/1.1 200 OK', '' }, headers)
  local response = net.read_response(headers, body)
  eq(response.status, 200)
  eq(response.body, '')
  eq(vim.fn.filereadable(headers), 0)
end

T['net']['request_once rejects partial responses when curl fails'] = function()
  local net = helpers.mod('net')
  helpers.with_stub(
    'leetcode-ui.async',
    'system',
    function() return { code = 28, stdout = '', stderr = 'timeout' } end,
    function()
      helpers.with_stub(
        'leetcode-ui.net',
        'read_response',
        function() return { status = 200, headers = {}, body = 'partial' } end,
        function()
          local response, err = net.request_once({ url = 'https://example.com' })
          eq(response, nil)
          eq(err, 'timeout')
        end
      )
    end
  )
end

T['net']['request_once reports curl exit codes without stderr'] = function()
  local net = helpers.mod('net')
  helpers.with_stub(
    'leetcode-ui.async',
    'system',
    function() return { code = 7, stdout = '', stderr = '' } end,
    function()
      local response, err = net.request_once({ url = 'https://example.com' })
      eq(response, nil)
      eq(err, 'curl 7')
    end
  )
end

return T
