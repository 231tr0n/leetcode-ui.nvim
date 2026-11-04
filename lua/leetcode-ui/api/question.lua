--- *leetcode-ui-api-question* Problem list, daily, random, and question detail
---
--- Normalized shapes (snake_case, `vim.NIL` values removed):
---   list entries: `{ title, title_slug, frontend_id, difficulty, ac_rate,
---                   is_paid_only, status,
---                   topic_tags = { { name, slug }, ... } }`
---   detail:       `{ id, frontend_id, title, title_slug, is_paid_only,
---                   difficulty, status, ac_rate, topic_tags, content, hints,
---                   snippets = { lang_slug = {...} },
---                   testcases = { string, ... } }`
---@tag LeetCodeQuestion
---@toc_entry Questions API

local LeetCodeQuestion = {}

local api = require('leetcode-ui.api')
local auth = require('leetcode-ui.auth')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local queries = require('leetcode-ui.api.queries')
local storage = require('leetcode-ui.storage')

-- Helper functionality =============================================================================================

--- Remove `vim.NIL` values recursively and compact array entries.
---
---@param value any
---@return any
LeetCodeQuestion.remove_nil = function(value)
  if api.is_null(value) then return nil end
  if type(value) ~= 'table' then return value end

  local result = {}
  if (vim.islist or vim.tbl_islist)(value) then
    for _, entry in ipairs(value) do
      local cleaned = LeetCodeQuestion.remove_nil(entry)
      if cleaned ~= nil then table.insert(result, cleaned) end
    end
    return result
  end

  for key, entry in pairs(value) do
    result[key] = LeetCodeQuestion.remove_nil(entry)
  end
  return result
end

-- Public API ========================================================================================================

--- Normalize an API status to `'solved'`, `'attempted'`, or nil.
---
---@param status any
---@return string|nil
LeetCodeQuestion.normalize_status = function(status)
  if status == 'ac' or status == 'AC' or status == 'solved' then return 'solved' end
  if status == 'notac' or status == 'attempted' then return 'attempted' end
  return nil
end

--- Normalize a single `questionList` row.
---
---@param question table GraphQL row.
---@return table Normalized entry.
LeetCodeQuestion.normalize_entry = function(question)
  local tags = {}
  local topic_tags = type(question.topic_tags) == 'table' and question.topic_tags or {}
  for _, tag in ipairs(topic_tags) do
    if type(tag) == 'table' and type(tag.name) == 'string' and type(tag.slug) == 'string' then
      table.insert(tags, { name = tag.name, slug = tag.slug })
    end
  end

  local frontend_id = question.frontend_id
  if api.is_null(frontend_id) or frontend_id == '' then
    frontend_id = ''
  else
    frontend_id = tostring(frontend_id)
  end

  return {
    title = question.title,
    title_slug = question.title_slug,
    frontend_id = frontend_id,
    difficulty = question.difficulty,
    ac_rate = tonumber(question.ac_rate) or 0,
    is_paid_only = question.is_paid_only == true,
    status = LeetCodeQuestion.normalize_status(question.status),
    topic_tags = tags,
  }
end

