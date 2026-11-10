-- Generate help docs with mini.doc (mini.nvim style).
--
--   nvim --headless -u scripts/minidoc.lua

local script = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')
vim.opt.runtimepath:prepend(root)

local mini = vim.env.LEETCODE_UI_MINI_DIR or vim.fn.expand('~/.local/share/nvim/site/pack/core/opt/mini.nvim')
if vim.uv.fs_stat(mini .. '/lua/mini/doc.lua') then vim.opt.runtimepath:append(mini) end

local MiniDoc = require('mini.doc')
if _G.MiniDoc == nil then MiniDoc.setup() end

local modules = {
  'leetcode-ui',
  'leetcode-ui.commands',
  'leetcode-ui.config',
  'leetcode-ui.log',
  'leetcode-ui.ui',
  'leetcode-ui.buffer',
  'leetcode-ui.question',
  'leetcode-ui.console',
  'leetcode-ui.solution',
  'leetcode-ui.picker',
  'leetcode-ui.stats_view',
  'leetcode-ui.auth',
  'leetcode-ui.browser',
  'leetcode-ui.net',
  'leetcode-ui.storage',
  'leetcode-ui.parser',
  'leetcode-ui.format',
  'leetcode-ui.async',
  'leetcode-ui.api',
  'leetcode-ui.api.queries',
  'leetcode-ui.api.question',
  'leetcode-ui.api.runner',
  'leetcode-ui.api.stats',
}

local inputs = {}
local documented_modules = {}
for _, module in ipairs(modules) do
  local relative = module == 'leetcode-ui.api' and 'leetcode-ui/api/init.lua' or module:gsub('%.', '/') .. '.lua'
  local path = vim.fs.joinpath(root, 'lua', relative)
  if vim.fn.filereadable(path) == 0 then error('Missing documentation input: ' .. path) end
  documented_modules[module] = true
  table.insert(inputs, path)
end

local lua_root = vim.fs.joinpath(root, 'lua') .. '/'
for _, path in ipairs(vim.fn.globpath(lua_root, '**/*.lua', true, true)) do
  local relative = path:sub(#lua_root + 1):gsub('%.lua$', ''):gsub('/init$', ''):gsub('/', '.')
  if relative:match('^leetcode%-ui') and not documented_modules[relative] then
    error('Missing documentation module: ' .. relative)
  end
end

-- mini.nvim help files use a single dashed separator per section. The
-- default `file` hook adds an extra `====` line before every module, which
-- produces a redundant `====`/`----` pair in a multi-module help file.
local config = { hooks = { file = function() end } }
local output = vim.env.LEETCODE_UI_DOC_OUTPUT
if output == nil or output == '' then
  output = vim.fs.joinpath(root, 'doc', 'leetcode-ui.txt')
else
  output = vim.fs.normalize(output)
end

MiniDoc.generate(inputs, output, config)

local contents = table.concat(vim.fn.readfile(output), '\n')
local required_tags = {
  '*leetcode-ui*',
  '*LeetCode*',
  '*LeetCode.setup()*',
  '*LeetCodeCommands*',
  '*LeetCodeConfig*',
  '*LeetCodeLog*',
  '*LeetCodeUI*',
  '*LeetCodeBuffer*',
  '*LeetCodeQuestionView*',
  '*LeetCodeConsole*',
  '*LeetCodeSolution*',
  '*LeetCodePicker*',
  '*LeetCodeStatsView*',
  '*LeetCodeAuth*',
  '*LeetCodeBrowser*',
  '*LeetCodeNet*',
  '*LeetCodeStorage*',
  '*LeetCodeParser*',
  '*LeetCodeFormat*',
  '*LeetCodeAsync*',
  '*LeetCodeApi*',
  '*LeetCodeQueries*',
  '*LeetCodeQuestion*',
  '*LeetCodeRunnerApi*',
  '*LeetCodeStatsApi*',
  '*LeetCodeApi.graphql()*',
  '*LeetCodeApi.rest()*',
  '*LeetCodeConsole.start_spinner()*',
  '*leetcode-ui-commands*',
  '*leetcode-ui-config*',
  '*leetcode-ui-log*',
  '*leetcode-ui-ui*',
  '*leetcode-ui-buffer*',
  '*leetcode-ui-question*',
  '*leetcode-ui-console*',
  '*leetcode-ui-solution*',
  '*leetcode-ui-picker*',
  '*leetcode-ui-stats-view*',
  '*leetcode-ui-auth*',
  '*leetcode-ui-browser*',
  '*leetcode-ui-net*',
  '*leetcode-ui-storage*',
  '*leetcode-ui-parser*',
  '*leetcode-ui-format*',
  '*leetcode-ui-async*',
  '*leetcode-ui-api*',
  '*leetcode-ui-api-queries*',
  '*leetcode-ui-api-question*',
  '*leetcode-ui-api-runner*',
  '*leetcode-ui-api-stats*',
}
for _, tag in ipairs(required_tags) do
  if contents:find(tag, 1, true) == nil then error('Generated help is missing ' .. tag) end
end

for reference in contents:gmatch('|([^|\n]+)|') do
  local is_local = reference:match('^LeetCode') or reference:match('^leetcode%-ui')
  if is_local and contents:find('*' .. reference .. '*', 1, true) == nil then
    error('Generated help has an unresolved reference: ' .. reference)
  end
end

vim.cmd('qa!')
