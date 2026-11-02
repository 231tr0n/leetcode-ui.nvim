--- *leetcode-ui-auth* Session handling based on LeetCode cookies
---
--- Cookies are resolved in this order:
--- 1. `cookie_file`: a Netscape-format cookie jar consumed by curl directly.
--- 2. `cookies` from configuration.
--- 3. Environment variables `LEETCODE_SESSION` and `CSRFTOKEN`.
--- 4. LeetCode cookies imported from a supported browser.
---
--- |LeetCodeAuth.verify()| lazily runs the `userStatus` GraphQL query and
--- caches `{ signed_in, name, is_premium }` for the rest of the session.
---
---@tag LeetCodeAuth
---@toc_entry Authentication

local LeetCodeAuth = {}

local config = require('leetcode-ui.config')
local net = require('leetcode-ui.net')
local queries = require('leetcode-ui.api.queries')

-- Helper data =======================================================================================================

LeetCodeAuth.session = {}

-- Helper functionality =============================================================================================

--- Configured cookie-jar path, if any.
---
---@return string|nil
LeetCodeAuth.cookie_file = function()
  local path = config.config.cookie_file
  if path == nil or path == '' then return nil end
  return vim.fs.normalize(path)
end

--- Read the `csrftoken` value from a Netscape cookie jar.
---
---@param path string
---@return string|nil
LeetCodeAuth.jar_csrf = function(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end

  for _, line in ipairs(lines) do
    if not line:find('^#') and not line:find('^%s*$') then
      local fields = vim.split(line, '\t', { plain = true })
      if fields[6] == 'csrftoken' then return fields[7] end
    end
  end
  return nil
end

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

--- Whether any session source is configured.
---
---@return boolean
LeetCodeAuth.has_session = function()
  if LeetCodeAuth.cookie_file() ~= nil then return true end
  local cookies = LeetCodeAuth.cookies()
  return cookies.LEETCODE_SESSION ~= nil and cookies.csrftoken ~= nil
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
      for name, value in pairs(cookies) do
        table.insert(parts, ('%s=%s'):format(name, value))
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
    LeetCodeAuth.session = {}
    return nil, 'Authentication failed or session expired (check cookies)'
  end
  return res, nil
end

-- Public API ========================================================================================================

--- Verify the current session against LeetCode, caching the result.
---
---@return table|nil session
---@return string|nil err
LeetCodeAuth.verify = function()
  if LeetCodeAuth.session ~= nil and LeetCodeAuth.session.checked then return LeetCodeAuth.session, nil end

  if not LeetCodeAuth.has_session() then
    LeetCodeAuth.session = { checked = true, signed_in = false, name = nil, is_premium = false }
    return LeetCodeAuth.session, nil
  end

  local body = vim.json.encode({ query = queries.auth, variables = {} })
  local res, err = net.request({
    url = ('https://%s/graphql/'):format(config.config.url),
    method = 'POST',
    headers = LeetCodeAuth.headers(),
    body = body,
    cookie_file = LeetCodeAuth.cookie_file(),
  })

  if err ~= nil then return nil, err end

  res, err = LeetCodeAuth.handle_status(res)
  if err ~= nil then return nil, err end
  if res == nil then return nil, 'Empty response' end

  local ok, decoded = pcall(vim.json.decode, res.body)
  if not ok or decoded == nil or decoded.data == nil then
    return nil, 'Failed to verify authentication (bad response)'
  end

  local user = decoded.data.userStatus or {}
  local signed_in = user.is_signed_in == true and user.id ~= nil and user.id ~= vim.NIL
  LeetCodeAuth.session = {
    checked = true,
    signed_in = signed_in,
    name = user.name,
    is_premium = user.is_premium == true,
    user_id = user.id,
  }
  return LeetCodeAuth.session, nil
end

--- Drop the cached session (cookie expired or user changed configuration).
LeetCodeAuth.reset = function() LeetCodeAuth.session = {} end

return LeetCodeAuth
