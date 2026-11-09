-- Tests for leetcode-ui.auth.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

local function has_header(headers, prefix)
  for _, header in ipairs(headers) do
    if vim.startswith(header, prefix) then return header end
  end
  return nil
end

T['cookie_file'] = new_set()

T['cookie_file']['returns nil for empty values'] = function()
  local auth = helpers.mod('auth')
  eq(auth.cookie_file(), nil)
  helpers.configure({ cookie_file = '', browser = 'none' })
  eq(auth.cookie_file(), nil)
end

T['cookie_file']['normalizes configured path'] = function()
  helpers.configure({ cookie_file = '~/cookies.txt', browser = 'none' })
  local auth = helpers.mod('auth')
  eq(auth.cookie_file(), vim.fs.normalize('~/cookies.txt'))
end

T['cookie_file']['expands user-home shorthand'] = function()
  local user = vim.env.USER
  if user == nil or user == '' then return end
  helpers.configure({ cookie_file = '~' .. user .. '/cookies.txt', browser = 'none' })
  local auth = helpers.mod('auth')
  eq(auth.cookie_file(), vim.fn.expand('~') .. '/cookies.txt')
end

T['cookies'] = new_set()

T['cookies']['reads configured cookies before environment'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's1', csrftoken = 'c1' } })
  vim.env.LEETCODE_SESSION = 'env-session'
  vim.env.CSRFTOKEN = 'env-csrf'
  MiniTest.finally(function()
    vim.env.LEETCODE_SESSION = nil
    vim.env.CSRFTOKEN = nil
  end)
  local cookies = helpers.mod('auth').cookies()
  eq(cookies.LEETCODE_SESSION, 's1')
  eq(cookies.csrftoken, 'c1')
end

T['cookies']['falls back to environment variables'] = function()
  vim.env.LEETCODE_SESSION = 'env-session'
  vim.env.CSRFTOKEN = 'env-csrf'
  MiniTest.finally(function()
    vim.env.LEETCODE_SESSION = nil
    vim.env.CSRFTOKEN = nil
  end)
  local cookies = helpers.mod('auth').cookies()
  eq(cookies.LEETCODE_SESSION, 'env-session')
  eq(cookies.csrftoken, 'env-csrf')
end

T['cookies']['browser cookies only fill missing entries'] = function()
  helpers.with_stub(
    'leetcode-ui.browser',
    'get_cookies',
    function() return { LEETCODE_SESSION = 'browser-session', csrftoken = 'browser-csrf' } end,
    function()
      helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 'configured' } })
      local cookies = helpers.mod('auth').cookies()
      eq(cookies.LEETCODE_SESSION, 'configured')
      eq(cookies.csrftoken, 'browser-csrf')
    end
  )
end

T['cookies']['does not touch browsers when both cookies are configured'] = function()
  helpers.configure({ browser = 'auto', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  helpers.with_stub('leetcode-ui.browser', 'get_cookies', function() error('browser should not be read') end, function()
    local cookies = helpers.mod('auth').cookies()
    eq(cookies.LEETCODE_SESSION, 's')
    eq(cookies.csrftoken, 'c')
  end)
end

T['csrf'] = new_set()

T['csrf']['reads csrf token from a cookie jar'] = function()
  local path = helpers.tmpdir() .. '/cookies.txt'
  vim.fn.writefile({
    '# Netscape HTTP Cookie File',
    '#HttpOnly_.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tjar-csrf',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\tjar-session',
  }, path)
  helpers.configure({ cookie_file = path, browser = 'none' })
  local auth = helpers.mod('auth')
  eq(auth.jar_csrf(path), 'jar-csrf')
  eq(auth.csrf(), 'jar-csrf')
  eq(auth.has_session(), true)
end

T['csrf']['jar_csrf skips other domains and expired cookies'] = function()
  local path = helpers.tmpdir() .. '/cookies.txt'
  local auth = helpers.mod('auth')
  vim.fn.writefile({
    '.example.com\tTRUE\t/\tTRUE\t0\tcsrftoken\twrong-domain',
    '.leetcode.com\tTRUE\t/\tTRUE\t1\tcsrftoken\texpired',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tvalid',
  }, path)
  eq(auth.jar_csrf(path), 'valid')

  helpers.configure({ url = 'leetcode.cn' })
  vim.fn.writefile({
    '.example.com\tTRUE\t/\tTRUE\t0\tcsrftoken\twrong-domain',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tcom-csrf',
    '.leetcode.cn\tTRUE\t/\tTRUE\t0\tcsrftoken\tcn-csrf',
  }, path)
  eq(auth.jar_csrf(path), 'cn-csrf')

  vim.fn.writefile({ '.leetcode.cn\tTRUE\t/\tTRUE\t' .. (os.time() + 60) .. '\tcsrftoken\tfuture' }, path)
  eq(auth.jar_csrf(path), 'future')

  vim.fn.writefile({
    '.leetcode.cn\tTRUE\t/\tTRUE\t0\tcsrftoken\t',
    '.leetcode.cn\tTRUE\t/\tTRUE\t0\tcsrftoken\tvalid',
  }, path)
  eq(auth.jar_csrf(path), 'valid')

  vim.fn.writefile({ '.example.com\tTRUE\t/\tTRUE\t0\tcsrftoken\twrong-domain', 'malformed' }, path)
  eq(auth.jar_csrf(path), nil)
end

T['csrf']['jar_csrf returns nil for missing files'] = function()
  local auth = helpers.mod('auth')
  eq(auth.jar_csrf('/definitely/missing/cookies.txt'), nil)
end

T['has_session'] = new_set()

T['has_session']['requires both cookies or a cookie jar'] = function()
  local auth = helpers.mod('auth')

  helpers.configure({ browser = 'none', cookies = {} })
  eq(auth.has_session(), false)

  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's' } })
  eq(auth.has_session(), false)

  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = '', csrftoken = 'c' } })
  eq(auth.has_session(), false)

  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  eq(auth.has_session(), true)

  local path = helpers.tmpdir() .. '/cookies.txt'
  vim.fn.writefile({
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tc',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\ts',
  }, path)
  helpers.configure({ browser = 'none', cookies = {}, cookie_file = path })
  eq(auth.has_session(), true)
