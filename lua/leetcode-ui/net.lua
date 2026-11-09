--- *leetcode-ui-net* HTTP layer on top of curl
---
--- |LeetCodeNet.request()| works both inside a coroutine (yields until the
--- request finishes) and on the main thread (uses blocking `vim.system`).
---
--- Transient transport failures and responses (403/429/5xx) are retried with
--- short backoff because LeetCode's middleware occasionally fails valid
--- requests.
---@tag LeetCodeNet
---@toc_entry Networking

local LeetCodeNet = {}

local async = require('leetcode-ui.async')
local log = require('leetcode-ui.log')

-- Helper functionality ==============================================================================================

local function remove_temp(path, flags)
  if vim.fn.getftype(path) == '' then return end
  local ok, result
  if flags ~= nil then
    ok, result = pcall(vim.fn.delete, path, flags)
  else
    ok, result = pcall(vim.fn.delete, path)
  end
  if not ok or result ~= 0 then log.warn('Failed to remove temporary request data') end
end

--- Build curl arguments for one request.
---
---@param opts table Request options.
---@param header_file string
---@param body_file string
---@param request_file string|nil
---@return table args
LeetCodeNet.curl_args = function(opts, header_file, body_file, request_file)
  local args = {
    'curl',
    '--silent',
    '--show-error',
    '--compressed',
    '-X',
    opts.method or 'GET',
    '--max-time',
    tostring(opts.timeout or 30),
    '-D',
    header_file,
    '-o',
    body_file,
  }

  if request_file ~= nil then
    vim.list_extend(args, { '-H', '@' .. request_file })
  else
    for _, header in ipairs(opts.headers or {}) do
      vim.list_extend(args, { '-H', header })
    end
  end

  if opts.body ~= nil and opts.body ~= '' then vim.list_extend(args, { '--data-binary', '@-' }) end

  if opts.cookie_file ~= nil then vim.list_extend(args, { '-b', opts.cookie_file }) end

  table.insert(args, '--')
  table.insert(args, opts.url)
  return args
end

--- Parse the final HTTP status line and its headers.
---
---@param text string
---@return number status
---@return table headers Lowercase header names.
LeetCodeNet.parse_headers = function(text)
  local status, headers = 0, {}

  for _, raw_line in ipairs(vim.split(text, '\n', { plain = true })) do
    local line = raw_line:gsub('\r$', '')
    if line:find('^HTTP/') then
      status = tonumber(line:match('^HTTP/%S+%s+(%d+)') or '') or status
      headers = {}
    elseif line ~= '' then
      local name, value = line:match('^([%w%-]+):%s*(.*)')
      if name ~= nil then headers[name:lower()] = value end
    end
  end

  return status, headers
end

--- Read and delete curl's temporary response files.
---
---@param header_file string
---@param body_file string
---@return table|nil response `{ status, headers, body }`
LeetCodeNet.read_response = function(header_file, body_file)
  local ok, header_text = pcall(vim.fn.readblob, header_file)
  local body_ok, body_lines = pcall(vim.fn.readfile, body_file, 'b')
  if not body_ok or type(body_lines) ~= 'table' then body_lines = {} end
  local body = table.concat(body_lines, '\n')

  remove_temp(header_file)
  remove_temp(body_file)

  if not ok or header_text == nil then return nil end

  local status, headers = LeetCodeNet.parse_headers(header_text)
  if status == 0 then return nil end

  return { status = status, headers = headers, body = body }
end

-- Public API ========================================================================================================

--- Perform an HTTP request.
---
--- Options:
--- - `url` (string, required)
--- - `method` (`GET`, `POST`, `PUT`, or `DELETE`; default `GET`)
--- - `headers` (array of raw `'Name: value'` strings)
--- - `body` (string|nil raw request body)
--- - `timeout` (number seconds, default 30)
--- - `retries` (number of transient-failure retries, default 3)
--- - `cookie_file` (string|nil Netscape cookie jar passed to curl)
---
--- Returns `{status, headers, body}` and an error string on transport
--- failure.
--- Inside a coroutine, yields until the request completes.
---
---@param opts table Request options.
---@return table|nil Response
---@return string|nil Error
LeetCodeNet.request = function(opts)
  local retries = opts.retries or 3
  local res, err

  for attempt = 0, retries do
    res, err = LeetCodeNet.request_once(opts)
    if res ~= nil and not LeetCodeNet.should_retry(res.status) then return res, nil end
    if attempt < retries then async.sleep(200 * (attempt + 1)) end
  end

  if res ~= nil then return res, nil end
  return nil, err or 'curl failed'
end

--- One request attempt on the main thread or inside a coroutine.
---
---@param opts table
---@return table|nil Response
---@return string|nil Error
---@private
LeetCodeNet.request_once = function(opts)
  local temp_dir = vim.fn.tempname()
  local dir_ok = pcall(vim.fn.mkdir, temp_dir, 'p', 448)
  if not dir_ok or vim.fn.isdirectory(temp_dir) == 0 then return nil, 'Failed to create temporary directory' end

  local header_file = temp_dir .. '/headers'
  local body_file = temp_dir .. '/body'
  local request_file = nil
  if #(opts.headers or {}) > 0 then
    request_file = temp_dir .. '/request-headers'
    local ok, result = pcall(vim.fn.writefile, opts.headers, request_file)
    if not ok or result ~= 0 then
      remove_temp(temp_dir, 'rf')
      return nil, 'Failed to create request headers'
    end
  end

  local args = LeetCodeNet.curl_args(opts, header_file, body_file, request_file)
  local out = async.system(args, { text = true, stdin = opts.body })
  local res = LeetCodeNet.read_response(header_file, body_file)
  remove_temp(temp_dir, 'rf')

  local err = vim.trim(out.stderr or '')
  if err == '' then err = out.code ~= 0 and ('curl %s'):format(out.code) or 'curl failed' end
  if out.code ~= 0 then return nil, err end
  if res ~= nil then return res, nil end
  return nil, err
end

--- Whether a status should trigger a retry.
---
---@param status number
---@return boolean
LeetCodeNet.should_retry = function(status) return status == 403 or status == 429 or status >= 500 end

return LeetCodeNet
