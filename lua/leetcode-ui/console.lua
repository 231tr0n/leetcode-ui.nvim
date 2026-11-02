--- *leetcode-ui-console* Test case console
---
--- A plain data model for the Console tab. |leetcode-ui-question| turns
--- |LeetCodeConsole.lines()| into rendered spans; the console itself never
--- owns buffers or windows.
---
---@tag LeetCodeConsole
---@toc_entry Console

local LeetCodeConsole = {}

local config = require('leetcode-ui.config')
local storage = require('leetcode-ui.storage')

-- Helper data =======================================================================================================

LeetCodeConsole.spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

LeetCodeConsole.stdout_fold_threshold = 5

-- Helper functionality =============================================================================================

--- Create a console for a question view.
---
---@param view table
---@return table console
LeetCodeConsole.new = function(view)
  return setmetatable({
    view = view,
    cases = {},
    selected = 1,
    timer = nil,
    frame = 1,
    submission_result = nil,
  }, { __index = LeetCodeConsole })
end

--- Replace all test cases from API-provided example inputs.
---
---@param console table
---@param testcases table|nil Array of raw inputs.
LeetCodeConsole.set_cases = function(console, testcases)
  local cases = {}
  for _, input in ipairs(testcases or {}) do
    table.insert(cases, { input = input, status = 'unknown', result = nil, running = false })
  end
  if #cases == 0 then table.insert(cases, { input = '', status = 'unknown', result = nil, running = false }) end
  console.cases = cases
  console.selected = 1
end

--- Normalize a testcase entered on one line.
---
---@param input string|nil
---@return string
LeetCodeConsole.normalize_input = function(input) return ((input or ''):gsub('\\n', '\n')) end

LeetCodeConsole.case_icon = function(console, case)
  local icons = config.config.icons.case
  if case.running then return LeetCodeConsole.spinner[console.frame], 'LeetCodeWarn' end
  if case.status == 'passed' then return icons.passed, 'LeetCodeOk' end
  if case.status == 'failed' then return icons.failed, 'LeetCodeErr' end
  if case.status == 'error' then return icons.err, 'LeetCodeErr' end
  if case.status == 'ran' then return icons.ran, 'LeetCodeCode' end
  return icons.unknown, 'LeetCodeDim'
end

local function value_text(value)
  if type(value) == 'table' then return vim.json.encode(value) end
  return tostring(value)
end

local function append_value(lines, label, value)
  if value == nil or value == '' then return end
  for _, line in ipairs(vim.split(value_text(value), '\n')) do
    table.insert(lines, { { text = '    ' .. label .. line, hl = 'LeetCodeDim' } })
  end
end

