--- *leetcode-ui-console* Test case console
---
--- A plain data model for the Console tab. |leetcode-ui-question| turns
--- |LeetCodeConsole.lines()| into rendered spans; the console itself never
--- owns buffers or windows.
---@tag LeetCodeConsole
---@toc_entry Console

local LeetCodeConsole = {}

local config = require('leetcode-ui.config')
local storage = require('leetcode-ui.storage')

-- Helper data =======================================================================================================

LeetCodeConsole.spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

LeetCodeConsole.stdout_fold_threshold = 5

-- Helper functionality =============================================================================================

local function new_case(input) return { input = input or '', status = 'unknown', result = nil, running = false } end

local function cases_from(testcases)
  local cases = {}
  for _, input in ipairs(type(testcases) == 'table' and testcases or {}) do
    if type(input) == 'string' then table.insert(cases, new_case(input)) end
  end
  if #cases == 0 then table.insert(cases, new_case('')) end
  return cases
end

local function can_mutate(console) return console.view == nil or console.view.busy ~= true end

local function persist(console, cases)
  if console.view == nil then return true end
  local inputs = {}
  for _, case in ipairs(cases) do
    table.insert(inputs, case.input)
  end
  return storage.write_testcases(console.view.slug, inputs)
end

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

--- Replace all testcases from raw inputs.
---
---@param console table
---@param testcases table|nil Array of raw inputs.
LeetCodeConsole.set_cases = function(console, testcases)
  console.cases = cases_from(testcases)
  console.selected = 1
end

--- Normalize a testcase entered on one line.
---
---@param input string|nil
---@return string
LeetCodeConsole.normalize_input = function(input) return ((input or ''):gsub('\\n', '\n')) end

--- Whether `index` identifies an existing testcase.
---
---@param console table
---@param index any
---@return boolean
LeetCodeConsole.is_valid_index = function(console, index)
  return type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= #console.cases
end

--- Icon and highlight for one testcase status.
---
---@param console table
---@param case table
---@return string icon
---@return string hl
LeetCodeConsole.case_icon = function(console, case)
  local icons = config.config.icons.case
  if case.running then return LeetCodeConsole.spinner[console.frame], 'LeetCodeWarn' end
  if case.status == 'passed' then return icons.passed, 'LeetCodeOk' end
  if case.status == 'failed' then return icons.failed, 'LeetCodeErr' end
  if case.status == 'error' then return icons.err, 'LeetCodeErr' end
  return icons.unknown, 'LeetCodeDim'
end

local function value_text(value)
  if value == nil or value == vim.NIL then return '' end
  if type(value) == 'table' then return vim.json.encode(value) end
  return tostring(value)
end