end

T['has_session']['rejects missing and incomplete cookie jars'] = function()
  local auth = helpers.mod('auth')
  local path = helpers.tmpdir() .. '/cookies.txt'
  helpers.configure({ browser = 'none', cookies = {}, cookie_file = path })
  eq(auth.has_session(), false)

  vim.fn.writefile({ '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tc' }, path)
  eq(auth.has_session(), false)

  vim.fn.writefile({ '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\ts' }, path)
  eq(auth.has_session(), false)

  vim.fn.writefile({
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tc',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\ts',
  }, path)
  eq(auth.has_session(), true)
end

T['cache_key'] = new_set()

T['cache_key']['distinguishes credential sources'] = function()
  local auth = helpers.mod('auth')

  helpers.configure({ browser = 'none', cookies = {} })
  eq(auth.cache_key(), 'anonymous')

  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 'first', csrftoken = 'c' } })
  local first = auth.cache_key()
  eq(first ~= 'anonymous', true)
  eq(auth.cache_key(), first)

  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 'second', csrftoken = 'c' } })
  eq(auth.cache_key() ~= first, true)

  local path = helpers.tmpdir() .. '/cookies.txt'
  vim.fn.writefile({ '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\tjar' }, path)
  helpers.configure({ browser = 'none', cookies = {}, cookie_file = path })
  local jar_key = auth.cache_key()
  eq(helpers.contains(jar_key, 'jar:'), true)
  vim.uv.fs_utime(path, os.time() + 10, os.time() + 10)
  eq(auth.cache_key(), jar_key)

  vim.fn.writefile({ '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\tother' }, path)
  eq(auth.cache_key() ~= jar_key, true)
end

T['cache_key']['changes when the csrf cookie changes'] = function()
  local auth = helpers.mod('auth')
  local path = helpers.tmpdir() .. '/cookies.txt'
  vim.fn.writefile({
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\ts',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tfirst',
  }, path)
  helpers.configure({ browser = 'none', cookies = {}, cookie_file = path })
  local first = auth.cache_key()
  vim.fn.writefile({
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\ts',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tsecond',
  }, path)
  eq(auth.cache_key() ~= first, true)

  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'first' } })
  local configured = auth.cache_key()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'second' } })
  eq(auth.cache_key() ~= configured, true)
end

T['headers'] = new_set()

T['headers']['omits session headers when anonymous'] = function()
  local headers = helpers.mod('auth').headers()
  eq(has_header(headers, 'Cookie:'), nil)
  eq(has_header(headers, 'X-CSRFToken:'), nil)
end

