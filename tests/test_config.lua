-- Tests for leetcode-ui.config (defaults, setup, validation, highlights).

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['defaults'] = new_set()

T['defaults']['exposes full default table'] = function()
  local config = helpers.mod('config')
  eq(config.config.url, 'leetcode.com')
  eq(config.config.lang, 'python3')
  eq(config.config.local_runner, true)
  eq(config.config.picker, 'auto')
  eq(config.config.browser, 'none')
  eq(type(config.config.keys), 'table')
  eq(config.config.keys.run, '<CR>')
  eq(type(config.config.icons.status.solved), 'string')
end

T['defaults']['setup marks module initialized'] = function()
  local config = helpers.mod('config')
  eq(config.is_setup, true)
  eq(type(config.setup), 'function')
end

T['defaults']['language metadata covers required languages'] = function()
  local config = helpers.mod('config')
  for _, slug in ipairs({ 'python3', 'javascript', 'typescript', 'cpp', 'c', 'golang', 'java', 'kotlin' }) do
    eq(type(config.langs[slug]), 'table')
  end
end

T['setup'] = new_set()

T['setup']['shallow applies overrides'] = function()
  local config = helpers.mod('config')
  config.setup({ lang = 'golang', console_height = 20, cookies = { LEETCODE_SESSION = 'abc' } })
  eq(config.config.lang, 'golang')
  eq(config.config.console_height, 20)
  eq(config.config.cookies.LEETCODE_SESSION, 'abc')
  -- Untouched defaults survive.
  eq(config.config.runner_timeout, 30)
end

T['setup']['normalizes language aliases'] = function()
  local config = helpers.mod('config')
  for alias, expected in pairs({ python = 'python3', go = 'golang', js = 'javascript', ts = 'typescript' }) do
    if config.langs[alias] ~= nil then
      config.setup({ lang = alias })
      eq(config.config.lang, expected)
    end
  end
end

T['setup']['rejects unknown language'] = function()
  local config = helpers.mod('config')
  helpers.expect.error(function() config.setup({ lang = 'brainfuck' }) end)
end

T['setup']['rejects unknown picker and browser'] = function()
  local config = helpers.mod('config')
  helpers.expect.error(function() config.setup({ picker = 'telescope' }) end)
  helpers.expect.error(function() config.setup({ browser = 'netscape' }) end)
end

T['setup']['rejects unknown keys and non-string keys'] = function()
  local config = helpers.mod('config')
  helpers.expect.error(function() config.setup({ keys = { bogus = 'x' } }) end)
  helpers.expect.error(function() config.setup({ keys = { run = 5 } }) end)
end

T['setup']['rejects bad types'] = function()
  local config = helpers.mod('config')
  helpers.expect.error(function() config.setup({ runner_timeout = 'thirty' }) end)
  helpers.expect.error(function() config.setup({ cookies = 'jar' }) end)
  helpers.expect.error(function() config.setup({ console_height = 'big' }) end)
end

T['setup']['nested tables are replaced not merged'] = function()
  local config = helpers.mod('config')
  config.setup({ keys = { run = 'r' } })
  eq(config.config.keys.run, 'r')
  eq(config.config.keys.submit, nil)
end

T['highlights'] = new_set()

T['highlights']['setup defines all groups'] = function()
  local config = helpers.mod('config')
  for name in pairs(config.highlights) do
    local hl = vim.api.nvim_get_hl(0, { name = name })
    eq(type(hl), 'table', 'highlight not defined: ' .. name)
  end
end

T['highlights']['difficulty groups exist'] = function()
  for _, name in ipairs({ 'LeetCodeEasy', 'LeetCodeMedium', 'LeetCodeHard', 'LeetCodeOk', 'LeetCodeErr' }) do
    eq(vim.fn.hlexists(name), 1)
  end
end

T['langs'] = new_set()

T['langs']['get_lang returns metadata'] = function()
  local config = require('leetcode-ui.config')
  local info = config.get_lang('python3')
  assert(info ~= nil)
  eq(type(info), 'table')
  eq(info.slug, 'python3')
  eq(config.get_lang('nope-slug'), nil)
end

T['langs']['lang_enabled respects languages filter'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ languages = { 'python3', 'cpp' }, browser = 'none', storage_path = helpers.tmpdir(), cookies = {} })
  eq(config.lang_enabled('python3'), true)
  eq(config.lang_enabled('java'), false)
  eq(config.lang_enabled('cpp'), true)
end

T['setup']['unknown picker errors'] = function()
  local config = require('leetcode-ui.config')
  local ok = pcall(config.setup, { picker = 'bogus', browser = 'none', storage_path = helpers.tmpdir(), cookies = {} })
  eq(ok, false)
end

T['setup']['unknown browser errors'] = function()
  local config = require('leetcode-ui.config')
  local ok = pcall(config.setup, { browser = 'bogus-browser', storage_path = helpers.tmpdir(), cookies = {} })
  eq(ok, false)
end

T['setup']['unknown default language errors'] = function()
  local config = require('leetcode-ui.config')
  local ok = pcall(config.setup, { lang = 'klingon', browser = 'none', storage_path = helpers.tmpdir(), cookies = {} })
  eq(ok, false)
end

return T
