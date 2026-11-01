--- *leetcode-ui-console* Test case console UI
---
---@tag LeetCodeConsole
---

-- |leetcode-ui-console| Test case console UI.
-- A scrollable bottom pane showing one row per test case: case number, status
-- icon, and a result line (runtime/memory/stdout) once judging finishes.
-- State is a plain table; |leetcode-ui-question| drives it from results of
-- |leetcode-ui-api-runner|.

-- Module design:
local LeetCodeConsole = {}

local config = require('leetcode-ui.config')
local buffer = require('leetcode-ui.buffer')

-- Helper data =======================================================================================================

LeetCodeConsole.spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

LeetCodeConsole.header = 'Testcase'

-- Helper functionality ==============================================================================================

LeetCodeConsole.new = function(view)
  return setmetatable({ view = view, cases = {}, selected = 1, timer = nil, frame = 1 }, { __index = LeetCodeConsole })
end

LeetCodeConsole.set_cases = function(console, testcase_list)
  local cases = {}
  for _, input in ipairs(testcase_list) do
    table.insert(cases, { input = input, status = 'unknown', result = nil, running = false, index = #cases + 1 })
  end
  if #cases == 0 then
    table.insert(cases, { input = '', status = 'unknown', result = nil, running = false, index = 1 })
  end
  console.cases = cases
  console.selected = 1
end

LeetCodeConsole.render = function(console)
  if console.bufnr == nil then return end

  local icons = config.config.icons.case
  local lines = {}

  local header = { { text = LeetCodeConsole.header, hl = 'LeetCodeTitle' } }
  table.insert(lines, header)
  table.insert(lines, { { text = '  (use \\n for multi-line input)', hl = 'LeetCodeDim' } })

  if console.submission_result ~= nil then
    local sr = console.submission_result
    local icon = sr.ok and '✔' or '✘'
    local hl = sr.ok and 'LeetCodeOk' or 'LeetCodeErr'
    table.insert(lines, {
      { text = 'Submission: ', hl = 'LeetCodeDim' },
      { text = icon .. ' ' .. (sr.status or ''), hl = hl },
    })
    if sr.runtime_ms ~= nil then
      table.insert(lines, {
        {
          text = ('  Runtime: %d ms  Memory: %.2f MB'):format(
            tonumber(sr.runtime_ms or 0),
            (sr.memory_mb or 0) / (1024 * 1024)
          ),
          hl = 'LeetCodeDim',
        },
      })
    end
    table.insert(lines, {})
  end

  for i, case in ipairs(console.cases) do
    local icon, icon_hl = 'unknown', 'LeetCodeDim'

    if case.running then
      icon, icon_hl = LeetCodeConsole.spinner[console.frame], 'LeetCodeWarn'
    elseif case.status == 'passed' then
      icon, icon_hl = icons.passed, 'LeetCodeOk'
    elseif case.status == 'failed' then
      icon, icon_hl = icons.failed, 'LeetCodeErr'
    elseif case.status == 'error' then
      icon, icon_hl = icons.err, 'LeetCodeErr'
    end

    local marker = i == console.selected and config.config.icons.status.active or ' '
    table.insert(lines, {
      { text = marker .. ' ', hl = i == console.selected and 'LeetCodeTitle' or nil },
      { text = icon .. ' ', hl = icon_hl },
      { text = ('Case %d'):format(i), hl = i == console.selected and 'LeetCodeTitle' or nil },
    })

    if case.input ~= nil and case.input ~= '' then
      for _, input_line in ipairs(vim.split(case.input, '\n')) do
        table.insert(lines, { { text = '    in:  ' .. input_line, hl = 'LeetCodeDim' } })
      end
    end

    if case.result ~= nil and case.status ~= 'unknown' and not case.running then
      local parts = { { text = '    ', hl = nil } }
      if case.result.runtime_ms ~= nil then
        table.insert(parts, { text = ('%d ms  '):format(tonumber(case.result.runtime_ms) or 0), hl = 'LeetCodeDim' })
      end
      local message = case.result.message
      if message ~= nil then message = message:gsub('%s+$', '') end
      if message ~= nil and message ~= '' then
        local message_lines = vim.split(message, '\n')
        for j, message_line in ipairs(message_lines) do
          table.insert(parts, { text = message_line, hl = 'LeetCodeErr' })
          if j < #message_lines then
            table.insert(lines, parts)
            parts = { { text = '    ', hl = nil } }
          end
        end
      end
      table.insert(lines, parts)

      local output = case.result.stdout or case.result.pretty_stdout
      if (output == nil or output == '') and case.result.message == nil then
        -- Fall back to compare bit for run-all results.
        if case.result.compare ~= nil then output = (case.result.compare == '1') and 'Accepted' or 'Wrong Answer' end
      end
      if output ~= nil and output ~= '' then
        for _, output_line in ipairs(vim.split(output, '\n')) do
          table.insert(lines, { { text = '    out: ' .. output_line, hl = 'LeetCodeDim' } })
        end
      end
    end
  end

  buffer.spans_write(console.bufnr, lines, false)
end

LeetCodeConsole.case_running = function(console, index)
  local case = console.cases[index]
  if case == nil then return end
  case.running = true
  case.status = 'unknown'
  case.result = nil
  console.selected = index
  console:start_spinner()
end

---Add a new test case with the given input.
---
---@param console table
---@param input string
LeetCodeConsole.add_case = function(console, input)
  input = input or ''
  -- Allow multi-line test cases to be entered on a single prompt line using
  -- the literal sequence "\n" (e.g. "[2,7,11,15]\n9").
  input = input:gsub('\\\\n', '\n')
  local cases = console.cases or {}
  table.insert(cases, { input = input, status = 'unknown', result = nil, running = false, index = #cases + 1 })
  console.cases = cases
  console.selected = #cases
  console:render()
end

LeetCodeConsole.delete_case = function(console, index)
  index = index or console.selected
  local cases = console.cases or {}
  if index == nil or index < 1 or index > #cases then return end
  if #cases <= 1 then return end
  table.remove(cases, index)
  for i, case in ipairs(cases) do
    case.index = i
  end
  console.cases = cases
  if console.selected > #cases then console.selected = #cases end
  if console.selected < 1 then console.selected = 1 end
  console:render()
end

LeetCodeConsole.edit_case = function(console, index, input)
  index = index or console.selected
  local case = (console.cases or {})[index]
  if case == nil then return end
  input = input or ''
  input = input:gsub('\\\\n', '\n')
  case.input = input
  case.status = 'unknown'
  case.result = nil
  console:render()
end

LeetCodeConsole.select_next = function(console)
  local cases = console.cases or {}
  if #cases == 0 then return end
  console.selected = (console.selected % #cases) + 1
  console:render()
end

LeetCodeConsole.select_prev = function(console)
  local cases = console.cases or {}
  if #cases == 0 then return end
  console.selected = ((console.selected - 2) % #cases) + 1
  console:render()
end

LeetCodeConsole.case_result = function(console, index, result)
  local case = console.cases[index]
  if case == nil then return end

  case.running = false
  case.result = result

  local correct, total = result.correct or 0, result.total or 0
  if result.status == 'Compile Error' then
    case.status = 'error'
  elseif result.is_submit == true then
    case.status = result.status == 'Accepted' and 'passed' or 'failed'
  elseif result.compare ~= nil then
    -- Per-case compare bit: last char of `compare_result`.
    case.status = result.compare:sub(-1) == '1' and 'passed' or 'failed'
  elseif correct == total and total > 0 then
    case.status = 'passed'
  else
    case.status = 'failed'
  end

  console:render()
end

LeetCodeConsole.start_spinner = function(console)
  if console.timer ~= nil then return end

  console.frame = 1
  local timer = vim.uv.new_timer()
  if timer == nil then return end
  console.timer = timer
  timer:start(0, 80, function()
    vim.schedule(function()
      if console.bufnr == nil or not vim.api.nvim_buf_is_valid(console.bufnr) then
        timer:stop()
        timer:close()
        console.timer = nil
        return
      end
      local running = false
      for _, case in ipairs(console.cases) do
        if case.running then
          running = true
          break
        end
      end
      if not running then
        timer:stop()
        timer:close()
        console.timer = nil
        console:render()
        return
      end
      console.frame = (console.frame % #LeetCodeConsole.spinner) + 1
      console:render()
    end)
  end)
end

LeetCodeConsole.stop_spinner = function(console)
  if console.timer ~= nil then
    console.timer:stop()
    console.timer:close()
    console.timer = nil
  end
end

LeetCodeConsole.open = function(console)
  if console.bufnr ~= nil and vim.api.nvim_buf_is_valid(console.bufnr) then return end

  console.bufnr = buffer.scratch('leetcode-ui://console/' .. (console.view.slug or ''), { ft = 'txt' })
  vim.api.nvim_set_option_value('modifiable', false, { buf = console.bufnr })

  buffer.keymaps(console.bufnr, {
    close = {
      rhs = function()
        if console.view then require('leetcode-ui.question').close(console.view) end
      end,
      desc = 'Close question',
    },
  })

  console:render()

  vim.keymap.set('n', '<Tab>', function()
    if console.view then require('leetcode-ui.question').cycle_tab(console.view, 1) end
  end, { buffer = console.bufnr, silent = true })
  vim.keymap.set('n', '<S-Tab>', function()
    if console.view then require('leetcode-ui.question').cycle_tab(console.view, -1) end
  end, { buffer = console.bufnr, silent = true })
end

LeetCodeConsole.close = function(console)
  buffer.maybe_delete(console.bufnr)
  console.bufnr = nil
  console.winid = nil
  console:stop_spinner()
end

LeetCodeConsole.toggle = function(console)
  if console.bufnr ~= nil then
    console:close()
  else
    console:open()
  end
end

return LeetCodeConsole
