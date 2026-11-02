--- *leetcode-ui-stats-view* Statistics view
---
--- Progress meters by difficulty, language breakdown, skill tags, and session
--- information. Rendered in the central |LeetCodeUI| window.
---
---@tag LeetCodeStatsView
---@toc_entry Statistics view

local LeetCodeStatsView = {}

local auth = require('leetcode-ui.auth')
local log = require('leetcode-ui.log')
local stats = require('leetcode-ui.api.stats')
local ui = require('leetcode-ui.ui')

-- Helper data =======================================================================================================

LeetCodeStatsView.difficulty_hl = {
  Easy = 'LeetCodeEasy',
  Medium = 'LeetCodeMedium',
  Hard = 'LeetCodeHard',
}

-- Helper functionality =============================================================================================

LeetCodeStatsView.as = function(fn) return require('leetcode-ui.async').run(fn) end

--- Build one difficulty progress meter.
---
---@param label string
---@param solved number
---@param total number
---@param width number|nil
---@return table spans
LeetCodeStatsView.meter = function(label, solved, total, width)
  width = width or 24
  local ratio = total > 0 and math.min(solved / total, 1) or 0
  local filled = math.floor(ratio * width + 0.5)

  local hl = LeetCodeStatsView.difficulty_hl[label] or 'LeetCodeTitle'
  return {
    { text = ('%-10s'):format(label), hl = hl },
    { text = ('%4d/%4d'):format(solved, total), hl = 'LeetCodeTitle' },
    { text = '  ', hl = nil },
    { text = ('█'):rep(filled), hl = hl },
    { text = ('░'):rep(width - filled), hl = 'LeetCodeDim' },
    { text = (' %3d%%'):format(math.floor(ratio * 100 + 0.5)), hl = 'LeetCodeDim' },
  }
end

--- Build language breakdown lines.
---
---@param rows table|nil
---@return table lines
LeetCodeStatsView.language_lines = function(rows)
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

--- Build skill-tag lines.
---
---@param tags table|nil
---@return table lines
LeetCodeStatsView.skills_lines = function(tags)
  tags = tags or {}
  local lines = { { { text = 'Skills', hl = 'LeetCodeTitle' } } }
  local sections = {
    { 'Advanced', tags.advanced or {} },
    { 'Intermediate', tags.intermediate or {} },
    { 'Fundamental', tags.fundamental or {} },
  }

  for _, section in ipairs(sections) do
    local name, rows = section[1], section[2]
    table.sort(rows, function(a, b) return (a.problems_solved or 0) > (b.problems_solved or 0) end)
    if #rows > 0 then
      table.insert(lines, {})
      table.insert(lines, { { text = ('  %s'):format(name), hl = 'LeetCodeLink' } })
      for index, row in ipairs(rows) do
        if index > 10 then break end
        table.insert(lines, {
          { text = ('    %-28s'):format(row.tag_name or ''), hl = nil },
          { text = ('%d'):format(row.problems_solved or 0), hl = 'LeetCodeTitle' },
        })
      end
    end
  end
  return lines
end

--- Build all statistics lines.
---
---@param solved table|nil
---@param languages table|nil
---@param skills table|nil
---@param err string|nil
---@param session table|nil
---@param streak table|nil
---@return table lines
LeetCodeStatsView.build_lines = function(solved, languages, skills, err, session, streak)
  local lines = {
    {
      { text = 'Progress   ', hl = 'LeetCodeTitle' },
      { text = 'leetcode.com', hl = 'LeetCodeDim' },
    },
  }

  if session ~= nil and session.signed_in then
    table.insert(lines, {
      { text = 'Signed in  ', hl = 'LeetCodeDim' },
      { text = session.name or 'unknown', hl = 'LeetCodeOk' },
      {
        text = streak ~= nil and ('  streak: %d day(s)'):format(tonumber(streak.streak_count) or 0) or '',
        hl = 'LeetCodeDim',
      },
    })
  else
    table.insert(
      lines,
      { { text = 'Not signed in (configure cookies to see personal statistics)', hl = 'LeetCodeWarn' } }
    )
  end

  local counts = (solved or {}).solved or {}
  local totals = (solved or {}).total or {}
  table.insert(lines, {})
  for _, difficulty in ipairs({ 'Easy', 'Medium', 'Hard' }) do
    table.insert(lines, LeetCodeStatsView.meter(difficulty, counts[difficulty] or 0, totals[difficulty] or 0))
  end

  if languages ~= nil then
    table.insert(lines, {})
    vim.list_extend(lines, LeetCodeStatsView.language_lines(languages))
  end
  if skills ~= nil then vim.list_extend(lines, LeetCodeStatsView.skills_lines(skills)) end

  if err ~= nil then
    table.insert(lines, {})
    table.insert(lines, {
      { text = 'Sign-in required: ', hl = 'LeetCodeErr' },
      { text = err, hl = 'LeetCodeDim' },
    })
  end
  return lines
end

-- Public API ========================================================================================================

--- Open the statistics view.
LeetCodeStatsView.open = function()
  ui.render({ { { text = 'Loading statistics…', hl = 'LeetCodeDim' } } })
  log.info('Loading statistics…')

  LeetCodeStatsView.as(function()
    local session = select(1, auth.verify())
    local solved, err = stats.solved()
    local languages, skills, streak = nil, nil, nil

    if err == nil then
      languages = select(1, stats.languages())
      skills = select(1, stats.skills())
      if session ~= nil and session.signed_in then streak = select(1, stats.streak()) end
    end

    ui.render(LeetCodeStatsView.build_lines(solved, languages, skills, err, session, streak))
    if err ~= nil then
      log.warn('Statistics unavailable: ' .. err)
    else
      log.info('Statistics loaded')
    end
  end)
end

--- Show session details in a notification.
LeetCodeStatsView.session = function()
  log.info('Checking session…')
  LeetCodeStatsView.as(function()
    local session, err = auth.verify()
    if err ~= nil or session == nil then
      log.warn('Session check failed: ' .. (err or 'Empty response'))
      return
    end

    local streak = nil
    if session.signed_in then streak = select(1, stats.streak()) end
    local message = session.signed_in and session.name or 'anonymous'
    message = message .. (session.is_premium and ' (premium)' or '')
    if streak ~= nil then message = message .. ('  streak: %d'):format(tonumber(streak.streak_count) or 0) end
    log.notify(message, session.signed_in and vim.log.levels.INFO or vim.log.levels.WARN)
  end)
end

--- Close the central window.
LeetCodeStatsView.close = function() ui.close() end

return LeetCodeStatsView
