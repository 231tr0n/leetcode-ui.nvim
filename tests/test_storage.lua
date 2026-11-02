-- Tests for leetcode-ui.storage.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['cache'] = new_set()

T['cache']['empty cache has defaults'] = function()
  local storage = helpers.mod('storage')
  local cache = storage.read_cache()
  eq(type(cache.problems), 'table')
  eq(#cache.problems, 0)
  eq(cache.cache_time, 0)
end

T['cache']['writes and reads back data'] = function()
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'two-sum' } }, total = 1, cache_time = 123 })
  local cache = storage.read_cache()
  eq(cache.total, 1)
  eq(cache.cache_time, 123)
  eq(cache.problems[1].title_slug, 'two-sum')
end

T['cache']['malformed JSON falls back to an empty cache'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({ '{not json' }, storage.cache_file())
  local cache = storage.read_cache()
  eq(#cache.problems, 0)
  eq(cache.cache_time, 0)
end

T['cache']['malformed problem lists fall back to an empty list'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({ '{"problems":"not a list","cache_time":1}' }, storage.cache_file())
  local cache = storage.read_cache()
  eq(type(cache.problems), 'table')
  eq(#cache.problems, 0)
end

T['cache']['missing file falls back to an empty cache'] = function()
  local storage = helpers.mod('storage')
  eq(#storage.read_cache().problems, 0)
end

T['drafts'] = new_set()

T['drafts']['missing drafts return nil'] = function()
  local storage = helpers.mod('storage')
  eq(storage.read_draft('missing', 'python3'), nil)
end

T['drafts']['writes and removes drafts'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('x', 'py', 'hello\nworld')
  eq(storage.read_draft('x', 'py'), 'hello\nworld')
  storage.write_draft('x', 'py', nil)
  eq(storage.read_draft('x', 'py'), nil)
end

T['drafts']['empty string removes the draft'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('x', 'py', 'hello')
  storage.write_draft('x', 'py', '')
  eq(storage.read_draft('x', 'py'), nil)
end

T['drafts']['draft file contains slug and language'] = function()
  local storage = helpers.mod('storage')
  local path = storage.draft_file('a-b', 'golang')
  eq(helpers.contains(path, 'a-b'), true)
  eq(helpers.contains(path, 'golang'), true)
end

T['paths'] = new_set()

T['paths']['root follows storage_path changes'] = function()
  local config = require('leetcode-ui.config')
  local first = helpers.tmpdir()
  config.setup({ storage_path = first, browser = 'none' })
  local storage = helpers.mod('storage')
  eq(storage.init(), vim.fs.normalize(first))

  local second = helpers.tmpdir()
  config.setup({ storage_path = second, browser = 'none' })
  eq(storage.init(), vim.fs.normalize(second))
end

return T