--- Fetch the full problem list, using the on-disk cache when it is fresh,
--- complete, and matches the current credentials. Expired, incomplete,
--- mismatched, or force-refreshed caches are rebuilt and replaced only after a
--- valid, complete response arrives.
---
---@param opts table|nil `{ force = boolean }` to bypass a fresh cache.
---@return table|nil { total, questions }
---@return string|nil err
LeetCodeQuestion.get_list = function(opts)
  opts = type(opts) == 'table' and opts or {}
  local request_domain = config.config.url
  local cache = storage.read_cache()
  local cache_time = tonumber(cache.cache_time or cache.saved) or 0
  local cache_total = tonumber(cache.total)
  local cache_problems = type(cache.problems) == 'table' and cache.problems or {}
  local complete = cache_total ~= nil and #cache_problems == cache_total
  local age = os.time() - cache_time
  local fresh = cache_time > 0 and age >= 0 and age < (config.config.cooldown * 60)
  local request_key = auth.cache_key()
  local same_user = cache.user == request_key
  local same_domain = cache.domain == request_domain and same_user
  local list_revision = tonumber(cache.list_revision) or 0

  if opts.force ~= true and fresh and complete and same_domain then
    return { total = cache_total, questions = cache_problems }, nil
  end

  log.info('Loading problem list…')
  local page_size = 100
  local function fail(message)
    log.error('Failed to load problem list: ' .. message)
    return nil, message
  end

  local function fetch_page(skip)
    if config.config.url ~= request_domain then return nil, 'LeetCode domain changed during fetch' end
    local variables = {
      categorySlug = 'all-code-essentials',
      limit = page_size,
      skip = skip,
      filters = vim.empty_dict(),
    }
    local data, err = api.graphql(queries.problems, variables)
    if err ~= nil or data == nil then return fail(err or 'Empty response') end

    local page = data.problemsetQuestionList
    if type(page) ~= 'table' or type(page.total) ~= 'number' or type(page.questions) ~= 'table' then
      return fail('Malformed problem-list response')
    end
    if page.total <= 0 or page.total % 1 ~= 0 then return fail('Malformed problem-list response') end
    return { total = page.total, rows = page.questions }, nil
  end

  local questions, skip = {}, 0
  local total
  while true do
    local page, err = fetch_page(skip)
    if err ~= nil or page == nil then return nil, err or 'Empty response' end

    total = page.total
    for _, row in ipairs(page.rows) do
      local cleaned = LeetCodeQuestion.remove_nil(row)
      if type(cleaned) == 'table' then table.insert(questions, LeetCodeQuestion.normalize_entry(cleaned)) end
    end

    if #page.rows < page_size or #questions >= total then break end
    skip = skip + page_size
  end

  if #questions ~= total then return fail('Incomplete problem-list response') end

  local current_key = auth.cache_key()
  local latest = storage.read_cache()
  local latest_revision = tonumber(latest.revision) or 0
  local latest_list_revision = tonumber(latest.list_revision) or 0
  local same_latest_user = latest.user == request_key
  if latest.domain == config.config.url and same_latest_user then
    local latest_status = {}
    for _, entry in ipairs(latest.problems or {}) do
      if type(entry) == 'table' and entry.title_slug ~= nil then latest_status[entry.title_slug] = entry.status end
    end
    for _, entry in ipairs(questions) do
      local status = latest_status[entry.title_slug]
      if status == 'solved' or (status == 'attempted' and entry.status ~= 'solved') then entry.status = status end
    end
  end

  if current_key ~= request_key then return nil, 'Authentication state changed during fetch' end
  if config.config.url ~= request_domain then return nil, 'LeetCode domain changed during fetch' end

  local result = { total = total, questions = questions }
  if latest_list_revision ~= list_revision then
    log.info(('Loaded %d problems'):format(#questions))
    return result, nil
  end

  cache.problems = questions
  cache.total = total
  cache.cache_time = os.time()
  cache.domain = request_domain
  cache.user = request_key
  cache.list_revision = list_revision + 1
  cache.revision = latest_revision + 1
  storage.write_cache(cache)
  log.info(('Loaded %d problems'):format(#questions))

  return result, nil
end

--- Find an entry in the existing cache without fetching the full list.
---
---@param title_slug string
---@return table|nil entry
LeetCodeQuestion.find_in_list = function(title_slug)
  local cache = storage.read_cache()
  local same_user = cache.user == auth.cache_key()
  if cache.domain ~= config.config.url or not same_user then return nil end
  for _, entry in ipairs(cache.problems or {}) do
    if entry.title_slug == title_slug then return entry end
  end
  return nil
end

--- Update the cached list status for one question.
---
---@param title_slug string
---@param status string|nil `'solved'`, `'attempted'`, or nil.
LeetCodeQuestion.update_list_status = function(title_slug, status)
  local user_key = auth.cache_key()
  local cache = storage.read_cache()
  local same_user = cache.user == user_key
  if cache.domain ~= config.config.url or not same_user then return end

  local changed = false
  for _, entry in ipairs(cache.problems or {}) do
    if entry.title_slug == title_slug and not (status == 'attempted' and entry.status == 'solved') then
      if entry.status ~= status then
        entry.status = status
        changed = true
      end
    end
  end
  if not changed then return end

  cache.revision = (tonumber(cache.revision) or 0) + 1
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
  if
    type(record) ~= 'table'
    or type(record.question) ~= 'table'
    or type(record.question.title_slug) ~= 'string'
    or record.question.title_slug == ''
  then
    return nil, 'No daily question found'
  end
  return record.question.title_slug, nil
end

--- Random question slug.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
---@return string|nil title_slug
---@return string|nil err
LeetCodeQuestion.get_random = function(opts)
  local filters = {}
  if opts ~= nil and type(opts.difficulty) == 'string' and opts.difficulty ~= '' then
    filters.difficulty = opts.difficulty:upper()
  end
  if config.config.hide_premium then filters.premiumOnly = false end
  if next(filters) == nil then filters = vim.empty_dict() end

  local variables = { categorySlug = 'all-code-essentials', filters = filters }
  local attempts = config.config.hide_premium and 5 or 1
  for _ = 1, attempts do
    local data, err = api.graphql(queries.random_question, variables)
    if err ~= nil or data == nil then return nil, err or 'Empty response' end

    local question = data.randomQuestion
    if type(question) ~= 'table' or type(question.title_slug) ~= 'string' or question.title_slug == '' then
      return nil, 'No random question found'
    end
    if question.is_paid_only ~= true then return question.title_slug, nil end
  end
  return nil, 'No free random question found'
end

--- Fetch and normalize a question detail.
---
---@param title_slug string
---@return table|nil detail
---@return string|nil err
LeetCodeQuestion.get_detail = function(title_slug)
  local data, err = api.graphql(queries.question, { titleSlug = title_slug })
  if err ~= nil or data == nil then return nil, err or 'Empty response' end

  local question = LeetCodeQuestion.remove_nil(data.question)
  if type(question) ~= 'table' or question.id == nil then
    return nil, ('Question "%s" was not found'):format(title_slug)
  end

  local snippets = {}
  local code_snippets = type(question.code_snippets) == 'table' and question.code_snippets or {}
  for _, snippet in ipairs(code_snippets) do
    if type(snippet) == 'table' and type(snippet.lang_slug) == 'string' and snippet.lang_slug ~= '' then
      snippets[snippet.lang_slug] = { lang = snippet.lang, lang_slug = snippet.lang_slug, code = snippet.code }
    end
  end

  local aliases = {}
  for slug, snippet in pairs(snippets) do
    local info = config.get_lang(slug)
    if info ~= nil and info.alt ~= nil then
      table.insert(aliases, { slug = slug, target = info.alt, snippet = snippet })
    end
  end
  for _, alias in ipairs(aliases) do
    if snippets[alias.target] == nil then
      local target = config.get_lang(alias.target)
      snippets[alias.target] = {
        lang = target ~= nil and target.lang or alias.snippet.lang,
        lang_slug = alias.target,
        code = alias.snippet.code,
      }
    end
    snippets[alias.slug] = nil
  end

  local testcases = {}
  for _, input in ipairs(type(question.testcase_list) == 'table' and question.testcase_list or {}) do
    if type(input) == 'string' then table.insert(testcases, input) end
  end

  question.code_snippets = nil
  question.snippets = snippets
  question.status = LeetCodeQuestion.normalize_status(question.status)
  question.testcases = testcases
  question.testcase_list = nil
  question.hints = type(question.hints) == 'table' and question.hints or {}

  return question, nil
end

return LeetCodeQuestion
