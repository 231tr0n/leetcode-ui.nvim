-- Tests for leetcode-ui.async.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set()

T['run'] = new_set()

T['run']['executes function'] = function()
  local async = helpers.mod('async')
  local ran = false
  async.run(function() ran = true end)
  eq(ran, true)
end

T['run']['catches errors'] = function()
  local async = helpers.mod('async')
  local ok = pcall(function()
    async.run(function() error('boom') end)
  end)
  eq(ok, true)
end

return T
