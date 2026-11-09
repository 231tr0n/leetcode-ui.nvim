--- *leetcode-ui-storage* Local caching and solution drafts
---
--- Layout (default `stdpath('data')/leetcode-ui`, override with
--- `storage_path` in |LeetCode.setup()|):
---
--- - `cache.json` - problem list, credential identity, domain, list/status
---   revisions, and timestamps.
--- - `drafts/{domain}/{slug}.{langSlug}` - raw typed code per question and
---   language.
--- - `testcases/{domain}/{slug}.json` - custom testcase inputs per question.
---
--- Legacy files from older versions stored at `drafts/{slug}.{langSlug}` and
--- `testcases/{slug}.json` are migrated into the `leetcode.com` layout on
--- first read; they are left untouched when another domain is configured.
--- Changing `storage_path` copies saved drafts and testcases into the new root.
--- A target nested inside the current root is rejected. The first setup in a
--- new process does not migrate from the default root.
---@tag LeetCodeStorage
---@toc_entry Storage

local LeetCodeStorage = {}

local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')

-- Helper data =======================================================================================================

LeetCodeStorage.root = nil

-- Helper functionality =============================================================================================

-- Resolve a path through symlinks, including dangling links and existing
-- ancestors.
local function resolve_path(path) return vim.fs.normalize(vim.fn.resolve(path)) end

local function expand_user(path)
  return (path:gsub('^~[^/\\]*', function(user) return vim.fn.expand(user) end))
end

local function root_path(configured)
  if configured == nil or configured == '' then configured = vim.fs.joinpath(vim.fn.stdpath('data'), 'leetcode-ui') end
  return resolve_path(vim.fn.fnamemodify(vim.fs.normalize(expand_user(configured)), ':p'))
end

local function delete_file(file)
  if vim.fn.getftype(file) == '' then return true end
  local ok, result = pcall(vim.fn.delete, file)
  return ok and result == 0
end

local function write_file_lines(lines, file)
  local ok, result = pcall(vim.fn.writefile, lines, file)
  return ok and result == 0
end

local function write_atomic(lines, file)
  local temp = ('%s.tmp.%d.%d'):format(file, vim.fn.getpid(), vim.uv.hrtime())
  local ok = write_file_lines(lines, temp)
  if ok then ok = vim.uv.fs_rename(temp, file) == true end
  if not ok then delete_file(temp) end
  return ok
end

