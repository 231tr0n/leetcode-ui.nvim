-- Tests for leetcode-ui.config.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local expect = helpers.expect
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['defaults'] = new_set()

T['defaults']['exposes defaults'] = function()
  local config = require('leetcode-ui.config')
  config.reset()
  eq(config.config.url, 'leetcode.com')
  eq(config.config.lang, 'python3')
  eq(config.config.local_runner, true)
  eq(config.config.picker, 'auto')
  eq(config.config.browser, 'auto')
  eq(config.config.notifications, true)
  eq(config.config.show_hints, false)
  eq(config.config.keys, nil)
  eq(type(config.config.icons.status.solved), 'string')
  eq(type(config.config.icons.case.ran), 'string')
end

T['defaults']['setup marks module initialized'] = function()
  local config = require('leetcode-ui.config')
  eq(config.is_setup, true)
  eq(type(config.setup), 'function')
end

T['defaults']['language metadata covers required languages'] = function()
  local config = require('leetcode-ui.config')
  for _, slug in ipairs({ 'python3', 'javascript', 'typescript', 'cpp', 'c', 'golang', 'java', 'kotlin' }) do
    eq(type(config.langs[slug]), 'table')
  end
end

T['setup'] = new_set()

T['setup']['applies overrides and keeps defaults'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ lang = 'golang', notifications = false, show_hints = true, cookies = { LEETCODE_SESSION = 'abc' } })
  eq(config.config.lang, 'golang')
  eq(config.config.notifications, false)
  eq(config.config.show_hints, true)
  eq(config.config.cookies.LEETCODE_SESSION, 'abc')
  eq(config.config.runner_timeout, 30)
end

T['setup']['normalizes language aliases'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ lang = 'python' })
  eq(config.config.lang, 'python3')
end

T['setup']['does not accumulate previous setup'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ hide_premium = true })
  config.setup({})
  eq(config.config.hide_premium, false)
end

T['setup']['rejects unknown language'] = function()
  local config = require('leetcode-ui.config')
  expect.error(function() config.setup({ lang = 'brainfuck' }) end)
end

T['setup']['rejects unknown picker and browser'] = function()
  local config = require('leetcode-ui.config')
  expect.error(function() config.setup({ picker = 'telescope' }) end)
  expect.error(function() config.setup({ browser = 'netscape' }) end)
end

T['setup']['rejects bad types'] = function()
  local config = require('leetcode-ui.config')
  expect.error(function() config.setup({ runner_timeout = 'thirty' }) end)
  expect.error(function() config.setup({ cookies = 'jar' }) end)
  expect.error(function() config.setup({ notifications = 'yes' }) end)
  expect.error(function() config.setup({ show_hints = 'yes' }) end)
end

T['setup']['rejects unknown and non-string icons'] = function()
  local config = require('leetcode-ui.config')
  expect.error(function() config.setup({ icons = { status = { solved = 1 } } }) end)
  expect.error(function() config.setup({ icons = { status = {} } }) end)
end

T['setup']['rejects unknown languages filter'] = function()
  local config = require('leetcode-ui.config')
  expect.error(function() config.setup({ languages = { 'python3', 'klingon' } }) end)
end

T['setup']['nested tables are replaced not merged'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ cookies = { LEETCODE_SESSION = 'session' } })
  eq(config.config.cookies.LEETCODE_SESSION, 'session')
  eq(config.config.cookies.csrftoken, nil)
end

T['highlights'] = new_set()

T['highlights']['setup defines all groups'] = function()
  local config = require('leetcode-ui.config')
  for name in pairs(config.highlights) do
    local hl = vim.api.nvim_get_hl(0, { name = name })
    assert(type(hl) == 'table', 'highlight not defined: ' .. name)
  end
end

T['highlights']['link highlights are not underlined'] = function()
  local link = vim.api.nvim_get_hl(0, { name = 'LeetCodeLink' })
  eq(link.underline, nil)
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

T['langs']['lang_enabled respects filter and aliases'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ languages = { 'python', 'cpp' } })
  eq(config.lang_enabled('python3'), true)
  eq(config.lang_enabled('python'), true)
  eq(config.lang_enabled('java'), false)
  eq(config.lang_enabled('cpp'), true)
  eq(config.lang_enabled('unknown'), false)
end

return T
