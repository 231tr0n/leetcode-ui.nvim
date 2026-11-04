--- *leetcode-ui-api* GraphQL and REST plumbing
---
--- |LeetCodeApi.graphql()| runs a query and returns decoded `data` (or an
--- error message built from GraphQL `errors`). |LeetCodeApi.rest()| covers
--- non-GraphQL REST endpoints. Both work inside coroutines; calling them on
--- the main thread falls back to blocking requests.
---@tag LeetCodeApi
---@toc_entry API plumbing

local LeetCodeApi = {}

local config = require('leetcode-ui.config')
local net = require('leetcode-ui.net')
local auth = require('leetcode-ui.auth')

-- Helper functionality ==============================================================================================

local function status_error(res)
  if res.status == 429 then return 'Too many requests, LeetCode requires a short cool-down' end
  if res.status < 200 or res.status >= 300 then return ('Request failed (HTTP %s)'):format(res.status) end
end

--- Base HTTPS URL for the configured LeetCode domain.
---
---@return string
LeetCodeApi.base_url = function() return ('https://%s'):format(config.config.url) end

--- Whether `value` is `nil` or `vim.NIL`.
---
---@param value any
---@return boolean
LeetCodeApi.is_null = function(value) return value == nil or value == vim.NIL end

-- Public API ========================================================================================================

--- Run a GraphQL query.
---
---@param query string GraphQL query text (|leetcode-ui-api-queries|).
---@param variables table|nil Query variables.
---@return table|nil data Decoded `data` field.
---@return string|nil err Error message.
LeetCodeApi.graphql = function(query, variables)
  local body = vim.json.encode({ query = query, variables = variables or vim.empty_dict() })
  local res, err = net.request({
    url = LeetCodeApi.base_url() .. '/graphql/',
    method = 'POST',
    headers = auth.headers(),
    body = body,
    cookie_file = auth.cookie_file(),
  })

  if err ~= nil then return nil, err end

  res, err = auth.handle_status(res)
  if err ~= nil then return nil, err end
  if res == nil then return nil, 'Empty response' end

  local http_err = status_error(res)
  if http_err ~= nil then return nil, http_err end

  local ok, decoded = pcall(vim.json.decode, res.body)
  if not ok or type(decoded) ~= 'table' then return nil, ('Malformed response (HTTP %s)'):format(res.status) end

  if type(decoded.errors) == 'table' and next(decoded.errors) ~= nil then
    local messages = {}
    for _, item in ipairs(decoded.errors) do
      local message = type(item) == 'table' and type(item.message) == 'string' and item.message or 'unknown error'
      table.insert(messages, message)
    end
    return nil, table.concat(messages, '\n')
  end

  if LeetCodeApi.is_null(decoded.data) then return nil, 'Empty response' end
  if type(decoded.data) ~= 'table' then return nil, ('Malformed response (HTTP %s)'):format(res.status) end
  return decoded.data, nil
end

--- Perform a REST request against the site.
---
---@param method string HTTP method, such as `'GET'`, `'POST'`, or `'PUT'`.
---@param path string Path like '/problems/two-sum/submit/'.
---@param body string|nil Raw request body (JSON already encoded).
---@param headers table|nil Extra raw headers.
---@param opts table|nil Additional |LeetCodeNet.request()| options.
---@return table|nil data Decoded JSON object.
---@return string|nil err
LeetCodeApi.rest = function(method, path, body, headers, opts)
  local request = vim.tbl_extend('force', {
    url = LeetCodeApi.base_url() .. path,
    method = method,
    body = body,
    headers = auth.headers(headers),
    cookie_file = auth.cookie_file(),
  }, opts or {})
  local res, err = net.request(request)

  if err ~= nil then return nil, err end

  res, err = auth.handle_status(res)
  if err ~= nil then return nil, err end
  if res == nil then return nil, 'Empty response' end

  local http_err = status_error(res)
  if http_err ~= nil then return nil, http_err end

  local ok, decoded = pcall(vim.json.decode, res.body)
  local malformed = not ok or (not LeetCodeApi.is_null(decoded) and type(decoded) ~= 'table')
  if malformed then return nil, ('Malformed response (HTTP %s)'):format(res.status) end
  if LeetCodeApi.is_null(decoded) then return nil, 'Empty response' end

  return decoded, nil
end

--- Problem page URL.
---
---@param title_slug string
---@return string
LeetCodeApi.problems_url = function(title_slug)
  local base = LeetCodeApi.base_url()
  return base .. '/problems/' .. title_slug .. '/'
end

return LeetCodeApi
