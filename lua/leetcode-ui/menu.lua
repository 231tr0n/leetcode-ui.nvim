--- *leetcode-ui-menu* Main menu view
---
---@tag LeetCodeMenu
---

-- |leetcode-ui-menu| Main menu view.
-- An unlisted buffer listing entry points: daily question, random, problem
-- list, statistics, and open actions. Each row is mapped to its command.

-- Module design:
local LeetCodeMenu = {}

local buffer = require('leetcode-ui.buffer')

-- Helper data =======================================================================================================

LeetCodeMenu.rows = function()
  return {
    { 'Daily', "Open today's daily question", function() require('leetcode-ui.picker').daily() end },
    { 'Random', 'Open a random question', function() require('leetcode-ui.picker').random() end },
    { 'Problems', 'Browse the problem list', function() require('leetcode-ui.picker').problem() end },
    { 'Statistics', 'View solve statistics', function() require('leetcode-ui.stats_view').open() end },
    { 'Session', 'Show session/status details', function() require('leetcode-ui.stats_view').session() end },
  }
end

-- Helper functionality =============================================================================================

LeetCodeMenu.render = function()
  local lines = {}

  table.insert(lines, { { text = 'LeetCode', hl = 'LeetCodeTitle' } })
  table.insert(lines, {})
  for _, row in ipairs(LeetCodeMenu.rows()) do
    table.insert(lines, {
      { text = '  ' .. string.format('%-11s', row[1]), hl = 'LeetCodeCode' },
      { text = row[2], hl = 'LeetCodeDim' },
    })
  end
  table.insert(lines, {})
  table.insert(lines, { { text = '  <CR> open current row', hl = 'LeetCodeDim' } })

  buffer.spans_write(LeetCodeMenu.bufnr, lines, false)
end

LeetCodeMenu.bind_cr = function()
  buffer.keymap(LeetCodeMenu.bufnr, '<CR>', function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local row = LeetCodeMenu.rows()[lnum - 2]
    if row ~= nil and type(row[3]) == 'function' then row[3]() end
  end, 'Open menu entry')
end

-- Public API ========================================================================================================

---Open (or refocus) the menu.
LeetCodeMenu.open = function()
  local winid = vim.fn.bufwinnr(LeetCodeMenu.bufnr or -1)
  if winid ~= -1 then
    vim.cmd(('%dwincmd w'):format(winid))
    return
  end

  LeetCodeMenu.bufnr = buffer.scratch('leetcode-ui://menu', { ft = 'txt' })
  LeetCodeMenu.render()
  LeetCodeMenu.bind_cr()

  buffer.open_float(LeetCodeMenu.bufnr, {
    width = math.max(vim.o.columns / 6, 50),
    height = 12,
    focus = true,
    title = ' LeetCode ',
  })
end

return LeetCodeMenu
