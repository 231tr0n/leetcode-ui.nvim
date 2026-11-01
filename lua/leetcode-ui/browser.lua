--- *LeetCodeBrowser*
---
---@tag LeetCodeBrowser

-- |leetcode-ui-browser| Automatic cookie import from browsers.
-- Supported (Linux):
--   firefox  - ~/.mozilla/firefox/<profile>/cookies.sqlite (plain SQLite)
--   google-chrome/chromium/microsoft-edge/brave - "Cookies" SQLite; legacy
--       `v10` blobs decrypt via the well-known Chromium scheme using `openssl`:
--       AES-128-CBC, key = first 16 HMAC-SHA1('peanuts', 'saltysalt' || be32(1)),
--       IV = 16 * 0x20, 3-byte 'v10' prefix stripped before decryption.
--       `v11+` blobs are keyring-protected: surfaced as an explicit error.
--
-- Browser DBs are COPIED to a temporary directory before reading, so browser
-- locks are untouched. Only rows for the two LeetCode cookie names on
-- `%.leetcode.com` hosts are queried; decrypted values never hit the disk.

local LeetCodeBrowser = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeBrowser.os_name = function()
  local sysname = (vim.uv.os_uname() or {}).sysname or ''
  if sysname == 'Darwin' then return 'macos' end
  if sysname == 'Windows_NT' then return 'windows' end
  return 'linux'
end

LeetCodeBrowser.home = function() return vim.env.HOME or vim.env.USERPROFILE or '' end

-- (OS-aware helpers above)

LeetCodeBrowser.cookie_names = { 'LEETCODE_SESSION', 'csrftoken' }

LeetCodeBrowser.is_chromium = function(browser)
  return browser == 'chrome' or browser == 'brave' or browser == 'edge' or browser == 'chromium'
end

LeetCodeBrowser.chromium_root = function(browser)
  local osname = LeetCodeBrowser.os_name()
  local home = LeetCodeBrowser.home()
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

LeetCodeBrowser.python_script = [[
import json, os, shutil, sqlite3, sys, tempfile

KIND, DB = sys.argv[1], sys.argv[2]
NAMES = tuple(sys.argv[3:5])
host_like = ('%leetcode.com',)

def query(con, sql, params):
    try:
        rows = con.execute(sql, params).fetchall()
        cols = [d[0] for d in con.execute(sql, params).description]
        return [dict(zip(cols, row)) for row in rows]
    finally:
        pass

def read(db_path, sql, params):
    with tempfile.TemporaryDirectory() as tmp:
        copied = os.path.join(tmp, os.path.basename(db_path))
        shutil.copyfile(db_path, copied)
        con = sqlite3.connect(copied)
        try:
            return query(con, sql, params)
        finally:
            con.close()

if KIND in ('firefox', 'epiphany'):
    sql = 'SELECT name AS name, value AS value, \'\' AS blob FROM moz_cookies ' \
        'WHERE host LIKE ? AND name IN (?, ?)'
else:
    sql = 'SELECT name AS name, value AS value, hex(encrypted_value) AS blob FROM cookies ' \
        'WHERE host_key LIKE ? AND name IN (?, ?)'

print(json.dumps(read(DB, sql, host_like + NAMES)))
]]
LeetCodeBrowser.safari_script = [[
import json, struct, sys
from io import BytesIO

path = sys.argv[1]
names = set(sys.argv[2:])

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
        cookie.read(8)
        cookie.read(8)

        url = read_str(cookie, url_off)
        name = read_str(cookie, name_off)
        value = read_str(cookie, value_off)

        if 'leetcode' in url.lower() and name in names:
            result[name] = value

print(json.dumps(result))
]]

-- Helper functionality ==============================================================================================

