--- *leetcode-ui-commands* `:LeetCode` command dispatcher
---
--- All user actions are exposed as subcommands, so no plugin-defined keymaps
--- are installed. Map the commands you use in your own configuration.
---
--- Top-level commands cover browsing and account views. Actions that operate
--- on the open question window live under |:LeetCode-question|.
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
  'question',
  'stats',
  'session',
  'refresh',
  'help',
}

LeetCodeCommands.usage = {
  list = 'list [difficulty]',
  daily = 'daily',
  random = 'random [difficulty]',
  open = 'open <slug>',
  question = 'question <subcommand>',
  stats = 'stats',
  session = 'session',
  refresh = 'refresh [difficulty]',
  help = 'help',
}

LeetCodeCommands.question_order = {
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
  'hints',
  'case',
  'close',
}

LeetCodeCommands.question_usage = {
  description = 'question description',
  code = 'question code',
  console = 'question console',
  info = 'question info',
  next = 'question next',
  prev = 'question prev',
  run = 'question run [index]',
  submit = 'question submit',
  reset = 'question reset',
  format = 'question format',
  language = 'question language [slug]',
  hints = 'question hints [show|hide]',
  case = 'question case add|edit|delete|reset|next|prev',
  close = 'question close',
}

LeetCodeCommands.case_order = { 'add', 'edit', 'delete', 'reset', 'next', 'prev' }

LeetCodeCommands.case_usage = {
  add = 'question case add <input>',
  edit = 'question case edit <index> <input>',
  delete = 'question case delete <index>',
  reset = 'question case reset',
  next = 'question case next',
  prev = 'question case prev',
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

LeetCodeCommands.join = function(args, from) return table.concat(args, ' ', from or 1) end

LeetCodeCommands.filter = function(items, lead)
  local result = {}
  for _, item in ipairs(items) do
    if lead == nil or lead == '' or vim.startswith(item, lead) then table.insert(result, item) end
  end
  return result
end

LeetCodeCommands.check_args = function(args, min_count, max_count, usage)
  if #args < min_count or (max_count ~= nil and #args > max_count) then
    log.error('Usage: :LeetCode ' .. usage)
    return false
  end
  return true
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

-- Question subcommands =============================================================================================

LeetCodeCommands.question_subcommands = {}

for _, tab in ipairs({ 'description', 'code', 'console', 'info' }) do
  LeetCodeCommands.question_subcommands[tab] = function(args)
    if not LeetCodeCommands.check_args(args, 0, 0, 'question ' .. tab) then return end
    local view = LeetCodeCommands.question()
    if view ~= nil then require('leetcode-ui.question').show_tab(view, tab) end
  end
end

LeetCodeCommands.question_subcommands.next = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'question next') then return end
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').cycle_tab(view, 1) end
end

LeetCodeCommands.question_subcommands.prev = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'question prev') then return end
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').cycle_tab(view, -1) end
end

LeetCodeCommands.question_subcommands.run = function(args)
  if not LeetCodeCommands.check_args(args, 0, 1, 'question run [index]') then return end
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').run(view, args[1]) end
end

LeetCodeCommands.question_subcommands.submit = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'question submit') then return end
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').submit(view) end
end

LeetCodeCommands.question_subcommands.reset = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'question reset') then return end
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.question').reset_code(view) end
end

LeetCodeCommands.question_subcommands.format = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'question format') then return end
  local view = LeetCodeCommands.question()
  if view ~= nil then require('leetcode-ui.solution').format(view) end
end

LeetCodeCommands.question_subcommands.language = function(args)
  if not LeetCodeCommands.check_args(args, 0, 1, 'question language [slug]') then return end
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

LeetCodeCommands.question_subcommands.hints = function(args)
  if not LeetCodeCommands.check_args(args, 0, 1, 'question hints [show|hide]') then return end
  local view = LeetCodeCommands.question()
  if view == nil then return end

  local action = args[1]
  local show = nil
  if action == 'show' or action == 'on' then
    show = true
  elseif action == 'hide' or action == 'off' then
    show = false
  elseif action ~= nil and action ~= 'toggle' then
    log.error('Usage: :LeetCode question hints [show|hide]')
    return
  end
  require('leetcode-ui.question').set_hints(view, show)
