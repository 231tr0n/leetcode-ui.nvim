-- |leetcode-ui-commands| User command for the |leetcode-ui| plugin.

if vim.g.loaded_leetcode_ui then return end
vim.g.loaded_leetcode_ui = true

local command_options = {
  nargs = '*',
  complete = function(arg_lead, cmd_line, cursor_pos)
    return require('leetcode-ui.commands').complete(arg_lead, cmd_line, cursor_pos)
  end,
  desc = 'LeetCode UI command entry point',
}

local function run(opts) require('leetcode-ui.commands').run(opts.fargs) end

vim.api.nvim_create_user_command('LeetCode', run, command_options)
