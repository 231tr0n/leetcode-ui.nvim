-- Test runner for leetcode-ui.nvim (mini.test).
--
--   nvim --headless -u scripts/minitest.lua
--
-- Runs everything under tests/ in-process, offline.

-- Resolve repo root from this script's location.
local script = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')

vim.opt.runtimepath:prepend(root)

-- mini.nvim provides mini.test; locate it in the standard pack layout when not
-- already on the runtime path.
if not pcall(require, 'mini.test') then
  local mini = vim.fn.expand('~/.local/share/nvim/site/pack/core/opt/mini.nvim')
  if vim.uv.fs_stat(mini .. '/lua/mini/test.lua') then vim.opt.runtimepath:append(mini) end
end

local minitest = require('mini.test')
if _G.MiniTest == nil then minitest.setup() end

local reporter = minitest.gen_reporter.stdout()
minitest.run({
  collect = {
    find_files = function()
      return vim.fn.globpath(root .. '/tests', 'test_*.lua', true, true)
    end,
  },
  reporter = reporter,
})

vim.cmd('qa!')