local function append_value(lines, label, value)
  if value == nil or value == vim.NIL or value == '' then return end
  local value_lines = vim.split(value_text(value), '\n', { plain = true })
  local indent = '    ' .. string.rep(' ', #label)

  table.insert(lines, { { text = '    ' .. label .. value_lines[1], hl = 'LeetCodeDim' } })
  for index = 2, #value_lines do
    table.insert(lines, { { text = indent .. value_lines[index], hl = 'LeetCodeDim' } })
  end
end

local function append_stdout(lines, folds, value)
  if value == nil or value == vim.NIL or value == '' then return end
  local output_lines = vim.split(value_text(value), '\n', { plain = true })

  if #output_lines <= LeetCodeConsole.stdout_fold_threshold then
    if #output_lines == 1 then
      table.insert(lines, { { text = '    stdout: ' .. output_lines[1], hl = 'LeetCodeDim' } })
      return
    end
    table.insert(lines, { { text = '    stdout:', hl = 'LeetCodeDim' } })
    for _, line in ipairs(output_lines) do
      table.insert(lines, { { text = '            ' .. line, hl = 'LeetCodeDim' } })
    end
    return
  end

  local start_line = #lines + 1
  table.insert(lines, { { text = '    stdout:', hl = 'LeetCodeDim' } })
  for _, line in ipairs(output_lines) do
    table.insert(lines, { { text = '            ' .. line, hl = 'LeetCodeDim' } })
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
    if submission.memory_bytes ~= nil then
      table.insert(details, ('Memory: %.2f MB'):format((tonumber(submission.memory_bytes) or 0) / (1024 * 1024)))
    end
    if #details > 0 then table.insert(lines, { { text = '  ' .. table.concat(details, '  '), hl = 'LeetCodeDim' } }) end

    if not submission.ok then
      append_value(lines, 'error: ', submission.message)
      append_value(lines, 'input: ', submission.input)
      append_value(lines, 'expected: ', submission.expected_output)
      append_value(lines, 'got: ', submission.code_output)
    end

    table.insert(lines, {})
  end

  table.insert(lines, { { text = 'Testcases', hl = 'LeetCodeTitle' } })
  table.insert(lines, { { text = '  :LeetCode help lists testcase commands', hl = 'LeetCodeDim' } })
  table.insert(lines, {
    { text = '  Use \\n for multi-line testcase input', hl = 'LeetCodeDim' },
  })
  table.insert(lines, {})

  for index, case in ipairs(console.cases) do
    if index > 1 then table.insert(lines, {}) end
    local icon, icon_hl = LeetCodeConsole.case_icon(console, case)
    local active = index == console.selected
    local marker = active and config.config.icons.status.active or ' '
    local marker_hl = active and 'LeetCodeTitle' or nil

    table.insert(lines, {
      { text = marker .. ' ', hl = marker_hl },
      { text = icon .. ' ', hl = icon_hl },
      { text = ('Case %d'):format(index) },
    })

    local input = case.input or ''
    if input == '' then
      table.insert(lines, { { text = '    in:  <empty>', hl = 'LeetCodeDim' } })
    else
      for line_index, input_line in ipairs(vim.split(input, '\n', { plain = true })) do
        local prefix = line_index == 1 and '    in:  ' or '         '
        table.insert(lines, { { text = prefix .. input_line, hl = 'LeetCodeDim' } })
      end
    end

    if case.result ~= nil and not case.running then
      local runtime = case.result.runtime_ms
      if runtime ~= nil then
        table.insert(lines, {
          { text = ('    ran: %d ms'):format(tonumber(runtime) or 0), hl = 'LeetCodeDim' },
        })
      end

      local message = case.result.message
      if type(message) == 'string' and message ~= '' then
        message = message:gsub('%s+$', '')
        local hl = (case.status == 'failed' or case.status == 'error') and 'LeetCodeErr' or 'LeetCodeDim'
        for _, message_line in ipairs(vim.split(message, '\n', { plain = true })) do
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
  if not can_mutate(console) then return end
  if console.view ~= nil and not storage.write_testcases(console.view.slug, nil) then return end
  local testcases = console.view ~= nil and (console.view.detail or {}).testcases or {}
  console:set_cases(testcases)
  console:clear_results()
  console:refresh()
end

--- Add a new test case.
---
---@param console table
---@param input string|nil
LeetCodeConsole.add_case = function(console, input)
  if not can_mutate(console) then return end
  local cases = vim.list_extend({}, console.cases)
  table.insert(cases, new_case(LeetCodeConsole.normalize_input(input)))
  if not persist(console, cases) then return end

  console.cases = cases
  console.selected = #cases
  console:refresh()
end

--- Delete a test case.
---
---@param console table
---@param index number|nil Defaults to the selected case.
LeetCodeConsole.delete_case = function(console, index)
  if not can_mutate(console) then return end
  index = index or console.selected
  local cases = console.cases
  if #cases <= 1 or not console:is_valid_index(index) then return end

  local remaining = {}
  for case_index, case in ipairs(cases) do
    if case_index ~= index then table.insert(remaining, case) end
  end
  if not persist(console, remaining) then return end

  console.cases = remaining
  if index < console.selected then console.selected = console.selected - 1 end
  console.selected = math.min(console.selected, #remaining)
  console:refresh()
end

--- Edit a test case input.
---
---@param console table
---@param index number|nil Defaults to the selected case.
---@param input string|nil
LeetCodeConsole.edit_case = function(console, index, input)
  if not can_mutate(console) then return end
  index = index or console.selected
  if not console:is_valid_index(index) then return end

  local cases = vim.list_extend({}, console.cases)
  local case = vim.tbl_extend('force', {}, cases[index])
  case.input = LeetCodeConsole.normalize_input(input)
  case.status = 'unknown'
  case.result = nil
  cases[index] = case
  if not persist(console, cases) then return end

  console.cases = cases
  console:refresh()
end

--- Select the next test case.
---
---@param console table
LeetCodeConsole.select_next = function(console)
  if not can_mutate(console) or #console.cases == 0 then return end
  console.selected = (console.selected % #console.cases) + 1
  console:refresh()
end

--- Select the previous test case.
---
---@param console table
LeetCodeConsole.select_prev = function(console)
  if not can_mutate(console) or #console.cases == 0 then return end
  console.selected = ((console.selected - 2) % #console.cases) + 1
  console:refresh()
end

--- Clear submission and per-case results.
---
---@param console table
LeetCodeConsole.clear_results = function(console)
  console.submission_result = nil
  for _, case in ipairs(console.cases) do
    case.status = 'unknown'
    case.result = nil
    case.running = false
  end
end

--- Store a normalized result for a test case.
---
---@param console table
---@param index number
---@param result table
---@param refresh boolean|nil Set to false to batch rendering.
LeetCodeConsole.set_case_result = function(console, index, result, refresh)
  local case = console.cases[index]
  if case == nil or type(result) ~= 'table' then return end

  case.running = false
  case.result = result

  local correct = tonumber(result.correct) or 0
  local total = tonumber(result.total) or 0
  if result.status == 'Compile Error' or result.status == 'Invalid Testcase' then
    case.status = 'error'
  elseif result.is_submit == true then
    case.status = result.status == 'Accepted' and 'passed' or 'failed'
  elseif result.compare ~= nil then
    case.status = tostring(result.compare) == '1' and 'passed' or 'failed'
  elseif result.status == 'Accepted' then
    case.status = 'passed'
  elseif correct == total and total > 0 then
    case.status = 'passed'
  else
    case.status = 'failed'
  end

  if refresh ~= false then console:refresh() end
end

--- Request a re-render of the question view when the console changes.
---
---@param console table
LeetCodeConsole.refresh = function(console)
  if console.view == nil then return end
  require('leetcode-ui.question').refresh(console.view)
end

-- Refresh only when the console tab is visible.
local function refresh_visible(console)
  if console.view ~= nil and console.view.active == 'console' then console:refresh() end
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
        refresh_visible(console)
        return
      end

      console.frame = (console.frame % #LeetCodeConsole.spinner) + 1
      refresh_visible(console)
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
