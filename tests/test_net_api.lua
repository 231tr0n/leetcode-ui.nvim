-- Tests for leetcode-ui.net and leetcode-ui.api plumbing (stubs).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      helpers.setup({ browser = 'none', cookies = {} })
    end,
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
  helpers.with_stub('leetcode-ui.api', 'graphql', function(query, variables)
    return { question = { titleSlug = 'two-sum' } }, nil
  end, function()
    local data, err = api.graphql('q', { a = 1 })
    eq(data.question.titleSlug, 'two-sum')
    eq(err, nil)
  end)
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

return T
