-- Test runner for leetcode-ui.nvim (mini.test).
--
--   nvim --headless -u scripts/minitest.lua
--   LEETCODE_UI_TEST_FILE=tests/test_commands.lua nvim --headless -u scripts/minitest.lua
--
-- Runs everything under tests/ in-process, offline. Set `LEETCODE_UI_TEST_FILE`
-- to run a single test file instead.

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

local MiniTest = require('mini.test')
if _G.MiniTest == nil then MiniTest.setup() end

local test_file = vim.env.LEETCODE_UI_TEST_FILE
local find_files = function()
  if test_file ~= nil and test_file ~= '' then
    local path = test_file
    if path:match('^/') == nil then path = vim.fs.joinpath(root, path) end
    return { vim.fs.normalize(path) }
  end
  return vim.fn.globpath(root .. '/tests', 'test_*.lua', true, true)
end

local reporter = MiniTest.gen_reporter.stdout()
MiniTest.run({
  collect = { find_files = find_files },
  reporter = reporter,
})

vim.cmd('qa!')
