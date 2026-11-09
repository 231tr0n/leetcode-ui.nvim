--- *leetcode-ui-browser* Automatic cookie import from browsers
---
--- Supported sources:
--- - Firefox (`cookies.sqlite`, plain SQLite).
--- - Chromium-family browsers (`Cookies` SQLite). Linux uses the tested
---   Chromium key derivation; macOS uses the Keychain password and PBKDF2.
---   Keyring-protected `v11` blobs (and macOS `v10`) report an explicit error
---   when the keyring is unavailable. Encrypted Chromium cookies on Windows are
---   not supported.
--- - Epiphany and Safari where available.
---
--- SQLite browser databases and available WAL sidecars are copied to a
--- temporary directory before reading, so browser locks are untouched. Only
--- the two LeetCode cookie names on the configured domain and its subdomains
--- are queried. Browser readers do not persist decrypted values; network
--- requests may place session headers in a private temporary directory.
--- Chromium decryption passes the derived key to the `openssl` CLI as an
--- argument, which can be visible to other local users on shared systems.
--- With `browser = 'auto'`, sources are checked in priority order and the first
--- complete pair is used. If no source has a complete pair, the source with
--- the most LeetCode cookies is used.
---@tag LeetCodeBrowser
---@toc_entry Browser cookies

local LeetCodeBrowser = {}

local async = require('leetcode-ui.async')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')

-- Helper data =======================================================================================================

local function os_name()
  local sysname = (vim.uv.os_uname() or {}).sysname or ''
  if sysname == 'Darwin' then return 'macos' end
  if sysname == 'Windows_NT' then return 'windows' end
  return 'linux'
end

local function home_directory() return vim.env.HOME or vim.env.USERPROFILE or '' end

local cookie_names = { 'LEETCODE_SESSION', 'csrftoken' }
local priority = { 'firefox', 'epiphany', 'safari', 'chrome', 'brave', 'edge', 'chromium' }
local cache_generation = 0
local failed_sources = {}
LeetCodeBrowser.cache_ttl = 300

--- Current Unix timestamp used for cookie cache expiry.
---
---@return number
LeetCodeBrowser.now = function() return os.time() end

local function source_unavailable(source)
  local failed_at = failed_sources[source]
  if failed_at == nil then return false end
  local age = LeetCodeBrowser.now() - failed_at
  if age >= 0 and age < LeetCodeBrowser.cache_ttl then return true end
  failed_sources[source] = nil
  return false
end

local function is_chromium(browser)
  return browser == 'chrome' or browser == 'brave' or browser == 'edge' or browser == 'chromium'
end

