--- *leetcode-ui-auth* Session handling based on LeetCode cookies
---
--- Requests use `cookie_file` when configured: curl consumes the Netscape jar
--- directly. Otherwise cookies are resolved from configuration, environment
--- variables (`LEETCODE_SESSION` and `CSRFTOKEN`), then supported browsers
--- when `browser` import is enabled.
---
--- |LeetCodeAuth.verify()| lazily runs the `userStatus` GraphQL query and
--- caches successful results as `{ checked, signed_in, name, is_premium,
--- user_id }` until reset, the first setup, or a credential/URL change.
--- Signed-out checks are not cached. With no resolved credentials, browser
--- caches are cleared so a fresh sign-in is found on the next check; sources
--- that rejected credentials stay skipped in `auto` browser mode until the
--- cookie cache TTL expires.
---@tag LeetCodeAuth
---@toc_entry Authentication

local LeetCodeAuth = {}

local config = require('leetcode-ui.config')
local net = require('leetcode-ui.net')
local queries = require('leetcode-ui.api.queries')

-- Helper data =======================================================================================================

LeetCodeAuth.session = {}

local verify_generation = 0
local session_key = nil

-- Helper functionality =============================================================================================

--- Configured cookie-jar path, if any.
---
---@return string|nil
LeetCodeAuth.cookie_file = function()
  local path = config.config.cookie_file
  if path == nil or path == '' then return nil end
  return vim.fs.normalize(path)
end

