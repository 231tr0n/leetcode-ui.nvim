--- *leetcode-ui-api-question* Problem list, daily, random, and question detail
---
--- Normalized shapes (snake_case, `vim.NIL` values removed):
---   list entries: `{ title, title_slug, frontend_id, difficulty, ac_rate,
---                   is_paid_only, status, topic_tags = { { name, slug }, ... } }`
---   detail:       `{ id, frontend_id, title, title_slug, is_paid_only,
---                   difficulty, content, hints, snippets = { lang_slug = {...} },
---                   testcases = { string, ... }, meta = parsed metaData table,
---                   stats = parsed `stats` table, similar = { ... } }`
---
---@tag LeetCodeQuestion
---@toc_entry Questions API

local LeetCodeQuestion = {}

local api = require('leetcode-ui.api')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local queries = require('leetcode-ui.api.queries')
local storage = require('leetcode-ui.storage')

-- Helper functionality =============================================================================================

--- Remove `vim.NIL` values recursively.
---
---@param value any
---@return any
LeetCodeQuestion.clean = function(value)
  if api.is_nillish(value) then return nil end
  if type(value) ~= 'table' then return value end

  local result = {}
  for key, entry in pairs(value) do
    if type(entry) ~= 'table' and api.is_nillish(entry) then
      result[key] = nil
    else
      result[key] = LeetCodeQuestion.clean(entry)
    end
  end
  return result
end

--- Decode a JSON string field, returning nil when it is absent or invalid.
---
---@param value any
---@return table|nil
LeetCodeQuestion.decode_meta = function(value)
  if value == nil or type(value) ~= 'string' or value == '' then return nil end
  local ok, decoded = pcall(vim.json.decode, value)
  return ok and decoded or nil
end

-- Public API ========================================================================================================

--- Normalize a single `questionList` row.
---
---@param question table GraphQL row.
---@return table Normalized entry.
LeetCodeQuestion.normalize = function(question)
  local status = question.status
  if status == 'AC' then status = 'solved' end
  if status == 'null' then status = nil end

  local tags = {}
  for _, tag in ipairs(question.topic_tags or {}) do
    table.insert(tags, { name = tag.name, slug = tag.slug })
  end

  return {
    title = question.title,
    title_slug = question.title_slug,
    frontend_id = question.frontend_id ~= nil and tostring(question.frontend_id) or '',
    difficulty = question.difficulty,
    ac_rate = question.ac_rate or 0,
    is_paid_only = question.is_paid_only == true,
    status = status,
    topic_tags = tags,
  }
end

