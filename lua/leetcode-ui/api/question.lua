-- |leetcode-ui-api-question| Problem list, daily, random, and question detail.
--------------------------------------------------------------------------------
-- Normalized shapes (snake_case, `vim.NIL` inputs sanitized):
--   list entries: { title, title_slug, frontend_id, difficulty, ac_rate,
--                   is_paid_only, status, topic_tags = { {name,slug}, ... } }
--   detail:       { id, frontend_id, title, title_slug, is_paid_only,
--                   difficulty, content, hints, snippets = { lang_slug = {...} },
--                   testcases = { string, ... }, meta = parsed metaData table,
--                   stats = parsed `stats` table, similar = { ... } }
--------------------------------------------------------------------------------

-- Module design:
local H = {}

local config = require('leetcode-ui.config')
local api = require('leetcode-ui.api')
local queries = require('leetcode-ui.api.queries')
local storage = require('leetcode-ui.storage')

-- Helper functionality ==============================================================================================

---Sanitize decoded GraphQL rows (`vim.NIL` -> nil, missing -> fallback).
---
---@param value any
---@return any
H.clean = function(value)
  if api.is_nillish(value) then return nil end
  if type(value) ~= 'table' then return value end

  local res = {}
  for key, entry in pairs(value) do
    if type(entry) ~= 'table' and api.is_nillish(entry) then
      res[key] = nil
    else
      res[key] = H.clean(entry)
    end
  end
  return res
end

---Parse JSON encoded response fields.
---
---@param s any JSON-encoded string or nil.
---@return any|nil
H.decode_meta = function(s)
  if s == nil or type(s) ~= 'string' or s == '' then return nil end
  local ok, data = pcall(vim.json.decode, s)
  if not ok then return nil end
  return data
end

-- Public API ========================================================================================================

---Normalize a single `questionList` row.
---
---@param q table GraphQL row.
---@return table Normalized entry.
H.normalize = function(q)
  local status = q.status
  status = status == 'AC' and 'solved' or status
  status = status == 'null' and nil or status

  local tags = {}
  for _, tag in ipairs(q.topic_tags or {}) do
    table.insert(tags, { name = tag.name, slug = tag.slug })
  end

  return {
    title = q.title,
    title_slug = q.title_slug,
    frontend_id = q.frontend_id ~= nil and tostring(q.frontend_id) or '',
    difficulty = q.difficulty,
    ac_rate = q.ac_rate or 0,
    is_paid_only = q.is_paid_only == true,
    status = status,
    topic_tags = tags,
  }
end

---Fetch the full problem list (single bulk query), cached in storage.
---
---Cached for |leetcode-ui-opt.cooldown| minutes per domain; temporarily refined
---with solved marks after successful submissions inside this session.
---
---@return table|nil { total, questions }
---@return string|nil err
H.get_list = function()
  local cache = storage.read_cache()
  local edge = cache['cache_time'] or cache['saved'] or 0
  local fresh = (os.time() - edge) < (config.config.cooldown * 60)

  if fresh and type(cache.problems) == 'table' and #cache.problems > 0 then
    return { total = cache.total, questions = cache.problems }, nil
  end

  local variables = { categorySlug = 'all-code-essentials', limit = 5000, skip = 0, filters = {} }
  local data, err = api.graphql(queries.problems, variables)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local rows = data.problemsetQuestionList or {}
  local questions = {}
  for _, q in ipairs(rows.questions or {}) do
    table.insert(questions, H.normalize(H.clean(q)))
  end

  cache.problems = questions
  cache.total = rows.total or #questions
  cache.domain = config.config.url
  cache.cache_time = os.time()
  storage.write_cache(cache)

  return { total = cache.total, questions = questions }, nil
end

---Find a cached list entry by slug; falls back to a fetch-through.
---
---@param title_slug string
---@param opts table|nil { force = boolean } always re-check via list.
---@return table|nil entry
H.find_in_list = function(title_slug, opts)
  if opts == nil or not opts.force then
    for _, entry in ipairs((storage.read_cache()).problems or {}) do
      if entry.title_slug == title_slug then return entry end
    end
  end

  local list, err = H.get_list()
  if err ~= nil or list == nil then return nil end
  for _, entry in ipairs(list.questions) do
    if entry.title_slug == title_slug then return entry end
  end
  return nil
end

---Update the cached list status for one question.
---
---@param title_slug string
---@param status string 'solved' | 'attempted' | nil
H.update_list_status = function(title_slug, status)
  local cache = storage.read_cache()
  for _, entry in ipairs(cache.problems or {}) do
    if entry.title_slug == title_slug then entry.status = status end
  end
  storage.write_cache(cache)
end

---Today's daily question slug.
---
---@return string|nil title_slug
---@return string|nil err
H.get_daily = function()
  local data, err = api.graphql(queries.qot)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local record = data.todayRecord
  if record == nil or record.question == nil then return nil, 'No daily question found' end

  return record.question.title_slug, nil
end

---Random question slug.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
---@return string|nil title_slug
---@return string|nil err
H.get_random = function(opts)
  local filters = {}
  if opts ~= nil and opts.difficulty ~= nil then filters.difficulty = opts.difficulty end

  local variables = { categorySlug = 'all-code-essentials', filters = filters }
  local data, err = api.graphql(queries.random_question, variables)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local question = data.randomQuestion
  if question == nil or question.title_slug == nil then return nil, 'No random question found' end

  return question.title_slug, nil
end

---Fetch and normalize a question detail.
---
---@param title_slug string
---@return table|nil detail
---@return string|nil err
H.get_infos = function(title_slug)
  local data, err = api.graphql(queries.question, { titleSlug = title_slug })
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local q = H.clean(data.question or {})
  if q.id == nil then return nil, ('Question "%s" not found'):format(title_slug) end

  local snippets = {}
  for _, snippet in ipairs(q.code_snippets or {}) do
    snippets[snippet.lang_slug] = { lang = snippet.lang, lang_slug = snippet.lang_slug, code = snippet.code }
  end

  q.code_snippets = nil
  q.snippets = snippets
  q.testcases = q.testcase_list or {}
  q.testcase_list = nil
  q.meta = H.decode_meta(q.meta_data)
  q.meta_data = nil
  q.stats = H.decode_meta(q.stats)
  q.similar = q.similar or {}
  q.hints = q.hints or {}

  return q, nil
end

return H