end

LeetCodeCommands.question_subcommands.case = function(args)
  if not LeetCodeCommands.check_args(args, 1, nil, 'question case add|edit|delete|reset|next|prev') then return end
  local action = args[1]
  local handler = LeetCodeCommands.case_commands[action]
  if handler == nil then
    log.error('Usage: :LeetCode question case add|edit|delete|reset|next|prev')
    return
  end
  handler(args)
end

LeetCodeCommands.question_subcommands.close = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'question close') then return end
  require('leetcode-ui.question').close()
end

-- Testcase subcommands =============================================================================================

LeetCodeCommands.case_commands = {}

LeetCodeCommands.case_commands.add = function(args)
  if not LeetCodeCommands.check_args(args, 2, nil, 'question case add <input>') then return end
  local console = LeetCodeCommands.case_console()
  if console == nil then return end
  local input = LeetCodeCommands.join(args, 2)
  if input == '' then
    log.error('Usage: :LeetCode question case add <input>')
    return
  end
  console:add_case(input)
end

LeetCodeCommands.case_commands.edit = function(args)
  if not LeetCodeCommands.check_args(args, 3, nil, 'question case edit <index> <input>') then return end
  local console = LeetCodeCommands.case_console()
  if console == nil then return end

  local index = tonumber(args[2])
  if index == nil or index < 1 or index > #console.cases then
    log.error(('Testcase index must be between 1 and %d'):format(#console.cases))
    return
  end
  local input = LeetCodeCommands.join(args, 3)
  if input == '' then
    log.error(('Usage: :LeetCode question case edit %d <input>'):format(index))
    return
  end
  console:edit_case(index, input)
end

LeetCodeCommands.case_commands.delete = function(args)
  if not LeetCodeCommands.check_args(args, 2, 2, 'question case delete <index>') then return end
  local console = LeetCodeCommands.case_console()
  if console == nil then return end

  local index = tonumber(args[2])
  if index == nil or index < 1 or index > #console.cases then
    log.error(('Testcase index must be between 1 and %d'):format(#console.cases))
    return
  end
  if #console.cases <= 1 then
    log.error('Cannot delete the only testcase')
    return
  end
  console:delete_case(index)
end

LeetCodeCommands.case_commands.reset = function(args)
  if not LeetCodeCommands.check_args(args, 1, 1, 'question case reset') then return end
  local console = LeetCodeCommands.case_console()
  if console ~= nil then console:reset_cases() end
end

LeetCodeCommands.case_commands.next = function(args)
  if not LeetCodeCommands.check_args(args, 1, 1, 'question case next') then return end
  local console = LeetCodeCommands.case_console()
  if console ~= nil then console:select_next() end
end

LeetCodeCommands.case_commands.prev = function(args)
  if not LeetCodeCommands.check_args(args, 1, 1, 'question case prev') then return end
  local console = LeetCodeCommands.case_console()
  if console ~= nil then console:select_prev() end
end

-- Top-level subcommands ============================================================================================

LeetCodeCommands.subcommands = {}

LeetCodeCommands.subcommands.list = function(args)
  if not LeetCodeCommands.check_args(args, 0, 1, 'list [difficulty]') then return end
  local difficulty, valid = LeetCodeCommands.parse_difficulty(args[1])
  if not valid then return end
  require('leetcode-ui.picker').problem({ difficulty = difficulty })
end

LeetCodeCommands.subcommands.daily = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'daily') then return end
  require('leetcode-ui.picker').daily()
end

LeetCodeCommands.subcommands.random = function(args)
  if not LeetCodeCommands.check_args(args, 0, 1, 'random [difficulty]') then return end
  local difficulty, valid = LeetCodeCommands.parse_difficulty(args[1])
  if not valid then return end
  require('leetcode-ui.picker').random({ difficulty = difficulty })
end

LeetCodeCommands.subcommands.open = function(args)
  if not LeetCodeCommands.check_args(args, 1, 1, 'open <slug>') then return end
  require('leetcode-ui.question').open(args[1])
end

LeetCodeCommands.subcommands.question = function(args)
  if not LeetCodeCommands.check_args(args, 1, nil, 'question <subcommand>') then return end
  local action = args[1]
  local handler = LeetCodeCommands.question_subcommands[action]
  if handler == nil then
    log.error('Usage: :LeetCode question <subcommand>; see :LeetCode help')
    return
  end
  table.remove(args, 1)
  handler(args)
end

LeetCodeCommands.subcommands.stats = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'stats') then return end
  require('leetcode-ui.stats_view').open()
end

LeetCodeCommands.subcommands.session = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'session') then return end
  require('leetcode-ui.stats_view').session()
end

LeetCodeCommands.subcommands.refresh = function(args)
  if not LeetCodeCommands.check_args(args, 0, 1, 'refresh [difficulty]') then return end
  local difficulty, valid = LeetCodeCommands.parse_difficulty(args[1])
  if not valid then return end
  api.clear_cache()
  log.info('Cleared the problem-list cache')
  require('leetcode-ui.picker').problem({ difficulty = difficulty })
end

LeetCodeCommands.subcommands.help = function(args)
  if not LeetCodeCommands.check_args(args, 0, 0, 'help') then return end
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
  table.insert(lines, { { text = 'Question window', hl = 'LeetCodeHeader' } })
  for _, name in ipairs(LeetCodeCommands.question_order) do
    table.insert(lines, {
      { text = ('  :LeetCode %-34s'):format(LeetCodeCommands.question_usage[name]), hl = 'LeetCodeCode' },
    })
  end

  table.insert(lines, {})
  table.insert(lines, { { text = 'Question testcases', hl = 'LeetCodeHeader' } })
  for _, name in ipairs(LeetCodeCommands.case_order) do
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
  if name == 'question' then
    if #args == 1 then return LeetCodeCommands.filter(vim.tbl_keys(LeetCodeCommands.question_subcommands), arg_lead) end
    if #args == 2 and arg_lead ~= '' then
      return LeetCodeCommands.filter(vim.tbl_keys(LeetCodeCommands.question_subcommands), arg_lead)
    end

    local action = args[2]
    if action == 'case' then
      if #args == 2 then return LeetCodeCommands.filter(LeetCodeCommands.case_order, arg_lead) end

      local case_action = args[3]
      if #args == 3 then
        if arg_lead ~= '' then return LeetCodeCommands.filter(LeetCodeCommands.case_order, arg_lead) end
        if case_action == 'edit' or case_action == 'delete' then return LeetCodeCommands.case_indices() end
        return {}
      end

      if case_action == 'edit' or case_action == 'delete' then
        if #args == 4 then
          if arg_lead == '' then return {} end
          return LeetCodeCommands.filter(LeetCodeCommands.case_indices(), arg_lead)
        end
        return {}
      end
      return {}
    end

    if action == 'language' and #args <= 3 then
      if #args == 3 and arg_lead == '' then return {} end
      local view = require('leetcode-ui.question').current()
      if view == nil then return {} end
      return LeetCodeCommands.filter(require('leetcode-ui.solution').languages(view), arg_lead)
    end

    if action == 'hints' and #args <= 3 then
      if #args == 3 and arg_lead == '' then return {} end
      return LeetCodeCommands.filter({ 'show', 'hide' }, arg_lead)
    end

    if action == 'run' and #args <= 3 then
      if #args == 3 and arg_lead == '' then return {} end
      return LeetCodeCommands.filter(LeetCodeCommands.case_indices(), arg_lead)
    end

    return {}
  end

  if (name == 'list' or name == 'random' or name == 'refresh') and #args <= 2 then
    if #args == 2 and arg_lead == '' then return {} end
    return LeetCodeCommands.filter(LeetCodeCommands.difficulties, arg_lead)
  end

  if name == 'open' and #args <= 2 then
    if #args == 2 and arg_lead == '' then return {} end
    return LeetCodeCommands.filter(LeetCodeCommands.cached_slugs(), arg_lead)
  end

  return {}
end

return LeetCodeCommands
