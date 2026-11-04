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
  config.setup({})
  eq(config.config.url, 'leetcode.com')
  eq(config.config.lang, 'python3')
  eq(config.config.picker, 'auto')
  eq(config.config.browser, 'none')
  eq(config.config.notifications, true)
  eq(config.config.show_hints, false)
  eq(type(config.config.icons.status.solved), 'string')
  eq(type(config.config.icons.case.passed), 'string')
  eq(config.difficulty_highlights.Hard, 'LeetCodeHard')
end

T['defaults']['language metadata covers required languages'] = function()
  local config = require('leetcode-ui.config')
  for _, slug in ipairs({ 'python3', 'javascript', 'typescript', 'cpp', 'c', 'golang', 'java', 'kotlin' }) do
    local info = config.langs[slug]
    eq(type(info), 'table')
    eq(info.slug, slug)
    eq(type(info.lang) == 'string' and info.lang ~= '', true)
    eq(type(info.ft) == 'string' and info.ft ~= '', true)
  end
  eq(config.langs.python.alt, 'python3')
end

T['setup'] = new_set()

T['setup']['applies overrides and keeps defaults'] = function()
  local config = require('leetcode-ui.config')
  helpers.configure({
    lang = 'golang',
    notifications = false,
    show_hints = true,
    cookies = { LEETCODE_SESSION = 'abc' },
  })
  eq(config.config.lang, 'golang')
  eq(config.config.notifications, false)
  eq(config.config.show_hints, true)
  eq(config.config.cookies.LEETCODE_SESSION, 'abc')
  eq(config.config.picker, 'auto')
  eq(config.config.cooldown, 60)
  eq(config.config.hide_premium, false)
end

T['setup']['normalizes language aliases'] = function()
  local config = require('leetcode-ui.config')
  helpers.configure({ lang = 'python' })
  eq(config.config.lang, 'python3')
end

T['setup']['does not accumulate previous setup'] = function()
  local config = require('leetcode-ui.config')
  helpers.configure({ hide_premium = true })
  helpers.configure({})
  eq(config.config.hide_premium, false)
end

T['setup']['rejects unknown language'] = function()
  expect.error(function() helpers.configure({ lang = 'brainfuck' }) end, 'Unknown default language')
end

T['setup']['rejects unknown picker and browser'] = function()
  expect.error(function() helpers.configure({ picker = 'telescope' }) end, 'Unknown picker')
  expect.error(function() helpers.configure({ browser = 'netscape' }) end, 'Unknown browser')
end

T['setup']['rejects bad types'] = function()
  ---@diagnostic disable-next-line: param-type-mismatch
  expect.error(function() require('leetcode-ui.config').setup('not a table') end, 'should be a table or nil')
  expect.error(function() helpers.configure({ cookies = 'jar' }) end, 'expected table')
  expect.error(function() helpers.configure({ notifications = 'yes' }) end, 'expected boolean')
  expect.error(function() helpers.configure({ show_hints = 'yes' }) end, 'expected boolean')
end

T['setup']['rejects incomplete, unknown, and non-string icons'] = function()
  local icons = vim.deepcopy(require('leetcode-ui.config').config.icons)
  icons.status.solved = 1
  expect.error(function() helpers.configure({ icons = icons }) end, 'should be a string')

  icons = vim.deepcopy(require('leetcode-ui.config').config.icons)
  icons.status.solved = nil
  expect.error(function() helpers.configure({ icons = icons }) end, 'should be a string')

  icons = vim.deepcopy(require('leetcode-ui.config').config.icons)
  icons.status.unknown = '?'
  expect.error(function() helpers.configure({ icons = icons }) end, 'Unknown icon')

  icons = vim.deepcopy(require('leetcode-ui.config').config.icons)
  icons.unknown = {}
  expect.error(function() helpers.configure({ icons = icons }) end, 'Unknown icon group')
end

T['setup']['rejects invalid domains, cookies, and browser paths'] = function()
  for _, url in ipairs({
    '',
    '  ',
    'https://leetcode.com',
    'leetcode.com/path',
    '.leetcode.com',
    'leetcode.com.',
    'a..b',
  }) do
    expect.error(function() helpers.configure({ url = url }) end, 'bare host')
  end
  expect.error(function() helpers.configure({ cookies = { UNKNOWN = 'value' } }) end, 'Unknown cookie')
  expect.error(function() helpers.configure({ cookies = { LEETCODE_SESSION = 1 } }) end, 'should be a string')
  expect.error(function() helpers.configure({ browser_paths = { firefox = 1 } }) end, 'should be a string')
  expect.error(
    function() helpers.configure({ browser_paths = { netscape = '/tmp/cookies' } }) end,
    'Unknown browser in'
  )
  expect.error(function() helpers.configure({ langg = 'python3' }) end, 'Unknown option')
end

T['setup']['rejects malformed language lists'] = function()
  expect.error(function() helpers.configure({ languages = {} }) end, 'non%-empty list')
  expect.error(function() helpers.configure({ languages = { python3 = true } }) end, 'non%-empty list')
  expect.error(function() helpers.configure({ languages = { 'python3', 1 } }) end, 'only contain strings')
  helpers.configure({ languages = { 'python3' } })
