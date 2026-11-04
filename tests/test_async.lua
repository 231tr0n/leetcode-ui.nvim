-- Tests for leetcode-ui.async.
---@diagnostic disable: duplicate-set-field
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ notifications = true }) end,
  },
})

T['run'] = new_set()

T['run']['executes the function synchronously'] = function()
  local async = helpers.mod('async')
  local ran = false
  async.run(function() ran = true end)
  eq(ran, true)
end

T['run']['reports errors as notifications'] = function()
  local async = helpers.mod('async')
  local messages = helpers.capture_notify(function()
    async.run(function() error('boom') end)
  end)
  eq(#messages, 1)
  eq(helpers.contains(messages[1].message, 'boom'), true)
  eq(messages[1].level, vim.log.levels.ERROR)
end

T['run']['returns immediately when the function yields'] = function()
  local async = helpers.mod('async')
  local started, resumed = false, false
  async.run(function()
    started = true
    coroutine.yield()
    resumed = true
  end)
  eq(started, true)
  eq(resumed, false)
end

T['run']['runs error cleanup after yielding'] = function()
  local async = helpers.mod('async')
  local cleaned = false
  helpers.with_field(vim, 'notify', function() end, function()
    async.run(function()
      async.sleep(1)
      error('delayed failure')
    end, function() cleaned = true end)
    eq(helpers.wait_for(function() return cleaned end), true)
  end)
end

T['system'] = new_set()

T['system']['returns a result for asynchronous commands'] = function()
  local async = helpers.mod('async')
  local result
  helpers.with_field(vim, 'system', function(_command, _opts, on_exit)
    vim.defer_fn(function() on_exit({ code = 0, stdout = 'done', stderr = '' }) end, 1)
    return {}
  end, function()
    async.run(function() result = async.system({ 'command' }, { text = true }) end)
    eq(helpers.wait_for(function() return result ~= nil end), true)
  end)
  eq(result.stdout, 'done')
end

T['system']['returns spawn failures without throwing'] = function()
  local async = helpers.mod('async')
  local main_result = async.system({ '/definitely/missing/executable' }, { text = true })
  eq(main_result.code, -1)
  eq(type(main_result.stderr), 'string')

  local async_result = nil
  async.run(function() async_result = async.system({ '/definitely/missing/executable' }, { text = true }) end)
  eq(helpers.wait_for(function() return async_result ~= nil end), true)
  assert(async_result ~= nil)
  eq(async_result.code, -1)
  eq(type(async_result.stderr), 'string')
end

T['resume'] = new_set()

T['resume']['reports errors raised after yielding'] = function()
  local async = helpers.mod('async')
  local thread
  async.run(function()
    thread = coroutine.running()
    coroutine.yield()
    error('resumed boom')
  end)

  local ok, err, messages
  messages = helpers.capture_notify(function()
    ok, err = async.resume(thread)
  end)

  eq(ok, false)
  eq(helpers.contains(err, 'resumed boom'), true)
  eq(#messages, 1)
  eq(messages[1].level, vim.log.levels.ERROR)
end

return T
