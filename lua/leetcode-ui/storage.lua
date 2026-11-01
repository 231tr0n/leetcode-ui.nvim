-- |leetcode-ui-storage| Local caching and solution drafts.
--------------------------------------------------------------------------------
-- Layout (default `stdpath('data')/leetcode-ui`, override with
-- `storage_path` in options):
--   cache.json      - problem list cache + timestamps
--   drafts/{slug}.{langSlug} - raw typed code per question and language
--------------------------------------------------------------------------------

local H = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

---Base storage directory.
H.root = nil

-- Helper functionality ==============================================================================================

---Ensure the storage directory exists and is initialized.
---
---@private
H.init = function()
  if H.root ~= nil then return H.root end

  local root = vim.fs.normalize(config.config.storage_path or vim.fs.joinpath(vim.fn.stdpath('data'), 'leetcode-ui'))
  vim.fn.mkdir(root, 'p')
  vim.fn.mkdir(vim.fs.joinpath(root, 'drafts'), 'p')

  H.root = root
  return H.root
end

---Path to the cache file.
H.cache_file = function() return vim.fs.joinpath(H.init(), 'cache.json') end

---Read the whole cache file.
---
---@return table
H.read_cache = function()
  local ok, lines = pcall(vim.fn.readfile, H.cache_file())
  if not ok or #lines == 0 then return { problems = {}, saved = 0, updated = {} } end

  local ok_dec, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_dec or type(data) ~= 'table' then return { problems = {}, saved = 0, updated = {} } end
  data.problems = data.problems or {}
  return data
end

---Write the whole cache file.
---
---@param data table
H.write_cache = function(data)
  local file = io.open(H.cache_file(), 'w')
  if file == nil then return end
  file:write(vim.json.encode(data))
  file:close()
end

---Draft file path for a question and language.
---
---@param title_slug string
---@param lang_slug string
---@return string
H.draft_file = function(title_slug, lang_slug)
  return vim.fs.joinpath(H.init(), 'drafts', ('%s.%s'):format(title_slug, lang_slug))
end

---Read a draft if it exists.
---
---@param title_slug string
---@param lang_slug string
---@return string|nil
H.read_draft = function(title_slug, lang_slug)
  local ok, lines = pcall(vim.fn.readfile, H.draft_file(title_slug, lang_slug))
  if not ok then return nil end
  return table.concat(lines, '\n')
end

---Save a draft.
---
---@param title_slug string
---@param lang_slug string
---@param code string|nil Save nil to delete the draft.
H.write_draft = function(title_slug, lang_slug, code)
  local file = H.draft_file(title_slug, lang_slug)

  if code == nil or code == '' then
    pcall(vim.fn.delete, file)
    return
  end

  local ok, _ = pcall(vim.fn.writefile, vim.split(code, '\n'), file)
  if not ok then vim.notify('(leetcode-ui) Failed to save draft', vim.log.levels.WARN) end
end

return H
