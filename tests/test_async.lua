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
  local original = vim.notify
  local messages = {}
  vim.notify = function(message, level) table.insert(messages, { message = message, level = level }) end
  local ok = pcall(async.run, function() error('boom') end)
  vim.notify = original

  eq(ok, true)
  eq(#messages, 1)
  eq(helpers.contains(messages[1].message, 'boom'), true)
  eq(messages[1].level, vim.log.levels.ERROR)
end

T['run']['returns immediately when the function yields'] = function()
  local async = helpers.mod('async')
  local resumed = false
  async.run(function()
    coroutine.yield()
    resumed = true
  end)
  eq(resumed, false)
end

return T
