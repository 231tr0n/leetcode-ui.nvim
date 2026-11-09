-- Tests for leetcode-ui.browser (cookie parsing, offline fixtures).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none' }) end,
  },
})

T['selection'] = new_set()

T['selection']['none disables import'] = function()
  local browser = helpers.mod('browser')
  local reads = 0
  helpers.with_stub('leetcode-ui.browser', 'read_cookies', function()
    reads = reads + 1
    return { LEETCODE_SESSION = 'unexpected' }, nil
  end, function() eq(browser.get_cookies(), nil) end)
  eq(reads, 0)
end

T['selection']['explicit browser reads its cookies'] = function()
  helpers.configure({ browser = 'firefox' })
  local browser = helpers.mod('browser')
  helpers.with_stub(
    'leetcode-ui.browser',
    'read_cookies',
    function(name) return { source = name, LEETCODE_SESSION = 's', csrftoken = 'c' }, nil end,
    function() eq(browser.get_cookies().source, 'firefox') end
  )
end

T['selection']['cache is invalidated when the browser changes'] = function()
  local browser = helpers.mod('browser')
  local config = helpers.mod('config')
  helpers.with_stub('leetcode-ui.browser', 'read_cookies', function(name) return { source = name }, nil end, function()
    helpers.configure({ browser = 'firefox' })
    eq(browser.get_cookies().source, 'firefox')
    config.config.browser = 'chrome'
    eq(browser.get_cookies().source, 'chrome')
  end)
end

T['selection']['cache is invalidated when the domain changes'] = function()
  local browser = helpers.mod('browser')
  local config = helpers.mod('config')
  local reads = 0
  helpers.with_stub('leetcode-ui.browser', 'read_cookies', function(name)
    reads = reads + 1
    return { source = name, domain = config.config.url }, nil
  end, function()
    helpers.configure({ browser = 'firefox' })
    eq(browser.get_cookies().domain, 'leetcode.com')
    config.config.url = 'leetcode.cn'
    eq(browser.get_cookies().domain, 'leetcode.cn')
    eq(reads, 2)
  end)
end

T['selection']['cache expires after the TTL'] = function()
  helpers.configure({ browser = 'firefox' })
  local browser = helpers.mod('browser')
  local now = 1000
  local reads = 0
  helpers.with_stub('leetcode-ui.browser', 'now', function() return now end, function()
    helpers.with_stub('leetcode-ui.browser', 'read_cookies', function()
      reads = reads + 1
      return { LEETCODE_SESSION = 's', csrftoken = 'c' }, nil
    end, function()
      browser.get_cookies()
      now = now + browser.cache_ttl - 1
      browser.get_cookies()
      eq(reads, 1)
      now = now + 2
      browser.get_cookies()
      eq(reads, 2)
    end)
  end)
end

T['selection']['auto skips empty databases and uses a complete session'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
    if name == 'firefox' or name == 'chrome' then return '/tmp/' .. name end
    return nil
  end, function()
    helpers.with_stub('leetcode-ui.browser', 'read_cookies', function(name)
      if name == 'firefox' then return {}, nil end
      return { LEETCODE_SESSION = 'session', csrftoken = 'csrf' }, nil
    end, function()
      local cookies = browser.get_cookies()
      eq(cookies.LEETCODE_SESSION, 'session')
      eq(browser.cache.browser, 'chrome')
    end)
  end)
end

