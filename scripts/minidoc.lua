-- Generate help docs with mini.doc (mini.nvim style).
--
--   nvim --headless -u scripts/minidoc.lua

local script = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')
vim.opt.runtimepath:prepend(root)

local mini = vim.fn.expand('~/.local/share/nvim/site/pack/core/opt/mini.nvim')
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
  'leetcode-ui.async',
  'leetcode-ui.api',
  'leetcode-ui.api.queries',
  'leetcode-ui.api.question',
  'leetcode-ui.api.runner',
  'leetcode-ui.api.stats',
}

local inputs = {}
for _, module in ipairs(modules) do
  local path = vim.fs.joinpath(root, 'lua', module:gsub('%.', '/') .. '.lua')
  if vim.fn.filereadable(path) == 1 then table.insert(inputs, path) end
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
vim.cmd('qa!')
