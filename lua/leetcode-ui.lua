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
--- - Read parsed descriptions, with hints hidden by default.
--- - Edit, run, and submit solutions with draft persistence.
--- - Run and submit solutions through LeetCode's API.
--- - Format with LeetCode's formatter, then fall back to local CLI formatters or LSP.
--- - Show progress statistics and session information.
--- - Import session cookies from supported browsers.
---
--- Commands:
---
--- Browsing and account views:
---
--- - `:LeetCode` or `:LeetCode list [difficulty]` - browse problems.
--- - `:LeetCode daily` - open the daily challenge.
--- - `:LeetCode random [difficulty]` - open a random problem.
--- - `:LeetCode open <slug>` - open a problem by its title slug.
--- - `:LeetCode stats` - show progress statistics.
--- - `:LeetCode session` - show the current session.
--- - `:LeetCode refresh [difficulty]` - clear the problem cache and reopen.
--- - `:LeetCode help` - show a command summary in the central window.
---
--- Question-window actions live under `:LeetCode question`:
---
--- - `:LeetCode question description`, `:LeetCode question code`,
---   `:LeetCode question console`, `:LeetCode question info` - show a tab.
--- - `:LeetCode question hints [show|hide]` - show or hide hints (hidden
---   by default).
--- - `:LeetCode question next`, `:LeetCode question prev` - cycle tabs.
--- - `:LeetCode question run [index]` - run all testcases or one testcase.
--- - `:LeetCode question submit` - submit the current solution.
--- - `:LeetCode question reset` - restore the starter snippet.
--- - `:LeetCode question format` - format the current solution.
--- - `:LeetCode question language [slug]` - switch language.
--- - `:LeetCode question case add <input>`,
---   `:LeetCode question case edit <index> <input>`,
---   `:LeetCode question case delete <index>`,
---   `:LeetCode question case next`, `:LeetCode question case prev`
---   - manage testcases. Use `\n` for newlines in one-line command input.
--- - `:LeetCode question close` - close the question window.
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
