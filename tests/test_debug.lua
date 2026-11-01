local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = { pre_case = function() helpers.setup() end },
})

local function stub_detail()
  local qmod = require('leetcode-ui.api.question')
  qmod.get_detail = function(slug) return helpers.fake_detail({ title_slug = slug }), nil end
  qmod.find_in_list = function(_slug) return { ac_rate = 50.5, topic_tags = { { name = 'Array', slug = 'array' } }, status = nil } end
  qmod.get_list = function() return { total = 1, questions = { { title_slug = 'two-sum', frontend_id = '1', difficulty = 'Easy', status = nil, is_paid_only = false, ac_rate = 50.5, topic_tags = { { name = 'Array', slug = 'array' } } } } }, nil end
end

T['x'] = new_set()
T['x']['opens'] = function()
  stub_detail()
  local q = require('leetcode-ui.question')
  local msgs = {}
  local orig = vim.notify
  vim.notify = function(m, lvl) table.insert(msgs, tostring(m)) end
  q.open('two-sum')
  helpers.wait_for(function() return q.current() ~= nil end, 5000)
  vim.notify = orig
  print('MSGS:', table.concat(msgs, ' | '))
  print('CURRENT:', q.current() and q.current().slug or 'nil')
  for k,v in pairs(q.views or {}) do print('VIEW', k, v.slug, v.active, 'winid=', v.winid) end
  eq(q.current() ~= nil, true)
end

return T
