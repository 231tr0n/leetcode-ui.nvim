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
  eq(vim.fn.glob(storage.cache_file() .. '.tmp*', false, true), {})
end

T['cache']['removes the temp file and preserves the old cache when promotion fails'] = function()
  local storage = helpers.mod('storage')
  storage.write_cache({ problems = { { title_slug = 'old' } }, total = 1, cache_time = 1 })
  local temp = nil
  helpers.with_field(vim.uv, 'fs_rename', function(from)
    temp = from
    return nil, 'denied'
  end, function() eq(storage.write_cache({ problems = { { title_slug = 'new' } }, total = 1 }), false) end)
  eq(type(temp), 'string')
  eq(vim.fn.filereadable(temp), 0)
  eq(storage.read_cache().problems[1].title_slug, 'old')
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

T['cache']['rejects non-list problem tables'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({ '{"problems":{"title_slug":"two-sum"},"cache_time":1}' }, storage.cache_file())
  eq(storage.read_cache().problems, {})
end

T['cache']['drops malformed problem entries'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({ '{"problems":[1,{"title_slug":"ok"},false],"cache_time":1}' }, storage.cache_file())
  eq(storage.read_cache().problems, { { title_slug = 'ok' } })
end

T['cache']['empty files fall back to an empty cache'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({}, storage.cache_file())
  local cache = storage.read_cache()
  eq(#cache.problems, 0)
  eq(cache.cache_time, 0)
end

T['cache']['reports write failures'] = function()
  local storage = helpers.mod('storage')
  helpers.with_stub(
    'leetcode-ui.storage',
    'cache_file',
    function() return '/definitely/missing/dir/cache.json' end,
    function() eq(storage.write_cache({ problems = {} }), false) end
  )
end

T['testcases'] = new_set()

T['testcases']['writes and reads testcase inputs'] = function()
  local storage = helpers.mod('storage')
  storage.write_testcases('two-sum', { '[1,2]\n3', '[0]\n0' })
  local inputs = storage.read_testcases('two-sum')
  eq(inputs[1], '[1,2]\n3')
  eq(inputs[2], '[0]\n0')
end

T['testcases']['missing testcases return nil'] = function()
  local storage = helpers.mod('storage')
  eq(storage.read_testcases('missing'), nil)
end

T['testcases']['empty or nil inputs remove the file'] = function()
  local storage = helpers.mod('storage')
  storage.write_testcases('two-sum', { 'a' })
  storage.write_testcases('two-sum', {})
  eq(storage.read_testcases('two-sum'), nil)

  storage.write_testcases('two-sum', { 'a' })
  storage.write_testcases('two-sum', nil)
  eq(storage.read_testcases('two-sum'), nil)

  storage.write_testcases('two-sum', { 'a' })
  storage.write_testcases('two-sum', 'invalid')
  eq(storage.read_testcases('two-sum'), nil)
end

T['testcases']['malformed files return nil'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({ 'not json' }, storage.testcase_file('two-sum'))
  eq(storage.read_testcases('two-sum'), nil)
end

T['testcases']['ignores non-string entries'] = function()
  local storage = helpers.mod('storage')
  vim.fn.writefile({ '["a",1,null,"b"]' }, storage.testcase_file('two-sum'))
  eq(storage.read_testcases('two-sum'), { 'a', 'b' })
end

T['testcases']['migrates legacy flat testcases on read'] = function()
  local storage = helpers.mod('storage')
  local legacy = vim.fs.joinpath(storage.init(), 'testcases', 'two-sum.json')
  vim.fn.writefile({ '["legacy","input"]' }, legacy)

  eq(storage.read_testcases('two-sum'), { 'legacy', 'input' })
  eq(vim.fn.filereadable(storage.testcase_file('two-sum')), 1)
  eq(vim.fn.filereadable(legacy), 0)
  eq(storage.read_testcases('two-sum'), { 'legacy', 'input' })
end

T['testcases']['reports write failures'] = function()
  local storage = helpers.mod('storage')
  helpers.with_stub(
    'leetcode-ui.storage',
    'testcase_file',
    function() return '/definitely/missing/dir/test.json' end,
    function() eq(storage.write_testcases('two-sum', { 'x' }), false) end
  )
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

T['drafts']['empty string is a valid draft'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('x', 'py', 'hello')
  eq(storage.write_draft('x', 'py', ''), true)
  eq(storage.read_draft('x', 'py'), '')
end

T['drafts']['preserves trailing newlines and Unicode'] = function()
  local storage = helpers.mod('storage')
  local code = 'local symbol = "≤"\n\n'
  eq(storage.write_draft('x', 'lua', code), true)
  eq(storage.read_draft('x', 'lua'), code)
end

T['drafts']['reports write failures'] = function()
  local storage = helpers.mod('storage')
  helpers.with_stub(
    'leetcode-ui.storage',
    'draft_file',
    function() return '/definitely/missing/dir/draft' end,
    function() eq(storage.write_draft('x', 'py', 'hello'), false) end
  )
end

T['drafts']['scopes drafts by domain'] = function()
  local storage = helpers.mod('storage')
  local config = helpers.mod('config')
  local root = config.config.storage_path
  storage.write_draft('x', 'py', 'com')
  local com_path = storage.draft_file('x', 'py')

  helpers.configure({ url = 'leetcode.cn', storage_path = root })
  storage.write_draft('x', 'py', 'cn')
  local cn_path = storage.draft_file('x', 'py')
  eq(com_path ~= cn_path, true)
  eq(storage.read_draft('x', 'py'), 'cn')

  helpers.configure({ url = 'leetcode.com', storage_path = root })
  eq(storage.read_draft('x', 'py'), 'com')
end

T['drafts']['preserves existing files when an atomic write fails'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('x', 'py', 'old draft')
  storage.write_testcases('x', { 'old input' })

  local renames = 0
  helpers.with_field(vim.uv, 'fs_rename', function()
    renames = renames + 1
    return false
  end, function()
    eq(storage.write_draft('x', 'py', 'new draft'), false)
    eq(storage.write_testcases('x', { 'new input' }), false)
  end)
  eq(renames, 2)

  eq(storage.read_draft('x', 'py'), 'old draft')
  eq(storage.read_testcases('x'), { 'old input' })
  local draft_temps = vim.fn.glob(vim.fs.dirname(storage.draft_file('x', 'py')) .. '/*.tmp.*', false, true)
  local testcase_temps = vim.fn.glob(vim.fs.dirname(storage.testcase_file('x')) .. '/*.tmp.*', false, true)
  eq(draft_temps, {})
  eq(testcase_temps, {})
end

T['drafts']['writes remove legacy files after successful saves'] = function()
  local storage = helpers.mod('storage')
  local root = storage.init()
  local legacy_draft = vim.fs.joinpath(root, 'drafts', 'two-sum.python3')
  local legacy_testcases = vim.fs.joinpath(root, 'testcases', 'two-sum.json')
  vim.fn.writefile({ 'old' }, legacy_draft)
  vim.fn.writefile({ '["old"]' }, legacy_testcases)

  storage.write_draft('two-sum', 'python3', 'new')
  storage.write_testcases('two-sum', { 'new' })
  eq(vim.fn.filereadable(legacy_draft), 0)
  eq(vim.fn.filereadable(legacy_testcases), 0)
  eq(storage.read_draft('two-sum', 'python3'), 'new')
  eq(storage.read_testcases('two-sum'), { 'new' })
end

T['drafts']['does not migrate legacy files under another domain'] = function()
  local storage = helpers.mod('storage')
  local root = storage.init()
  local legacy_draft = vim.fs.joinpath(root, 'drafts', 'two-sum.python3')
  local legacy_testcases = vim.fs.joinpath(root, 'testcases', 'two-sum.json')
  vim.fn.writefile({ 'legacy' }, legacy_draft)
  vim.fn.writefile({ '["legacy"]' }, legacy_testcases)

  helpers.configure({ url = 'leetcode.cn', storage_path = root })
  eq(storage.read_draft('two-sum', 'python3'), nil)
  eq(storage.read_testcases('two-sum'), nil)
  eq(vim.fn.filereadable(legacy_draft), 1)
  eq(vim.fn.filereadable(legacy_testcases), 1)

  storage.write_draft('two-sum', 'python3', 'cn draft')
  storage.write_testcases('two-sum', { 'cn input' })
  eq(vim.fn.filereadable(legacy_draft), 1)
  eq(vim.fn.filereadable(legacy_testcases), 1)
  eq(storage.read_draft('two-sum', 'python3'), 'cn draft')
  eq(storage.read_testcases('two-sum'), { 'cn input' })
end

T['drafts']['migrates legacy flat drafts on read'] = function()
  local storage = helpers.mod('storage')
  local legacy = vim.fs.joinpath(storage.init(), 'drafts', 'two-sum.python3')
  vim.fn.writefile({ 'legacy', 'draft' }, legacy)

  eq(storage.read_draft('two-sum', 'python3'), 'legacy\ndraft')
  local scoped = storage.draft_file('two-sum', 'python3')
  eq(vim.fn.filereadable(scoped), 1)
  eq(vim.fn.filereadable(legacy), 0)
  eq(storage.read_draft('two-sum', 'python3'), 'legacy\ndraft')
end

T['drafts']['removing a draft also removes a legacy file'] = function()
  local storage = helpers.mod('storage')
  local legacy = vim.fs.joinpath(storage.init(), 'drafts', 'two-sum.python3')
  vim.fn.writefile({ 'legacy' }, legacy)
  storage.write_draft('two-sum', 'python3', nil)
  eq(vim.fn.filereadable(legacy), 0)
  eq(storage.read_draft('two-sum', 'python3'), nil)
end

T['drafts']['reports failures deleting an unreadable draft'] = function()
  local storage = helpers.mod('storage')
  local scoped = storage.draft_file('x', 'py')
  vim.fn.writefile({ 'old' }, scoped)
  helpers.with_field(vim.fn, 'getftype', function(path) return path == scoped and 'file' or '' end, function()
    helpers.with_field(
      vim.fn,
      'delete',
      function(path) return path == scoped and 1 or 0 end,
      function() eq(storage.write_draft('x', 'py', nil), false) end
    )
  end)
  eq(vim.fn.filereadable(scoped), 1)
end

T['paths'] = new_set()

T['paths']['builds exact domain-scoped file paths'] = function()
  local storage = helpers.mod('storage')
  local domain = helpers.mod('config').config.url
  local root = storage.init()
  eq(storage.testcase_file('two-sum'), vim.fs.joinpath(root, 'testcases', domain, 'two-sum.json'))
  eq(storage.draft_file('a-b', 'golang'), vim.fs.joinpath(root, 'drafts', domain, 'a-b.golang'))
end

T['paths']['encodes unsafe filename components'] = function()
  local storage = helpers.mod('storage')
  local domain = helpers.mod('config').config.url
  local drafts = vim.fs.joinpath(storage.init(), 'drafts', domain)
  local draft = storage.draft_file('../../escape', '../lang')
  eq(vim.fs.dirname(draft), drafts)
  eq(vim.fs.basename(draft), '%2E%2E%2F%2E%2E%2Fescape.%2E%2E%2Flang')

  local testcases = vim.fs.joinpath(storage.init(), 'testcases', domain)
  local testcase = storage.testcase_file('../../escape')
  eq(vim.fs.dirname(testcase), testcases)
  eq(vim.fs.basename(testcase), '%2E%2E%2F%2E%2E%2Fescape.json')
end

T['paths']['repairs missing layout directories'] = function()
  local storage = helpers.mod('storage')
  local root = storage.init()
  local drafts = vim.fs.joinpath(root, 'drafts')
  local testcases = vim.fs.joinpath(root, 'testcases')
  vim.fn.delete(drafts, 'rf')
  vim.fn.delete(testcases, 'rf')
  eq(vim.fn.isdirectory(drafts), 0)
  eq(vim.fn.isdirectory(testcases), 0)
  eq(storage.init(), root)
  eq(vim.fn.isdirectory(drafts), 1)
  eq(vim.fn.isdirectory(testcases), 1)
end

T['paths']['root follows storage_path changes'] = function()
  local first = helpers.tmpdir()
  helpers.configure({ storage_path = first, browser = 'none' })
  local storage = helpers.mod('storage')
  eq(storage.init(), vim.fs.normalize(first))

  local second = helpers.tmpdir()
  helpers.configure({ storage_path = second, browser = 'none' })
  eq(storage.init(), vim.fs.normalize(second))
end

return T
