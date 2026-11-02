--- *leetcode-ui-question* Question view
---
--- The question view is a set of tabs rendered in the central |LeetCodeUI|
--- window: Description, Code, Console, and Info. The code tab is the only
--- editable buffer; all other tabs use the shared read-only scratch buffer.
---
--- Open views live in |LeetCodeQuestionView.views| keyed by slug.
---
---@tag LeetCodeQuestionView
---@toc_entry Question view

local LeetCodeQuestionView = {}

local api = require('leetcode-ui.api.question')
local client_api = require('leetcode-ui.api')
local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')
local Console = require('leetcode-ui.console')
local log = require('leetcode-ui.log')
local parser = require('leetcode-ui.parser')
local runner = require('leetcode-ui.api.runner')
local solution = require('leetcode-ui.solution')
local storage = require('leetcode-ui.storage')
local ui = require('leetcode-ui.ui')

-- Helper data =======================================================================================================

LeetCodeQuestionView.views = {}
LeetCodeQuestionView.active = nil
LeetCodeQuestionView.tabs = { 'description', 'code', 'console', 'info' }
LeetCodeQuestionView.tab_labels = {
  description = 'Description',
  code = 'Code',
  console = 'Console',
  info = 'Info',
}
LeetCodeQuestionView.difficulty_hl = {
  Easy = 'LeetCodeEasy',
  Medium = 'LeetCodeMedium',
  Hard = 'LeetCodeHard',
}

-- Helper functionality =============================================================================================

LeetCodeQuestionView.as = function(fn) return require('leetcode-ui.async').run(fn) end

LeetCodeQuestionView.escape_statusline = function(text) return (tostring(text):gsub('%%', '%%%%')) end

LeetCodeQuestionView.difficulty = function(difficulty)
  return LeetCodeQuestionView.difficulty_hl[difficulty] or 'LeetCodeTitle'
end

local function click_tab(tab)
  local view = LeetCodeQuestionView.current()
  if view ~= nil then LeetCodeQuestionView.show_tab(view, tab) end
end

for _, tab in ipairs(LeetCodeQuestionView.tabs) do
  local suffix = tab:gsub('^%l', string.upper)
  _G['LeetCodeClick' .. suffix] = function() click_tab(tab) end
end