T['headers']['adds cookie and csrf headers'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local headers = helpers.mod('auth').headers({ 'X-Test: yes' })
  local cookie = has_header(headers, 'Cookie:')
  eq(helpers.contains(cookie, 'LEETCODE_SESSION=s'), true)
  eq(helpers.contains(cookie, 'csrftoken=c'), true)
  eq(has_header(headers, 'X-CSRFToken:'), 'X-CSRFToken: c')
  eq(headers[#headers], 'X-Test: yes')
end

T['headers']['adds only csrf header for a cookie jar'] = function()
  local path = helpers.tmpdir() .. '/jar.txt'
  vim.fn.writefile({ '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tjar-csrf' }, path)
  helpers.configure({ cookie_file = path, browser = 'none' })
  local headers = helpers.mod('auth').headers()
  eq(has_header(headers, 'Cookie:'), nil)
  eq(has_header(headers, 'X-CSRFToken:'), 'X-CSRFToken: jar-csrf')
end

T['headers']['omits session headers for partial credentials'] = function()
  local auth = helpers.mod('auth')
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's' } })
  eq(has_header(auth.headers(), 'Cookie:'), nil)
  eq(has_header(auth.headers(), 'X-CSRFToken:'), nil)

  helpers.configure({ browser = 'none', cookies = { csrftoken = 'c' } })
  eq(has_header(auth.headers(), 'Cookie:'), nil)
  eq(has_header(auth.headers(), 'X-CSRFToken:'), nil)
end

T['handle_status'] = new_set()

T['handle_status']['passes through successful responses'] = function()
  local auth = helpers.mod('auth')
  local res, err = auth.handle_status({ status = 200, body = '{}' })
  eq(res.status, 200)
  eq(err, nil)
end

T['handle_status']['missing response becomes an error'] = function()
  local auth = helpers.mod('auth')
  local res, err = auth.handle_status(nil)
  eq(res, nil)
  eq(err, 'Network request failed')
end

T['handle_status']['401 and 403 clear the cached session and browser cache'] = function()
  local auth = helpers.mod('auth')
  local browser = helpers.mod('browser')
  for _, status in ipairs({ 401, 403 }) do
    auth.session = { checked = true, signed_in = true, name = 'old' }
    browser.cache = { value = {}, at = os.time() }
    local res, err = auth.handle_status({ status = status })
    eq(res, nil)
    eq(err, 'Authentication failed or session expired (check cookies)')
    eq(auth.session, {})
    eq(browser.cache, nil)
  end
end

T['verify'] = new_set()

T['verify']['anonymous when no cookies are configured'] = function()
  local auth = helpers.mod('auth')
  local browser = helpers.mod('browser')
  auth.reset()
  browser.cache = { value = nil, at = os.time() }
  local session, err = auth.verify()
  eq(err, nil)
  eq(session.signed_in, false)
  eq(session.checked, true)
  eq(auth.session, {})
  eq(browser.cache, nil)
end

T['verify']['revalidates cached sessions when credentials change'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()
  local key, requests = 'first', 0

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function() return key end, function()
    helpers.with_stub('leetcode-ui.net', 'request', function()
      requests = requests + 1
      local name = requests == 1 and 'first-user' or 'second-user'
      return {
        status = 200,
        body = vim.json.encode({ data = { userStatus = { is_signed_in = true, id = 1, name = name } } }),
      },
        nil
    end, function()
      eq(auth.verify().name, 'first-user')
      key = 'second'
      eq(auth.verify().name, 'second-user')
      eq(requests, 2)
    end)
  end)
end

T['verify']['does not cache results after a credential change during the request'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()
  local keys = 0

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function()
    keys = keys + 1
    return keys == 1 and 'old-user' or 'new-user'
  end, function()
    helpers.with_stub(
      'leetcode-ui.net',
      'request',
      function()
        return {
          status = 200,
          body = vim.json.encode({ data = { userStatus = { is_signed_in = true, id = 1, name = 'user' } } }),
        },
          nil
      end,
      function()
        local session, err = auth.verify()
        eq(session, nil)
        eq(err, 'Authentication state changed')
        eq(auth.session.checked, nil)
      end
    )
  end)
end

T['verify']['does not cache when reset during the final identity check'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  local async = helpers.mod('async')
  auth.reset()
  local calls, thread = 0, nil

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function()
    calls = calls + 1
    if calls == 2 then
      thread = coroutine.running()
      coroutine.yield()
    end
    return 'same-key'
  end, function()
    helpers.with_stub(
      'leetcode-ui.net',
      'request',
      function()
        return {
          status = 200,
          body = vim.json.encode({ data = { userStatus = { is_signed_in = true, id = 1, name = 'user' } } }),
        },
          nil
      end,
      function()
        local session, err
        async.run(function()
          session, err = auth.verify()
        end)
        assert(thread ~= nil)
        auth.reset()
        eq(async.resume(thread), true)
        eq(session, nil)
        eq(err, 'Authentication state changed')
        eq(auth.session.checked, nil)
      end
    )
  end)
end