-- Whether `path` is `parent` or is nested under it.
local function path_is_within(path, parent)
  path, parent = vim.fs.normalize(path), vim.fs.normalize(parent)
  if vim.fn.has('win32') == 1 or vim.fn.has('mac') == 1 then
    path, parent = path:lower(), parent:lower()
  end
  if path == parent then return true end
  local prefix = parent:sub(-1) == '/' and parent or (parent .. '/')
  return path:sub(1, #prefix) == prefix
end

local function ensure_dir(path)
  local ok = pcall(vim.fn.mkdir, path, 'p')
  return ok and vim.fn.isdirectory(path) == 1
end

local function path_equal(a, b)
  a, b = vim.fs.normalize(a), vim.fs.normalize(b)
  if a == b then return true end
  if vim.fn.has('win32') == 1 or vim.fn.has('mac') == 1 then return a:lower() == b:lower() end
  return false
end

--- Whether two paths identify the same location.
---
---@param a string
---@param b string
---@return boolean
LeetCodeStorage.path_equal = function(a, b) return path_equal(a, b) end

--- Ensure the storage directory layout exists.
---
---@return string root
LeetCodeStorage.init = function()
  local configured = root_path(config.config.storage_path)
  local drafts = vim.fs.joinpath(configured, 'drafts')
  local testcases = vim.fs.joinpath(configured, 'testcases')
  if LeetCodeStorage.root == configured and vim.fn.isdirectory(drafts) == 1 and vim.fn.isdirectory(testcases) == 1 then
    return configured
  end

  if not ensure_dir(configured) or not ensure_dir(drafts) or not ensure_dir(testcases) then
    log.error(('Failed to create storage directories under `%s`'):format(configured))
  end
  LeetCodeStorage.root = configured
  return configured
end

--- Copy saved drafts and testcases into a new storage root.
---
--- Existing destination files are left untouched.
---
---@param target string
---@return boolean ok
LeetCodeStorage.migrate = function(target)
  local source_root = LeetCodeStorage.init()
  target = root_path(target)
  if path_equal(source_root, target) then return true end
  if path_is_within(target, source_root) then
    log.error('The new storage_path cannot be inside the current storage root')
    return false
  end

  local function copy_tree(source, destination)
    if vim.fn.isdirectory(source) == 0 then return true end
    if not ensure_dir(destination) then return false end
    local ok = true
    for name, kind in vim.fs.dir(source) do
      local from = vim.fs.joinpath(source, name)
      local to = vim.fs.joinpath(destination, name)
      if kind == 'directory' then
        ok = copy_tree(from, to) and ok
      elseif kind == 'file' and vim.fn.getftype(to) == '' then
        local read_ok, lines = pcall(vim.fn.readfile, from)
        if not read_ok or not write_atomic(lines, to) then ok = false end
      end
    end
    return ok
  end

  local ok = true
  for _, kind in ipairs({ 'drafts', 'testcases' }) do
    ok = copy_tree(vim.fs.joinpath(source_root, kind), vim.fs.joinpath(target, kind)) and ok
  end
  if not ok then log.warn('Failed to migrate saved drafts and testcases') end
  return ok
end

--- Path to the problem-list cache file.
---
---@return string
LeetCodeStorage.cache_file = function() return vim.fs.joinpath(LeetCodeStorage.init(), 'cache.json') end

local function domain_dir(kind)
  local dir = vim.fs.joinpath(LeetCodeStorage.init(), kind, config.config.url)
  if not ensure_dir(dir) then log.warn(('Failed to create `%s` storage directory'):format(kind)) end
  return dir
end

--- Absolute, symlink-resolved storage root for a configured path.
---
--- Uses `stdpath('data')/leetcode-ui` when `configured` is nil or empty.
---
---@param configured string|nil
---@return string
LeetCodeStorage.root_path = function(configured) return root_path(configured) end

local function empty_cache() return { problems = {}, total = 0, cache_time = 0 } end

--- Read the problem-list cache, falling back to an empty cache.
---
---@return table cache
LeetCodeStorage.read_cache = function()
  local ok, lines = pcall(vim.fn.readfile, LeetCodeStorage.cache_file())
  if not ok or #lines == 0 then return empty_cache() end

  local decoded_ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok or type(data) ~= 'table' then return empty_cache() end
  if type(data.problems) ~= 'table' or not (vim.islist or vim.tbl_islist)(data.problems) then
    data.problems = {}
  else
    data.problems = vim.tbl_filter(function(entry) return type(entry) == 'table' end, data.problems)
  end
  return data
end

local function file_component(value)
  return (tostring(value):gsub('[^%w_-]', function(char) return ('%%%02X'):format(char:byte()) end))
end

local function legacy_file(kind, file)
  -- Legacy flat files predate domain scoping and belong to the default domain.
  if config.config.url ~= 'leetcode.com' then return nil end
  return vim.fs.joinpath(LeetCodeStorage.init(), kind, vim.fs.basename(file))
end

local function remove_legacy(kind, legacy)
  if legacy == nil or delete_file(legacy) then return true end
  log.warn(('Failed to remove a legacy %s file'):format(kind))
  return false
end

local function read_with_legacy(kind, file)
  if vim.fn.getftype(file) ~= '' then
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok then return lines end
    log.warn('Failed to read a saved file')
    return nil
  end

  local legacy = legacy_file(kind, file)
  if legacy == nil then return nil end
  local ok, lines = pcall(vim.fn.readfile, legacy)
  if not ok then return nil end
  if write_atomic(lines, file) then remove_legacy(kind, legacy) end
  return lines
end

--- Write the problem-list cache.
---
---@param data table
---@return boolean ok
LeetCodeStorage.write_cache = function(data)
  if data.user == nil then data.user = 'anonymous' end
  local ok = write_atomic({ vim.json.encode(data) }, LeetCodeStorage.cache_file())
  if not ok then log.warn('Failed to write the problem-list cache') end
  return ok
end

--- Path to a question's saved testcases.
---
---@param title_slug string
---@return string
LeetCodeStorage.testcase_file = function(title_slug)
  return vim.fs.joinpath(domain_dir('testcases'), ('%s.json'):format(file_component(title_slug)))
end

local function decode_testcases(lines)
  if lines == nil or #lines == 0 then return nil end
  local decoded_ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok or type(data) ~= 'table' then return nil end

  local inputs = {}
  for _, value in ipairs(data) do
    if type(value) == 'string' then table.insert(inputs, value) end
  end
  return #inputs > 0 and inputs or nil
end

--- Read a question's saved testcase inputs.
---
---@param title_slug string
---@return table|nil inputs
LeetCodeStorage.read_testcases = function(title_slug)
  local file = LeetCodeStorage.testcase_file(title_slug)
  if vim.fn.getftype(file) ~= '' then
    local ok, lines = pcall(vim.fn.readfile, file)
    if not ok then
      log.warn('Failed to read saved testcases')
      return nil
    end
    return decode_testcases(lines)
  end

  local legacy = legacy_file('testcases', file)
  if legacy == nil then return nil end
  local ok, lines = pcall(vim.fn.readfile, legacy)
  if not ok then return nil end
  local inputs = decode_testcases(lines)
  if inputs == nil then return nil end
  if write_atomic(lines, file) then remove_legacy('testcases', legacy) end
  return inputs
end

--- Save a question's testcase inputs, or remove them when empty.
---
---@param title_slug string
---@param inputs table|nil
---@return boolean ok
LeetCodeStorage.write_testcases = function(title_slug, inputs)
  local file = LeetCodeStorage.testcase_file(title_slug)
  local legacy = legacy_file('testcases', file)
  local ok
  if inputs == nil or type(inputs) ~= 'table' or #inputs == 0 then
    local legacy_ok = remove_legacy('testcases', legacy)
    local file_ok = delete_file(file)
    ok = legacy_ok and file_ok
  else
    ok = write_atomic({ vim.json.encode(inputs) }, file)
    if ok then remove_legacy('testcases', legacy) end
  end

  if not ok then log.warn('Failed to update testcases') end
  return ok
end

--- Path to a question's draft for one language.
---
---@param title_slug string
---@param lang_slug string
---@return string
LeetCodeStorage.draft_file = function(title_slug, lang_slug)
  return vim.fs.joinpath(domain_dir('drafts'), ('%s.%s'):format(file_component(title_slug), file_component(lang_slug)))
end

--- Read a saved solution draft.
---
---@param title_slug string
---@param lang_slug string
---@return string|nil
LeetCodeStorage.read_draft = function(title_slug, lang_slug)
  local file = LeetCodeStorage.draft_file(title_slug, lang_slug)
  local lines = read_with_legacy('drafts', file)
  if lines == nil then return nil end
  return table.concat(lines, '\n')
end

--- Save a solution draft, or remove it when `code` is nil.
---
---@param title_slug string
---@param lang_slug string
---@param code string|nil
---@return boolean ok
LeetCodeStorage.write_draft = function(title_slug, lang_slug, code)
  local file = LeetCodeStorage.draft_file(title_slug, lang_slug)
  local legacy = legacy_file('drafts', file)
  local ok
  if code == nil then
    local legacy_ok = remove_legacy('drafts', legacy)
    local file_ok = delete_file(file)
    ok = legacy_ok and file_ok
  else
    ok = write_atomic(vim.split(code, '\n', { plain = true }), file)
    if ok then remove_legacy('drafts', legacy) end
  end
  if not ok then log.warn('Failed to save the solution draft') end
  return ok
end

return LeetCodeStorage
