-- Integration tests: emulating menu/question flows offline via stubs.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

local function stub_detail()
  local qmod = require('leetcode-ui.api.question') --[[@as any]]
  local original_get_detail = qmod.get_detail
  local original_find = qmod.find_in_list
  local original_get_list = qmod.get_list
  qmod['get_detail'] = function(slug) return helpers.fake_detail({ title_slug = slug }), nil end
  qmod['find_in_list'] = function(_slug)
    return { ac_rate = 50.5, topic_tags = { { name = 'Array', slug = 'array' } }, status = nil }
  end
  qmod['get_list'] = function()
    return {
      total = 1,
      questions = {
        {
          title_slug = 'two-sum',
          frontend_id = '1',
          difficulty = 'Easy',
          status = nil,
          is_paid_only = false,
          ac_rate = 50.5,
          topic_tags = { { name = 'Array', slug = 'array' } },
        },
      },
    },
      nil
  end
  return function()
    qmod['get_detail'] = original_get_detail
    qmod['find_in_list'] = original_find
    qmod['get_list'] = original_get_list
  end
end

local function stub_runner()
  local rmod = require('leetcode-ui.api.runner') --[[@as any]]
  local oi = rmod.interpret
  local os = rmod.submit
  rmod['interpret'] = function(_question, _code, _data_input)
    return {
      status = 'Accepted',
      ok = true,
      runtime_ms = 10,
      memory_mb = 1024 * 1024,
      compare = '1',
      correct = 1,
      total = 1,
      message = nil,
    },
      nil
  end
  rmod['submit'] = function(_question, _code)
    return { status = 'Accepted', ok = true, runtime_ms = 10, memory_mb = 1024 * 1024 }, nil
  end
  return function()
    rmod['interpret'] = oi
    rmod['submit'] = os
  end
end

T['question'] = new_set()

T['question']['opens two-sum'] = function()
  local restore = stub_detail()
  local q = require('leetcode-ui.question')
  q.open('two-sum')
  local ok = helpers.wait_for(function() return q.current() ~= nil end, 5000)
  eq(ok, true)
  local view = q.current() --[[@as any]]
  eq(view.slug, 'two-sum')
  eq(view.active, 'code')
  restore()
  q.close(view)
end

T['question']['tab switching'] = function()
  local restore = stub_detail()
  local q = require('leetcode-ui.question')
  q.open('two-sum')
  helpers.wait_for(function() return q.current() ~= nil end, 5000)
  local view = q.current() --[[@as any]]
  q.show_tab(view, 'description')
  eq(view.active, 'description')
  q.show_tab(view, 'console')
  eq(view.active, 'console')
  q.show_tab(view, 'info')
  eq(view.active, 'info')
  q.show_tab(view, 'code')
  eq(view.active, 'code')
  restore()
  q.close(view)
end

T['question']['tab cycle'] = function()
  local restore = stub_detail()
  local q = require('leetcode-ui.question')
  q.open('two-sum')
  helpers.wait_for(function() return q.current() ~= nil end, 5000)
  local view = q.current() --[[@as any]]
  q.cycle_tab(view, 1)
  eq(view.active, 'console')
  q.cycle_tab(view, -1)
  eq(view.active, 'code')
  restore()
  q.close(view)
end

T['question']['reset code'] = function()
  local restore = stub_detail()
  local q = require('leetcode-ui.question')
  q.open('two-sum')
  helpers.wait_for(function() return q.current() ~= nil end, 5000)
  local view = q.current() --[[@as any]]
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'junk' })
  q.reset_code(view)
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  eq(lines[1], 'class Solution:')
  restore()
  q.close(view)
end

T['question']['run all'] = function()
  local restore = stub_detail()
  local restore2 = stub_runner()
  local q = require('leetcode-ui.question')
  q.open('two-sum')
  helpers.wait_for(function() return q.current() ~= nil end, 5000)
  local view = q.current() --[[@as any]]
  q.run(view)
  helpers.wait_for(function()
    for _, c in ipairs(view.console.cases) do
      if c.result ~= nil then return true end
    end
    return false
  end, 5000)
  eq(view.console.cases[1].status, 'passed')
  restore2()
  restore()
  q.close(view)
end

T['question']['submit'] = function()
  local restore = stub_detail()
  local restore2 = stub_runner()
  local q = require('leetcode-ui.question')
  q.open('two-sum')
  helpers.wait_for(function() return q.current() ~= nil end, 5000)
  local view = q.current() --[[@as any]]
  q.submit(view)
  helpers.wait_for(function() return true end, 500)
  restore2()
  restore()
  q.close(view)
end

T['list'] = new_set()

T['list']['opens problem on main thread'] = function()
  local restore = stub_detail()
  local mp = require('mini.pick') --[[@as any]]
  local original_start = mp.start
  mp.start = function(opts)
    local o = opts --[[@as any]]
    return ((o.source or {}).items or {})[1]
  end
  local picker = require('leetcode-ui.picker')
  local ok = pcall(picker.problem, {})
  eq(ok, true)
  mp.start = original_start
  restore()
end

T['list']['problem_source works on main thread'] = function()
  local qmod = require('leetcode-ui.api.question') --[[@as any]]
  local original_get_list = qmod.get_list
  qmod.get_list = function()
    return {
      total = 1,
      questions = {
        {
          title_slug = 'two-sum',
          frontend_id = '1',
          difficulty = 'Easy',
          status = nil,
          is_paid_only = false,
          ac_rate = 50.5,
          topic_tags = {},
        },
      },
    },
      nil
  end
  local picker = require('leetcode-ui.picker')
  local lines, entries = picker.problem_source({})
  eq(#lines, 1)
  eq(#entries, 1)
  qmod.get_list = original_get_list
end

T['stats'] = new_set()

T['stats']['opens'] = function()
  local stats = helpers.mod('stats_view')
  local ok = pcall(stats.open)
  eq(ok, true)
end

return T
