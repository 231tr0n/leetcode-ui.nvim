--- *LeetCodeApi* GraphQL and REST plumbing
---

-- |leetcode-ui-api| GraphQL and REST plumbing.
-- `LeetCodeApi.graphql` runs a query and returns decoded `data` (or an error message built
-- from GraphQL `errors`). `LeetCodeApi.rest` covers non-GraphQL REST endpoints. Both work
-- inside coroutines; calling them on the main thread falls back to blocking
-- requests.

-- Module design:
local LeetCodeApi = {}

local config = require('leetcode-ui.config')
local net = require('leetcode-ui.net')
local auth = require('leetcode-ui.auth')

-- Helper functionality ==============================================================================================

LeetCodeApi.base_url = function() return ('https://%s'):format(config.config.url) end

LeetCodeApi.is_nillish = function(value) return value == nil or (type(value) == 'userdata' and value == vim.NIL) end

-- Public API ========================================================================================================

---Run a GraphQL query.
---
---@param query string GraphQL query text (|leetcode-ui-api-queries|).
---@param variables table|nil Query variables.
---@return table|nil data Decoded `data` field.
---@return string|nil err Error message.
LeetCodeApi.graphql = function(query, variables)
  local body = vim.json.encode({ query = query, variables = variables or {} })
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

  local ok, decoded = pcall(vim.json.decode, res.body)
  if not ok or decoded == nil then return nil, ('Malformed response (HTTP %s)'):format(res.status) end

  if decoded.errors ~= nil and next(decoded.errors) ~= nil then
    local messages = {}
    for _, e in ipairs(decoded.errors) do
      table.insert(messages, e.message ~= nil and e.message or 'unknown error')
    end
    return nil, table.concat(messages, '\n')
  end

  return decoded.data, nil
end

---Perform a REST request against the site.
---
---@param method string `'GET'|'POST'|'PUT'`
---@param path string Path like '/problems/two-sum/submit/'.
---@param body string|nil Raw request body (JSON already encoded).
---@param headers table|nil Extra raw headers.
---@return table|nil data Decoded JSON body (nil for HTML or empty).
---@return string|nil err
LeetCodeApi.rest = function(method, path, body, headers)
  local res, err = net.request({
    url = LeetCodeApi.base_url() .. path,
    method = method,
    body = body,
    headers = auth.headers(headers),
    cookie_file = auth.cookie_file(),
  })

  if err ~= nil then return nil, err end

  res, err = auth.handle_status(res)
  if err ~= nil then return nil, err end
  if res == nil then return nil, 'Empty response' end

  if res.status == 429 then return nil, 'Too many requests, LeetCode requires a short cool-down' end

  local ok, decoded = pcall(vim.json.decode, res.body)
  if not ok or decoded == nil then return nil, ('Malformed response (HTTP %s)'):format(res.status) end

  return decoded, nil
end

---Problem page URL.
---
---@param title_slug string
---@return string
LeetCodeApi.problems_url = function(title_slug)
  local base = LeetCodeApi.base_url()
  return base .. '/problems/' .. title_slug .. '/'
end

return LeetCodeApi
