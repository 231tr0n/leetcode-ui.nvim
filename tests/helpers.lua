-- Shared helpers for mini.test suites of leetcode-ui.nvim.
--
-- Everything runs in-process and offline:
--   - `storage_path` points into a per-case temp directory,
--   - network entry points (`api.graphql`, `api.rest`, `net.request`) are
--     stubbed per test, never hitting leetcode.com,
--   - browser cookies come from synthetic SQLite fixtures.

local H = {}

-- mini.test globals provided by runner
H.expect = MiniTest.expect
H.eq = MiniTest.expect.equality
H.new_set = MiniTest.new_set

--- Fresh temporary directory (removed by the test runner).
H.tmpdir = function()
  local dir = vim.fn.tempname() .. '-lcui-test'
  vim.fn.mkdir(dir, 'p')
  dir = vim.fn.resolve(dir)
  _G.LEETCODE_UI_TEST_TEMP_DIRS = _G.LEETCODE_UI_TEST_TEMP_DIRS or {}
  table.insert(_G.LEETCODE_UI_TEST_TEMP_DIRS, dir)
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
    question.loading_slugs = {}
    question.active = nil
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:find('leetcode-ui://', 1, true) ~= nil then pcall(vim.api.nvim_buf_delete, bufnr, { force = true }) end
    end
  end
end

--- Reconfigure while preserving test storage and notification isolation.
---
---@param opts table|nil Setup overrides.
H.configure = function(opts)
  local config = require('leetcode-ui.config')
  local base = {
    browser = 'none',
    storage_path = config.config.storage_path,
    cookies = {},
    notifications = false,
    markdown = false,
  }
  require('leetcode-ui').setup(vim.tbl_extend('force', base, opts or {}))
end

--- Reset the plugin to a known offline state.
---
---@param opts table|nil Extra setup overrides.
H.setup = function(opts)
  -- Keep geometry tests independent of the host terminal size/options.
  vim.o.lines = 40
  vim.o.columns = 100
  vim.o.laststatus = 2
  vim.o.showtabline = 1
  vim.o.cmdheight = 1

  local config = require('leetcode-ui.config')
  local previous_storage = config.config.storage_path
  config.setup({})
  if previous_storage ~= nil and previous_storage:find('%-lcui%-test$') ~= nil then
    vim.fn.delete(previous_storage, 'rf')
  end
  local storage_path = H.tmpdir()
  config.config.storage_path = storage_path
  H.configure(vim.tbl_extend('force', { storage_path = storage_path }, opts or {}))

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

--- Run a function while capturing notifications.
---
---@param fn function Test body.
---@return table messages `{ { message, level }, ... }`
H.capture_notify = function(fn)
  local original = vim.notify
  local messages = {}
  vim.notify = function(message, level) table.insert(messages, { message = message, level = level }) end
  local ok, err = pcall(fn)
  vim.notify = original
  if not ok then error(err, 0) end
  return messages
end

--- Run a function with a temporarily replaced module field.
---
---@param module_name string e.g. 'leetcode-ui.api'
---@param field string Field to replace.
---@param replacement any Temporary value.
---@param fn function Test body.
H.with_stub = function(module_name, field, replacement, fn)
  local mod = require(module_name)
  H.with_field(mod, field, replacement, fn)
end

--- Run a function with a temporarily replaced table field.
---
---@param target table
---@param field string
---@param replacement any
---@param fn function Test body.
H.with_field = function(target, field, replacement, fn)
  local original = target[field]
  target[field] = replacement
  local ok, err = pcall(fn)
  target[field] = original
  if not ok then error(err, 0) end
end

--- Create a synthetic Firefox cookies.sqlite with two LeetCode rows.
---
---@param dir string
---@param values table|nil { LEETCODE_SESSION = ..., csrftoken = ... }
---@param domain string|nil
---@param expiry number|nil Cookie expiry in Unix seconds; 0 means a session cookie.
---@return string path
H.make_firefox_db = function(dir, values, domain, expiry)
  values = values or { LEETCODE_SESSION = 'fx-session', csrftoken = 'fx-csrf' }
  domain = domain or 'leetcode.com'
  expiry = expiry or 0
  local path = dir .. '/cookies.sqlite'
  local script = 'import sqlite3,sys\n'
    .. 'c=sqlite3.connect(sys.argv[1])\n'
    .. "c.execute('CREATE TABLE moz_cookies(id INTEGER PRIMARY KEY,name TEXT,value TEXT,host TEXT,expiry INTEGER)')\n"
    .. "c.execute(\"INSERT INTO moz_cookies(name,value,host,expiry) VALUES('LEETCODE_SESSION',?,'.' || ?,?)\","
    .. '(sys.argv[2], sys.argv[4], sys.argv[5]))\n'
    .. "c.execute(\"INSERT INTO moz_cookies(name,value,host,expiry) VALUES('csrftoken',?,'.' || ?,?)\","
    .. '(sys.argv[3], sys.argv[4], sys.argv[5]))\n'
    .. 'c.execute("INSERT INTO moz_cookies(name,value,host,expiry) '
    .. "VALUES('LEETCODE_SESSION','hostile','notleetcode.com',0)\")\n"
    .. "c.execute(\"INSERT INTO moz_cookies(name,value,host,expiry) VALUES('other','ignore','.example.com',0)\")\n"
    .. 'c.commit()\n'
    .. 'c.close()\n'
  local out = vim
    .system(
      { 'python3', '-c', script, path, values.LEETCODE_SESSION, values.csrftoken, domain, tostring(expiry) },
      { text = true }
    )
    :wait()
  if out.code ~= 0 then error('firefox fixture failed: ' .. (out.stderr or '')) end
  return path