end

T['setup']['rejects invalid window geometry'] = function()
  for _, value in ipairs({ 0, -1, 1.5, math.huge, 0 / 0 }) do
    expect.error(function() helpers.configure({ float_width = value }) end, 'positive integer')
    expect.error(function() helpers.configure({ float_height = value }) end, 'positive integer')
  end
end

T['setup']['validates cache cooldown'] = function()
  for _, value in ipairs({ -1, math.huge, 0 / 0 }) do
    expect.error(function() helpers.configure({ cooldown = value }) end, 'finite, non%-negative number')
  end
  helpers.configure({ cooldown = 0.5 })
  eq(require('leetcode-ui.config').config.cooldown, 0.5)
end

T['setup']['rejects unknown languages filter'] = function()
  expect.error(function() helpers.configure({ languages = { 'python3', 'klingon' } }) end, 'Unknown language')
  expect.error(function() helpers.configure({ languages = { 1 } }) end, 'only contain strings')
end

T['setup']['nested tables are replaced not merged'] = function()
  local config = require('leetcode-ui.config')
  helpers.configure({ cookies = { LEETCODE_SESSION = 'session', csrftoken = 'csrf' } })
  eq(config.config.cookies.csrftoken, 'csrf')
  helpers.configure({ cookies = { LEETCODE_SESSION = 'session' } })
  eq(config.config.cookies.LEETCODE_SESSION, 'session')
  eq(config.config.cookies.csrftoken, nil)
end

T['highlights'] = new_set()

local highlight_groups = {
  'LeetCodeOk',
  'LeetCodeErr',
  'LeetCodeWarn',
  'LeetCodeDim',
  'LeetCodeTitle',
  'LeetCodeCode',
  'LeetCodeLink',
  'LeetCodeItalic',
  'LeetCodeEasy',
  'LeetCodeMedium',
  'LeetCodeHard',
  'LeetCodeHeader',
  'LeetCodeQuestionTitle',
  'LeetCodeTab',
  'LeetCodeTabActive',
  'LeetCodeCursor',
  'LeetCodeCursorLine',
  'LeetCodeCodeNormal',
  'LeetCodeNormalFloat',
  'LeetCodeFloatBorder',
  'LeetCodeWinBar',
  'LeetCodeWinBarNC',
}

T['highlights']['setup defines all groups'] = function()
  local config = require('leetcode-ui.config')
  local expected = {}
  for _, name in ipairs(highlight_groups) do
    expected[name] = true
    assert(config.highlights[name] ~= nil, 'missing highlight definition: ' .. name)
    local hl = vim.api.nvim_get_hl(0, { name = name })
    assert(type(hl) == 'table' and next(hl) ~= nil, 'highlight not defined: ' .. name)
  end
  for name in pairs(config.highlights) do
    assert(expected[name] == true, 'unexpected highlight definition: ' .. name)
  end
end

T['highlights']['setup preserves user-defined highlights'] = function()
  MiniTest.finally(function() vim.api.nvim_set_hl(0, 'LeetCodeTitle', { link = 'Title' }) end)
  vim.api.nvim_set_hl(0, 'LeetCodeTitle', { fg = '#123456' })
  helpers.configure({})
  eq(vim.api.nvim_get_hl(0, { name = 'LeetCodeTitle' }).fg, 0x123456)
end

T['highlights']['link highlights are not underlined'] = function()
  eq(vim.fn.hlexists('LeetCodeLink'), 1)
  local link = vim.api.nvim_get_hl(0, { name = 'LeetCodeLink', link = false })
  eq(link.underline, nil)
end

T['highlights']['tabs are distinct from the title and active tab'] = function()
  local config = require('leetcode-ui.config')
  eq(config.highlights.LeetCodeQuestionTitle.link, 'LeetCodeWinBar')
  eq(config.highlights.LeetCodeTab.link, 'TabLine')
  eq(config.highlights.LeetCodeTabActive.link, 'PmenuSel')
end

T['highlights']['groups link to existing Neovim highlights'] = function()
  local config = require('leetcode-ui.config')
  for _, name in ipairs(highlight_groups) do
    local spec = config.highlights[name]
    assert(spec ~= nil, 'missing highlight definition: ' .. name)
    if name == 'LeetCodeCursor' then
      eq(spec.blend, 100)
      eq(spec.nocombine, true)
    else
      assert(type(spec.link) == 'string', 'highlight not linked: ' .. name)
      local target = spec.link
      if vim.fn.hlexists(target) == 0 then target = config.highlight_fallbacks[target] end
      assert(target ~= nil and vim.fn.hlexists(target) == 1, 'missing link target for ' .. name .. ': ' .. spec.link)
    end
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

T['langs']['lang_enabled respects filter and aliases'] = function()
  local config = require('leetcode-ui.config')
  helpers.configure({ languages = { 'python', 'cpp' } })
  eq(config.lang_enabled('python3'), true)
  eq(config.lang_enabled('python'), true)
  eq(config.lang_enabled('java'), false)
  eq(config.lang_enabled('cpp'), true)
  eq(config.lang_enabled('unknown'), false)
end

return T
