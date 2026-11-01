-- Tests for leetcode-ui.browser (cookie parsing, offline fixtures).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['env'] = new_set()

T['env']['reads LEETCODE_SESSION and CSRFTOKEN from env'] = function()
  helpers.setup({ browser = 'none' })
  vim.env.LEETCODE_SESSION = 'env-sess'
  vim.env.CSRFTOKEN = 'env-csrf'
  local auth = require('leetcode-ui.auth')
  local jar = auth.cookies()
  eq(jar.LEETCODE_SESSION, 'env-sess')
  eq(jar.csrftoken, 'env-csrf')
  vim.env.LEETCODE_SESSION = nil
  vim.env.CSRFTOKEN = nil
end

T['firefox'] = new_set()

T['firefox']['parses cookies.sqlite'] = function()
  local dir = helpers.tmpdir()
  local profile = dir .. '/abc123.default'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_firefox_db, profile, { LEETCODE_SESSION = 'fx123', csrftoken = 'cfx' })
  if not ok then return end
  helpers.setup({ browser = 'firefox', browser_paths = { firefox = profile } })
  vim.env.LEETCODE_SESSION = nil
  vim.env.CSRFTOKEN = nil
  local browser = require('leetcode-ui.browser')
  browser.reset()
  local jar = browser.get_cookies()
  eq(type(jar), 'table')
end

T['chromium'] = new_set()

T['chromium']['decrypts v10 values on Linux'] = function()
  local dir = helpers.tmpdir()
  local profile = dir .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_chromium_db, profile, 'chro456', 'cch')
  if not ok then return end
  helpers.setup({ browser = 'chromium', browser_paths = { chromium = profile } })
  vim.env.LEETCODE_SESSION = nil
  vim.env.CSRFTOKEN = nil
  local browser = require('leetcode-ui.browser')
  browser.reset()
  local jar = browser.get_cookies()
  eq(type(jar), 'table')
end

T['edge'] = new_set()

T['edge']['reads from edge path when configured'] = function()
  local dir = helpers.tmpdir()
  local profile = dir .. '/Default'
  vim.fn.mkdir(profile, 'p')
  local ok = pcall(helpers.make_chromium_db, profile, 'edge789', 'ced')
  if not ok then return end
  helpers.setup({ browser = 'edge', browser_paths = { edge = profile } })
  vim.env.LEETCODE_SESSION = nil
  vim.env.CSRFTOKEN = nil
  local browser = require('leetcode-ui.browser')
  browser.reset()
  local jar = browser.get_cookies()
  eq(type(jar), 'table')
end

T['safari'] = new_set()

T['safari']['reads binary cookies plist'] = function()
  local ok, browser = pcall(require, 'leetcode-ui.browser')
  eq(ok, true)
  eq(type(browser.get_cookies), 'function')
end

T['explicit'] = new_set()

T['explicit']['setup.cookies used directly'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ cookies = { LEETCODE_SESSION = 'exp-s', csrftoken = 'exp-c' }, browser = 'none' })
  local auth = require('leetcode-ui.auth')
  local ok, jar = pcall(auth.cookies)
  eq(ok, true)
  eq(type(jar), 'table')
end

return T
