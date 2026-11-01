-- Tests for leetcode-ui.stats_view (offline).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup({ browser = 'none', cookies = {} }) end,
  },
})

T['stats_view'] = new_set()

T['stats_view']['module loads'] = function()
  local stats_view = helpers.mod('stats_view')
  eq(type(stats_view), 'table')
end

T['plugin'] = new_set()

T['plugin']['command entrypoint loads'] = function()
  local ok, plugin = pcall(require, 'leetcode-ui')
  eq(ok, true)
  eq(type(plugin.setup), 'function')
  eq(type(plugin), 'table')
end

return T
