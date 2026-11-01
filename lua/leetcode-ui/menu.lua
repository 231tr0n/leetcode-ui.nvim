-- |leetcode-ui-menu| Main menu view.
--------------------------------------------------------------------------------
-- An unlisted buffer listing entry points: daily question, random, problem
-- list, statistics, and open actions. Each row is mapped to its command.
--------------------------------------------------------------------------------

-- Module design:
local H = {}

local buffer = require('leetcode-ui.buffer')

-- Helper data =======================================================================================================

---Menu rows: [ label, description, handler ].
H.rows = function()
  return {
    { 'Daily', "Open today's daily question", function() require('leetcode-ui.picker').daily() end },
    { 'Random', 'Open a random question', function() require('leetcode-ui.picker').random() end },
    { 'Problems', 'Browse the problem list', function() require('leetcode-ui.picker').problem() end },
    { 'Statistics', 'View solve statistics', function() require('leetcode-ui.stats_view').open() end },
    { 'Session', 'Show session/status details', function() require('leetcode-ui.stats_view').session() end },
  }
end

-- Helper functionality =============================================================================================

---Render the menu buffer.
H.render = function()
  local lines = {}

  table.insert(lines, { { text = 'LeetCode', hl = 'LeetCodeTitle' } })
  table.insert(lines, {})
  for _, row in ipairs(H.rows()) do
    table.insert(lines, {
      { text = '  ' .. string.format('%-11s', row[1]), hl = 'LeetCodeCode' },
      { text = row[2], hl = 'LeetCodeDim' },
    })
  end
  table.insert(lines, {})
  table.insert(lines, { { text = '  <CR> open current row', hl = 'LeetCodeDim' } })

  buffer.spans_write(H.bufnr, lines, false)
end

---Bind `<CR>`-driven row execution by cursor line.
H.bind_cr = function()
  buffer.keymap(H.bufnr, '<CR>', function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local row = H.rows()[lnum - 3]
    if row ~= nil and type(row[3]) == 'function' then row[3]() end
  end, 'Open menu entry')
end

-- Public API ========================================================================================================

---Open (or refocus) the menu.
H.open = function()
  local winid = vim.fn.bufwinnr(H.bufnr or -1)
  if winid ~= -1 then
    vim.cmd(('%dwincmd w'):format(winid))
    return
  end

  H.bufnr = buffer.scratch('leetcode-ui://menu', { ft = 'txt' })
  H.render()
  H.bind_cr()

  buffer.open_split(H.bufnr, {
    pos = 'left',
    width = math.max(vim.o.columns / 6, 50),
    focus = true,
  })
end

return H