T['verify']['works with a stubbed network response'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()
  local request_body, requests = nil, 0

  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    requests = requests + 1
    request_body = opts.body
    return {
      status = 200,
      body = vim.json.encode({
        data = { userStatus = { is_signed_in = true, id = 1, name = 'user', is_premium = true } },
      }),
    },
      nil
  end, function()
    local session, err = auth.verify()
    eq(err, nil)
    eq(session.signed_in, true)
    eq(session.name, 'user')
    eq(helpers.contains(request_body or '', '"variables":{}'), true)
    eq(session.is_premium, true)
    eq(session.user_id, 1)

    local cached = auth.verify()
    eq(cached.name, 'user')
    eq(requests, 1)
    eq(auth.session.checked, true)
  end)
end

T['verify']['treats missing user id as signed out'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()

  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function()
      return {
        status = 200,
        body = vim.json.encode({ data = { userStatus = { is_signed_in = true, name = 'user' } } }),
      },
        nil
    end,
    function()
      local session = auth.verify()
      eq(session.signed_in, false)
    end
  )
end

T['verify']['retries signed-out server responses'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()
  local requests, signed_in = 0, false

  helpers.with_stub('leetcode-ui.net', 'request', function()
    requests = requests + 1
    local user = { is_signed_in = signed_in, id = signed_in and 1 or nil, name = 'user' }
    return { status = 200, body = vim.json.encode({ data = { userStatus = user } }) }, nil
  end, function()
    eq(auth.verify().signed_in, false)
    eq(auth.session, {})

    signed_in = true
    eq(auth.verify().signed_in, true)
    eq(requests, 2)
    eq(auth.session.signed_in, true)
  end)
end

T['verify']['reports network and malformed responses'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')

  helpers.with_stub('leetcode-ui.net', 'request', function() return nil, 'curl failed' end, function()
    auth.reset()
    local session, err = auth.verify()
    eq(session, nil)
    eq(err, 'curl failed')
  end)

  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = 'not json' }, nil end,
    function()
      auth.reset()
      local session, err = auth.verify()
      eq(session, nil)
      eq(err, 'Failed to verify authentication (bad response)')
    end
  )

  for _, body in ipairs({ '{"data":null}', '{"data":{"userStatus":null}}' }) do
    helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 200, body = body }, nil end, function()
      auth.reset()
      local session, err = auth.verify()
      if body == '{"data":null}' then
        eq(session, nil)
        eq(err, 'Failed to verify authentication (bad response)')
      else
        eq(err, nil)
        eq(session.signed_in, false)
      end
    end)
  end

  for status, expected in pairs({
    [429] = 'Too many requests, LeetCode requires a short cool-down',
    [500] = 'Request failed (HTTP 500)',
  }) do
    helpers.with_stub(
      'leetcode-ui.net',
      'request',
      function() return { status = status, body = '{}' }, nil end,
      function()
        auth.reset()
        local session, err = auth.verify()
        eq(session, nil)
        eq(err, expected)
      end
    )
  end

  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = '{"errors":[{"message":"bad"},1]}' }, nil end,
    function()
      auth.reset()
      local session, err = auth.verify()
      eq(session, nil)
      eq(err, 'bad\nunknown error')
    end
  )
end

T['verify']['discards results superseded by reset'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()

  local session, err
  helpers.with_stub('leetcode-ui.net', 'request', function()
    coroutine.yield()
    return {
      status = 200,
      body = vim.json.encode({ data = { userStatus = { is_signed_in = true, id = 1, name = 'user' } } }),
    },
      nil
  end, function()
    local thread = coroutine.create(function()
      session, err = auth.verify()
    end)
    coroutine.resume(thread)
    auth.reset()
    coroutine.resume(thread)
  end)

  eq(session, nil)
  eq(err, 'Authentication state changed')
  eq(auth.session, {})
end

T['verify']['does not cache a result superseded by a 401'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()

  local session, err
  helpers.with_stub('leetcode-ui.net', 'request', function()
    coroutine.yield()
    return {
      status = 200,
      body = vim.json.encode({ data = { userStatus = { is_signed_in = true, id = 1, name = 'user' } } }),
    },
      nil
  end, function()
    local worker = coroutine.create(function()
      session, err = auth.verify()
    end)
    coroutine.resume(worker)
    auth.handle_status({ status = 401 })
    coroutine.resume(worker)
  end)

  eq(session, nil)
  eq(err, 'Authentication state changed')
  eq(auth.session, {})
end

T['verify']['does not cache authentication failures'] = function()
  helpers.configure({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()

  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 403 }, nil end, function()
    local session, err = auth.verify()
    eq(session, nil)
    eq(err, 'Authentication failed or session expired (check cookies)')
    eq(auth.session.checked, nil)
  end)
end

T['reset'] = new_set()

T['reset']['clears the cache'] = function()
  local auth = helpers.mod('auth')
  auth.session = { checked = true }
  auth.reset()
  eq(auth.session, {})
end

return T