--- Fetch the full problem list, using the on-disk cache when fresh and complete.
--- The cache contents are only replaced when the API reports a different total.
---
---@return table|nil { total, questions }
---@return string|nil err
LeetCodeQuestion.get_list = function()
  local cache = storage.read_cache()
  local cache_time = tonumber(cache.cache_time or cache.saved) or 0
  local cache_total = tonumber(cache.total)
  local cache_problems = type(cache.problems) == 'table' and cache.problems or {}
  local complete = cache_total ~= nil and #cache_problems > 0 and #cache_problems == cache_total
  local fresh = (os.time() - cache_time) < (config.config.cooldown * 60)

  if fresh and complete then return { total = cache_total, questions = cache_problems }, nil end

  log.info('Loading problem list…')
  local page_size = 100

  local function fetch_page(skip)
    local variables = {
      categorySlug = 'all-code-essentials',
      limit = page_size,
      skip = skip,
      filters = vim.empty_dict(),
    }
    local data, err = api.graphql(queries.problems, variables)
    if err ~= nil or data == nil then
      log.error('Failed to load problem list: ' .. (err or 'Empty response'))
      return nil, err or 'Empty response'
    end

    local page = data.problemsetQuestionList or {}
    local rows = page.questions
    if type(rows) ~= 'table' then rows = {} end
    return { total = page.total or 0, rows = rows }, nil
  end

  local first_page = nil
  if complete then
    local page, err = fetch_page(0)
    if err ~= nil or page == nil then return nil, err or 'Empty response' end
    if page.total == cache_total then
      cache.cache_time = os.time()
      storage.write_cache(cache)
      log.info(('Problem count unchanged (%d); using cached list'):format(cache_total))
      return { total = cache_total, questions = cache_problems }, nil
    end
    first_page = page
    log.info(('Problem count changed (%d -> %d); updating cache'):format(cache_total, page.total))
  end

  local questions, total, skip, page = {}, 0, 0, first_page
  while true do
    if page == nil then
      local err
      page, err = fetch_page(skip)
      if err ~= nil or page == nil then return nil, err or 'Empty response' end
    end

    total = page.total > 0 and page.total or total
    for _, row in ipairs(page.rows) do
      table.insert(questions, LeetCodeQuestion.normalize(LeetCodeQuestion.clean(row) --[[@as table]]))
    end

    if total > 0 then
      log.info(('Loading problem list… %d/%d'):format(#questions, total))
    else
      log.info(('Loading problem list… %d'):format(#questions))
    end

    if #page.rows < page_size then break end
    if total > 0 and #questions >= total then break end
    skip = skip + page_size
    page = nil
  end

  cache.problems = questions
  cache.total = total > 0 and total or #questions
  cache.cache_time = os.time()
  storage.write_cache(cache)
  log.info(('Loaded %d problems'):format(#questions))

  return { total = cache.total, questions = questions }, nil
end

--- Clear the cached problem list.
LeetCodeQuestion.clear_cache = function()
  local cache = storage.read_cache()
  cache.problems = {}
  cache.total = 0
  cache.cache_time = 0
  storage.write_cache(cache)
end

--- Find a cached list entry by slug; falls back to a full fetch.
---
---@param title_slug string
---@param opts table|nil { force = boolean }
---@return table|nil entry
LeetCodeQuestion.find_in_list = function(title_slug, opts)
  if opts == nil or not opts.force then
    for _, entry in ipairs(storage.read_cache().problems or {}) do
      if entry.title_slug == title_slug then return entry end
    end
  end

  local list, err = LeetCodeQuestion.get_list()
  if err ~= nil or list == nil then return nil end
  for _, entry in ipairs(list.questions) do
    if entry.title_slug == title_slug then return entry end
  end
  return nil
end

--- Update the cached list status for one question.
---
---@param title_slug string
---@param status string|nil `'solved'`, `'attempted'`, or nil.
LeetCodeQuestion.update_list_status = function(title_slug, status)
  local cache = storage.read_cache()
  for _, entry in ipairs(cache.problems or {}) do
    if entry.title_slug == title_slug then entry.status = status end
  end
  storage.write_cache(cache)
end

--- Today's daily question slug.
---
---@return string|nil title_slug
---@return string|nil err
LeetCodeQuestion.get_daily = function()
  local data, err = api.graphql(queries.qot)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local record = data.todayRecord
  if record == nil or record.question == nil then return nil, 'No daily question found' end
  return record.question.title_slug, nil
end

--- Random question slug.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
---@return string|nil title_slug
---@return string|nil err
LeetCodeQuestion.get_random = function(opts)
  local filters = vim.empty_dict()
  if opts ~= nil and opts.difficulty ~= nil then filters = { difficulty = opts.difficulty } end

  local variables = { categorySlug = 'all-code-essentials', filters = filters }
  local data, err = api.graphql(queries.random_question, variables)
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local question = data.randomQuestion
  if question == nil or question.title_slug == nil then return nil, 'No random question found' end
  return question.title_slug, nil
end

--- Fetch and normalize a question detail.
---
---@param title_slug string
---@return table|nil detail
---@return string|nil err
LeetCodeQuestion.get_detail = function(title_slug)
  local data, err = api.graphql(queries.question, { titleSlug = title_slug })
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local question = LeetCodeQuestion.clean(data.question or {}) --[[@as table]]
  if question.id == nil then return nil, ('Question "%s" was not found'):format(title_slug) end

  local snippets = {}
  for _, snippet in ipairs(question.code_snippets or {}) do
    snippets[snippet.lang_slug] = { lang = snippet.lang, lang_slug = snippet.lang_slug, code = snippet.code }
  end

  question.code_snippets = nil
  question.snippets = snippets
  question.testcases = question.testcase_list or {}
  question.testcase_list = nil
  question.meta = LeetCodeQuestion.decode_meta(question.meta_data)
  question.meta_data = nil
  question.stats = LeetCodeQuestion.decode_meta(question.stats)
  question.similar = question.similar or {}
  question.hints = question.hints or {}

  return question, nil
end

return LeetCodeQuestion