local function append_stdout(lines, folds, value)
  if value == nil or value == '' then return end
  local output_lines = vim.split(value_text(value), '\n')

  if #output_lines <= LeetCodeConsole.stdout_fold_threshold then
    for _, line in ipairs(output_lines) do
      table.insert(lines, { { text = '    stdout: ' .. line, hl = 'LeetCodeDim' } })
    end
    return
  end

  local start_line = #lines + 1
  table.insert(lines, { { text = '    stdout:', hl = 'LeetCodeDim' } })
  for _, line in ipairs(output_lines) do
    table.insert(lines, { { text = '      ' .. line, hl = 'LeetCodeDim' } })
  end
  table.insert(folds, { start_line = start_line, end_line = #lines })
end

--- Build renderable span lines for the Console tab.
---
---@param console table
---@return table lines
---@return table folds
LeetCodeConsole.lines = function(console)
  local lines = {}
  local folds = {}
  local submission = console.submission_result
  if submission ~= nil then
    local icon = submission.ok and config.config.icons.case.passed or config.config.icons.case.failed
    local hl = submission.ok and 'LeetCodeOk' or 'LeetCodeErr'
    table.insert(lines, { { text = 'Submission', hl = 'LeetCodeHeader' } })
    table.insert(lines, { { text = icon .. ' ' .. (submission.status or ''), hl = hl } })

    local details = {}
    if submission.runtime_ms ~= nil then
      table.insert(details, ('Runtime: %d ms'):format(tonumber(submission.runtime_ms) or 0))
    end
    if submission.memory_mb ~= nil then
      table.insert(details, ('Memory: %.2f MB'):format((tonumber(submission.memory_mb) or 0) / (1024 * 1024)))
    end
    if #details > 0 then table.insert(lines, { { text = '  ' .. table.concat(details, '  '), hl = 'LeetCodeDim' } }) end

    table.insert(lines, {})
  end

  table.insert(lines, { { text = 'Testcases', hl = 'LeetCodeTitle' } })
  table.insert(lines, {
    { text = '  :LeetCode question case add|delete|edit|next|prev', hl = 'LeetCodeDim' },
  })
  table.insert(lines, {
    { text = '  Use \\n for multi-line testcase input', hl = 'LeetCodeDim' },
  })
  table.insert(lines, {})

  for index, case in ipairs(console.cases) do
    local icon, icon_hl = LeetCodeConsole.case_icon(console, case)
    local active = index == console.selected
    local marker = active and config.config.icons.status.active or ' '
    local marker_hl = active and 'LeetCodeTitle' or nil

    table.insert(lines, {
      { text = marker .. ' ', hl = marker_hl },
      { text = icon .. ' ', hl = icon_hl },
      { text = ('Case %d'):format(index) },
    })

    for _, input_line in ipairs(vim.split(case.input or '', '\n')) do
      if input_line ~= '' then table.insert(lines, { { text = '    in:  ' .. input_line, hl = 'LeetCodeDim' } }) end
    end

    if case.result ~= nil and not case.running then
      local runtime = case.result.runtime_ms
      if runtime ~= nil then
        table.insert(lines, {
          { text = ('    ran: %d ms'):format(tonumber(runtime) or 0), hl = 'LeetCodeDim' },
        })
      end

      local message = case.result.message
      if message ~= nil and message ~= '' then
        message = message:gsub('%s+$', '')
        local hl = (case.status == 'failed' or case.status == 'error') and 'LeetCodeErr' or 'LeetCodeDim'
        for _, message_line in ipairs(vim.split(message, '\n')) do
          table.insert(lines, { { text = '    ' .. message_line, hl = hl } })
        end
      end

      append_value(lines, 'return: ', case.result.answer)
      if case.status == 'failed' or case.status == 'error' then
        append_value(lines, 'expected: ', case.result.expected_answer)
      end
      append_stdout(lines, folds, case.result.stdout)
    end
  end

  return lines, folds
end

--- Restore the API-provided testcases.
---
---@param console table
LeetCodeConsole.reset_cases = function(console)
  local testcases = console.view ~= nil and (console.view.detail or {}).testcases or {}
  if console.view ~= nil then storage.write_testcases(console.view.slug, nil) end
  console:set_cases(testcases)
  console:refresh()
end

LeetCodeConsole.persist = function(console)
  if console.view == nil then return end
  local inputs = {}
  for _, case in ipairs(console.cases) do
    table.insert(inputs, case.input)
  end
  storage.write_testcases(console.view.slug, inputs)
end

--- Add a new test case.
---
---@param console table
---@param input string|nil
LeetCodeConsole.add_case = function(console, input)
  if console.view ~= nil and console.view.busy then return end
  local cases = console.cases
  table.insert(cases, {
    input = LeetCodeConsole.normalize_input(input),
    status = 'unknown',
    result = nil,
    running = false,
  })
  console.selected = #cases
  console:persist()
  console:refresh()
end

--- Delete a test case.
---
---@param console table
---@param index number|nil Defaults to the selected case.
LeetCodeConsole.delete_case = function(console, index)
  if console.view ~= nil and console.view.busy then return end
  index = index or console.selected
  local cases = console.cases
  if #cases <= 1 or index < 1 or index > #cases then return end
  table.remove(cases, index)
  console.selected = math.min(console.selected, #cases)
  console:persist()
  console:refresh()
end

--- Edit a test case input.
---
---@param console table
---@param index number|nil Defaults to the selected case.
---@param input string|nil
LeetCodeConsole.edit_case = function(console, index, input)
  if console.view ~= nil and console.view.busy then return end
  index = index or console.selected
  local case = console.cases[index]
  if case == nil then return end
  case.input = LeetCodeConsole.normalize_input(input)
  case.status = 'unknown'
  case.result = nil
  console:persist()
  console:refresh()
end

--- Select the next test case.
---
---@param console table
LeetCodeConsole.select_next = function(console)
  if console.view ~= nil and console.view.busy then return end
  local count = #console.cases
  if count == 0 then return end
  console.selected = (console.selected % count) + 1
  console:refresh()
end

--- Select the previous test case.
---
---@param console table
LeetCodeConsole.select_prev = function(console)
  if console.view ~= nil and console.view.busy then return end
  local count = #console.cases
  if count == 0 then return end
  console.selected = ((console.selected - 2) % count) + 1
  console:refresh()
end

--- Store a normalized result for a test case.
---
---@param console table
---@param index number
---@param result table
LeetCodeConsole.case_result = function(console, index, result)
  local case = console.cases[index]
  if case == nil then return end

  case.running = false
  case.result = result

  local correct, total = result.correct or 0, result.total or 0
  if result.status == 'Compile Error' then
    case.status = 'error'
  elseif result.local_run == true or result.status == 'Ran' then
    case.status = 'ran'
  elseif result.is_submit == true then
    case.status = result.status == 'Accepted' and 'passed' or 'failed'
  elseif result.compare ~= nil then
    case.status = result.compare == '1' and 'passed' or 'failed'
  elseif correct == total and total > 0 then
    case.status = 'passed'
  else
    case.status = 'failed'
  end

  console:refresh()
end

--- Request a re-render of the question view when the console changes.
---
---@param console table
LeetCodeConsole.refresh = function(console)
  if console.view == nil then return end
  require('leetcode-ui.question').refresh(console.view)
end

--- Start the spinner used by running cases.
---
---@param console table
LeetCodeConsole.start_spinner = function(console)
  if console.timer ~= nil then return end

  console.frame = 1
  local timer = vim.uv.new_timer()
  if timer == nil then return end
  console.timer = timer

  timer:start(0, 80, function()
    vim.schedule(function()
      local running = false
      for _, case in ipairs(console.cases) do
        if case.running then
          running = true
          break
        end
      end

      if not running then
        console:stop_spinner()
        console:refresh()
        return
      end

      console.frame = (console.frame % #LeetCodeConsole.spinner) + 1
      console:refresh()
    end)
  end)
end

--- Stop the spinner if it is running.
---
---@param console table
LeetCodeConsole.stop_spinner = function(console)
  if console.timer == nil then return end
  console.timer:stop()
  console.timer:close()
  console.timer = nil
end

return LeetCodeConsole
