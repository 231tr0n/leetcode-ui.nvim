-- Shared helpers for mini.test suites of leetcode-ui.nvim.
--
-- Everything runs in-process and offline:
--   - `storage_path` points into a per-suite temp directory,
--   - network entry points (`api.graphql`, `api.rest`, `net.request`) are
--     stubbed per test, never hitting leetcode.com,
--   - browser cookies come from synthetic SQLite fixtures.

local H = {}

-- mini.test globals provided by runner
H.expect = MiniTest.expect
H.eq = MiniTest.expect.equality
H.new_set = MiniTest.new_set

--- Fresh temporary directory (removed by the caller).
H.tmpdir = function()
  local dir = vim.fn.tempname() .. '-lcui-test'
  vim.fn.mkdir(dir, 'p')
  return dir
end

--- Delete every plugin-created buffer and close the central window.
H.reset_ui = function()
  local ok, ui = pcall(require, 'leetcode-ui.ui')
  if ok then ui.close() end

  local ok_question, question = pcall(require, 'leetcode-ui.question')
  if ok_question then
    for _, view in pairs(question.views) do
      if view.console ~= nil then view.console:stop_spinner() end
    end
    question.views = {}
    question.active = nil
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:find('leetcode-ui://', 1, true) ~= nil then pcall(vim.api.nvim_buf_delete, bufnr, { force = true }) end
    end
  end
end

--- Reset the plugin to a known offline state.
---
---@param opts table|nil Extra setup overrides.
H.setup = function(opts)
  local base = {
    browser = 'none',
    storage_path = H.tmpdir(),
    cookies = {},
    local_runner = false,
    notifications = false,
  }
  local config = require('leetcode-ui.config')
  config.reset()
  config.setup(vim.tbl_extend('force', base, opts or {}))

  -- Neutralize environment cookie sources.
  vim.env.LEETCODE_SESSION = nil
  vim.env.CSRFTOKEN = nil

  H.reset_ui()

  -- Reset singleton caches.
  require('leetcode-ui.browser').reset()
  require('leetcode-ui.auth').reset()
  require('leetcode-ui.storage').root = nil
end

--- Load a module (after H.setup ensured state).
H.mod = function(name) return require('leetcode-ui.' .. name) end

