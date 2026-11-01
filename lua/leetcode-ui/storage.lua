--- *LeetCodeStorage* Local caching and solution drafts
---

-- |leetcode-ui-storage| Local caching and solution drafts.
-- Layout (default `stdpath('data')/leetcode-ui`, override with
-- `storage_path` in options):
--   cache.json      - problem list cache + timestamps
--   drafts/{slug}.{langSlug} - raw typed code per question and language

local LeetCodeStorage = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeStorage.root = nil

-- Helper functionality ==============================================================================================

LeetCodeStorage.init = function()
  if LeetCodeStorage.root ~= nil then return LeetCodeStorage.root end

  local root = vim.fs.normalize(config.config.storage_path or vim.fs.joinpath(vim.fn.stdpath('data'), 'leetcode-ui'))
  vim.fn.mkdir(root, 'p')
  vim.fn.mkdir(vim.fs.joinpath(root, 'drafts'), 'p')

  LeetCodeStorage.root = root
  return LeetCodeStorage.root
end

LeetCodeStorage.cache_file = function() return vim.fs.joinpath(LeetCodeStorage.init(), 'cache.json') end

LeetCodeStorage.read_cache = function()
  local ok, lines = pcall(vim.fn.readfile, LeetCodeStorage.cache_file())
  if not ok or #lines == 0 then return { problems = {}, saved = 0, updated = {} } end

  local ok_dec, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_dec or type(data) ~= 'table' then return { problems = {}, saved = 0, updated = {} } end
  data.problems = data.problems or {}
  return data
end

LeetCodeStorage.write_cache = function(data)
  local file = io.open(LeetCodeStorage.cache_file(), 'w')
  if file == nil then return end
  file:write(vim.json.encode(data))
  file:close()
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

  local ok, _ = pcall(vim.fn.writefile, vim.split(code, '\n'), file)
  if not ok then vim.notify('(leetcode-ui) Failed to save draft', vim.log.levels.WARN) end
end

return LeetCodeStorage