end

--- Mark every cookie in a synthetic Firefox database as expired.
---
---@param path string
H.expire_firefox_cookies = function(path)
  local script = 'import sqlite3,sys\n'
    .. 'c=sqlite3.connect(sys.argv[1])\n'
    .. "c.execute('UPDATE moz_cookies SET expiry=1')\n"
    .. 'c.commit()\n'
    .. 'c.close()\n'
  local out = vim.system({ 'python3', '-c', script, path }, { text = true }):wait()
  if out.code ~= 0 then error('firefox expiry fixture failed: ' .. (out.stderr or '')) end
end

--- Mark every cookie in a synthetic Chromium database as expired.
---
---@param path string
H.expire_chromium_cookies = function(path)
  local script = 'import sqlite3,sys\n'
    .. 'c=sqlite3.connect(sys.argv[1])\n'
    .. "c.execute('UPDATE cookies SET expires_utc=1')\n"
    .. 'c.commit()\n'
    .. 'c.close()\n'
  local out = vim.system({ 'python3', '-c', script, path }, { text = true }):wait()
  if out.code ~= 0 then error('chromium expiry fixture failed: ' .. (out.stderr or '')) end
end

--- Create a synthetic Safari `Cookies.binarycookies` file.
---
---@param dir string
---@param values table|nil { LEETCODE_SESSION = ..., csrftoken = ... }
---@param domain string|nil
---@param expiry number|nil
---@return string path
H.make_safari_cookies = function(dir, values, domain, expiry)
  values = values or { LEETCODE_SESSION = 'safari-session', csrftoken = 'safari-csrf' }
  domain = domain or 'leetcode.com'
  expiry = expiry or 0
  local path = dir .. '/Cookies.binarycookies'
  local script = [[
import struct, sys

path = sys.argv[1]
values = [('LEETCODE_SESSION', sys.argv[2]), ('csrftoken', sys.argv[3])]
expiry = float(sys.argv[5])

def record(name, value):
    url = sys.argv[4].encode() + b'\0'
    cookie_name = name.encode() + b'\0'
    cookie_path = b'/\0'
    cookie_value = value.encode() + b'\0'
    base = 52
    url_off = base + 4
    name_off = url_off + len(url)
    path_off = name_off + len(cookie_name)
    value_off = path_off + len(cookie_path)
    cookie = (b'\0' * 12 + struct.pack('<IIII', url_off, name_off, path_off, value_off)
              + b'\0' * 8 + struct.pack('<d', expiry) + b'\0' * 8
              + url + cookie_name + cookie_path + cookie_value)
    return struct.pack('<I', len(cookie)) + cookie

records = [record(name, value) for name, value in values]
header_size = 12 + 4 * len(records)
offsets = []
pos = header_size
for rec in records:
    offsets.append(pos)
    pos += len(rec)
page = b'\0' * 4 + struct.pack('<I', len(records)) + b''.join(struct.pack('<I', x) for x in offsets)
page += b'\0' * 4 + b''.join(records)
contents = b'cook' + struct.pack('>I', 1) + struct.pack('>I', len(page)) + page
with open(path, 'wb') as f:
    f.write(contents)
]]
  local out = vim
    .system(
      { 'python3', '-c', script, path, values.LEETCODE_SESSION, values.csrftoken, domain, tostring(expiry) },
      { text = true }
    )
    :wait()
  if out.code ~= 0 then error('safari fixture failed: ' .. (out.stderr or '')) end
  return path
end