LeetCodeBrowser.cookie_db = function(browser)
  local overridden = (config.config.browser_paths or {})[browser]
  if overridden ~= nil and overridden ~= '' then
    local path = vim.fs.normalize(overridden)
    local stat = vim.uv.fs_stat(path)
    if stat ~= nil then
      if stat.type == 'directory' then
        if browser == 'firefox' or browser == 'epiphany' then
          local nested = vim.fn.glob(vim.fs.joinpath(path, '*', 'cookies.sqlite'), true, true)
          if #nested == 0 then nested = vim.fn.glob(vim.fs.joinpath(path, 'cookies.sqlite'), true, true) end
          if #nested > 0 then return nested[1] end
        else
          local nested = vim.fn.glob(vim.fs.joinpath(path, '*', 'Cookies'), true, true)
          if #nested == 0 then nested = vim.fn.glob(vim.fs.joinpath(path, 'Cookies'), true, true) end
          if #nested > 0 then return nested[1] end
        end
        return nil
      end
      return path
    end
    if browser == 'firefox' or browser == 'epiphany' then
      local nested = vim.fn.glob(vim.fs.joinpath(path, '*', 'cookies.sqlite'), true, true)
      if #nested == 0 then nested = vim.fn.glob(vim.fs.joinpath(path, 'cookies.sqlite'), true, true) end
      if #nested > 0 then return nested[1] end
    else
      local nested = vim.fn.glob(vim.fs.joinpath(path, '*', 'Cookies'), true, true)
      if #nested == 0 then nested = vim.fn.glob(vim.fs.joinpath(path, 'Cookies'), true, true) end
      if #nested > 0 then return nested[1] end
    end
    return nil
  end

  local candidates = {}
  if browser == 'firefox' then
    local osname = LeetCodeBrowser.os_name()
    local home = LeetCodeBrowser.home()
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
    local home = LeetCodeBrowser.home()
    vim.list_extend(
      candidates,
      vim.fn.glob(vim.fs.joinpath(home, '.local', 'share', 'epiphany', 'cookies.sqlite'), true, true)
    )
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(home, '.config', 'epiphany', 'cookies.sqlite'), true, true))
  elseif browser == 'safari' then
    local home = LeetCodeBrowser.home()
    local p = vim.fs.joinpath(home, 'Library', 'Cookies', 'Cookies.binarycookies')
    if vim.uv.fs_stat(p) ~= nil then table.insert(candidates, p) end
  else
    local root = LeetCodeBrowser.chromium_root(browser)
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(root or '', '*', 'Cookies'), true, true))
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(root or '', '*', 'Network', 'Cookies'), true, true))
  end
  if #candidates == 0 then return nil end

  table.sort(candidates, function(a, b)
    local am = (vim.uv.fs_stat(a) or {}).mtime
    local bm = (vim.uv.fs_stat(b) or {}).mtime
    return (am and am.sec or 0) > (bm and bm.sec or 0)
  end)
  return candidates[1]
end

LeetCodeBrowser.selected = function()
  local browser = config.config.browser
  if browser == nil or browser == 'none' then return nil end

  if browser == 'auto' then
    for _, key in ipairs({ 'firefox', 'epiphany', 'safari', 'chrome', 'brave', 'edge', 'chromium' }) do
      if LeetCodeBrowser.cookie_db(key) ~= nil then return key end
    end
    return nil
  end

  return browser
end

LeetCodeBrowser.unhex = function(hex)
  return (hex:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end))
end

LeetCodeBrowser.keyring_password = function(browser)
  local osname = LeetCodeBrowser.os_name()
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
      local out = vim.system({ 'secret-tool', 'lookup', 'application', app }, { text = true }):wait()
      if out.code == 0 then
        local pw = vim.trim(out.stdout or '')
        if pw ~= '' then return pw end
      end
    end
    return nil
  elseif osname == 'macos' then
    local svc = service .. ' Safe Storage'
    local out = vim.system({ 'security', 'find-generic-password', '-w', '-s', svc }, { text = true }):wait()
    if out.code == 0 then return vim.trim(out.stdout or '') end
    return nil
  elseif osname == 'windows' then
    -- Windows Chrome uses DPAPI; not implemented. Use cookie_file or env vars.
    return nil
  end
  return nil
end

LeetCodeBrowser.derive_key = function(password)
  password = password or 'peanuts'
  local message = 'saltysalt' .. string.char(0, 0, 0, 1)
  local out = vim
    .system({ 'openssl', 'dgst', '-sha1', '-hmac', password }, {
      text = true,
      stdin = message,
    })
    :wait()
  if out.code ~= 0 then return nil end

  local stdout = vim.trim(out.stdout or '')
  local hex = stdout:match('%x+$')
  if hex == nil or #hex < 32 then return nil end
  return hex:sub(1, 32)
end

