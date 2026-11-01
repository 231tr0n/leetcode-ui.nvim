-- Tests for leetcode-ui.storage (drafts in tempdir).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['paths'] = new_set()

T['paths']['draft path uses storage_path'] = function()
  local storage = helpers.mod('storage')
  if type(storage.draft_path) ~= 'function' then return end
  local path = storage.draft_path('two-sum', 'python3')
  eq(type(path), 'string')
  eq(path:find('two-sum', 1, true) ~= nil, true)
  eq(path:find('python3', 1, true) ~= nil, true)
end

T['read/write'] = new_set()

T['read/write']['nil content returns nil'] = function()
  local storage = helpers.mod('storage')
  eq(storage.read_draft('missing', 'python3'), nil)
end

T['read/write']['write nil removes draft'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('x', 'py', 'hello')
  eq(storage.read_draft('x', 'py'), 'hello')
  storage.write_draft('x', 'py', nil)
  eq(storage.read_draft('x', 'py'), nil)
end

T['read/write']['empty string treated as removal'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('x', 'py', '')
  eq(storage.read_draft('x', 'py'), nil)
end

T['read/write']['persists across instances'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('a-b', 'golang', 'package main')
  eq(storage.read_draft('a-b', 'golang'), 'package main')
end

return T