--- Create a synthetic Chromium Cookies DB.
---
---@param dir string
---@param session string Session value.
---@param csrf string Plain csrftoken.
---@param mode string|nil `'v10'` (default), `'v11'`, or `'plain'`.
---@param password string|nil Encryption password for encrypted modes.
---@param domain string|nil Cookie host domain.
---@param expiry number|string|nil Chromium `expires_utc`; 0 means a session cookie.
---@param prefix boolean|nil Prefix encrypted values with a 32-byte binary hash.
---@return string path
H.make_chromium_db = function(dir, session, csrf, mode, password, domain, expiry, prefix)
  local path = dir .. '/Cookies'
  mode = mode or 'v10'
  domain = domain or 'leetcode.com'
  expiry = expiry or 0

  local script
  if mode == 'plain' then
    script = 'import sqlite3,sys\n'
      .. 'db,s,c=sys.argv[1],sys.argv[2],sys.argv[3]\n'
      .. 'domain=sys.argv[6]\n'
      .. 'expiry=int(sys.argv[7])\n'
      .. 'con=sqlite3.connect(db)\n'
      .. "con.execute('CREATE TABLE cookies(name TEXT,value TEXT,encrypted_value BLOB,"
      .. "host_key TEXT,expires_utc INTEGER)')\n"
      .. "con.execute(\"INSERT INTO cookies VALUES('LEETCODE_SESSION',?,NULL,'.'||?,?)\",(s,domain,expiry))\n"
      .. "con.execute(\"INSERT INTO cookies VALUES('csrftoken',?,NULL,'.'||?,?)\",(c,domain,expiry))\n"
      .. 'con.commit()\n'
      .. 'con.close()\n'
  else
    script = 'import sqlite3,subprocess,sys\n'
      .. 'db,s,c,mode,password=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5]\n'
      .. 'domain=sys.argv[6]\n'
      .. 'expiry=int(sys.argv[7])\n'
      .. 'prefix=int(sys.argv[8])\n'
      .. "k=subprocess.run(['openssl','dgst','-sha1','-hmac',password],input=b'saltysalt\\x00\\x00\\x00\\x01',"
      .. 'capture_output=True).stdout.decode().strip().split()[-1][:32]\n'
      .. 'plain=(b"\\x00"*32+s.encode()) if prefix else s.encode()\n'
      .. "ct=subprocess.run(['openssl','enc','-e','-aes-128-cbc','-K',k,'-iv','20'*16],"
      .. 'input=plain,capture_output=True,check=True).stdout\n'
      .. 'con=sqlite3.connect(db)\n'
      .. "con.execute('CREATE TABLE cookies(name TEXT,value TEXT,encrypted_value BLOB,"
      .. "host_key TEXT,expires_utc INTEGER)')\n"
      .. "con.execute(\"INSERT INTO cookies VALUES('LEETCODE_SESSION','',?,'.'||?,?)\","
      .. '(mode.encode()+ct,domain,expiry))\n'
      .. "con.execute(\"INSERT INTO cookies VALUES('csrftoken',?,NULL,'.'||?,?)\",(c,domain,expiry))\n"
      .. 'con.commit()\n'
      .. 'con.close()\n'
  end
  local out = vim
    .system({
      'python3',
      '-c',
      script,
      path,
      session,
      csrf,
      mode,
      password or 'peanuts',
      domain,
      tostring(expiry),
      prefix and '1' or '0',
    }, { text = true })
    :wait()
  if out.code ~= 0 then error('chromium fixture failed: ' .. (out.stderr or '')) end
  return path
end

--- Attach an encrypted value to every Chromium cookie row.
---
---@param path string
---@param blob_hex string
H.set_chromium_encrypted = function(path, blob_hex)
  local script = 'import sqlite3,sys\n'
    .. 'con=sqlite3.connect(sys.argv[1])\n'
    .. "con.execute('UPDATE cookies SET encrypted_value=?',(bytes.fromhex(sys.argv[2]),))\n"
    .. 'con.commit()\n'
    .. 'con.close()\n'
  local out = vim.system({ 'python3', '-c', script, path, blob_hex }, { text = true }):wait()
  if out.code ~= 0 then error('chromium update failed: ' .. (out.stderr or '')) end
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
  }
  return vim.tbl_extend('force', detail, opts or {})
end

--- Attach a console to a fake view.
---
---@param view table
---@param testcases table|nil Defaults to the view's question testcases.
---@return table console
H.fake_console = function(view, testcases)
  local Console = require('leetcode-ui.console')
  local console = Console.new(view)
  view.console = console
  console:set_cases(testcases or view.detail.testcases)
  return console
end

--- A minimal fake question view (as question.lua would build).
---
---@param opts table|nil Overrides.
H.fake_view = function(opts)
  opts = opts or {}
  local detail = H.fake_detail(opts.detail)
  local overrides = vim.deepcopy(opts)
  overrides.detail = nil
  local view = vim.tbl_extend('force', {
    slug = detail.title_slug,
    detail = detail,
    entry = { ac_rate = 50.5, topic_tags = { { name = 'Array', slug = 'array' } }, status = nil },
    lang = 'python3',
    console = nil,
    active = 'code',
    busy = false,
  }, overrides)
  view.detail = detail
  return view
end

--- Wait for an async predicate (default 5s).
H.wait_for = function(predicate, ms) return vim.wait(ms or 5000, predicate, 20) end

--- Snapshot editor layout options and restore them after the current case.
H.preserve_layout = function()
  local names = { 'showtabline', 'laststatus', 'cmdheight' }
  local original = {}
  for _, name in ipairs(names) do
    original[name] = vim.o[name]
  end
  MiniTest.finally(function()
    for _, name in ipairs(names) do
      vim.o[name] = original[name]
    end
  end)
end

return H