local function chromium_root(browser)
  local osname = os_name()
  local home = home_directory()
  local name_map = {
    chrome = {
      linux = { '.config', 'google-chrome' },
      macos = { 'Library', 'Application Support', 'Google', 'Chrome' },
      windows = { 'AppData', 'Local', 'Google', 'Chrome', 'User Data' },
    },
    brave = {
      linux = { '.config', 'BraveSoftware', 'Brave-Browser' },
      macos = { 'Library', 'Application Support', 'BraveSoftware', 'Brave-Browser' },
      windows = { 'AppData', 'Local', 'BraveSoftware', 'Brave-Browser', 'User Data' },
    },
    edge = {
      linux = { '.config', 'microsoft-edge' },
      macos = { 'Library', 'Application Support', 'Microsoft Edge' },
      windows = { 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data' },
    },
    chromium = {
      linux = { '.config', 'chromium' },
      macos = { 'Library', 'Application Support', 'Chromium' },
      windows = { 'AppData', 'Local', 'Chromium', 'User Data' },
    },
  }
  local parts = (name_map[browser] or {})[osname]
  if parts == nil then return nil end
  return vim.fs.joinpath(home, unpack(parts))
end

local python_script = [[
import json, os, shutil, sqlite3, sys, tempfile

KIND, DB, DOMAIN = sys.argv[1], sys.argv[2], sys.argv[5]
NAMES = tuple(sys.argv[3:5])
HOSTS = (DOMAIN, '%.' + DOMAIN)

def query(con, sql, params):
    cursor = con.execute(sql, params)
    rows = cursor.fetchall()
    cols = [d[0] for d in cursor.description]
    return [dict(zip(cols, row)) for row in rows]

def read(db_path, sql, params):
    with tempfile.TemporaryDirectory() as tmp:
        copied = os.path.join(tmp, os.path.basename(db_path))
        shutil.copyfile(db_path, copied)
        for suffix in ('-wal', '-shm'):
            if os.path.exists(db_path + suffix):
                shutil.copyfile(db_path + suffix, copied + suffix)
        con = sqlite3.connect(copied)
        try:
            return query(con, sql, params)
        finally:
            con.close()

if KIND in ('firefox', 'epiphany'):
    sql = 'SELECT name AS name, value AS value, \'\' AS blob FROM moz_cookies ' \
        'WHERE (host = ? OR host LIKE ?) AND name IN (?, ?) ' \
        'AND (expiry = 0 OR expiry > CAST(strftime(\'%s\', \'now\') AS INTEGER))'
else:
    sql = 'SELECT name AS name, value AS value, hex(encrypted_value) AS blob FROM cookies ' \
        'WHERE (host_key = ? OR host_key LIKE ?) AND name IN (?, ?) ' \
        'AND (expires_utc = 0 OR expires_utc > ' \
        '(CAST(strftime(\'%s\', \'now\') AS INTEGER) + 11644473600) * 1000000)'

print(json.dumps(read(DB, sql, HOSTS + NAMES)))
]]
local safari_script = [[
import json, struct, sys, time
from io import BytesIO

path, domain = sys.argv[1], sys.argv[2]
names = set(sys.argv[3:])
now = time.time() - 978307200

try:
    with open(path, 'rb') as f:
        data = f.read()
except IOError:
    print(json.dumps({}))
    sys.exit(0)

if data[:4] != b'cook':
    print(json.dumps({}))
    sys.exit(0)

num_pages = struct.unpack('>I', data[4:8])[0]
off = 8
page_sizes = list(struct.unpack('>' + 'I' * num_pages, data[off:off + 4 * num_pages]))
off += 4 * num_pages

pages = []
for ps in page_sizes:
    pages.append(data[off:off + ps])
    off += ps

result = {}

def read_str(buf, o):
    buf.seek(o - 4)
    out = b''
    ch = buf.read(1)
    while ch and ch != b'\x00':
        out += ch
        ch = buf.read(1)
    return out.decode('utf-8', 'replace')

for page in pages:
    p = BytesIO(page)
    p.read(4)
    num_cookies = struct.unpack('<I', p.read(4))[0]
    offsets = [struct.unpack('<I', p.read(4))[0] for _ in range(num_cookies)]
    p.read(4)
    for offset in offsets:
        p.seek(offset)
        cookie_size = struct.unpack('<I', p.read(4))[0]
        cookie = BytesIO(p.read(cookie_size))
        cookie.read(4)
        cookie.read(4)
        cookie.read(4)
        url_off = struct.unpack('<I', cookie.read(4))[0]
        name_off = struct.unpack('<I', cookie.read(4))[0]
        path_off = struct.unpack('<I', cookie.read(4))[0]
        value_off = struct.unpack('<I', cookie.read(4))[0]
        cookie.read(8)
        expiry = struct.unpack('<d', cookie.read(8))[0]

        url = read_str(cookie, url_off)
        name = read_str(cookie, name_off)
        value = read_str(cookie, value_off)

        host = url.lower()
        if (expiry == 0 or expiry >= now) and (host == domain or host.endswith('.' + domain)) and name in names:
            result[name] = value

print(json.dumps(result))
]]

-- Helper functionality ==============================================================================================

local function newest_file(candidates)
  table.sort(candidates, function(a, b)
    local a_mtime = (vim.uv.fs_stat(a) or {}).mtime
    local b_mtime = (vim.uv.fs_stat(b) or {}).mtime
    return (a_mtime and a_mtime.sec or 0) > (b_mtime and b_mtime.sec or 0)
  end)
  return candidates[1]
end

local function nested_cookie_file(path, filename, browser)
  local patterns = { { '*', filename }, { filename } }
  if is_chromium(browser) then
    patterns = {
      { '*', 'Network', filename },
      { 'Network', filename },
      { '*', filename },
      { filename },
    }
  end

  local candidates = {}
  for _, parts in ipairs(patterns) do
    local glob = vim.fs.joinpath(path, unpack(parts))
    vim.list_extend(candidates, vim.fn.glob(glob, true, true))
  end
  return newest_file(candidates)
end

--- Locate the newest cookie database for a browser.
---
---@param browser string
---@return string|nil path
LeetCodeBrowser.cookie_db = function(browser)
  local filename = 'Cookies'
  if browser == 'firefox' or browser == 'epiphany' then
    filename = 'cookies.sqlite'
  elseif browser == 'safari' then
    filename = 'Cookies.binarycookies'
  end
  local overridden = (config.config.browser_paths or {})[browser]

  if overridden ~= nil and overridden ~= '' then
    overridden = overridden:gsub('^~[^/\\]*', function(user) return vim.fn.expand(user) end)
    local path = vim.fs.normalize(overridden)
    local stat = vim.uv.fs_stat(path)
    if stat == nil then return nested_cookie_file(path, filename, browser) end
    if stat.type == 'directory' then return nested_cookie_file(path, filename, browser) end
    return path
  end

  local candidates = {}
  if browser == 'firefox' then
    local osname = os_name()
    local home = home_directory()
    if osname == 'macos' then
      vim.list_extend(
        candidates,
        vim.fn.glob(
          vim.fs.joinpath(home, 'Library', 'Application Support', 'Firefox', 'Profiles', '*', 'cookies.sqlite'),
          true,
          true
        )
      )
    elseif osname == 'windows' then
      local appdata = vim.env.APPDATA or home
      vim.list_extend(
        candidates,
        vim.fn.glob(vim.fs.joinpath(appdata, 'Mozilla', 'Firefox', 'Profiles', '*', 'cookies.sqlite'), true, true)
      )
    else
      vim.list_extend(
        candidates,
        vim.fn.glob(vim.fs.joinpath(home, '.mozilla', 'firefox', '*', 'cookies.sqlite'), true, true)
      )
      vim.list_extend(
        candidates,
        vim.fn.glob(vim.fs.joinpath(home, '.config', 'mozilla', 'firefox', '*', 'cookies.sqlite'), true, true)
      )
    end
  elseif browser == 'epiphany' then
    local home = home_directory()
    vim.list_extend(
      candidates,
      vim.fn.glob(vim.fs.joinpath(home, '.local', 'share', 'epiphany', 'cookies.sqlite'), true, true)
    )
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(home, '.config', 'epiphany', 'cookies.sqlite'), true, true))
  elseif browser == 'safari' then
    local home = home_directory()
    for _, parts in ipairs({
      { 'Library', 'Cookies', 'Cookies.binarycookies' },
      { 'Library', 'Containers', 'com.apple.Safari', 'Data', 'Library', 'Cookies', 'Cookies.binarycookies' },
    }) do
      local path = vim.fs.joinpath(home, unpack(parts))
      if vim.uv.fs_stat(path) ~= nil then table.insert(candidates, path) end
    end
  else
    local root = chromium_root(browser)
    if root == nil then return nil end
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(root, '*', 'Cookies'), true, true))
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(root, '*', 'Network', 'Cookies'), true, true))
  end
  if #candidates == 0 then return nil end

  return newest_file(candidates)
