--- *LeetCodeStatsApi*
---
---@tag LeetCodeStatsApi

-- |leetcode-ui-api-stats| User statistics wrappers.
-- Wrappers around the `matchedUser`-based queries: solved counts, calendar
-- (streak + passive heatmap data), skills, language stats, and streak counter.

-- Module design:
local LeetCodeStatsApi = {}

local api = require('leetcode-ui.api')
local auth = require('leetcode-ui.auth')
local queries = require('leetcode-ui.api.queries')

-- Helper functionality ==============================================================================================

LeetCodeStatsApi.username = function()
  local session, err = auth.verify()
  if err ~= nil or session == nil then return nil, err or 'No session' end
  if not session.signed_in or session.name == nil then return nil, 'Not signed in (check cookies)' end
  return session.name, nil
end

-- Public API ========================================================================================================

---Solved/accepted counts by difficulty against totals.
---
---@return table|nil { all = {...}, easy = {...}, medium = {...}, hard = {...} }
---@return string|nil err
LeetCodeStatsApi.solved = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, qerr = api.graphql(queries.solved, { username = name })
  if qerr ~= nil or data == nil then return nil, qerr or 'Empty response' end

  local total = {}
  for _, row in ipairs(data.allQuestionsCount or {}) do
    total[row.difficulty] = row.count
  end

  local matched = data.matchedUser or {}
  local solved = {}
  for _, row in ipairs((matched.solved_counts or {}).acSubmissionNum or {}) do
    solved[row.difficulty] = row.count
  end

  return { total = total, solved = solved }, nil
end

---Calendar data for the activity heatmap, plus solving percentiles.
---
---@param year number|nil
---@return table|nil { calendar = {...}, beats = {...} }
---@return string|nil err
LeetCodeStatsApi.calendar = function(year)
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, qerr = api.graphql(queries.calendar, { username = name, year = year })
  if qerr ~= nil or data == nil then return nil, qerr or 'Empty response' end

  local matched = data.matchedUser or {}
  local calendar = matched.calendar or {}
  local submission_calendar = calendar.submission_calendar
  if type(submission_calendar) == 'string' then
    local ok, decoded = pcall(vim.json.decode, submission_calendar)
    calendar.submission_calendar = ok and decoded or {}
  end

  return {
    calendar = calendar,
    beats = matched.solved_beats or {},
  }, nil
end

---Skill tag statistics.
---
---@return table|nil { advanced = {...}, intermediate = {...}, fundamental = {...} }
---@return string|nil err
LeetCodeStatsApi.skills = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, qerr = api.graphql(queries.skills, { username = name })
  if qerr ~= nil or data == nil then return nil, qerr or 'Empty response' end

  return (data.matchedUser or {}).tag_problems_counts or {}, nil
end

---Solved problems per language.
---
---@return table|nil { { language_name, problems_solved }, ... }
---@return string|nil err
LeetCodeStatsApi.languages = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, qerr = api.graphql(queries.languages, { username = name })
  if qerr ~= nil or data == nil then return nil, qerr or 'Empty response' end

  return (data.matchedUser or {}).language_problem_count or {}, nil
end

---Streak counter for the current session user.
---
---@return table|nil { streak_count, days_skipped, today_completed }
---@return string|nil err
LeetCodeStatsApi.streak = function()
  local data, err = api.graphql(queries.streak)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end
  if data.streakCounter == nil then return nil, 'Streak counter not available' end
  return data.streakCounter, nil
end

return LeetCodeStatsApi
