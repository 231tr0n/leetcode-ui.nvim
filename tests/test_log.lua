-- Tests for leetcode-ui.log.
---@diagnostic disable: duplicate-set-field
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ notifications = true }) end,
  },
})

local capture = function(fn)
  local original = vim.notify
  local messages = {}
  vim.notify = function(message, level) table.insert(messages, { message = message, level = level }) end
  local ok, err = pcall(fn)
  vim.notify = original
  if not ok then error(err, 0) end
  return messages
end

T['levels'] = new_set()

T['levels']['info prepends the plugin prefix'] = function()
  local log = helpers.mod('log')
  local messages = capture(function() log.info('hello') end)
  eq(#messages, 1)
  eq(messages[1].message, '(leetcode-ui) hello')
  eq(messages[1].level, vim.log.levels.INFO)
end

T['levels']['warn and error use their levels'] = function()
  local log = helpers.mod('log')
  local messages = capture(function()
    log.warn('warn')
    log.error('error')
  end)
  eq(messages[1].level, vim.log.levels.WARN)
  eq(messages[2].level, vim.log.levels.ERROR)
end

T['disabled'] = new_set()

T['disabled']['notifications = false suppresses messages'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ notifications = false })
  local log = helpers.mod('log')
  local messages = capture(function() log.info('hidden') end)
  eq(#messages, 0)
end

return T