local function jar_value(path, name)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end

  local site = config.config.url:gsub('^www%.', ''):lower()
  local function domain_matches(domain)
    domain = domain:gsub('^%.', ''):lower()
    return domain == site or site:sub(-#domain - 1) == '.' .. domain
  end

  local now = os.time()
  for _, line in ipairs(lines) do
    line = line:gsub('^#HttpOnly_', '')
    if not line:find('^#') and not line:find('^%s*$') then
      local fields = vim.split(line, '\t', { plain = true })
      local expires = tonumber(fields[5])
      local value = fields[7]
      local valid = fields[6] == name
        and domain_matches(fields[1] or '')
        and (expires == nil or expires == 0 or expires > now)
        and type(value) == 'string'
        and value ~= ''
      if valid then return value end
    end
  end
  return nil
end

--- Read the `csrftoken` value from a Netscape cookie jar.
---
---@param path string
---@return string|nil
LeetCodeAuth.jar_csrf = function(path) return jar_value(path, 'csrftoken') end

--- Resolve cookies from configuration, environment, and browsers.
---
---@return table cookies name -> value
LeetCodeAuth.cookies = function()
  local resolved = {}
  local configured = config.config.cookies or {}
  local environment = {
    LEETCODE_SESSION = vim.env.LEETCODE_SESSION,
    csrftoken = vim.env.CSRFTOKEN,
  }

  for _, name in ipairs({ 'LEETCODE_SESSION', 'csrftoken' }) do
    local value = configured[name]
    if value == nil or value == '' then value = environment[name] end
    if value ~= nil and value ~= '' then resolved[name] = value end
  end

  if resolved.LEETCODE_SESSION ~= nil and resolved.csrftoken ~= nil then return resolved end

  local browser_cookies = require('leetcode-ui.browser').get_cookies() or {}
  for name, value in pairs(browser_cookies) do
    if resolved[name] == nil or resolved[name] == '' then resolved[name] = value end
  end

  return resolved
end

--- Stable identity for the current credentials.
---
--- Used to invalidate caches that contain user-specific data without storing
--- cookie values in plain text.
---
---@return string key
LeetCodeAuth.cache_key = function()
  local jar = LeetCodeAuth.cookie_file()
  if jar ~= nil then
    local session = jar_value(jar, 'LEETCODE_SESSION')
    return 'jar:' .. vim.fn.sha256(session ~= nil and session or jar)
  end

  local session = LeetCodeAuth.cookies().LEETCODE_SESSION
  if session == nil or session == '' then return 'anonymous' end
  return 'session:' .. vim.fn.sha256(session)
end

--- Whether complete session credentials are available.
---
---@return boolean
LeetCodeAuth.has_session = function()
  if LeetCodeAuth.cookie_file() ~= nil then return true end
  local cookies = LeetCodeAuth.cookies()
  return type(cookies.LEETCODE_SESSION) == 'string'
    and cookies.LEETCODE_SESSION ~= ''
    and type(cookies.csrftoken) == 'string'
    and cookies.csrftoken ~= ''
end

--- Current CSRF token.
---
---@return string|nil
LeetCodeAuth.csrf = function()
  local jar = LeetCodeAuth.cookie_file()
  if jar ~= nil then return LeetCodeAuth.jar_csrf(jar) end
  return LeetCodeAuth.cookies().csrftoken
end

--- Build request headers, including session data when available.
---
---@param opts table|nil Extra raw header strings.
---@return table headers
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
    -- curl reads the cookie jar itself; only the CSRF header is needed here.
    if csrf ~= nil then table.insert(headers, ('X-CSRFToken: %s'):format(csrf)) end
  else
    local cookies = LeetCodeAuth.cookies()
    if cookies.LEETCODE_SESSION ~= nil and cookies.csrftoken ~= nil then
      local parts = {}
      local names = vim.tbl_keys(cookies)
      table.sort(names)
      for _, name in ipairs(names) do
        table.insert(parts, ('%s=%s'):format(name, cookies[name]))
      end
      table.insert(headers, ('Cookie: %s'):format(table.concat(parts, '; ')))
      if csrf ~= nil then table.insert(headers, ('X-CSRFToken: %s'):format(csrf)) end
    end
  end

  for _, header in ipairs(opts or {}) do
    table.insert(headers, header)
  end
  return headers
end

--- Convert authentication failures into user-facing errors.
---
---@param res table|nil
---@return table|nil response
---@return string|nil err
LeetCodeAuth.handle_status = function(res)
  if res == nil then return nil, 'Network request failed' end
  if res.status == 401 or res.status == 403 then
    LeetCodeAuth.reset()
    require('leetcode-ui.browser').reset_cookies()
    return nil, 'Authentication failed or session expired (check cookies)'
  end
  return res, nil
end

-- Public API ========================================================================================================

--- Verify the current session against LeetCode, caching successful results.
---
---@return table|nil session
---@return string|nil err
LeetCodeAuth.verify = function()
  if LeetCodeAuth.session ~= nil and LeetCodeAuth.session.checked then
    if session_key == LeetCodeAuth.cache_key() then return LeetCodeAuth.session, nil end
    LeetCodeAuth.reset()
  end
  local generation = verify_generation
  local request_key = LeetCodeAuth.cache_key()

  if not LeetCodeAuth.has_session() then
    if generation ~= verify_generation then return nil, 'Authentication state changed' end
    -- Re-read browsers on the next check. Sources that rejected credentials
    -- stay skipped until the cookie cache TTL expires.
    require('leetcode-ui.browser').reset_cache()
    return { checked = true, signed_in = false, name = nil, is_premium = false }, nil
  end

  local body = vim.json.encode({ query = queries.auth, variables = vim.empty_dict() })
  local res, err = net.request({
    url = ('https://%s/graphql/'):format(config.config.url),
    method = 'POST',
    headers = LeetCodeAuth.headers(),
    body = body,
    cookie_file = LeetCodeAuth.cookie_file(),
  })

  if generation ~= verify_generation then return nil, 'Authentication state changed' end
  local final_key = LeetCodeAuth.cache_key()
  if generation ~= verify_generation or request_key ~= final_key then return nil, 'Authentication state changed' end
  if err ~= nil then return nil, err end

  res, err = LeetCodeAuth.handle_status(res)
  if err ~= nil then return nil, err end
  if res == nil then return nil, 'Empty response' end
  if res.status == 429 then return nil, 'Too many requests, LeetCode requires a short cool-down' end
  if res.status < 200 or res.status >= 300 then return nil, ('Request failed (HTTP %s)'):format(res.status) end

  local ok, decoded = pcall(vim.json.decode, res.body)
  if not ok or type(decoded) ~= 'table' then return nil, 'Failed to verify authentication (bad response)' end
  if type(decoded.errors) == 'table' and next(decoded.errors) ~= nil then
    local messages = {}
    for _, item in ipairs(decoded.errors) do
      table.insert(
        messages,
        type(item) == 'table' and type(item.message) == 'string' and item.message or 'unknown error'
      )
    end
    return nil, table.concat(messages, '\n')
  end
  if type(decoded.data) ~= 'table' then return nil, 'Failed to verify authentication (bad response)' end

  local user = type(decoded.data.userStatus) == 'table' and decoded.data.userStatus or {}
  local signed_in = user.is_signed_in == true and user.id ~= nil and user.id ~= vim.NIL
  local session = {
    checked = true,
    signed_in = signed_in,
    name = type(user.name) == 'string' and user.name or nil,
    is_premium = user.is_premium == true,
    user_id = user.id,
  }
  if signed_in then
    if generation ~= verify_generation then return nil, 'Authentication state changed' end
    session_key = request_key
    LeetCodeAuth.session = session
  else
    session_key = nil
    -- Skip the browser source that failed and retry the next verification.
    require('leetcode-ui.browser').reset_cookies()
  end
  return session, nil
end

--- Drop the cached session (cookie expired or user changed configuration).
LeetCodeAuth.reset = function()
  verify_generation = verify_generation + 1
  session_key = nil
  LeetCodeAuth.session = {}
end

return LeetCodeAuth