--- Read a file's contents.
H.read_file = function(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  return table.concat(lines, '\n')
end

--- Whether a substring is contained (plain match).
H.contains = function(haystack, needle) return tostring(haystack):find(needle, 1, true) ~= nil end

--- Run a function with a temporarily replaced module field.
---
---@param module_name string e.g. 'leetcode-ui.api'
---@param field string Field to replace.
---@param replacement any Temporary value.
---@param fn function Test body.
H.with_stub = function(module_name, field, replacement, fn)
  local mod = require(module_name)
  local original = mod[field]
  mod[field] = replacement
  local ok, err = pcall(fn)
  mod[field] = original
  if not ok then error(err, 0) end
end

--- Create a synthetic Firefox cookies.sqlite with two LeetCode rows.
---
---@param dir string
---@param values table|nil { LEETCODE_SESSION = ..., csrftoken = ... }
---@return string path
H.make_firefox_db = function(dir, values)
  values = values or { LEETCODE_SESSION = 'fx-session', csrftoken = 'fx-csrf' }
  local path = dir .. '/cookies.sqlite'
  local script = 'import sqlite3,sys\n'
    .. 'c=sqlite3.connect(sys.argv[1])\n'
    .. "c.execute('CREATE TABLE moz_cookies(id INTEGER PRIMARY KEY,name TEXT,value TEXT,host TEXT)')\n"
    .. "c.execute(\"INSERT INTO moz_cookies(name,value,host) VALUES('LEETCODE_SESSION',? ,'.leetcode.com')\","
    .. '(sys.argv[2],))\n'
    .. "c.execute(\"INSERT INTO moz_cookies(name,value,host) VALUES('csrftoken',? ,'.leetcode.com')\",(sys.argv[3],))\n"
    .. "c.execute(\"INSERT INTO moz_cookies(name,value,host) VALUES('other','ignore','.example.com')\")\n"
    .. 'c.commit()\n'
    .. 'c.close()\n'
  local out = vim
    .system({ 'python3', '-c', script, path, values.LEETCODE_SESSION, values.csrftoken }, { text = true })
    :wait()
  if out.code ~= 0 then error('firefox fixture failed: ' .. (out.stderr or '')) end
  return path
end

--- Create a synthetic Chromium Cookies DB with a v10-encrypted session value.
---
---@param dir string
---@param session string Plaintext session value to encrypt.
---@param csrf string Plain csrftoken.
---@return string path
H.make_chromium_db = function(dir, session, csrf)
  local path = dir .. '/Cookies'
  local script = 'import sqlite3,subprocess,sys\n'
    .. 'db,s=sys.argv[1],sys.argv[2]\n'
    .. 'c=sys.argv[3]\n'
    .. "k=subprocess.run(['openssl','dgst','-sha1','-hmac','peanuts'],input=b'saltysalt\\x00\\x00\\x00\\x01',"
    .. 'capture_output=True).stdout.decode().strip().split()[-1][:32]\n'
    .. "ct=subprocess.run(['openssl','enc','-e','-aes-128-cbc','-K',k,'-iv','20'*16],"
    .. 'input=s.encode(),capture_output=True,check=True).stdout\n'
    .. 'con=sqlite3.connect(db)\n'
    .. "con.execute('CREATE TABLE cookies(name TEXT,value TEXT,encrypted_value BLOB,host_key TEXT)')\n"
    .. "con.execute(\"INSERT INTO cookies VALUES('LEETCODE_SESSION','',? ,'.leetcode.com')\",(b'v10'+ct,))\n"
    .. "con.execute(\"INSERT INTO cookies VALUES('csrftoken',?,NULL,'.leetcode.com')\",(c,))\n"
    .. 'con.commit()\n'
    .. 'con.close()\n'
  local out = vim.system({ 'python3', '-c', script, path, session, csrf }, { text = true }):wait()
  if out.code ~= 0 then error('chromium fixture failed: ' .. (out.stderr or '')) end
  return path
end

--- A minimal fake question detail (normalized shape).
---
---@param opts table|nil Overrides.
H.fake_detail = function(opts)
  local detail = {
    id = '1',
    frontend_id = '1',
    title = 'Two Sum',
    title_slug = 'two-sum',
    is_paid_only = false,
    difficulty = 'Easy',
    content = '<p>Given <code>nums</code>, find two indices.</p>',
    hints = {},
    snippets = {
      python3 = {
        lang = 'Python3',
        lang_slug = 'python3',
        code = 'class Solution:\n    def twoSum(self, nums, target):\n        pass',
      },
      golang = { lang = 'Go', lang_slug = 'golang', code = 'func twoSum(nums []int, target int) []int {\n\t\n}' },
    },
    testcases = { '[2,7,11,15]\n9', '[3,2,4]\n6' },
    meta = {
      name = 'twoSum',
      params = { { name = 'nums', type = 'integer[]' }, { name = 'target', type = 'integer' } },
      ['return'] = { type = 'integer[]' },
    },
    stats = {},
    similar = {},
  }
  return vim.tbl_extend('force', detail, opts or {})
end

--- A minimal fake question view (as question.lua would build).
---
---@param opts table|nil Overrides.
H.fake_view = function(opts)
  opts = opts or {}
  local detail = H.fake_detail(opts.detail)
  local view = {
    slug = detail.title_slug,
    detail = detail,
    entry = { ac_rate = 50.5, topic_tags = { { name = 'Array', slug = 'array' } }, status = nil },
    lang = 'python3',
    console = nil,
    active = 'code',
    busy = false,
  }
  if opts.lang ~= nil then view.lang = opts.lang end
  return vim.tbl_extend('force', view, opts or {})
end

--- Wait for an async predicate (default 5s).
H.wait_for = function(predicate, ms) return vim.wait(ms or 5000, predicate, 20) end

return H
