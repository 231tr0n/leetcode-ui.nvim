-- |leetcode-ui-commands| User commands for the |leetcode-ui| plugin.

if vim.g.loaded_leetcode_ui then return end
vim.g.loaded_leetcode_ui = true

local M = require('leetcode-ui')

---Subcommand table: name -> handler(opts).
local commands = {
  daily = function() M.daily() end,
  random = function(opts) M.random(opts.fargs[2] ~= nil and { difficulty = opts.fargs[2] } or nil) end,
  list = function(opts) M.list(opts.fargs[2] ~= nil and { difficulty = opts.fargs[2] } or nil) end,
  stats = function() M.stats() end,
  session = function() M.session() end,
  close = function() M.close() end,
}

---Top-level :LeetCode command.
---
---   :LeetCode [daily|random|list|stats|session|close] [Easy|Medium|Hard]
---
vim.api.nvim_create_user_command('LeetCode', function(opts)
  local name = opts.fargs[1] or 'list'
  local action = commands[name]
  if action == nil then
    vim.notify(('(leetcode-ui) Unknown argument `%s`.'):format(name), vim.log.levels.WARN)
    action = commands.list
  end
  action(opts)
end, {
  nargs = '*',
  complete = function(_, cmd_line, _)
    local parts = vim.split(cmd_line, '%s+', { trimempty = false })
    if #parts <= 2 then return vim.tbl_keys(commands) end
    return { 'Easy', 'Medium', 'Hard' }
  end,
  desc = 'LeetCode UI entry point',
})
