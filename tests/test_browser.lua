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
  eq(browser.selected(), nil)
  eq(browser.get_cookies(), nil)
end

T['selection']['explicit browser is selected'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'firefox' })
  eq(helpers.mod('browser').selected(), 'firefox')
end

T['selection']['auto picks the first available browser'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'auto' })
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'cookie_db', function(name)
    if name == 'brave' then return '/tmp/Cookies' end
    return nil
  end, function() eq(browser.selected(), 'brave') end)
end

T['firefox'] = new_set()

T['firefox']['parses cookies.sqlite'] = function()
  local profile = helpers.tmpdir() .. '/abc123.default'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_firefox_db, profile, { LEETCODE_SESSION = 'fx123', csrftoken = 'cfx' })
  if not ok then return end

  local config = require('leetcode-ui.config')
  config.setup({ browser = 'firefox', browser_paths = { firefox = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(type(cookies), 'table')
  eq(cookies.LEETCODE_SESSION, 'fx123')
  eq(cookies.csrftoken, 'cfx')
end

T['firefox']['missing database returns an error'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'firefox', browser_paths = { firefox = '/definitely/missing' } })
  local browser = helpers.mod('browser')
  local cookies, err = browser.read_cookies('firefox')
  eq(cookies, nil)
  eq(type(err), 'string')
end

T['chromium'] = new_set()

T['chromium']['decrypts v10 values'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_chromium_db, profile, 'chro456', 'cch')
  if not ok then return end

  local config = require('leetcode-ui.config')
  config.setup({ browser = 'chromium', browser_paths = { chromium = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(type(cookies), 'table')
  eq(cookies.LEETCODE_SESSION, 'chro456')
  eq(cookies.csrftoken, 'cch')
end

T['chromium']['edge uses edge paths'] = function()
  local profile = helpers.tmpdir() .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_chromium_db, profile, 'edge789', 'ced')
  if not ok then return end

  local config = require('leetcode-ui.config')
  config.setup({ browser = 'edge', browser_paths = { edge = profile } })
  local browser = helpers.mod('browser')
  browser.reset()
  local cookies = browser.get_cookies()
  eq(type(cookies), 'table')
  eq(cookies.LEETCODE_SESSION, 'edge789')
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
  eq(type(err), 'string')
end

T['decrypt_blob']['keyring versions without a password return an error'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'keyring_password', function() return nil end, function()
    local value, err = browser.decrypt_blob('763131', 'chromium')
    eq(value, nil)
    eq(type(err), 'string')
  end)
end

T['decrypt_blob']['missing openssl returns an error'] = function()
  local browser = helpers.mod('browser')
  helpers.with_stub('leetcode-ui.browser', 'derive_key', function() return nil end, function()
    local value, err = browser.decrypt_blob('763130', 'chromium')
    eq(value, nil)
    eq(err, 'openssl is unavailable')
  end)
end

T['safari'] = new_set()

T['safari']['module exposes a reader'] = function()
  local browser = helpers.mod('browser')
  eq(type(browser.read_cookies), 'function')
  eq(type(browser.safari_script), 'string')
end

T['paths'] = new_set()

T['paths']['cookie_db honours directory overrides'] = function()
  local profile = helpers.tmpdir() .. '/profile'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_firefox_db, profile)
  if not ok then return end

  local config = require('leetcode-ui.config')
  config.setup({ browser = 'firefox', browser_paths = { firefox = profile } })
  local browser = helpers.mod('browser')
  eq(browser.cookie_db('firefox'), profile .. '/cookies.sqlite')
end

T['paths']['cookie_db returns nil for missing overrides'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'firefox', browser_paths = { firefox = '/definitely/missing' } })
  eq(helpers.mod('browser').cookie_db('firefox'), nil)
end

return T