end

-- Decode a hexadecimal string into bytes.
local function decode_hex(hex)
  return (hex:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end))
end

--- Read the Chromium-family keyring password when decryption requires it.
---
---@param browser string
---@return string|nil password
LeetCodeBrowser.keyring_password = function(browser)
  local osname = os_name()
  local app_map = {
    chrome = 'Chrome',
    brave = 'Brave',
    edge = 'Microsoft Edge',
    chromium = 'Chromium',
  }
  local service = app_map[browser]
  if service == nil then return nil end

  if osname == 'linux' then
    local candidates = ({
      chrome = { 'chrome' },
      brave = { 'brave' },
      edge = { 'microsoft-edge', 'edge', 'chromium' },
      chromium = { 'chromium' },
    })[browser] or {}
    for _, app in ipairs(candidates) do
      local out = async.system({ 'secret-tool', 'lookup', 'application', app }, { text = true })
      if out.code == 0 then
        local pw = vim.trim(out.stdout or '')
        if pw ~= '' then return pw end
      end
    end
    return nil
  elseif osname == 'macos' then
    local svc = service .. ' Safe Storage'
    local out = async.system({ 'security', 'find-generic-password', '-w', '-s', svc }, { text = true })
    if out.code == 0 then return vim.trim(out.stdout or '') end
    return nil
  elseif osname == 'windows' then
    -- Windows Chrome uses DPAPI; not implemented. Use cookie_file or env vars.
    return nil
  end
  return nil
end

