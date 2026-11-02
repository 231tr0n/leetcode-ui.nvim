--- *leetcode-ui-api-stats* User statistics wrappers
---
--- Wrappers around the `matchedUser`-based queries: solved counts, skills,
--- language statistics, and the streak counter.
---
---@tag LeetCodeStatsApi
---@toc_entry Statistics API

local LeetCodeStatsApi = {}

local api = require('leetcode-ui.api')
local auth = require('leetcode-ui.auth')
local queries = require('leetcode-ui.api.queries')

-- Helper functionality =============================================================================================

LeetCodeStatsApi.username = function()
  local session, err = auth.verify()
  if err ~= nil or session == nil then return nil, err or 'No session' end
  if not session.signed_in or session.name == nil then return nil, 'Not signed in (check cookies)' end
  return session.name, nil
end

-- Public API ========================================================================================================

--- Solved/accepted counts by difficulty against totals.
---
---@return table|nil { total = { [difficulty] = number }, solved = { [difficulty] = number } }
---@return string|nil err
LeetCodeStatsApi.solved = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, query_err = api.graphql(queries.solved, { username = name })
  if query_err ~= nil or data == nil then return nil, query_err or 'Empty response' end

  local total = {}
  for _, row in ipairs(data.allQuestionsCount or {}) do
    total[row.difficulty] = row.count
  end

  local solved = {}
  local matched = data.matchedUser or {}
  for _, row in ipairs((matched.solved_counts or {}).acSubmissionNum or {}) do
    solved[row.difficulty] = row.count
  end

  return { total = total, solved = solved }, nil
end

--- Skill tag statistics.
---
---@return table|nil { advanced = {...}, intermediate = {...}, fundamental = {...} }
---@return string|nil err
LeetCodeStatsApi.skills = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, query_err = api.graphql(queries.skills, { username = name })
  if query_err ~= nil or data == nil then return nil, query_err or 'Empty response' end

  return (data.matchedUser or {}).tag_problems_counts or {}, nil
end

--- Solved problems per language.
---
---@return table|nil { { language_name, problems_solved }, ... }
---@return string|nil err
LeetCodeStatsApi.languages = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, query_err = api.graphql(queries.languages, { username = name })
  if query_err ~= nil or data == nil then return nil, query_err or 'Empty response' end

  return (data.matchedUser or {}).language_problem_count or {}, nil
end

--- Streak counter for the current session user.
---
---@return table|nil { streak_count, days_skipped, today_completed }
---@return string|nil err
LeetCodeStatsApi.streak = function()
  local data, err = api.graphql(queries.streak)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end
  if data.streakCounter == nil then return nil, 'Streak counter is not available' end
  return data.streakCounter, nil
end

return LeetCodeStatsApi
