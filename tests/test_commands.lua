-- Tests for leetcode-ui public commands (M.*).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['menu'] = new_set()
T['menu']['opens without error'] = function()
  local m = require('leetcode-ui')
  local ok = pcall(m.menu)
  eq(ok, true)
end

T['stats'] = new_set()
T['stats']['opens without error'] = function()
  local m = require('leetcode-ui')
  local ok = pcall(m.stats)
  eq(ok, true)
end

T['session'] = new_set()
T['session']['runs without error'] = function()
  local m = require('leetcode-ui')
  local ok = pcall(m.session)
  eq(ok, true)
end

T['close'] = new_set()
T['close']['runs without error'] = function()
  local m = require('leetcode-ui')
  local ok = pcall(m.close)
  eq(ok, true)
end

T['random'] = new_set()
T['random']['calls picker with stubbed api'] = function()
  local api = require('leetcode-ui.api.question')
  helpers.with_stub('leetcode-ui.api.question', 'get_random', function() return 'two-sum', nil end, function()
    local m = require('leetcode-ui')
    local ok = pcall(m.random)
    eq(ok, true)
  end)
end

T['daily'] = new_set()
T['daily']['calls picker with stubbed api'] = function()
  local api = require('leetcode-ui.api.question')
  helpers.with_stub('leetcode-ui.api.question', 'get_daily', function() return 'two-sum', nil end, function()
    local m = require('leetcode-ui')
    local ok = pcall(m.daily)
    eq(ok, true)
  end)
end

T['list'] = new_set()
T['list']['calls picker with stubbed api'] = function()
  local api = require('leetcode-ui.api.question')
  helpers.with_stub('leetcode-ui.api.question', 'get_list', function() return { total = 1, questions = {} }, nil end, function()
    local m = require('leetcode-ui')
    local ok = pcall(m.list)
    eq(ok, true)
  end)
end

return T
