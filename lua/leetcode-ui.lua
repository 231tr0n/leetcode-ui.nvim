--- *leetcode-ui* LeetCode UI for Neovim
---
--- A command-driven LeetCode client. The whole interface lives in one central
--- window: problem description, solution editor, test console, and information
--- are tabs in that window. Statistics use the same window.
---
--- No keymaps are created by the plugin. Every action is available as a
--- `:LeetCode` subcommand, so you can map exactly the actions you use:
---
--- >lua
---   vim.keymap.set('n', '<leader>lr', '<cmd>LeetCode run<cr>', { desc = 'LeetCode: run' })
---   vim.keymap.set('n', '<leader>ls', '<cmd>LeetCode submit<cr>', { desc = 'LeetCode: submit' })
--- <
---
--- Features:
---
--- - Browse problems with `mini.pick` or |vim.ui.select()|.
--- - Read parsed descriptions and hints.
--- - Edit, run, and submit solutions with draft persistence.
--- - Run Python 3 solutions locally with the bundled harness.
--- - Show progress statistics and session information.
--- - Import session cookies from supported browsers.
---
--- Commands:
---
--- - `:LeetCode list [difficulty]` - browse problems, optionally filtered.
--- - `:LeetCode daily` - open the daily challenge.
--- - `:LeetCode random [difficulty]` - open a random problem.
--- - `:LeetCode open <slug>` - open a problem by its title slug.
--- - `:LeetCode description`, `:LeetCode code`, `:LeetCode console`,
---   `:LeetCode info` - show a question tab.
--- - `:LeetCode next`, `:LeetCode prev` - cycle question tabs.
--- - `:LeetCode run [index]` - run all testcases or one testcase.
--- - `:LeetCode submit` - submit the current solution.
--- - `:LeetCode reset` - restore the starter snippet.
--- - `:LeetCode format` - format the current solution.
--- - `:LeetCode language [slug]` - switch language (picker without `slug`).
--- - `:LeetCode case add [input]`, `:LeetCode case edit [index] [input]`,
---   `:LeetCode case delete [index]`, `:LeetCode case next`,
---   `:LeetCode case prev` - manage testcases. Use `\n` for newlines in
---   one-line command input.
--- - `:LeetCode stats` - show progress statistics.
--- - `:LeetCode session` - show the current session.
--- - `:LeetCode refresh [difficulty]` - clear the problem cache and reopen.
--- - `:LeetCode close` - close the central window.
--- - `:LeetCode help` - show a command summary in the central window.
---
---@toc_entry Overview
---@tag LeetCode
---@toc

local LeetCode = {}

-- Modules ===========================================================================================================

LeetCode.config = require('leetcode-ui.config')

-- Public API ========================================================================================================

--- Set up plugin options (full docs in |leetcode-ui-config|).
---
---@param opts table|nil Setup options.
LeetCode.setup = function(opts) LeetCode.config.setup(opts) end

--- Ensure a default setup has happened once.
LeetCode.ensure_setup = function()
  if LeetCode.config.is_setup ~= true then LeetCode.setup({}) end
end

--- Run a `:LeetCode` subcommand.
---
---@param fargs table Argument list, like `{ 'run', '1' }`.
LeetCode.command = function(fargs)
  LeetCode.ensure_setup()
  require('leetcode-ui.commands').run(fargs)
end

--- Open today's daily coding challenge.
LeetCode.daily = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').daily()
end

--- Open a random question.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCode.random = function(opts)
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').random(opts)
end

--- Browse the problem list.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCode.list = function(opts)
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').problem(opts)
end

--- Open a question by slug.
---
---@param title_slug string
LeetCode.open = function(title_slug)
  LeetCode.ensure_setup()
  require('leetcode-ui.question').open(title_slug)
end

--- Open the statistics view.
LeetCode.stats = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.stats_view').open()
end

--- Show current session information.
LeetCode.session = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.stats_view').session()
end

--- Close the focused question view.
LeetCode.close = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.question').close()
end

return LeetCode
