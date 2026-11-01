-- |leetcode-ui-browser| Automatic cookie import from browsers.
--------------------------------------------------------------------------------
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
--------------------------------------------------------------------------------

local H = {}

local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

---Names of cookies the plugin needs, in query order.
H.cookie_names = { 'LEETCODE_SESSION', 'csrftoken' }

---Chromium-based browser roots (checked in list order).
H.chromium_roots = {
  chrome = vim.fs.joinpath(vim.env.HOME or '', '.config', 'google-chrome'),
  brave = vim.fs.joinpath(vim.env.HOME or '', '.config', 'BraveSoftware', 'Brave-Browser'),
  edge = vim.fs.joinpath(vim.env.HOME or '', '.config', 'microsoft-edge'),
  chromium = vim.fs.joinpath(vim.env.HOME or '', '.config', 'chromium'),
}

---Whether `browser` is a Chromium-based one (uses `encrypted_value` blobs).
H.is_chromium = function(browser) return H.chromium_roots[browser] ~= nil and browser ~= 'firefox' end

---The embedded reader script. Runs standalone: `python3 SCRIPT <kind> <db>`.
H.python_script = [[
import json, os, shutil, sqlite3, sys, tempfile

KIND, DB = sys.argv[1], sys.argv[2]
NAMES = tuple(sys.argv[3:5])
host_like = ('%.leetcode.com',)

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

if KIND == 'firefox':
    sql = 'SELECT name AS name, value AS value, \'\' AS blob FROM moz_cookies ' \
        'WHERE host LIKE ? AND name IN (?, ?)'
else:
    sql = 'SELECT name AS name, value AS value, hex(encrypted_value) AS blob FROM cookies ' \
        'WHERE host_key LIKE ? AND name IN (?, ?)'

print(json.dumps(read(DB, sql, host_like + NAMES)))
]]

-- Helper functionality ==============================================================================================

---Locate the most recently modified cookie database for a browser.
---
---@param browser string
---@return string|nil db path.
---@private
H.cookie_db = function(browser)
  local overridden = (config.config.browser_paths or {})[browser]
  if overridden ~= nil and overridden ~= '' then
    local path = vim.fs.normalize(overridden)
    local stat = vim.uv.fs_stat(path)
    if stat ~= nil then
      if stat.type == 'directory' then
        if browser == 'firefox' then
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
    if browser == 'firefox' then
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
    vim.list_extend(
      candidates,
      vim.fn.glob(vim.fs.joinpath(vim.env.HOME or '', '.mozilla', 'firefox', '*', 'cookies.sqlite'), true, true)
    )
  else
    local root = H.chromium_roots[browser]
    vim.list_extend(candidates, vim.fn.glob(vim.fs.joinpath(root or '', '*', 'Cookies'), true, true))
  end
  if #candidates == 0 then return nil end

  table.sort(candidates, function(a, b)
    local am = (vim.uv.fs_stat(a) or {}).mtime
    local bm = (vim.uv.fs_stat(b) or {}).mtime
    return (am and am.sec or 0) > (bm and bm.sec or 0)
  end)
  return candidates[1]
end

---Configured browser selection.
---
---@return string|nil browser key, nil when disabled or not found.
H.selected = function()
  local browser = config.config.browser
  if browser == nil or browser == 'none' then return nil end

  if browser == 'auto' then
    for _, key in ipairs({ 'firefox', 'chrome', 'brave', 'edge', 'chromium' }) do
      if H.cookie_db(key) ~= nil then return key end
    end
    return nil
  end

  return browser
end

---Hex string to raw bytes.
---
---@param hex string
---@return string
H.unhex = function(hex)
  return (hex:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end))
end

---Chromium v10 AES key derivation (first 32 hex chars of an HMAC-SHA1 block).
---
---@return string|nil key_hex
H.derive_key = function()
  local message = 'saltysalt' .. string.char(0, 0, 0, 1)
  local out = vim
    .system({ 'openssl', 'dgst', '-sha1', '-hmac', 'peanuts' }, {
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

---Decrypt one Chromium `v10` cookie blob.
---
---@param blob_hex string|nil Hex of hex-encoded blob.
---@return string|nil value nil/'': nothing usable.
---@return string|nil err Message only for unsupported versions or failures.
H.decrypt_blob = function(blob_hex)
  if blob_hex == nil or blob_hex == '' then return nil, nil end

  local raw = H.unhex(blob_hex:lower())
  if raw:sub(1, 3) ~= 'v10' then
    return nil, ('blob version %q is not supported (keyring-protected)'):format(raw:sub(1, 3))
  end

  local key_hex = H.derive_key()
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
  return value, nil
end

---Read all LeetCode cookies from a browser database.
---
---@param browser string
---@return table|nil cookies name -> value
---@return string|nil err Collected warning/error messages.
H.read_cookies = function(browser)
  local db = H.cookie_db(browser)
  if db == nil then return nil, ('No %s cookie database found'):format(browser) end

  local out = vim
    .system(vim.list_extend({ 'python3', '-c', H.python_script, browser, db }, H.cookie_names), { text = true })
    :wait()
  if out.code ~= 0 then return nil, ('sqlite reader failed: %s'):format(vim.trim(out.stderr or 'unknown error')) end

  local ok, rows = pcall(vim.json.decode, vim.trim(out.stdout or ''))
  if not ok or type(rows) ~= 'table' then return nil, 'sqlite reader returned invalid JSON' end

  local cookies, warnings = {}, {}
  for _, row in ipairs(rows) do
    local name = row.name
    local value = row.value

    if H.is_chromium(browser) and (value == nil or value == '') then
      local plain, derr = H.decrypt_blob(row.blob)
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
H.get_cookies = function()
  local cache = H.cache or {}
  if cache.at ~= nil and (os.time() - cache.at) <= 300 then return cache.value end

  local browser = H.selected()
  if browser == nil then
    H.cache = { value = nil, at = os.time() }
    return nil
  end

  local cookies, err = H.read_cookies(browser)
  H.cache = { value = cookies, at = os.time(), err = err, browser = browser }

  if err ~= nil then vim.notify('(leetcode-ui) browser cookies: ' .. err, vim.log.levels.WARN) end

  return cookies
end

---Reset the cache (e.g. forced refresh after login changes).
H.reset = function() H.cache = nil end

return H