--- Build Description tab lines.
---
---@param view table
---@return table lines
LeetCodeQuestionView.describe = function(view)
  local detail = view.detail or {}
  local icons = config.config.icons.status

  local lines = {
    {
      {
        text = ('%s. %s'):format(detail.frontend_id or '?', detail.title or 'Unknown question'),
        hl = 'LeetCodeTitle',
      },
    },
  }

  local marks = {
    { text = detail.difficulty or '', hl = LeetCodeQuestionView.difficulty(detail.difficulty) },
  }
  if detail.is_paid_only then table.insert(marks, { text = 'Premium', hl = 'LeetCodeWarn' }) end
  if detail.status == 'solved' then
    table.insert(marks, { text = icons.solved, hl = 'LeetCodeOk' })
  elseif detail.status ~= nil then
    table.insert(marks, { text = icons.attempted, hl = 'LeetCodeWarn' })
  else
    table.insert(marks, { text = icons.todo, hl = 'LeetCodeDim' })
  end
  if view.entry ~= nil and view.entry.ac_rate ~= nil then
    table.insert(marks, { text = ('%.1f%%'):format(view.entry.ac_rate), hl = 'LeetCodeDim' })
  end

  local metadata = {}
  for index, mark in ipairs(marks) do
    if index > 1 then table.insert(metadata, { text = '  ', hl = 'LeetCodeDim' }) end
    table.insert(metadata, mark)
  end
  table.insert(lines, metadata)
  table.insert(lines, {})

  vim.list_extend(lines, parser.render(detail.content))

  local hints = detail.hints or {}
  if #hints > 0 then
    table.insert(lines, {})
    if view.show_hints ~= true then
      table.insert(lines, {
        {
          text = ('Hints (%d) hidden. Use `:LeetCode question hints` to show them.'):format(#hints),
          hl = 'LeetCodeDim',
        },
      })
    else
      table.insert(lines, { { text = 'Hints', hl = 'LeetCodeHeader' } })
      for index, hint in ipairs(hints) do
        local hint_lines = parser.render(hint)
        if #hint_lines == 0 then
          table.insert(lines, { { text = ('%d. '):format(index), hl = 'LeetCodeDim' } })
        else
          table.insert(hint_lines[1], 1, { text = ('%d. '):format(index), hl = 'LeetCodeDim' })
          vim.list_extend(lines, hint_lines)
        end
      end
    end
  end

  return lines
end

--- Build Info tab lines.
---
---@param view table
---@return table lines
LeetCodeQuestionView.info = function(view)
  local detail = view.detail or {}
  local tags = {}
  for _, tag in ipairs((view.entry or {}).topic_tags or {}) do
    table.insert(tags, tag.name)
  end

  local lines = {
    {
      { text = 'Question:    ', hl = 'LeetCodeDim' },
      { text = ('%s. %s'):format(detail.frontend_id or '?', detail.title or 'Unknown question'), hl = 'LeetCodeTitle' },
    },
    {
      { text = 'Difficulty:  ', hl = 'LeetCodeDim' },
      { text = detail.difficulty or 'Unknown', hl = LeetCodeQuestionView.difficulty(detail.difficulty) },
    },
    { { text = 'Language:    ', hl = 'LeetCodeDim' }, { text = view.lang, hl = 'LeetCodeCode' } },
    { { text = 'Testcases:   ', hl = 'LeetCodeDim' }, { text = tostring(#view.console.cases), hl = 'LeetCodeCode' } },
    { { text = 'Runner:      ', hl = 'LeetCodeDim' }, { text = 'LeetCode API', hl = 'LeetCodeOk' } },
    {
      { text = 'Link:        ', hl = 'LeetCodeDim' },
      { text = client_api.problems_url(view.slug), hl = 'LeetCodeLink' },
    },
  }

  if #tags > 0 then
    table.insert(
      lines,
      { { text = 'Tags:        ', hl = 'LeetCodeDim' }, { text = table.concat(tags, ', '), hl = 'LeetCodeLink' } }
    )
  end

  table.insert(lines, {})
  table.insert(lines, { { text = 'Commands', hl = 'LeetCodeHeader' } })
  table.insert(lines, { { text = '  Map these commands if you want key bindings.', hl = 'LeetCodeDim' } })
  local rows = {
    { ':LeetCode question run [index]', 'Run all testcases or one testcase' },
    { ':LeetCode question submit', 'Submit the current solution' },
    { ':LeetCode question reset', 'Restore the starter snippet' },
    { ':LeetCode question format', 'Format the current solution' },
    { ':LeetCode question language [slug]', 'Switch language' },
    { ':LeetCode question case add <input>', 'Add a testcase' },
    { ':LeetCode question case edit <index> <input>', 'Edit a testcase' },
    { ':LeetCode question case delete <index>', 'Delete a testcase' },
    { ':LeetCode question case next|prev', 'Select a testcase' },
    { ':LeetCode question case reset', 'Restore the original testcases' },
    { ':LeetCode question description|code|console|info', 'Show a tab' },
    { ':LeetCode question hints [show|hide]', 'Show or hide hints' },
    { ':LeetCode question next|prev', 'Cycle tabs' },
    { ':LeetCode question close', 'Close the question' },
  }
  local command_width = 0
  for _, row in ipairs(rows) do
    command_width = math.max(command_width, #row[1])
  end
  local command_format = ('  %%-%ds'):format(command_width + 2)
  for _, row in ipairs(rows) do
    table.insert(lines, {
      { text = command_format:format(row[1]), hl = 'LeetCodeCode' },
      { text = row[2], hl = 'LeetCodeDim' },
    })
  end

  return lines
end

--- Render the question title and clickable tab strip in the central window's winbar.
---
---@param view table
LeetCodeQuestionView.render_winbar = function(view)
  if view == nil or not ui.is_open() then return end

  local detail = view.detail or {}
  local title = ('LeetCode %s'):format(detail.frontend_id or '?')
  local parts = {
    ('%%#LeetCodeQuestionTitle#%s %%#LeetCodeWinBar#'):format(LeetCodeQuestionView.escape_statusline(title)),
  }

  for _, tab in ipairs(LeetCodeQuestionView.tabs) do
    local label = LeetCodeQuestionView.tab_labels[tab]
    if tab == 'code' then label = ('%s (%s)'):format(label, view.lang) end
    local hl = tab == view.active and 'LeetCodeTabActive' or 'LeetCodeTab'
    local click = ('%%@v:lua.LeetCodeClick%s@'):format(tab:gsub('^%l', string.upper))
    table.insert(parts, ('%s%%#%s# %s %%X%%#LeetCodeWinBar#'):format(click, hl, label))
  end

  if view.busy then table.insert(parts, '%#LeetCodeWarn# … %#LeetCodeWinBar#') end
  ui.set_winbar(' ' .. table.concat(parts, ' │ ') .. ' ')
end

--- Re-render the active tab.
---
---@param view table|nil
LeetCodeQuestionView.refresh = function(view)
  view = view or LeetCodeQuestionView.active
  if view == nil or LeetCodeQuestionView.views[view.slug] ~= view then return end

  if view.active == 'code' then
    if view.code_bufnr ~= nil and vim.api.nvim_buf_is_valid(view.code_bufnr) then
      ui.show(view.code_bufnr, {
        number = true,
        wrap = false,
        cursorline = vim.go.cursorline,
        signcolumn = 'auto',
        foldenable = true,
        foldmethod = vim.go.foldmethod,
        foldcolumn = 1,
        statuscolumn = '%s%C%l ',
      })
    end
  else
    local lines = nil
    if view.active == 'description' then
      lines = LeetCodeQuestionView.describe(view)
    elseif view.active == 'console' then
      local folds
      lines, folds = view.console:lines()
      if folds ~= nil then
        ui.render(lines, {
          number = false,
          wrap = true,
          pad_top = true,
          folds = folds,
          foldenable = true,
          foldmethod = 'manual',
          foldcolumn = 1,
          statuscolumn = '%C ',
        })
        LeetCodeQuestionView.render_winbar(view)
        return
      end
    elseif view.active == 'info' then
      lines = LeetCodeQuestionView.info(view)
    end
    if lines ~= nil then ui.render(lines, { number = false, wrap = true, pad_top = true }) end
  end

  LeetCodeQuestionView.render_winbar(view)
end

--- Show a tab.
---
---@param view table|nil
---@param name string
LeetCodeQuestionView.show_tab = function(view, name)
  view = view or LeetCodeQuestionView.active
  if view == nil or LeetCodeQuestionView.tab_labels[name] == nil then return end

  if name == 'code' and (view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr)) then
    solution.prepare(view)
    solution.open(view)
  end

  view.active = name
  LeetCodeQuestionView.active = view
  LeetCodeQuestionView.refresh(view)
end

--- Cycle through tabs.
---
---@param view table|nil
---@param delta number|nil
LeetCodeQuestionView.cycle_tab = function(view, delta)
  view = view or LeetCodeQuestionView.active
  if view == nil then return end

  local index = 1
  for position, tab in ipairs(LeetCodeQuestionView.tabs) do
    if tab == view.active then
      index = position
      break
    end
  end

  index = index + (delta or 1)
  if index > #LeetCodeQuestionView.tabs then index = 1 end
  if index < 1 then index = #LeetCodeQuestionView.tabs end
  LeetCodeQuestionView.show_tab(view, LeetCodeQuestionView.tabs[index])
end

-- Public API ========================================================================================================

--- Get the question view belonging to the current buffer, falling back to the
--- most recently active view.
---
---@return table|nil
LeetCodeQuestionView.current = function()
  local bufnr = vim.api.nvim_get_current_buf()
  for _, view in pairs(LeetCodeQuestionView.views) do
    if bufnr == view.code_bufnr then return view end
  end
  return LeetCodeQuestionView.active
end

--- Open a question by slug.
---
---@param title_slug string
LeetCodeQuestionView.open = function(title_slug)
  if title_slug == nil or title_slug == '' then
    log.error('A question slug is required')
    return
  end

  local existing = LeetCodeQuestionView.views[title_slug]
  if existing ~= nil then
    LeetCodeQuestionView.active = existing
    LeetCodeQuestionView.show_tab(existing, existing.active or 'code')
    return
  end

  log.info(('Loading question `%s`…'):format(title_slug))
  LeetCodeQuestionView.as(function()
    local detail, err = api.get_detail(title_slug)
    if err ~= nil or detail == nil then
      log.error('Failed to load question: ' .. (err or 'Empty response'))
      return
    end

    local view = {
      slug = title_slug,
      detail = detail,
      entry = api.find_in_list(title_slug),
      lang = config.config.lang,
      console = nil,
      code_bufnr = nil,
      active = 'code',
      busy = false,
      show_hints = config.config.show_hints,
    }
    view.console = Console.new(view)
    local saved_testcases = storage.read_testcases(title_slug)
    view.console:set_cases(saved_testcases or detail.testcases)
    LeetCodeQuestionView.views[title_slug] = view

    solution.prepare(view)
    solution.open(view)

    LeetCodeQuestionView.active = view
    LeetCodeQuestionView.show_tab(view, 'code')
    log.info(('Opened %s. %s'):format(detail.frontend_id or '?', detail.title or title_slug))
  end)
end

--- Close a question view.
---
---@param view table|nil
LeetCodeQuestionView.close = function(view)
  view = view or LeetCodeQuestionView.active
  if view == nil then
    ui.close()
    return
  end

  solution.save_draft(view)
  if view.console ~= nil then view.console:stop_spinner() end

  if LeetCodeQuestionView.active == view then
    ui.close()
    LeetCodeQuestionView.active = nil
  end

  buffer.maybe_delete(view.code_bufnr)
  LeetCodeQuestionView.views[view.slug] = nil
  log.info(('Closed question `%s`'):format(view.slug))
end

--- Show or hide hints in the Description tab.
---
---@param view table|nil
---@param show boolean|nil `nil` toggles the current state.
LeetCodeQuestionView.set_hints = function(view, show)
  view = view or LeetCodeQuestionView.current()
  if view == nil then return end

  local hints = (view.detail or {}).hints or {}
  if #hints == 0 then
    log.info('This question has no hints')
    return
  end

  view.show_hints = show == nil and not view.show_hints or show == true
  if view.show_hints and view.active ~= 'description' then
    LeetCodeQuestionView.show_tab(view, 'description')
  elseif view.active == 'description' then
    LeetCodeQuestionView.refresh(view)
  end

  if view.show_hints then
    log.info(('Showing %d hint(s)'):format(#hints))
  else
    log.info('Hints hidden')
  end
end

--- Restore the starter snippet.
---
---@param view table|nil
LeetCodeQuestionView.reset_code = function(view)
  view = view or LeetCodeQuestionView.current()
  if view == nil or view.busy then return end
  solution.reset(view)
  LeetCodeQuestionView.refresh(view)
end

--- Switch to another available language.
---
---@param view table|nil
LeetCodeQuestionView.switch_language = function(view)
  view = view or LeetCodeQuestionView.current()
  if view == nil or view.busy then return end

  local languages = solution.languages(view)
  if #languages <= 1 then
    log.info('No other languages are available for this question')
    return
  end

  local picker = require('leetcode-ui.picker')
  picker.select(languages, ' Select language ', function(choice)
    if choice == nil then return end
    solution.switch_language(view, choice)
    LeetCodeQuestionView.refresh(view)
  end)
end

--- Mark cases as running and show the Console tab.
---
---@param view table
---@param indexes table
LeetCodeQuestionView.mark_running = function(view, indexes)
  for _, index in ipairs(indexes) do
    local case = view.console.cases[index]
    if case ~= nil then
      case.running = true
      case.status = 'unknown'
      case.result = nil
    end
  end
  view.console.selected = indexes[1] or view.console.selected
  view.console:start_spinner()
  LeetCodeQuestionView.show_tab(view, 'console')
end

--- Run testcases through the LeetCode API.
---
---@param view table
---@param question table
---@param code string
---@param indexes table
---@param index number|nil Single-case index.
LeetCodeQuestionView.run_api = function(view, question, code, indexes, index)
  local cases = view.console.cases
  local result, err

  if index ~= nil then
    result, err = runner.interpret(question, code, cases[index].input)
  else
    local inputs = {}
    for _, case in ipairs(cases) do
      table.insert(inputs, case.input)
    end
    result, err = runner.interpret(question, code, table.concat(inputs, '\n'))
  end

  if err ~= nil or result == nil then
    for _, case_index in ipairs(indexes) do
      local case = cases[case_index]
      case.running = false
      case.status = 'error'
      case.result = { status = 'Error', message = err or 'Empty response' }
    end
    view.console:stop_spinner()
    LeetCodeQuestionView.refresh(view)
    log.error('Test run failed: ' .. (err or 'Empty response'))
    return
  end

  local passed = 0
  for _, case_index in ipairs(indexes) do
    local case = cases[case_index]
    case.running = false

    local case_result
    if result.compare ~= nil then
      local bit = index ~= nil and result.compare:sub(1, 1) or result.compare:sub(case_index, case_index)
      if bit == '' then bit = '0' end
      local stdout_index = index ~= nil and 1 or case_index
      local answer = type(result.answers) == 'table' and result.answers[stdout_index] or nil
      local expected_answer = type(result.expected_answers) == 'table' and result.expected_answers[stdout_index] or nil

      case_result = {
        status = result.status,
        runtime_ms = result.runtime_ms,
        compare = bit,
        correct = bit == '1' and 1 or 0,
        total = 1,
        stdout = (result.stdouts or {})[stdout_index] or result.pretty_stdout,
        answer = answer or result.code_output,
        expected_answer = expected_answer or result.expected_output,
        is_submit = false,
      }
    else
      case_result = {
        status = result.status,
        message = result.message,
        runtime_ms = result.runtime_ms,
        stdout = result.pretty_stdout,
        answer = result.code_output,
        expected_answer = result.expected_output,
      }
    end

    view.console:case_result(case_index, case_result)
    if case.status == 'passed' then passed = passed + 1 end
  end

  view.console:stop_spinner()
  LeetCodeQuestionView.refresh(view)
  if passed == #indexes then
    log.info(('All %d testcase(s) passed'):format(passed))
  else
    log.warn(('%d of %d testcase(s) passed'):format(passed, #indexes))
  end
end

--- Run all testcases or one testcase.
---
---@param view table|nil
---@param index number|string|nil
LeetCodeQuestionView.run = function(view, index)
  view = view or LeetCodeQuestionView.current()
  if view == nil then
    log.error('No question is open')
    return
  end
  if view.busy then
    log.warn('Another action is already running')
    return
  end

  local cases = view.console.cases
  local indexes = {}
  if index ~= nil then
    index = tonumber(index)
    if index == nil or index < 1 or index > #cases then
      log.error(('Testcase index must be between 1 and %d'):format(#cases))
      return
    end
    indexes = { index }
  else
    for case_index = 1, #cases do
      table.insert(indexes, case_index)
    end
  end

  if #indexes == 0 then
    log.warn('There are no testcases to run')
    return
  end

  view.busy = true
  LeetCodeQuestionView.as(function()
    solution.save_draft(view)
    local code = solution.code(view)
    local question = { id = view.detail.id, title_slug = view.slug, lang_slug = view.lang }

    log.info(('Running %d testcase(s) through LeetCode…'):format(#indexes))
    LeetCodeQuestionView.mark_running(view, indexes)
    LeetCodeQuestionView.run_api(view, question, code, indexes, index)
    view.busy = false
    LeetCodeQuestionView.refresh(view)
  end)
end

--- Submit the current solution.
---
---@param view table|nil
LeetCodeQuestionView.submit = function(view)
  view = view or LeetCodeQuestionView.current()
  if view == nil then
    log.error('No question is open')
    return
  end
  if view.busy then
    log.warn('Another action is already running')
    return
  end

  view.busy = true
  LeetCodeQuestionView.as(function()
    solution.save_draft(view)
    local code = solution.code(view)
    local question = { id = view.detail.id, title_slug = view.slug, lang_slug = view.lang }

    log.info('Submitting solution…')
    local result, err = runner.submit(question, code)
    view.busy = false
    if err ~= nil or result == nil then
      log.error('Submission failed: ' .. (err or 'Empty response'))
      LeetCodeQuestionView.refresh(view)
      return
    end

    local icons = config.config.icons.case
    local icon = result.status == 'Accepted' and icons.passed or icons.failed
    local details = {}
    if not result.ok then
      if result.message ~= nil and result.message ~= '' then table.insert(details, result.message) end
      if result.input ~= nil and result.input ~= '' then table.insert(details, 'Input: ' .. tostring(result.input)) end
      if result.expected_output ~= nil and result.expected_output ~= '' then
        table.insert(details, 'Expected: ' .. tostring(result.expected_output))
      end
      if result.code_output ~= nil and result.code_output ~= '' then
        table.insert(details, 'Got: ' .. tostring(result.code_output))
      end
    end
    local extra = #details > 0 and ('\n' .. table.concat(details, '\n')) or ''

    local message = ('%s %s  Runtime: %d ms  Memory: %.2f MB%s'):format(
      icon,
      result.status or 'Finished',
      tonumber(result.runtime_ms) or 0,
      (tonumber(result.memory_mb) or 0) / (1024 * 1024),
      extra
    )
    log.notify(message, result.ok and vim.log.levels.INFO or vim.log.levels.WARN)

    view.console.submission_result = result
    LeetCodeQuestionView.show_tab(view, 'console')

    if result.ok then
      api.update_list_status(view.slug, 'solved')
      if view.entry ~= nil then view.entry.status = 'solved' end
    elseif view.entry ~= nil and view.entry.status == 'solved' then
      api.update_list_status(view.slug, 'attempted')
      view.entry.status = 'attempted'
    end
    LeetCodeQuestionView.refresh(view)
  end)
end

return LeetCodeQuestionView
