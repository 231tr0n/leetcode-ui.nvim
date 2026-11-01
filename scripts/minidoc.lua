local script = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')
vim.opt.runtimepath:prepend(root)

local mini = vim.fn.expand('~/.local/share/nvim/site/pack/core/opt/mini.nvim')
if vim.uv.fs_stat(mini .. '/lua/mini/doc.lua') then vim.opt.runtimepath:append(mini) end

local MiniDoc = require('mini.doc')
if _G.MiniDoc == nil then MiniDoc.setup() end

local modules = {
  'leetcode-ui',
  'leetcode-ui.config',
  'leetcode-ui.auth',
  'leetcode-ui.browser',
  'leetcode-ui.api',
  'leetcode-ui.api.question',
  'leetcode-ui.api.runner',
  'leetcode-ui.api.stats',
  'leetcode-ui.api.queries',
  'leetcode-ui.net',
  'leetcode-ui.storage',
  'leetcode-ui.parser',
  'leetcode-ui.buffer',
  'leetcode-ui.console',
  'leetcode-ui.solution',
  'leetcode-ui.question',
  'leetcode-ui.picker',
  'leetcode-ui.stats_view',
  'leetcode-ui.menu',
  'leetcode-ui.runner.common',
  'leetcode-ui.runner.langs.python3',
  'leetcode-ui.async',
  'leetcode-ui.openers',
}

local inputs = {}
for _, mod in ipairs(modules) do
  local path = vim.fs.joinpath(root, 'lua', mod:gsub('%.', '/') .. '.lua')
  if vim.fn.filereadable(path) == 1 then table.insert(inputs, path) end
end

local config = {
  hooks = {
    write_post = function() end,
  },
}

MiniDoc.generate(inputs, vim.fs.joinpath(root, 'doc', 'leetcode-ui.txt'), config)
vim.cmd('qa!')
