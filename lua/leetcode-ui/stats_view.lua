-- |leetcode-ui-stats-view| Statistics view.
--------------------------------------------------------------------------------
-- Progress meters by difficulty, language breakdown, and skill tags, plus a
-- signed-in session line. Requires cookies; renders guidance when anonymous.
--------------------------------------------------------------------------------

local H = {}

local buffer = require('leetcode-ui.buffer')
local auth = require('leetcode-ui.auth')
local stats = require('leetcode-ui.api.stats')

-- Helper functionality =============================================================================================

---Difficulties and their highlight groups.
H.difficulty_hl = { Easy = 'LeetCodeEasy', Medium = 'LeetCodeMedium', Hard = 'LeetCodeHard' }

---Run a function in a coroutine (error-safe driver, mirrors question.h).
---
---@private
H.as = function(fn) return require('leetcode-ui.async').run(fn) end

---A progress meter line.
---
---@param label string Difficulty label.
---@param solved number
---@param total number
---@param width number|nil
---@return table Line spans.
H.meter = function(label, solved, total, width)
  width = width or 28
  local ratio = total > 0 and math.min(solved / total, 1) or 0
  local filled = math.floor(ratio * width + 0.5)

  local hl = H.difficulty_hl[label] or 'LeetCodeTitle'
  return {
    { text = ('%-8s'):format(label), hl = hl },
    { text = ('%3d/%-3d'):format(solved, total), hl = 'LeetCodeTitle' },
    { text = ('█'):rep(filled), hl = hl },
    { text = ('─'):rep(width - filled), hl = 'LeetCodeDim' },
    { text = (' %2d%%'):format(math.floor(ratio * 100 + 0.5)), hl = 'LeetCodeDim' },
  }
end

---Language breakdown section spans.
---
---@param rows table [{language_name, problems_solved}]
---@return table lines
H.language_lines = function(rows)
  local lines = { { { text = 'Languages', hl = 'LeetCodeTitle' } } }

  table.sort(rows or {}, function(a, b) return (a.problems_solved or 0) > (b.problems_solved or 0) end)
  for _, row in ipairs(rows or {}) do
    table.insert(lines, {
      { text = ('  %-12s'):format(tostring(row.language_name)), hl = 'LeetCodeCode' },
      { text = ('%d'):format(row.problems_solved or 0), hl = 'LeetCodeTitle' },
    })
  end
  return lines
end

---Skills section spans.
---
---@param tags table tagProblemCounts result.
---@return table lines
H.skills_lines = function(tags)
  tags = tags or {}
  local lines = { { { text = 'Skills', hl = 'LeetCodeTitle' } } }

  local sections = {
    { 'Advanced', tags.advanced or {} },
    { 'Intermediate', tags.intermediate or {} },
    { 'Fundamental', tags.fundamental or {} },
  }

  for _, section in ipairs(sections) do
    local name, rows = section[1], section[2] or {}
    table.sort(rows, function(x, y) return (x.problems_solved or 0) > (y.problems_solved or 0) end)
    if #rows > 0 then
      table.insert(lines, {})
      table.insert(lines, { { text = ('  %s'):format(name), hl = 'LeetCodeLink' } })
      for i, row in ipairs(rows) do
        if i > 10 then break end
        table.insert(lines, {
          { text = ('    %-28s'):format(row.tag_name or ''), hl = nil },
          { text = ('%d'):format(row.problems_solved or 0), hl = 'LeetCodeTitle' },
        })
      end
    end
  end
  return lines
end

---Fetch all stats and render into `bufnr`.
---
---@param bufnr number
H.render_stats = function(bufnr)
  H.as(function()
    local solved, solved_err = stats.solved()
    local langs = nil
    local skills = nil

    if solved_err == nil then
      langs = select(1, stats.languages())
      skills = select(1, stats.skills())
    end

    local counts = (solved or {}).solved or {}
    local total = (solved or {}).total or {}

    local lines = { { { text = 'Progress   ', hl = 'LeetCodeTitle' }, { text = 'leetcode.com', hl = 'LeetCodeDim' } } }
    table.insert(lines, {})
    for _, difficulty in ipairs({ 'Easy', 'Medium', 'Hard' }) do
      table.insert(lines, H.meter(difficulty, counts[difficulty] or 0, total[difficulty] or 0))
    end

    if langs ~= nil then
      table.insert(lines, {})
      vim.list_extend(lines, H.language_lines(langs))
    end

    if skills ~= nil then vim.list_extend(lines, H.skills_lines(skills)) end

    -- Failure note at the end (helps when partially signed in / flaky net).
    local err = solved_err
    if err ~= nil then
      table.insert(lines, {})
      table.insert(lines, { { text = 'Sign-in required: ', hl = 'LeetCodeErr' }, { text = err, hl = 'LeetCodeDim' } })
    end

    buffer.spans_write(bufnr, lines, false)
  end)
end

-- Public API ========================================================================================================

---Open the statistics split.
H.open = function()
  if H.bufnr == nil then H.bufnr = buffer.scratch('leetcode-ui://stats', { ft = 'txt' }) end

  buffer.open_split(H.bufnr, {
    pos = 'left',
    width = 62,
    focus = true,
  })

  buffer.keymaps(H.bufnr, {
    close = {
      rhs = function() H.close() end,
      desc = 'Close statistics',
    },
  })

  H.render_stats(H.bufnr)
end

---Session details (user + streak) in a notification.
H.session = function()
  H.as(function()
    local session, err = auth.verify()
    if err ~= nil then
      vim.schedule(function() vim.notify('(leetcode-ui) ' .. err, vim.log.levels.WARN) end)
      return
    end
    if session == nil then return end

    local streak = select(1, stats.streak())
    vim.schedule(
      function()
        vim.notify(
          ('leetcode-ui: %s%s%s'):format(
            session.signed_in and session.name or 'anonymous',
            session.is_premium and ' (premium)' or '',
            streak ~= nil and ('  streak: %d'):format(tonumber(streak.streak_count) or 0) or ''
          ),
          session.signed_in and vim.log.levels.INFO or vim.log.levels.WARN
        )
      end
    )
  end)
end

---Close the statistics buffer, if open.
H.close = function()
  local winid = vim.fn.bufwinnr(H.bufnr or -1)
  if winid ~= -1 then vim.api.nvim_win_close(vim.fn.win_getid(winid), false) end
end

return H