T['selection']['auto keeps warnings from the selected cookie source'] = function()
  helpers.configure({ browser = 'auto', notifications = true })
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
    if name == 'firefox' or name == 'chrome' then return '/tmp/' .. name end
    return nil
  end, function()
    helpers.with_stub('leetcode-ui.browser', 'read_cookies', function(name)
      if name == 'firefox' then return {}, 'keyring unavailable' end
      return {}, nil
    end, function()
      local messages = helpers.capture_notify(function() eq(browser.get_cookies(), nil) end)
      eq(helpers.contains(messages[#messages].message, 'keyring unavailable'), true)
    end)
  end)
end

T['selection']['auto skips partial cookie pairs'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
    if name == 'firefox' or name == 'chrome' then return '/tmp/' .. name end
    return nil
  end, function()
    helpers.with_stub('leetcode-ui.browser', 'read_cookies', function(name)
      if name == 'firefox' then return { LEETCODE_SESSION = 'partial' }, nil end
      return { LEETCODE_SESSION = 'session', csrftoken = 'csrf' }, nil
    end, function()
      local cookies = browser.get_cookies()
      eq(cookies.LEETCODE_SESSION, 'session')
      eq(cookies.csrftoken, 'csrf')
      eq(browser.cache.browser, 'chrome')
    end)
  end)
end

T['selection']['auto skips the source that failed authentication'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
    if name == 'firefox' or name == 'chrome' then return '/tmp/' .. name end
    return nil
  end, function()
    helpers.with_stub(
      'leetcode-ui.browser',
      'read_cookies',
      function(name) return { LEETCODE_SESSION = name, csrftoken = 'csrf' }, nil end,
      function()
        eq(browser.get_cookies().LEETCODE_SESSION, 'firefox')
        browser.reset_cookies()
        eq(browser.get_cookies().LEETCODE_SESSION, 'chrome')
      end
    )
  end)
end

T['selection']['retries a failed source after the TTL'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  local now = 1000
  helpers.with_stub('leetcode-ui.browser', 'now', function() return now end, function()
    helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
      if name == 'firefox' or name == 'chrome' then return '/tmp/' .. name end
      return nil
    end, function()
      helpers.with_stub(
        'leetcode-ui.browser',
        'read_cookies',
        function(name) return { LEETCODE_SESSION = name, csrftoken = 'csrf' }, nil end,
        function()
          eq(browser.get_cookies().LEETCODE_SESSION, 'firefox')
          browser.reset_cookies()
          eq(browser.get_cookies().LEETCODE_SESSION, 'chrome')

          now = now + browser.cache_ttl + 1
          eq(browser.get_cookies().LEETCODE_SESSION, 'firefox')
        end
      )
    end)
  end)
end

T['selection']['auto prefers the partial source with more cookies'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
    if name == 'firefox' or name == 'chrome' then return '/tmp/' .. name end
    return nil
  end, function()
    helpers.with_stub('leetcode-ui.browser', 'read_cookies', function(name)
      if name == 'firefox' then return { LEETCODE_SESSION = 'firefox', marker = 'fx' }, nil end
      return { LEETCODE_SESSION = 'chrome', marker = 'chrome', extra = true }, nil
    end, function()
      local cookies = browser.get_cookies()
      eq(cookies.LEETCODE_SESSION, 'chrome')
      eq(browser.cache.browser, 'chrome')
    end)
  end)
end

T['selection']['auto ignores an empty database'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub(
    'leetcode-ui.browser',
    'cookie_db',
    function(name) return name == 'firefox' and '/tmp/firefox' or nil end,
    function()
      helpers.with_stub('leetcode-ui.browser', 'read_cookies', function() return {}, nil end, function()
        eq(browser.get_cookies(), nil)
        eq(browser.cache.value, nil)
        eq(browser.cache.browser, nil)
      end)
    end
  )
end

T['selection']['auto without databases returns nil'] = function()
  helpers.configure({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub(
    'leetcode-ui.browser',
    'cookie_db',
    function() return nil end,
    function() eq(browser.get_cookies(), nil) end
  )
end

T['firefox'] = new_set()

T['firefox']['parses only cookies from LeetCode domains'] = function()
  local profile = helpers.tmpdir() .. '/abc123.default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_firefox_db(profile, { LEETCODE_SESSION = 'fx123', csrftoken = 'cfx' })

  helpers.configure({ browser = 'firefox', browser_paths = { firefox = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(type(cookies), 'table')
  eq(cookies.LEETCODE_SESSION, 'fx123')
  eq(cookies.csrftoken, 'cfx')
end

T['firefox']['honours the configured domain'] = function()
  local profile = helpers.tmpdir() .. '/abc123.default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_firefox_db(profile, { LEETCODE_SESSION = 'cn-session', csrftoken = 'cn-csrf' }, 'leetcode.cn')

  local browser = helpers.mod('browser')
  helpers.configure({ url = 'leetcode.cn', browser = 'firefox', browser_paths = { firefox = profile } })
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, 'cn-session')
  eq(cookies.csrftoken, 'cn-csrf')

  helpers.configure({ url = 'leetcode.com', browser = 'firefox', browser_paths = { firefox = profile } })
  browser.reset()
  cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['firefox']['ignores expired cookies'] = function()
  local profile = helpers.tmpdir() .. '/abc123.default'
  vim.fn.mkdir(profile, 'p')
  local path = helpers.make_firefox_db(profile)
  helpers.expire_firefox_cookies(path)

  helpers.configure({ browser = 'firefox', browser_paths = { firefox = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['firefox']['accepts cookies with a future expiry'] = function()
  local profile = helpers.tmpdir() .. '/abc123.default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_firefox_db(profile, { LEETCODE_SESSION = 'future', csrftoken = 'future-csrf' }, nil, os.time() + 3600)

  helpers.configure({ browser = 'firefox', browser_paths = { firefox = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  eq(browser.get_cookies().LEETCODE_SESSION, 'future')
end

T['firefox']['missing database returns an error'] = function()
  helpers.configure({ browser = 'firefox', browser_paths = { firefox = '/definitely/missing' } })
  local browser = helpers.mod('browser')
  local cookies, err = browser.read_cookies('firefox')
  eq(cookies, nil)
  eq(type(err), 'string')
end

T['epiphany'] = new_set()

T['epiphany']['parses cookies from its SQLite database'] = function()
  local profile = helpers.tmpdir() .. '/epiphany'
  vim.fn.mkdir(profile, 'p')
  helpers.make_firefox_db(profile, { LEETCODE_SESSION = 'eph-session', csrftoken = 'eph-csrf' })

  helpers.configure({ browser = 'epiphany', browser_paths = { epiphany = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, 'eph-session')
  eq(cookies.csrftoken, 'eph-csrf')
end

T['decoding'] = new_set()

T['decoding']['ignores JSON null cookie values'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function() return '/tmp/firefox' end, function()
    helpers.with_stub('leetcode-ui.async', 'system', function()
      local rows = {
        { name = 'LEETCODE_SESSION', value = vim.NIL, blob = '' },
        { name = 'csrftoken', value = 'csrf', blob = '' },
      }
      return { code = 0, stdout = vim.json.encode(rows), stderr = '' }
    end, function()
      local cookies = browser.read_cookies('firefox')
      eq(cookies.LEETCODE_SESSION, nil)
      eq(cookies.csrftoken, 'csrf')
    end)
  end)
end

T['decoding']['ignores null encrypted blobs'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function() return '/tmp/chromium' end, function()
    helpers.with_stub('leetcode-ui.async', 'system', function()
      local rows = { { name = 'LEETCODE_SESSION', value = vim.NIL, blob = vim.NIL } }
      return { code = 0, stdout = vim.json.encode(rows), stderr = '' }
    end, function()
      local cookies, err = browser.read_cookies('chromium')
      eq(cookies.LEETCODE_SESSION, nil)
      eq(err, nil)
    end)
  end)
end

T['decoding']['reports invalid reader JSON'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function() return '/tmp/firefox' end, function()
    helpers.with_stub(
      'leetcode-ui.async',
      'system',
      function() return { code = 0, stdout = 'not json', stderr = '' } end,
      function()
        local cookies, err = browser.read_cookies('firefox')
        eq(cookies, nil)
        eq(helpers.contains(err, 'invalid JSON'), true)
      end
    )
  end)
end

T['chromium'] = new_set()

T['chromium']['decrypts v10 values'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_chromium_db(profile, 'chro456', 'cch')

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(type(cookies), 'table')
  eq(cookies.LEETCODE_SESSION, 'chro456')
  eq(cookies.csrftoken, 'cch')
end

T['chromium']['prefers plaintext values over encrypted blobs'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local path = helpers.make_chromium_db(profile, 'plain456', 'cplain', 'plain')
  helpers.set_chromium_encrypted(path, 'deadbeef')

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, 'plain456')
  eq(cookies.csrftoken, 'cplain')
end

T['chromium']['strips the Linux integrity prefix'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_chromium_db(profile, 'prefixed', 'prefixed-csrf', 'v10', nil, nil, nil, true)

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  eq(browser.get_cookies().LEETCODE_SESSION, 'prefixed')
end

T['chromium']['ignores cookies from another domain'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_chromium_db(profile, 'other-session', 'other-csrf', 'plain', nil, 'leetcode.cn')

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['chromium']['ignores expired cookies'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local path = helpers.make_chromium_db(profile, 'expired-session', 'expired-csrf', 'plain')
  helpers.expire_chromium_cookies(path)

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['chromium']['accepts cookies with a future expiry'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local expiry = tostring(os.time() + 3600 + 11644473600) .. '000000'
  helpers.make_chromium_db(profile, 'future-session', 'future-csrf', 'plain', nil, nil, expiry)

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  eq(browser.get_cookies().LEETCODE_SESSION, 'future-session')
end

T['chromium']['decrypts v11 values with a keyring password'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_chromium_db(profile, 'v11-session', 'v11-csrf', 'v11', 'test-keyring')

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  helpers.with_stub('leetcode-ui.browser', 'keyring_password', function() return 'test-keyring' end, function()
    local cookies = browser.get_cookies()
    eq(cookies.LEETCODE_SESSION, 'v11-session')
    eq(cookies.csrftoken, 'v11-csrf')
  end)
end

T['chromium']['edge decrypts with an explicit override'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  helpers.make_chromium_db(profile, 'edge789', 'ced')

  helpers.configure({ browser = 'edge', browser_paths = { edge = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(type(cookies), 'table')
  eq(cookies.LEETCODE_SESSION, 'edge789')
end

T['keyring'] = new_set()

T['keyring']['reads Linux and macOS keyring passwords'] = function()
  local browser = helpers.mod('browser')
  helpers.with_field(vim.uv, 'os_uname', function() return { sysname = 'Linux' } end, function()
    helpers.with_stub('leetcode-ui.async', 'system', function(command)
      eq(command[1], 'secret-tool')
      return { code = 0, stdout = 'linux-password\n', stderr = '' }
    end, function() eq(browser.keyring_password('chrome'), 'linux-password') end)
  end)

  helpers.with_field(vim.uv, 'os_uname', function() return { sysname = 'Darwin' } end, function()
    helpers.with_stub('leetcode-ui.async', 'system', function(command)
      eq(command[1], 'security')
      return { code = 0, stdout = 'mac-password\n', stderr = '' }
    end, function() eq(browser.keyring_password('brave'), 'mac-password') end)
  end)

  helpers.with_field(
    vim.uv,
    'os_uname',
    function() return { sysname = 'Windows_NT' } end,
    function() eq(browser.keyring_password('chrome'), nil) end
  )
  eq(browser.keyring_password('unknown'), nil)
end

T['derive_key'] = new_set()

T['derive_key']['uses platform-specific KDF'] = function()
  local browser = helpers.mod('browser')
  helpers.with_field(
    vim.uv,
    'os_uname',
    function() return { sysname = 'Linux' } end,
    function() eq(browser.derive_key('password'), '23cf6cce5463214e9e0c459c944dd395') end
  )
  helpers.with_field(
    vim.uv,
    'os_uname',
    function() return { sysname = 'Darwin' } end,
    function() eq(browser.derive_key('password'), '9395139d5abdba8b749042ad882c0937') end
  )
end

T['decrypt_blob'] = new_set()

T['decrypt_blob']['empty input returns nil'] = function()
  local browser = helpers.mod('browser')
  local value, err = browser.decrypt_blob('', 'chromium')
  eq(value, nil)
  eq(err, nil)
end

T['decrypt_blob']['unsupported versions return an error'] = function()
  local browser = helpers.mod('browser')
  local value, err = browser.decrypt_blob('763132', 'chromium')
  eq(value, nil)
  eq(err, 'blob version "v12" is not supported')
end

T['decrypt_blob']['uses platform-specific keyring requirements'] = function()
  local browser = helpers.mod('browser')
  helpers.with_field(vim.uv, 'os_uname', function() return { sysname = 'Windows_NT' } end, function()
    local value, err = browser.decrypt_blob('763130', 'chrome')
    eq(value, nil)
    eq(err, 'encrypted Chromium cookies are not supported on Windows')
  end)

  helpers.with_field(vim.uv, 'os_uname', function() return { sysname = 'Darwin' } end, function()
    helpers.with_stub('leetcode-ui.browser', 'keyring_password', function() return nil end, function()
      local value, err = browser.decrypt_blob('763130', 'chrome')
      eq(value, nil)
      eq(helpers.contains(err, 'keyring-protected'), true)
    end)
  end)
end

T['decrypt_blob']['keyring versions without a password return an error'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'keyring_password', function() return nil end, function()
    local value, err = browser.decrypt_blob('763131', 'chromium')
    eq(value, nil)
    eq(err, 'blob version "v11" is not supported (keyring-protected)')
  end)
end

T['decrypt_blob']['key derivation failures return an error'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'derive_key', function() return nil end, function()
    local value, err = browser.decrypt_blob('763130', 'chromium')
    eq(value, nil)
    eq(err, 'cannot derive the cookie key')
  end)
end

T['decrypt_blob']['strips integrity prefixes on macOS'] = function()
  local browser = helpers.mod('browser')
  local key = '00112233445566778899aabbccddeeff'
  local script = [[
import subprocess, sys
plain = b'\0' * 32 + b'mac-value'
ct = subprocess.run(
    ['openssl', 'enc', '-e', '-aes-128-cbc', '-K', sys.argv[1], '-iv', '20' * 16],
    input=plain, capture_output=True, check=True
).stdout
print(ct.hex())
]]
  local out = vim.system({ 'python3', '-c', script, key }, { text = true }):wait()
  eq(out.code, 0)
  local blob_hex = '763130' .. vim.trim(out.stdout)

  helpers.with_field(vim.uv, 'os_uname', function() return { sysname = 'Darwin' } end, function()
    helpers.with_stub('leetcode-ui.browser', 'keyring_password', function() return 'peanuts' end, function()
      helpers.with_stub('leetcode-ui.browser', 'derive_key', function() return key end, function()
        local value, err = browser.decrypt_blob(blob_hex, 'chrome')
        eq(err, nil)
        eq(value, 'mac-value')
      end)
    end)
  end)
end

T['safari'] = new_set()

T['safari']['parses binary cookie files'] = function()
  local dir = helpers.tmpdir()
  local path = helpers.make_safari_cookies(dir, { LEETCODE_SESSION = 'safari-session', csrftoken = 'safari-csrf' })

  helpers.configure({ browser = 'safari', browser_paths = { safari = path } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, 'safari-session')
  eq(cookies.csrftoken, 'safari-csrf')
end

T['safari']['ignores empty cookie values'] = function()
  local dir = helpers.tmpdir()
  local path = helpers.make_safari_cookies(dir, { LEETCODE_SESSION = '', csrftoken = 'csrf' })
  helpers.configure({ browser = 'safari', browser_paths = { safari = path } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, 'csrf')
end

T['safari']['ignores cookies from another domain'] = function()
  local dir = helpers.tmpdir()
  local path =
    helpers.make_safari_cookies(dir, { LEETCODE_SESSION = 'cn-session', csrftoken = 'cn-csrf' }, 'leetcode.cn')

  helpers.configure({ browser = 'safari', browser_paths = { safari = path } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['safari']['ignores expired cookies'] = function()
  local dir = helpers.tmpdir()
  local path = helpers.make_safari_cookies(dir, nil, nil, 1)

  helpers.configure({ browser = 'safari', browser_paths = { safari = path } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['safari']['accepts cookies with a future expiry'] = function()
  local dir = helpers.tmpdir()
  local path = helpers.make_safari_cookies(dir, nil, nil, os.time() + 3600 - 978307200)

  helpers.configure({ browser = 'safari', browser_paths = { safari = path } })
  local browser = helpers.mod('browser')
  browser.reset()
  eq(browser.get_cookies().LEETCODE_SESSION, 'safari-session')
end

T['safari']['honours the configured domain'] = function()
  local dir = helpers.tmpdir()
  local path =
    helpers.make_safari_cookies(dir, { LEETCODE_SESSION = 'cn-session', csrftoken = 'cn-csrf' }, 'leetcode.cn')

  local browser = helpers.mod('browser')
  helpers.configure({ url = 'leetcode.cn', browser = 'safari', browser_paths = { safari = path } })
  browser.reset()
  local cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, 'cn-session')
  eq(cookies.csrftoken, 'cn-csrf')

  helpers.configure({ url = 'leetcode.com', browser = 'safari', browser_paths = { safari = path } })
  browser.reset()
  cookies = browser.get_cookies()
  eq(cookies.LEETCODE_SESSION, nil)
  eq(cookies.csrftoken, nil)
end

T['safari']['reports a missing cookie file'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function() return nil end, function()
    local cookies, err = browser.read_cookies('safari')
    eq(cookies, nil)
    eq(err, 'No Safari cookie file found')
  end)
end

T['paths'] = new_set()

T['paths']['cookie_db honours directory overrides'] = function()
  local profile = helpers.tmpdir() .. '/profile'
  vim.fn.mkdir(profile, 'p')
  vim.fn.writefile({}, profile .. '/cookies.sqlite')

  helpers.configure({ browser = 'firefox', browser_paths = { firefox = profile } })
  local browser = helpers.mod('browser')
  eq(browser.cookie_db('firefox'), profile .. '/cookies.sqlite')
end

T['paths']['cookie_db expands user-home overrides'] = function()
  local user = vim.env.USER
  if user == nil or user == '' then return end
  local expected = vim.fn.expand('~') .. '/profile/Cookies'
  helpers.configure({ browser = 'firefox', browser_paths = { firefox = '~' .. user .. '/profile/Cookies' } })
  local browser = helpers.mod('browser')
  helpers.with_field(vim.uv, 'fs_stat', function(path)
    if path == expected then return { type = 'file' } end
  end, function() eq(browser.cookie_db('firefox'), expected) end)
end

T['paths']['Chromium overrides discover Network/Cookies'] = function()
  local profile = helpers.tmpdir() .. '/Default/Network'
  vim.fn.mkdir(profile, 'p')
  vim.fn.writefile({}, profile .. '/Cookies')

  helpers.configure({ browser = 'chromium', browser_paths = { chromium = vim.fs.dirname(profile) } })
  eq(helpers.mod('browser').cookie_db('chromium'), profile .. '/Cookies')
end

T['paths']['Safari overrides discover binary cookie files'] = function()
  local dir = helpers.tmpdir() .. '/Safari'
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'cook' }, dir .. '/Cookies.binarycookies')

  helpers.configure({ browser = 'safari', browser_paths = { safari = dir } })
  eq(helpers.mod('browser').cookie_db('safari'), dir .. '/Cookies.binarycookies')
end

T['paths']['Safari discovers the current container path'] = function()
  local home = helpers.tmpdir()
  local cookies = home .. '/Library/Containers/com.apple.Safari/Data/Library/Cookies'
  vim.fn.mkdir(cookies, 'p')
  vim.fn.writefile({ 'cook' }, cookies .. '/Cookies.binarycookies')

  helpers.with_field(vim.env, 'HOME', home, function()
    helpers.configure({ browser = 'safari', browser_paths = {} })
    eq(helpers.mod('browser').cookie_db('safari'), cookies .. '/Cookies.binarycookies')
  end)
end

T['paths']['cookie_db returns nil for missing overrides'] = function()
  helpers.configure({ browser = 'firefox', browser_paths = { firefox = '/definitely/missing' } })
  eq(helpers.mod('browser').cookie_db('firefox'), nil)
end

return T
