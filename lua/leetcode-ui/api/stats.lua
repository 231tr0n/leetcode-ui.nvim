--- *leetcode-ui-api-stats* User statistics wrappers
---
--- Wrappers around LeetCode statistics queries: solved counts, skills,
--- language statistics, and the streak counter.
---@tag LeetCodeStatsApi
---@toc_entry Statistics API

local LeetCodeStatsApi = {}

local api = require('leetcode-ui.api')
local auth = require('leetcode-ui.auth')
local queries = require('leetcode-ui.api.queries')

-- Helper functionality =============================================================================================

--- Verified username for the current session.
---
---@return string|nil username
---@return string|nil err
LeetCodeStatsApi.username = function()
  local session, err = auth.verify()
  if err ~= nil or session == nil then return nil, err or 'No session' end
  if not session.signed_in or type(session.name) ~= 'string' or session.name == '' then
    return nil, 'Not signed in (check cookies)'
  end
  return session.name, nil
end

-- Public API ========================================================================================================

--- Solved/accepted counts by difficulty against totals.
---
---@return table|nil counts `total` and `solved` maps by difficulty.
---@return string|nil err
LeetCodeStatsApi.solved = function()
  local name, err = LeetCodeStatsApi.username()
  if err ~= nil then return nil, err end

  local data, query_err = api.graphql(queries.solved, { username = name })
  if query_err ~= nil or data == nil then return nil, query_err or 'Empty response' end

  local total = {}
  local all_counts = type(data.allQuestionsCount) == 'table' and data.allQuestionsCount or {}
  for _, row in ipairs(all_counts) do
    if type(row) == 'table' and row.difficulty ~= nil then total[row.difficulty] = row.count end
  end

  local solved = {}
  if type(data.matchedUser) ~= 'table' then return nil, 'User statistics are not available' end
  local matched = data.matchedUser
  local solved_counts = type(matched.solved_counts) == 'table' and matched.solved_counts or {}
  local accepted = type(solved_counts.acSubmissionNum) == 'table' and solved_counts.acSubmissionNum or {}
  for _, row in ipairs(accepted) do
    if type(row) == 'table' and row.difficulty ~= nil then solved[row.difficulty] = row.count end
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

  local matched = type(data.matchedUser) == 'table' and data.matchedUser or {}
  return type(matched.tag_problems_counts) == 'table' and matched.tag_problems_counts or {}, nil
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

  local matched = type(data.matchedUser) == 'table' and data.matchedUser or {}
  return type(matched.language_problem_count) == 'table' and matched.language_problem_count or {}, nil
end

--- Streak counter for the current session user.
---
---@return table|nil { streak_count }
---@return string|nil err
LeetCodeStatsApi.streak = function()
  local data, err = api.graphql(queries.streak)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end
  if type(data.streakCounter) ~= 'table' then return nil, 'Streak counter is not available' end
  return data.streakCounter, nil
end

return LeetCodeStatsApi