--- Derive the AES key used by Chromium-family cookie blobs.
---
---@param password string|nil
---@return string|nil key_hex
LeetCodeBrowser.derive_key = function(password)
  local script = [[
import hashlib, hmac, sys
mode = sys.argv[1]
key = sys.stdin.buffer.read()
if mode == 'macos':
    print(hashlib.pbkdf2_hmac('sha1', key, b'saltysalt', 1003, 16).hex())
else:
    message = b'saltysalt' + bytes((0, 0, 0, 1))
    print(hmac.new(key, message, hashlib.sha1).hexdigest())
]]
  local mode = os_name() == 'macos' and 'macos' or 'linux'
  local out = async.system({ 'python3', '-c', script, mode }, {
    text = true,
    stdin = password or 'peanuts',
  })
  if out.code ~= 0 then return nil end

  local hex = vim.trim(out.stdout or '')
  if #hex < 32 or not hex:match('^%x+$') then return nil end
  return hex:sub(1, 32)
end

--- Decrypt one Chromium-family cookie blob.
---
---@param blob_hex string|nil
---@param browser string
---@return string|nil value
---@return string|nil err
LeetCodeBrowser.decrypt_blob = function(blob_hex, browser)
  if type(blob_hex) ~= 'string' or blob_hex == '' then return nil, nil end

  local raw = decode_hex(blob_hex:lower())
  local version = raw:sub(1, 3)
  local osname = os_name()
  if osname == 'windows' then return nil, 'encrypted Chromium cookies are not supported on Windows' end

  ---@type string|nil
  local password = 'peanuts'
  if version == 'v11' or (version == 'v10' and osname == 'macos') then
    password = LeetCodeBrowser.keyring_password(browser)
    if password == nil or password == '' then
      return nil, ('blob version %q is not supported (keyring-protected)'):format(version)
    end
  elseif version ~= 'v10' then
    return nil, ('blob version %q is not supported'):format(version)
  end

  local key_hex = LeetCodeBrowser.derive_key(password)
  if key_hex == nil then return nil, 'cannot derive the cookie key' end

  local out = async.system({
    'openssl',
    'enc',
    '-d',
    '-aes-128-cbc',
    '-K',
    key_hex,
    '-iv',
    string.rep('20', 16),
  }, { text = true, stdin = raw:sub(4) })

  if out.code ~= 0 then return nil, 'AES-CBC decryption failed' end

  local value = out.stdout or ''
  if value == '' then return nil, nil end

  -- Chromium DB `meta.version >= 24` prefixes the plaintext with a 32-byte
  -- integrity hash on macOS and Linux. Windows uses AES-GCM (unsupported).
  if osname ~= 'windows' and #value > 32 then
    local prefix = value:sub(1, 32)
    local has_binary = false
    for i = 1, #prefix do
      local b = prefix:byte(i)
      if b < 32 or b > 126 then
        has_binary = true
        break
      end
    end
    if has_binary then value = value:sub(33) end
  end

  if value == '' then return nil, nil end
  return value, nil
end

local function reader_failure(label, out)
  return ('%s reader failed: %s'):format(label, vim.trim(out.stderr or 'unknown error'))
end

local function decode_reader_output(out, label)
  local ok, decoded = pcall(vim.json.decode, vim.trim(out.stdout or ''))
  if not ok or type(decoded) ~= 'table' then return nil, ('%s reader returned invalid JSON'):format(label) end
  return decoded, nil
end

