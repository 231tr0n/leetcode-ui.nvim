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
  local config = require('leetcode-ui.config')
  config.setup({ cookie_file = '', browser = 'none' })
  eq(auth.cookie_file(), nil)
end

T['cookie_file']['normalizes configured path'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ cookie_file = '~/cookies.txt', browser = 'none' })
  local auth = helpers.mod('auth')
  eq(auth.cookie_file(), vim.fs.normalize('~/cookies.txt'))
end

T['cookies'] = new_set()

T['cookies']['reads configured cookies first'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's1', csrftoken = 'c1' } })
  local cookies = helpers.mod('auth').cookies()
  eq(cookies.LEETCODE_SESSION, 's1')
  eq(cookies.csrftoken, 'c1')
end

T['cookies']['falls back to environment variables'] = function()
  vim.env.LEETCODE_SESSION = 'env-session'
  vim.env.CSRFTOKEN = 'env-csrf'
  local cookies = helpers.mod('auth').cookies()
  eq(cookies.LEETCODE_SESSION, 'env-session')
  eq(cookies.csrftoken, 'env-csrf')
  vim.env.LEETCODE_SESSION = nil
  vim.env.CSRFTOKEN = nil
end

T['cookies']['browser cookies only fill missing entries'] = function()
  helpers.with_stub(
    'leetcode-ui.browser',
    'get_cookies',
    function() return { LEETCODE_SESSION = 'browser-session', csrftoken = 'browser-csrf' } end,
    function()
      local config = require('leetcode-ui.config')
      config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 'configured' } })
      local cookies = helpers.mod('auth').cookies()
      eq(cookies.LEETCODE_SESSION, 'configured')
      eq(cookies.csrftoken, 'browser-csrf')
    end
  )
end

T['cookies']['does not touch browsers when both cookies are configured'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'auto', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
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
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tcsrftoken\tjar-csrf',
    '.leetcode.com\tTRUE\t/\tTRUE\t0\tLEETCODE_SESSION\tjar-session',
  }, path)
  local config = require('leetcode-ui.config')
  config.setup({ cookie_file = path, browser = 'none' })
  local auth = helpers.mod('auth')
  eq(auth.jar_csrf(path), 'jar-csrf')
  eq(auth.csrf(), 'jar-csrf')
  eq(auth.has_session(), true)
end

T['csrf']['jar_csrf returns nil for missing files'] = function()
  local auth = helpers.mod('auth')
  eq(auth.jar_csrf('/definitely/missing/cookies.txt'), nil)
end

T['has_session'] = new_set()

T['has_session']['requires both cookies'] = function()
  local config = require('leetcode-ui.config')
  local auth = helpers.mod('auth')

  config.setup({ browser = 'none', cookies = {} })
  eq(auth.has_session(), false)

  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's' } })
  eq(auth.has_session(), false)

  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  eq(auth.has_session(), true)
end

T['headers'] = new_set()

T['headers']['omits session headers when anonymous'] = function()
  local headers = helpers.mod('auth').headers()
  eq(has_header(headers, 'Cookie:'), nil)
  eq(has_header(headers, 'X-CSRFToken:'), nil)
end

T['headers']['adds cookie and csrf headers'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
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
  local config = require('leetcode-ui.config')
  config.setup({ cookie_file = path, browser = 'none' })
  local headers = helpers.mod('auth').headers()
  eq(has_header(headers, 'Cookie:'), nil)
  eq(has_header(headers, 'X-CSRFToken:'), 'X-CSRFToken: jar-csrf')
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

T['handle_status']['401 clears the cached session'] = function()
  local auth = helpers.mod('auth')
  auth.session = { checked = true, signed_in = true, name = 'old' }
  local res, err = auth.handle_status({ status = 401 })
  eq(res, nil)
  eq(type(err), 'string')
  eq(auth.session, {})
end

T['verify'] = new_set()

T['verify']['anonymous when no cookies are configured'] = function()
  local auth = helpers.mod('auth')
  auth.reset()
  local session, err = auth.verify()
  eq(err, nil)
  eq(session.signed_in, false)
  eq(session.checked, true)
end

T['verify']['returns cached sessions'] = function()
  local auth = helpers.mod('auth')
  auth.session = { checked = true, signed_in = true, name = 'cached' }
  local session, err = auth.verify()
  eq(err, nil)
  eq(session.name, 'cached')
end

T['verify']['works with a stubbed network response'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()

  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function()
      return {
        status = 200,
        body = vim.json.encode({
          data = { userStatus = { is_signed_in = true, id = 1, name = 'user', is_premium = true } },
        }),
      },
        nil
    end,
    function()
      local session, err = auth.verify()
      eq(err, nil)
      eq(session.signed_in, true)
      eq(session.name, 'user')
      eq(session.is_premium, true)
      eq(session.user_id, 1)
    end
  )
end

T['verify']['treats missing user id as signed out'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
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

T['verify']['reports network and malformed responses'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
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
      eq(type(err), 'string')
    end
  )
end

T['verify']['does not cache authentication failures'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  local auth = helpers.mod('auth')
  auth.reset()

  helpers.with_stub('leetcode-ui.net', 'request', function() return { status = 403 }, nil end, function()
    local session, err = auth.verify()
    eq(session, nil)
    eq(type(err), 'string')
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
