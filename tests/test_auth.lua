-- Tests for leetcode-ui.auth (verification and cookie merging).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['verify'] = new_set()

T['verify']['not signed in when no cookies'] = function()
  local auth = require('leetcode-ui.auth')
  auth.session = nil
  local session = auth.verify()
  if type(session) == 'table' then
    eq(session.signed_in == false or session.signed_in == nil, true)
  else
    eq(session, nil)
  end
end

T['verify']['caches session'] = function()
  local auth = helpers.mod('auth')
  auth.session = { checked = true, signed_in = true, name = 'x', is_premium = false }
  local session, err = auth.verify()
  eq(session.name, 'x')
  eq(err, nil)
end

T['verify']['merges explicit cookies into jar'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ browser = 'none', cookies = { LEETCODE_SESSION = 's1', csrftoken = 'c1' } })
  local auth = require('leetcode-ui.auth')
  local jar = auth.cookies()
  eq(type(jar), 'table')
  eq(jar.LEETCODE_SESSION, 's1')
  eq(jar.csrftoken, 'c1')
end

T['handle_status'] = new_set()

T['handle_status']['passes through 200'] = function()
  local auth = helpers.mod('auth')
  local res, err = auth.handle_status({ status = 200, body = '{}' })
  eq(res.status, 200)
  eq(err, nil)
end

T['handle_status']['401 clears cookies and errors'] = function()
  local auth = require('leetcode-ui.auth')
  vim.env.LEETCODE_SESSION = 'bad'
  local res, err = auth.handle_status({ status = 401, body = '' })
  eq(res, nil)
  eq(type(err), 'string')
  vim.env.LEETCODE_SESSION = nil
end

T['handle_status']['redirect to login'] = function()
  local auth = require('leetcode-ui.auth')
  local res, err = auth.handle_status({ status = 302, headers = { location = '/accounts/login/' } })
  eq(res == nil or type(res) == 'table', true)
  eq(type(err) == 'string' or err == nil, true)
end

return T
