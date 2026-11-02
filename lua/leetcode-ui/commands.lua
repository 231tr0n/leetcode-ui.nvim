--- *leetcode-ui-commands* `:LeetCode` command dispatcher
---
--- All user actions are exposed as subcommands, so no plugin-defined keymaps
--- are installed. Map the commands you use in your own configuration.
---
---@tag LeetCodeCommands
---@toc_entry Commands

local LeetCodeCommands = {}

local api = require('leetcode-ui.api.question')
local log = require('leetcode-ui.log')
local storage = require('leetcode-ui.storage')
local ui = require('leetcode-ui.ui')

-- Helper functionality =============================================================================================

LeetCodeCommands.difficulties = { 'Easy', 'Medium', 'Hard' }

LeetCodeCommands.order = {
  'list',
  'daily',
  'random',
  'open',
  'stats',
  'session',
  'close',
  'description',
  'code',
  'console',
  'info',
  'next',
  'prev',
  'run',
  'submit',
  'reset',
  'format',
  'language',
  'case',
  'refresh',
  'help',
}

LeetCodeCommands.usage = {
  list = 'list [difficulty]',
  daily = 'daily',
  random = 'random [difficulty]',
  open = 'open <slug>',
  stats = 'stats',
  session = 'session',
  close = 'close',
  description = 'description',
  code = 'code',
  console = 'console',
  info = 'info',
  next = 'next',
  prev = 'prev',
  run = 'run [index]',
  submit = 'submit',
  reset = 'reset',
  format = 'format',
  language = 'language [slug]',
  case = 'case add|edit|delete|next|prev',
  refresh = 'refresh [difficulty]',
  help = 'help',
}

LeetCodeCommands.case_usage = {
  add = 'case add [input]',
  edit = 'case edit [index] [input]',
  delete = 'case delete [index]',
  next = 'case next',
  prev = 'case prev',
}

LeetCodeCommands.parse_difficulty = function(value)
  if value == nil then return nil, true end
  local names = { easy = 'Easy', medium = 'Medium', hard = 'Hard' }
  local difficulty = names[value:lower()]
  if difficulty == nil then
    log.error(('Unknown difficulty `%s`; use Easy, Medium, or Hard'):format(value))
    return nil, false
  end
  return difficulty, true
end

LeetCodeCommands.question = function()
  local question = require('leetcode-ui.question')
  local view = question.current()
  if view == nil then log.error('No question is open') end
  return view
end

LeetCodeCommands.case_console = function()
  local view = LeetCodeCommands.question()
  if view == nil then return nil end
  return view.console
end

LeetCodeCommands.read_input = function(value)
  if value ~= nil and value ~= '' then return value end
  return vim.fn.input('Testcase input (use \\n for multiple lines): ')
end

LeetCodeCommands.join = function(args, from) return table.concat(args, ' ', from or 1) end

LeetCodeCommands.filter = function(items, lead)
  local result = {}
  for _, item in ipairs(items) do
    if lead == nil or lead == '' or vim.startswith(item, lead) then table.insert(result, item) end
  end
  return result
end

LeetCodeCommands.case_indices = function()
  local view = require('leetcode-ui.question').current()
  if view == nil then return {} end
  local indices = {}
  for index = 1, #view.console.cases do
    table.insert(indices, tostring(index))
  end
  return indices
end

LeetCodeCommands.cached_slugs = function()
  local slugs = {}
  for _, entry in ipairs(storage.read_cache().problems or {}) do
    table.insert(slugs, entry.title_slug)
  end
  return slugs
end

-- Subcommands ======================================================================================================

LeetCodeCommands.subcommands = {}

LeetCodeCommands.subcommands.list = function(args)
  local difficulty, valid = LeetCodeCommands.parse_difficulty(args[1])
  if not valid then return end
  require('leetcode-ui.picker').problem({ difficulty = difficulty })
end

LeetCodeCommands.subcommands.daily = function() require('leetcode-ui.picker').daily() end

LeetCodeCommands.subcommands.random = function(args)
  local difficulty, valid = LeetCodeCommands.parse_difficulty(args[1])
  if not valid then return end
  require('leetcode-ui.picker').random({ difficulty = difficulty })
end

LeetCodeCommands.subcommands.open = function(args)
  if args[1] == nil or args[1] == '' then
    log.error('Usage: :LeetCode open <slug>')
    return
  end
  require('leetcode-ui.question').open(args[1])
end

LeetCodeCommands.subcommands.stats = function() require('leetcode-ui.stats_view').open() end

LeetCodeCommands.subcommands.session = function() require('leetcode-ui.stats_view').session() end

LeetCodeCommands.subcommands.close = function() require('leetcode-ui.question').close() end

for _, tab in ipairs({ 'description', 'code', 'console', 'info' }) do
  LeetCodeCommands.subcommands[tab] = function()
    local view = LeetCodeCommands.question()
    if view ~= nil then require('leetcode-ui.question').show_tab(view, tab) end
  end
end

LeetCodeCommands.subcommands.next = function()
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').cycle_tab(view, 1) end
end

LeetCodeCommands.subcommands.prev = function()
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').cycle_tab(view, -1) end
end

LeetCodeCommands.subcommands.run = function(args)
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').run(view, args[1]) end
end

LeetCodeCommands.subcommands.submit = function()
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').submit(view) end
end

LeetCodeCommands.subcommands.reset = function()
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').reset_code(view) end
end

LeetCodeCommands.subcommands.format = function()
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.solution').format(view) end
end