--- Read LeetCode cookies from one browser without caching.
---
---@param browser string
---@return table|nil cookies
---@return string|nil err
LeetCodeBrowser.read_cookies = function(browser)
  local domain = config.config.url:gsub('^www%.', ''):lower()
  if browser == 'safari' then
    local db = LeetCodeBrowser.cookie_db(browser)
    if db == nil then return nil, 'No Safari cookie file found' end
    local out =
      async.system(vim.list_extend({ 'python3', '-c', safari_script, db, domain }, cookie_names), { text = true })
    if out.code ~= 0 then return nil, reader_failure('safari', out) end

    local decoded, err = decode_reader_output(out, 'safari')
    if decoded == nil then return nil, err end
    local cookies = {}
    for name, value in pairs(decoded) do
      if type(name) == 'string' and type(value) == 'string' and value ~= '' then cookies[name] = value end
    end
    return cookies, nil
  end

  local db = LeetCodeBrowser.cookie_db(browser)
  if db == nil then return nil, ('No %s cookie database found'):format(browser) end

  local args = { 'python3', '-c', python_script, browser, db }
  vim.list_extend(args, cookie_names)
  table.insert(args, domain)

  local out = async.system(args, { text = true })
  if out.code ~= 0 then return nil, reader_failure('sqlite', out) end

  local rows, err = decode_reader_output(out, 'sqlite')
  if rows == nil then return nil, err end

  local cookies, warnings = {}, {}
  for _, row in ipairs(rows) do
    if type(row) == 'table' then
      local name = row.name
      if name == vim.NIL then name = nil end
      local value = row.value
      if value == vim.NIL then value = nil end
      local blob = row.blob
      if blob == vim.NIL then blob = nil end

      if is_chromium(browser) and (value == nil or value == '') then
        local plain, decrypt_err = LeetCodeBrowser.decrypt_blob(blob, browser)
        if decrypt_err ~= nil then table.insert(warnings, ('%s: %s'):format(name or 'cookie', decrypt_err)) end
        value = plain
      end

      if name ~= nil and value ~= nil and value ~= '' then cookies[name] = value end
    end
  end

  return cookies, #warnings > 0 and table.concat(warnings, '; ') or nil
end

-- Public API ========================================================================================================

local function cookie_count(cookies)
  local count = 0
  for _ in pairs(cookies or {}) do
    count = count + 1
  end
  return count
end

local function has_complete_session(cookies)
  return type(cookies) == 'table'
    and type(cookies.LEETCODE_SESSION) == 'string'
    and cookies.LEETCODE_SESSION ~= ''
    and type(cookies.csrftoken) == 'string'
    and cookies.csrftoken ~= ''
end

--- Resolved browser cookies (session cache, 5 minute TTL).
---
---@return table|nil cookies name -> value or nil
LeetCodeBrowser.get_cookies = function()
  local configured = config.config.browser
  local configured_url = config.config.url
  local generation = cache_generation
  local cache = LeetCodeBrowser.cache or {}
  local age = cache.at ~= nil and LeetCodeBrowser.now() - cache.at or nil
  if
    age ~= nil
    and age >= 0
    and age <= LeetCodeBrowser.cache_ttl
    and cache.source == configured
    and cache.url == configured_url
  then
    return cache.value
  end

  if configured == nil or configured == 'none' then
    LeetCodeBrowser.cache = { value = nil, at = LeetCodeBrowser.now(), source = configured, url = configured_url }
    return nil
  end

  local browser, cookies, err, cookie_source = configured, nil, nil, nil
  if configured == 'auto' then
    for _, candidate in ipairs(priority) do
      if not source_unavailable(candidate) and LeetCodeBrowser.cookie_db(candidate) ~= nil then
        local found, read_err = LeetCodeBrowser.read_cookies(candidate)
        if found ~= nil and next(found) ~= nil and (cookies == nil or cookie_count(found) > cookie_count(cookies)) then
          cookies, cookie_source, err = found, candidate, read_err
        elseif err == nil then
          err = read_err
        end
        if has_complete_session(found) then
          cookies, err, cookie_source = found, nil, candidate
          break
        end
      end
    end
  else
    cookies, err = LeetCodeBrowser.read_cookies(browser)
    cookie_source = cookies ~= nil and browser or nil
  end

  if generation ~= cache_generation then return nil end
  LeetCodeBrowser.cache = {
    value = cookies,
    at = LeetCodeBrowser.now(),
    browser = cookie_source,
    source = configured,
    url = configured_url,
  }
  if err ~= nil then log.warn('browser cookies: ' .. err) end
  return cookies
end

--- Reset the cookie cache without forgetting failed sources.
LeetCodeBrowser.reset_cache = function()
  cache_generation = cache_generation + 1
  LeetCodeBrowser.cache = nil
end

--- Reset the cache and failed-source tracking (e.g. after configuration changes).
LeetCodeBrowser.reset = function()
  LeetCodeBrowser.reset_cache()
  failed_sources = {}
end

--- Invalidate cookies from the source that failed authentication.
---
--- The source is skipped in `auto` mode until the cookie cache TTL expires.
LeetCodeBrowser.reset_cookies = function()
  cache_generation = cache_generation + 1
  local cache = LeetCodeBrowser.cache
  if cache ~= nil and cache.browser ~= nil then failed_sources[cache.browser] = LeetCodeBrowser.now() end
  LeetCodeBrowser.cache = nil
end

return LeetCodeBrowser
