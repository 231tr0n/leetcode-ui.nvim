--- *leetcode-ui-auth* Session handling based on LeetCode cookies
---
---@tag LeetCodeAuth
---

-- |leetcode-ui-auth| Session handling based on LeetCode cookies.
-- Cookies are resolved in this order:
-- 1. `cookie_file`: a Netscape-format cookie jar consumed by curl directly.
-- 2. `cookies` from configuration.
-- 3. Environment variables `LEETCODE_SESSION` and `CSRFTOKEN`.
-- Nothing is ever written to disk by this module.
--
-- Flow:
-- 1. Requests carry `Cookie` + `X-CSRFToken` headers only when a session exists.
-- 2. `LeetCodeAuth.verify()` lazily runs the `userStatus` GraphQL query and caches
--    `{signed_in, name, is_premium}` for the duration of the session.
-- 3. HTTP 401/403 invalidates cached state and reports a refresh hint.

-- Module design:
local LeetCodeAuth = {}

local config = require('leetcode-ui.config')
local net = require('leetcode-ui.net')
local queries = require('leetcode-ui.api.queries')

-- Helper data =======================================================================================================

LeetCodeAuth.session = {}

-- Helper functionality ==============================================================================================

LeetCodeAuth.cookie_file = function()
  local path = config.config.cookie_file
  if path == nil or path == '' then return nil end
  return vim.fs.normalize(path)
end

LeetCodeAuth.jar_csrf = function(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end

  for _, line in ipairs(lines) do
    if not line:find('^#') and not line:find('^%s*$') then
      local fields = vim.split(line, '	', { plain = true })
      if fields[6] == 'csrftoken' then return fields[7] end
    end
  end
  return nil
end

LeetCodeAuth.cookies = function()
  local resolved = {}
  local user = config.config.cookies or {}
  local env = {
    LEETCODE_SESSION = vim.env.LEETCODE_SESSION,
    csrftoken = vim.env.CSRFTOKEN,
  }

  for _, name in ipairs({ 'LEETCODE_SESSION', 'csrftoken' }) do
    local value = user[name]
    if value == nil or value == '' then value = env[name] end
    if value ~= nil and value ~= '' then resolved[name] = value end
  end

  -- Browser import only completes missing entries.
  local browser = require('leetcode-ui.browser')
  local browser_cookies = browser.get_cookies() or {}
  for name, value in pairs(browser_cookies) do
    if resolved[name] == nil or resolved[name] == '' then resolved[name] = value end
  end

  return resolved
end

LeetCodeAuth.has_session = function()
  if LeetCodeAuth.cookie_file() ~= nil then return true end
  local cookies = LeetCodeAuth.cookies()
  return cookies.LEETCODE_SESSION ~= nil and cookies.csrftoken ~= nil
end

LeetCodeAuth.csrf = function()
  local jar = LeetCodeAuth.cookie_file()
  if jar ~= nil then return LeetCodeAuth.jar_csrf(jar) end
  return LeetCodeAuth.cookies().csrftoken
end

LeetCodeAuth.headers = function(opts)
  local domain = config.config.url
  local headers = {
    ('User-Agent: %s'):format('Mozilla/5.0 (X11; Linux x86_64) leetcode-ui.nvim'),
    ('Referer: https://%s'):format(domain),
    ('Origin: https://%s'):format(domain),
    'Accept: application/json',
    'Content-Type: application/json',
  }

  local csrf = LeetCodeAuth.csrf()
  local jar = LeetCodeAuth.cookie_file()

  if jar ~= nil then
    -- Session cookies are supplied by curl itself; only the header matters.
    if csrf ~= nil then table.insert(headers, ('X-CSRFToken: %s'):format(csrf)) end
  elseif LeetCodeAuth.has_session() then
    local parts = {}
    for name, value in pairs(LeetCodeAuth.cookies()) do
      table.insert(parts, ('%s=%s'):format(name, value))
    end
    table.insert(headers, ('Cookie: %s'):format(table.concat(parts, '; ')))
    if csrf ~= nil then table.insert(headers, ('X-CSRFToken: %s'):format(csrf)) end
  end

  for _, header in ipairs(opts or {}) do
    table.insert(headers, header)
  end

  return headers
end

LeetCodeAuth.handle_status = function(res)
  if res == nil then return nil, 'Network request failed' end

  -- 429 or other server-side throttling handled inside net retries; treat as generic.
  if res.status == 401 or res.status == 403 then return nil, 'Authentication failed/Session expired (check cookies)' end

  return res, nil
end

-- Public API ========================================================================================================

---Verify current session against LeetCode, caching state.
---
---@return table|nil session
---@return string|nil err
LeetCodeAuth.verify = function()
  if LeetCodeAuth.session ~= nil and LeetCodeAuth.session.checked then return LeetCodeAuth.session, nil end

  if not LeetCodeAuth.has_session() then
    LeetCodeAuth.session = { checked = true, signed_in = false, name = nil, is_premium = false }
    return LeetCodeAuth.session, nil
  end

  local local_query = queries.auth
  local body = vim.json.encode({ query = local_query, variables = {} })
  local res, err = net.request({
    url = ('https://%s/graphql/'):format(config.config.url),
    method = 'POST',
    headers = LeetCodeAuth.headers(),
    body = body,
    cookie_file = LeetCodeAuth.cookie_file(),
  })

  if err ~= nil then return nil, err end

  res, err = LeetCodeAuth.handle_status(res)
  if err ~= nil then
    LeetCodeAuth.session = { checked = false, signed_in = false }
    return nil, err
  end
  if res == nil then return nil, 'Empty response' end

  local ok, decoded = pcall(vim.json.decode, res.body)
  if not ok or not decoded or not decoded.data then return nil, 'Failed to verify authentication (bad response)' end

  local user = decoded.data.userStatus or {}
  local signed_in = user.is_signed_in == true and (user.id ~= vim.NIL and user.id ~= nil)

  LeetCodeAuth.session = {
    checked = true,
    signed_in = signed_in,
    name = user.name,
    is_premium = user.is_premium == true,
    user_id = user.id,
  }

  return LeetCodeAuth.session, nil
end

---Whether cookies are configured and marked valid.
---
---@return boolean
LeetCodeAuth.is_signed_in = function() return LeetCodeAuth.session.signed_in == true end

---Current authenticated display name or nil.
---
---@return string|nil
LeetCodeAuth.name = function() return LeetCodeAuth.session.name end

---Premium unlock flag (nil until checked).
---
---@return boolean|nil
LeetCodeAuth.is_premium = function() return LeetCodeAuth.session.is_premium end

---Whether cookies are configured at all (not dictating validity).
---
---@return boolean
LeetCodeAuth.is_logged = function() return LeetCodeAuth.has_session() end

---Drop session cache (cookie expired / user changed config).
LeetCodeAuth.reset = function() LeetCodeAuth.session = {} end

return LeetCodeAuth
