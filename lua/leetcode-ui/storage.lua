--- *leetcode-ui-storage* Local caching and solution drafts
---
--- Layout (default `stdpath('data')/leetcode-ui`, override with
--- `storage_path` in |leetcode-ui.setup()|):
---   `cache.json` - problem-list cache and timestamps
---   `drafts/{slug}.{langSlug}` - raw typed code per question and language
---
---@tag LeetCodeStorage
---@toc_entry Storage

local LeetCodeStorage = {}

local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')

-- Helper data =======================================================================================================

LeetCodeStorage.root = nil

-- Helper functionality =============================================================================================

LeetCodeStorage.init = function()
  local configured =
    vim.fs.normalize(config.config.storage_path or vim.fs.joinpath(vim.fn.stdpath('data'), 'leetcode-ui'))
  if LeetCodeStorage.root == configured then return configured end

  vim.fn.mkdir(configured, 'p')
  vim.fn.mkdir(vim.fs.joinpath(configured, 'drafts'), 'p')
  vim.fn.mkdir(vim.fs.joinpath(configured, 'testcases'), 'p')
  LeetCodeStorage.root = configured
  return configured
end

LeetCodeStorage.cache_file = function() return vim.fs.joinpath(LeetCodeStorage.init(), 'cache.json') end

LeetCodeStorage.empty_cache = function() return { problems = {}, total = 0, cache_time = 0 } end

LeetCodeStorage.read_cache = function()
  local ok, lines = pcall(vim.fn.readfile, LeetCodeStorage.cache_file())
  if not ok or #lines == 0 then return LeetCodeStorage.empty_cache() end

  local decoded_ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok or type(data) ~= 'table' then return LeetCodeStorage.empty_cache() end
  if type(data.problems) ~= 'table' then data.problems = {} end
  return data
end

LeetCodeStorage.write_cache = function(data)
  local file = io.open(LeetCodeStorage.cache_file(), 'w')
  if file == nil then
    log.warn('Failed to write the problem-list cache')
    return
  end
  file:write(vim.json.encode(data))
  file:close()
end

LeetCodeStorage.testcase_file = function(title_slug)
  return vim.fs.joinpath(LeetCodeStorage.init(), 'testcases', ('%s.json'):format(title_slug))
end

LeetCodeStorage.read_testcases = function(title_slug)
  local ok, lines = pcall(vim.fn.readfile, LeetCodeStorage.testcase_file(title_slug))
  if not ok or #lines == 0 then return nil end

  local decoded_ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok or type(data) ~= 'table' then return nil end

  local inputs = {}
  for _, value in ipairs(data) do
    if type(value) == 'string' then table.insert(inputs, value) end
  end
  return #inputs > 0 and inputs or nil
end

LeetCodeStorage.write_testcases = function(title_slug, inputs)
  local file = LeetCodeStorage.testcase_file(title_slug)
  if inputs == nil or type(inputs) ~= 'table' or #inputs == 0 then
    pcall(vim.fn.delete, file)
    return
  end
  local ok = pcall(vim.fn.writefile, { vim.json.encode(inputs) }, file)
  if not ok then log.warn('Failed to save testcases') end
end

LeetCodeStorage.draft_file = function(title_slug, lang_slug)
  return vim.fs.joinpath(LeetCodeStorage.init(), 'drafts', ('%s.%s'):format(title_slug, lang_slug))
end

LeetCodeStorage.read_draft = function(title_slug, lang_slug)
  local ok, lines = pcall(vim.fn.readfile, LeetCodeStorage.draft_file(title_slug, lang_slug))
  if not ok then return nil end
  return table.concat(lines, '\n')
end

LeetCodeStorage.write_draft = function(title_slug, lang_slug, code)
  local file = LeetCodeStorage.draft_file(title_slug, lang_slug)

  if code == nil or code == '' then
    pcall(vim.fn.delete, file)
    return
  end

  local ok = pcall(vim.fn.writefile, vim.split(code, '\n'), file)
  if not ok then log.warn('Failed to save the solution draft') end
end

return LeetCodeStorage