LeetCodeCommands.subcommands.language = function(args)
  local view = LeetCodeCommands.question()
  if view == nil then return end
  if view.busy then
    log.warn('Another action is already running')
    return
  end

  local slug = args[1]
  if slug == nil or slug == '' then
    require('leetcode-ui.question').switch_language(view)
    return
  end

  local available = require('leetcode-ui.solution').languages(view)
  if not vim.tbl_contains(available, slug) then
    log.error(('`%s` is not available for this question'):format(slug))
    return
  end
  require('leetcode-ui.solution').switch_language(view, slug)
  require('leetcode-ui.question').refresh(view)
end

LeetCodeCommands.subcommands.case = function(args)
  local action = args[1]
  local handler = LeetCodeCommands.case_commands[action]
  if handler == nil then
    log.error('Usage: :LeetCode case add|edit|delete|next|prev')
    return
  end
  handler(args)
end

LeetCodeCommands.case_commands = {}

LeetCodeCommands.case_commands.add = function(args)
  local console = LeetCodeCommands.case_console()
  if console == nil then return end
  local input = LeetCodeCommands.read_input(LeetCodeCommands.join(args, 2))
  if input == '' then return end
  console:add_case(input)
end

LeetCodeCommands.case_commands.edit = function(args)
  local console = LeetCodeCommands.case_console()
  if console == nil then return end

  local index = tonumber(args[2])
  local input_start = 3
  if index == nil then
    index = console.selected
    input_start = 2
  end

  local input = LeetCodeCommands.read_input(LeetCodeCommands.join(args, input_start))
  if input == '' then return end
  console:edit_case(index, input)
end

LeetCodeCommands.case_commands.delete = function(args)
  local console = LeetCodeCommands.case_console()
  if console == nil then return end
  console:delete_case(tonumber(args[2]))
end

LeetCodeCommands.case_commands.next = function()
  local console = LeetCodeCommands.case_console()
  if console ~= nil then console:select_next() end
end

LeetCodeCommands.case_commands.prev = function()
  local console = LeetCodeCommands.case_console()
  if console ~= nil then console:select_prev() end
end

LeetCodeCommands.subcommands.refresh = function(args)
  local difficulty, valid = LeetCodeCommands.parse_difficulty(args[1])
  if not valid then return end
  api.clear_cache()
  log.info('Cleared the problem-list cache')
  require('leetcode-ui.picker').problem({ difficulty = difficulty })
end

LeetCodeCommands.subcommands.help = function()
  local lines = {
    { { text = 'LeetCode commands', hl = 'LeetCodeHeader' } },
    { { text = '  Map these commands in your own configuration.', hl = 'LeetCodeDim' } },
    {},
  }
  for _, name in ipairs(LeetCodeCommands.order) do
    table.insert(lines, {
      { text = ('  :LeetCode %-34s'):format(LeetCodeCommands.usage[name]), hl = 'LeetCodeCode' },
    })
  end
  table.insert(lines, {})
  table.insert(lines, { { text = 'Testcase commands', hl = 'LeetCodeHeader' } })
  for _, name in ipairs({ 'add', 'edit', 'delete', 'next', 'prev' }) do
    table.insert(lines, {
      { text = ('  :LeetCode %-34s'):format(LeetCodeCommands.case_usage[name]), hl = 'LeetCodeCode' },
    })
  end
  ui.render(lines)
end

-- Public API ========================================================================================================

--- Run a `:LeetCode` subcommand.
---
---@param fargs table Argument list from |nvim_create_user_command()|.
LeetCodeCommands.run = function(fargs)
  require('leetcode-ui').ensure_setup()
  local args = vim.deepcopy(fargs or {})
  local name = args[1] or 'list'
  table.remove(args, 1)

  local handler = LeetCodeCommands.subcommands[name]
  if handler == nil then
    log.error(('Unknown command `%s`; see :LeetCode help'):format(name))
    return
  end
  handler(args)
end

--- Command-line completion for `:LeetCode`.
---
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos number
---@return table
LeetCodeCommands.complete = function(arg_lead, cmd_line, cursor_pos)
  local before = cmd_line:sub(1, cursor_pos)
  local args = vim.split(before, '%s+', { trimempty = true })
  table.remove(args, 1)

  if #args == 0 or (#args == 1 and arg_lead ~= '') then
    return LeetCodeCommands.filter(vim.tbl_keys(LeetCodeCommands.subcommands), arg_lead)
  end

  local name = args[1]
  if name == 'case' then
    if #args == 1 then
      local actions = {}
      for action in pairs(LeetCodeCommands.case_commands) do
        table.insert(actions, action)
      end
      return LeetCodeCommands.filter(actions, arg_lead)
    end

    local action = args[2]
    if #args == 2 then
      if arg_lead == '' and (action == 'edit' or action == 'delete') then return LeetCodeCommands.case_indices() end
      local actions = {}
      for command in pairs(LeetCodeCommands.case_commands) do
        table.insert(actions, command)
      end
      return LeetCodeCommands.filter(actions, arg_lead)
    end

    if action == 'edit' or action == 'delete' then
      return LeetCodeCommands.filter(LeetCodeCommands.case_indices(), arg_lead)
    end
    return {}
  end

  if (name == 'list' or name == 'random' or name == 'refresh') and #args <= 2 then
    return LeetCodeCommands.filter(LeetCodeCommands.difficulties, arg_lead)
  end

  if name == 'language' and #args <= 2 then
    local view = require('leetcode-ui.question').current()
    if view == nil then return {} end
    return LeetCodeCommands.filter(require('leetcode-ui.solution').languages(view), arg_lead)
  end

  if name == 'open' and #args <= 2 then return LeetCodeCommands.filter(LeetCodeCommands.cached_slugs(), arg_lead) end

  if name == 'run' and #args <= 2 then return LeetCodeCommands.filter(LeetCodeCommands.case_indices(), arg_lead) end

  return {}
end

return LeetCodeCommands