LeetCodeBrowser.decrypt_blob = function(blob_hex, browser)
  if blob_hex == nil or blob_hex == '' then return nil, nil end

  local raw = LeetCodeBrowser.unhex(blob_hex:lower())
  local version = raw:sub(1, 3)
  ---@type string|nil
  local password = 'peanuts'
  if version == 'v11' then
    password = LeetCodeBrowser.keyring_password(browser)
    if password == nil or password == '' then
      return nil, ('blob version %q is not supported (keyring-protected)'):format(version)
    end
  elseif version ~= 'v10' then
    return nil, ('blob version %q is not supported'):format(version)
  end

  local key_hex = LeetCodeBrowser.derive_key(password)
  if key_hex == nil then return nil, 'openssl is unavailable' end

  local ct_file = vim.fn.tempname() .. '.lcv10'
  local file = io.open(ct_file, 'wb')
  if file == nil then return nil, 'cannot create temp file' end
  file:write(raw:sub(4))
  file:close()

  local out = vim
    .system({
      'openssl',
      'enc',
      '-d',
      '-aes-128-cbc',
      '-K',
      key_hex,
      '-iv',
      string.rep('20', 16),
      '-in',
      ct_file,
    }, { text = true })
    :wait()
  os.remove(ct_file)

  if out.code ~= 0 then return nil, 'AES-CBC decryption failed' end

  local value = out.stdout or ''
  if value == '' then return nil, nil end

  -- Chrome prefixes the plaintext with a 32-byte integrity hash on Linux.
  if #value > 32 then
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

LeetCodeBrowser.read_cookies = function(browser)
  if browser == 'safari' then
    local db = LeetCodeBrowser.cookie_db(browser)
    if db == nil then return nil, 'No Safari cookie file found' end
    local out = vim
      .system({ 'python3', '-c', LeetCodeBrowser.safari_script, db, 'LEETCODE_SESSION', 'csrftoken' }, { text = true })
      :wait()
    if out.code ~= 0 then return nil, ('safari reader failed: %s'):format(vim.trim(out.stderr or 'unknown error')) end
    local ok, cookies = pcall(vim.json.decode, vim.trim(out.stdout or ''))
    if not ok or type(cookies) ~= 'table' then return nil, 'safari reader returned invalid JSON' end
    return cookies, nil
  end

  local db = LeetCodeBrowser.cookie_db(browser)
  if db == nil then return nil, ('No %s cookie database found'):format(browser) end

  local out = vim
    .system(
      vim.list_extend({ 'python3', '-c', LeetCodeBrowser.python_script, browser, db }, LeetCodeBrowser.cookie_names),
      { text = true }
    )
    :wait()
  if out.code ~= 0 then return nil, ('sqlite reader failed: %s'):format(vim.trim(out.stderr or 'unknown error')) end

  local ok, rows = pcall(vim.json.decode, vim.trim(out.stdout or ''))
  if not ok or type(rows) ~= 'table' then return nil, 'sqlite reader returned invalid JSON' end

  local cookies, warnings = {}, {}
  for _, row in ipairs(rows) do
    local name = row.name
    local value = row.value

    if LeetCodeBrowser.is_chromium(browser) and (value == nil or value == '') then
      local plain, derr = LeetCodeBrowser.decrypt_blob(row.blob, browser)
      if derr ~= nil then table.insert(warnings, ('%s: %s'):format(name or 'cookie', derr)) end
      value = plain
    end

    if name ~= nil and value ~= nil and value ~= '' then cookies[name] = value end
  end

  local err = #warnings > 0 and table.concat(warnings, '; ') or nil
  return cookies, err
end

-- Public API ========================================================================================================

---Resolved browser cookies (session cache, 5 minute TTL).
---
---@return table|nil cookies name -> value or nil
LeetCodeBrowser.get_cookies = function()
  local cache = LeetCodeBrowser.cache or {}
  if cache.at ~= nil and (os.time() - cache.at) <= 300 then return cache.value end

  local browser = LeetCodeBrowser.selected()
  if browser == nil then
    LeetCodeBrowser.cache = { value = nil, at = os.time() }
    return nil
  end

  local cookies, err = LeetCodeBrowser.read_cookies(browser)
  LeetCodeBrowser.cache = { value = cookies, at = os.time(), err = err, browser = browser }

  if err ~= nil then vim.notify('(leetcode-ui) browser cookies: ' .. err, vim.log.levels.WARN) end

  return cookies
end

---Reset the cache (e.g. forced refresh after login changes).
LeetCodeBrowser.reset = function() LeetCodeBrowser.cache = nil end

return LeetCodeBrowser
