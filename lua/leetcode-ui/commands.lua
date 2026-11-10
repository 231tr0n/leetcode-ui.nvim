--- *leetcode-ui-commands* `:LeetCode` command dispatcher
---
--- All user actions are exposed as subcommands, so no plugin-defined keymaps
--- are installed. Map the commands you use in your own configuration.
---
--- Top-level commands cover browsing and account views. Actions that operate
--- on the open question window live under `:LeetCode question`.
---@tag LeetCodeCommands
---@toc_entry Commands

local LeetCodeCommands = {}

local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local parser = require('leetcode-ui.parser')
local storage = require('leetcode-ui.storage')
local ui = require('leetcode-ui.ui')

-- Helper data =======================================================================================================

local difficulties = { 'Easy', 'Medium', 'Hard' }

local function hint_actions() return { 'show', 'hide' } end

local difficulty_labels = {}
for _, name in ipairs(difficulties) do
  difficulty_labels[name:lower()] = name
end

-- Helper functionality =============================================================================================

local function current_question()
  local question = require('leetcode-ui.question')
  local view = question.current()
  if view == nil then log.error('No question is open') end
  return view
end

local function current_console()
  local view = current_question()
  if view == nil then return nil end
  if view.busy then
    log.warn('Another action is already running')
    return nil
  end
  return view.console
end

local function parse_difficulty(value)
  if value == nil then return nil, true end
  local difficulty = difficulty_labels[value:lower()]
  if difficulty == nil then
    log.error(('Unknown difficulty `%s`; use Easy, Medium, or Hard'):format(value))
    return nil, false
  end
  return difficulty, true
end

local function join_args(args, from) return table.concat(args, ' ', from or 1) end

local function filter_prefix(items, lead, ignore_case)
  local result = {}
  local prefix = ignore_case and (lead or ''):lower() or lead
  for _, item in ipairs(items) do
    local candidate = ignore_case and item:lower() or item
    if prefix == nil or prefix == '' or vim.startswith(candidate, prefix) then table.insert(result, item) end
  end
  return result
end

--- Validate a command's argument count.
---
---@param args table
---@param min_count number
---@param max_count number|nil
---@param usage string
---@return boolean
LeetCodeCommands.validate_args = function(args, min_count, max_count, usage)
  if #args < min_count or (max_count ~= nil and #args > max_count) then
    log.error('Usage: :LeetCode ' .. usage)
    return false
  end
  return true
end

local function case_indexes()
  local view = require('leetcode-ui.question').current()
  if view == nil or view.console == nil then return {} end
  local indexes = {}
  for index = 1, #view.console.cases do
    table.insert(indexes, tostring(index))
  end
  return indexes
end

local function cached_slugs()
  local cache = storage.read_cache()
  if cache.domain ~= config.config.url then return {} end

  local slugs = {}
  for _, entry in ipairs(cache.problems or {}) do
    local slug = entry.title_slug
    local hidden = config.config.hide_premium and entry.is_paid_only == true
    if type(slug) == 'string' and slug ~= '' and not hidden then table.insert(slugs, slug) end
  end
  return slugs
end

local function command_usage(name, definition, prefix)
  local usage = prefix ~= nil and (prefix .. ' ' .. name) or name
  if definition.args ~= nil and definition.args ~= '' then usage = usage .. ' ' .. definition.args end
  return usage
end

local function prepare_commands(definitions, prefix)
  for name, definition in pairs(definitions) do
    definition.usage = command_usage(name, definition, prefix)
    definition.min = definition.min or 0
  end
end

local function run_command(definition, args)
  if not LeetCodeCommands.validate_args(args, definition.min or 0, definition.max, definition.usage) then return end
  definition.run(args)
end

-- Convert command metadata into help rows.
local function help_rows(definitions, order, skip)
  local rows = {}
  for _, name in ipairs(order) do
    if skip == nil or skip[name] ~= true then
      local definition = definitions[name]
      table.insert(rows, { definition.usage, definition.summary })
    end
  end
  return rows
end

-- Command definitions ===============================================================================================

LeetCodeCommands.top_order = { 'list', 'daily', 'random', 'open', 'question', 'stats', 'session', 'refresh', 'help' }

