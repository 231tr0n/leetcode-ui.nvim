-- Tests for leetcode-ui.log.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ notifications = true }) end,
  },
})

T['levels'] = new_set()

T['levels']['info prepends the plugin prefix'] = function()
  local log = helpers.mod('log')
  local messages = helpers.capture_notify(function() log.info('hello') end)
  eq(#messages, 1)
  eq(messages[1].message, '(leetcode-ui) hello')
  eq(messages[1].level, vim.log.levels.INFO)
end

T['levels']['warn and error use their levels'] = function()
  local log = helpers.mod('log')
  local messages = helpers.capture_notify(function()
    log.warn('warn')
    log.error('error')
  end)
  eq(messages[1].level, vim.log.levels.WARN)
  eq(messages[2].level, vim.log.levels.ERROR)
end

T['disabled'] = new_set()

T['disabled']['notifications = false suppresses messages'] = function()
  helpers.configure({ notifications = false })
  local log = helpers.mod('log')
  local messages = helpers.capture_notify(function()
    log.info('hidden info')
    log.warn('hidden warning')
    log.error('hidden error')
  end)
  eq(#messages, 0)
end

return T