LeetCodeCommands.top_commands = {
  list = {
    args = '[difficulty]',
    max = 1,
    summary = 'Browse problems',
    run = function(args)
      local difficulty, valid = parse_difficulty(args[1])
      if valid then require('leetcode-ui.picker').problem({ difficulty = difficulty }) end
    end,
  },
  daily = {
    max = 0,
    summary = 'Open the daily challenge',
    run = function() require('leetcode-ui.picker').daily() end,
  },
  random = {
    args = '[difficulty]',
    max = 1,
    summary = 'Open a random problem',
    run = function(args)
      local difficulty, valid = parse_difficulty(args[1])
      if valid then require('leetcode-ui.picker').random({ difficulty = difficulty }) end
    end,
  },
  open = {
    args = '<slug>',
    min = 1,
    max = 1,
    summary = 'Open a problem by title slug',
    run = function(args) require('leetcode-ui.question').open(args[1]) end,
  },
  question = {
    args = '<subcommand>',
    min = 1,
    summary = 'Run a question-window action',
    run = function(args)
      local name = table.remove(args, 1)
      local command = LeetCodeCommands.question_commands[name]
      if command == nil then
        log.error('Usage: :LeetCode question <subcommand>; see :LeetCode help')
        return
      end
      run_command(command, args)
    end,
  },
  stats = {
    max = 0,
    summary = 'Show progress statistics',
    run = function() require('leetcode-ui.stats_view').open() end,
  },
  session = {
    max = 0,
    summary = 'Show the current session',
    run = function() require('leetcode-ui.stats_view').session() end,
  },
  refresh = {
    args = '[difficulty]',
    max = 1,
    summary = 'Fetch a fresh problem list and reopen it',
    run = function(args)
      local difficulty, valid = parse_difficulty(args[1])
      if valid then require('leetcode-ui.picker').problem({ difficulty = difficulty, force = true }) end
    end,
  },
  help = {
    max = 0,
    summary = 'Show this command summary',
    run = function()
      ui.claim('help')
      if ui.markdown_enabled() then
        ui.render_markdown(LeetCodeCommands.help_markdown(), { pad_top = true, owner = 'help' })
        ui.set_winbar(' LeetCode Help ')
        return
      end

      local top_rows = LeetCodeCommands.help_rows('top')
      table.insert(top_rows, 1, { '', 'Browse problems (same as list)' })
      local question_rows = LeetCodeCommands.help_rows('question', { case = true })
      local case_rows = LeetCodeCommands.help_rows('case')
      local width = math.max(
        LeetCodeCommands.help_width(top_rows),
        LeetCodeCommands.help_width(question_rows),
        LeetCodeCommands.help_width(case_rows)
      )

      local lines = {
        { { text = 'LeetCode commands', hl = 'LeetCodeHeader' } },
        { { text = '  Map these commands in your own configuration.', hl = 'LeetCodeDim' } },
        {},
      }
      vim.list_extend(lines, LeetCodeCommands.help_lines(top_rows, width))

      table.insert(lines, {})
      table.insert(lines, { { text = 'Question window', hl = 'LeetCodeHeader' } })
      vim.list_extend(lines, LeetCodeCommands.help_lines(question_rows, width))

      table.insert(lines, {})
      table.insert(lines, { { text = 'Question testcases', hl = 'LeetCodeHeader' } })
      vim.list_extend(lines, LeetCodeCommands.help_lines(case_rows, width))

      ui.render(lines, { pad_top = true, owner = 'help' })
      ui.set_winbar(' LeetCode Help ')
    end,
  },
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

local function show_tab(tab)
  return function()
    local view = current_question()
    if view ~= nil then require('leetcode-ui.question').show_tab(view, tab) end
  end
end

LeetCodeCommands.question_commands = {
  description = { max = 0, summary = 'Show the Description tab', run = show_tab('description') },
  code = { max = 0, summary = 'Show the Code tab', run = show_tab('code') },
  console = { max = 0, summary = 'Show the Console tab', run = show_tab('console') },
  info = { max = 0, summary = 'Show the Info tab', run = show_tab('info') },
  next = {
    max = 0,
    summary = 'Show the next tab',
    run = function()
      local view = current_question()
      if view ~= nil then require('leetcode-ui.question').cycle_tab(view, 1) end
    end,
  },
  prev = {
    max = 0,
    summary = 'Show the previous tab',
    run = function()
      local view = current_question()
      if view ~= nil then require('leetcode-ui.question').cycle_tab(view, -1) end
    end,
  },
  run = {
    args = '[index]',
    max = 1,
    summary = 'Run all testcases or one testcase',
    run = function(args)
      local view = current_question()
      if view ~= nil then require('leetcode-ui.question').run(view, args[1]) end
    end,
  },
  submit = {
    max = 0,
    summary = 'Submit the current solution',
    run = function()
      local view = current_question()
      if view ~= nil then require('leetcode-ui.question').submit(view) end
    end,
  },
  reset = {
    max = 0,
    summary = 'Restore the starter snippet',
    run = function()
      local view = current_question()
      if view ~= nil then require('leetcode-ui.question').reset_code(view) end
    end,
  },
  format = {
    max = 0,
    summary = 'Format the current solution',
    run = function()
      local view = current_question()
      if view == nil then return end
      if view.busy then
        log.warn('Another action is already running')
        return
      end
      if not require('leetcode-ui.solution').has_code_buffer(view) then
        log.error('Solution buffer is missing; reopen the code tab')
        return
      end
      require('leetcode-ui.async').run(function()
        require('leetcode-ui.solution').format(view)
        if ui.is_open() then require('leetcode-ui.question').refresh(view) end
      end, function()
        view.busy = false
        if ui.is_open() then require('leetcode-ui.question').refresh(view) end
      end)
    end,
  },
  language = {
    args = '[slug]',
    max = 1,
    summary = 'Switch the solution language',
    run = function(args)
      local view = current_question()
      if view == nil then return end
      if view.busy then
        log.warn('Another action is already running')
        return
      end
      if not require('leetcode-ui.solution').has_code_buffer(view) then
        log.error('Solution buffer is missing; reopen the code tab')
        return
      end

      local slug = args[1]
      if slug == nil or slug == '' then
        require('leetcode-ui.question').switch_language(view)
        return
      end

      local info = config.get_lang(slug)
      local target = info ~= nil and (info.alt or info.slug) or slug
      local available = require('leetcode-ui.solution').languages(view)
      if not vim.tbl_contains(available, target) then
        log.error(('`%s` is not available for this question'):format(slug))
        return
      end
      if require('leetcode-ui.solution').switch_language(view, target) then
        if view.console ~= nil then view.console:clear_results() end
        require('leetcode-ui.question').refresh(view)
      end
    end,
  },
  hints = {
    args = '[show|hide]',
    max = 1,
    summary = 'Show, hide, or toggle hints',
    run = function(args)
      local view = current_question()
      if view == nil then return end

      local action = args[1]
      local show = nil
      if action == 'show' then
        show = true
      elseif action == 'hide' then
        show = false
      elseif action ~= nil then
        log.error('Usage: :LeetCode question hints [show|hide]')
        return
      end
      require('leetcode-ui.question').set_hints(view, show)
    end,
  },
  case = {
    args = '<subcommand>',
    min = 1,
    summary = 'Manage testcases',
    run = function(args)
      local name = table.remove(args, 1)
      local command = LeetCodeCommands.case_commands[name]
      if command == nil then
        log.error('Usage: :LeetCode question case <subcommand>; see :LeetCode help')
        return
      end
      run_command(command, args)
    end,
  },
  close = {
    max = 0,
    summary = 'Close the question window',
    run = function() require('leetcode-ui.question').close() end,
  },
}

LeetCodeCommands.case_order = { 'add', 'edit', 'delete', 'reset', 'next', 'prev' }

LeetCodeCommands.case_commands = {
  add = {
    args = '<input>',
    min = 1,
    summary = 'Add a testcase',
    run = function(args)
      local console = current_console()
      if console == nil then return end
      local input = join_args(args, 1)
      if input == '' then
        log.error('Usage: :LeetCode question case add <input>')
        return
      end
      console:add_case(input)
    end,
  },
  edit = {
    args = '<index> <input>',
    min = 2,
    summary = 'Edit a testcase',
    run = function(args)
      local console = current_console()
      if console == nil then return end

      local index = tonumber(args[1])
      if not console:is_valid_index(index) then
        log.error(('Testcase index must be between 1 and %d'):format(#console.cases))
        return
      end
      local input = join_args(args, 2)
      if input == '' then
        log.error(('Usage: :LeetCode question case edit %d <input>'):format(index))
        return
      end
      console:edit_case(index, input)
    end,
  },
  delete = {
    args = '<index>',
    min = 1,
    max = 1,
    summary = 'Delete a testcase',
    run = function(args)
      local console = current_console()
      if console == nil then return end

      local index = tonumber(args[1])
      if not console:is_valid_index(index) then
        log.error(('Testcase index must be between 1 and %d'):format(#console.cases))
        return
      end
      if #console.cases <= 1 then
        log.error('Cannot delete the only testcase')
        return
      end
      console:delete_case(index)
    end,
  },
  reset = {
    max = 0,
    summary = 'Restore the original testcases',
    run = function()
      local console = current_console()
      if console ~= nil then console:reset_cases() end
    end,
  },
  next = {
    max = 0,
    summary = 'Select the next testcase',
    run = function()
      local console = current_console()
      if console ~= nil then console:select_next() end
    end,
  },
  prev = {
    max = 0,
    summary = 'Select the previous testcase',
    run = function()
      local console = current_console()
      if console ~= nil then console:select_prev() end
    end,
  },
}

prepare_commands(LeetCodeCommands.top_commands)
prepare_commands(LeetCodeCommands.question_commands, 'question')
prepare_commands(LeetCodeCommands.case_commands, 'question case')

-- Public API ========================================================================================================

--- Help rows for one command group.
---
---@param group string `'top'`, `'question'`, or `'case'`.
---@param skip table|nil Names to omit, like `{ case = true }`.
---@return table rows `{ { usage, summary }, ... }`
LeetCodeCommands.help_rows = function(group, skip)
  if group == 'top' then return help_rows(LeetCodeCommands.top_commands, LeetCodeCommands.top_order, skip) end
  if group == 'question' then
    return help_rows(LeetCodeCommands.question_commands, LeetCodeCommands.question_order, skip)
  end
  if group == 'case' then return help_rows(LeetCodeCommands.case_commands, LeetCodeCommands.case_order, skip) end
  return {}
end

--- Width needed to align a set of help rows.
---
---@param rows table `{ { usage, summary }, ... }`
---@return number width
LeetCodeCommands.help_width = function(rows)
  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row[1])
  end
  return width
end

local function wrap_text(text, limit)
  local parts, current = {}, ''
  for word in text:gmatch('%S+') do
    if current == '' then
      current = word
    elseif #current + 1 + #word <= limit then
      current = current .. ' ' .. word
    else
      table.insert(parts, current)
      current = word
    end
  end
  if current ~= '' then table.insert(parts, current) end
  return #parts > 0 and parts or { '' }
end

--- Render aligned help rows as span lines.
---
---@param rows table `{ { usage, summary }, ... }`
---@param width number|nil Usage column width shared across sections.
---@return table lines
LeetCodeCommands.help_lines = function(rows, width)
  width = width or LeetCodeCommands.help_width(rows)
  local format = ('  :LeetCode %%-%ds'):format(width + 2)
  local summary_column = 12 + width + 2
  local summary_width = math.max(1, 78 - summary_column)

  local lines = {}
  for _, row in ipairs(rows) do
    if row[1] == '' then
      for index, part in ipairs(wrap_text(row[2], math.max(1, 78 - 4))) do
        table.insert(lines, {
          { text = index == 1 and '  • ' or '    ', hl = 'LeetCodeDim' },
          { text = part, hl = 'LeetCodeDim' },
        })
      end
    else
      local first = format:format(row[1])
      for index, part in ipairs(wrap_text(row[2], summary_width)) do
        table.insert(lines, {
          index == 1 and { text = first, hl = 'LeetCodeCode' } or { text = string.rep(' ', summary_column) },
          { text = part, hl = 'LeetCodeDim' },
        })
      end
    end
  end
  return lines
end

--- Render command help as Markdown.
---
---@return string markdown
LeetCodeCommands.help_markdown = function()
  local top_rows = LeetCodeCommands.help_rows('top')
  table.insert(top_rows, 1, { '', 'Browse problems (same as list)' })
  local question_rows = LeetCodeCommands.help_rows('question', { case = true })
  local case_rows = LeetCodeCommands.help_rows('case')

  local lines = {
    '# LeetCode commands',
    '',
    '> Map these commands in your own configuration.',
  }
  local function section(title, rows)
    table.insert(lines, '')
    table.insert(lines, '## ' .. title)
    table.insert(lines, '')
    for _, row in ipairs(rows) do
      if row[1] == '' then
        table.insert(lines, '- `:LeetCode` - ' .. parser.markdown_escape(row[2]))
      else
        table.insert(lines, ('- `:LeetCode %s` - %s'):format(row[1], parser.markdown_escape(row[2])))
      end
    end
  end
  section('Browsing and account', top_rows)
  section('Question window', question_rows)
  section('Question testcases', case_rows)
  return table.concat(lines, '\n')
end

--- Run a `:LeetCode` subcommand.
---
---@param fargs table Argument list from |nvim_create_user_command()|.
LeetCodeCommands.run = function(fargs)
  require('leetcode-ui').ensure_setup()

  local args = vim.deepcopy(fargs or {})
  local name = args[1] or 'list'
  table.remove(args, 1)

  local command = LeetCodeCommands.top_commands[name]
  if command == nil then
    log.error(('Unknown command `%s`; see :LeetCode help'):format(name))
    return
  end
  run_command(command, args)
end

local function complete_optional_arg(args, lead, items, ignore_case)
  if #args > 2 or (#args == 2 and lead == '') then return {} end
  return filter_prefix(items, lead, ignore_case)
end

local function complete_question_case(args, lead)
  if #args == 2 then return filter_prefix(LeetCodeCommands.case_order, lead) end
  if #args == 3 and lead ~= '' then return filter_prefix(LeetCodeCommands.case_order, lead) end

  local case_action = args[3]
  if #args == 3 then
    if case_action == 'edit' or case_action == 'delete' then return case_indexes() end
    return {}
  end

  if (case_action == 'edit' or case_action == 'delete') and #args == 4 then
    if lead == '' then return {} end
    return filter_prefix(case_indexes(), lead)
  end
  return {}
end

local function complete_question_optional(args, lead, get_items)
  if #args > 3 or (#args == 3 and lead == '') then return {} end
  return filter_prefix(get_items() or {}, lead)
end

local function complete_question_command(args, lead)
  if #args == 1 or (#args == 2 and lead ~= '') then return filter_prefix(LeetCodeCommands.question_order, lead) end

  local action = args[2]
  if action == 'case' then return complete_question_case(args, lead) end
  if action == 'hints' then return complete_question_optional(args, lead, hint_actions) end
  if action == 'run' then return complete_question_optional(args, lead, case_indexes) end
  if action == 'language' then
    return complete_question_optional(args, lead, function()
      local view = require('leetcode-ui.question').current()
      if view == nil then return {} end
      return require('leetcode-ui.solution').languages(view)
    end)
  end
  return {}
end

--- Command-line completion for `:LeetCode`.
---
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos number
---@return table
LeetCodeCommands.complete = function(arg_lead, cmd_line, cursor_pos)
  require('leetcode-ui').ensure_setup()

  local before = cmd_line:sub(1, cursor_pos)
  local args = vim.split(before, '%s+', { trimempty = true })
  table.remove(args, 1)

  if #args == 0 or (#args == 1 and arg_lead ~= '') then return filter_prefix(LeetCodeCommands.top_order, arg_lead) end

  local name = args[1]
  if name == 'question' then return complete_question_command(args, arg_lead) end
  if name == 'list' or name == 'random' or name == 'refresh' then
    return complete_optional_arg(args, arg_lead, difficulties, true)
  end
  if name == 'open' then return complete_optional_arg(args, arg_lead, cached_slugs()) end
  return {}
end

return LeetCodeCommands
