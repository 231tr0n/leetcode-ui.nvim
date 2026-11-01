-- |leetcode-ui-net| HTTP layer on top of `curl`.
--------------------------------------------------------------------------------
-- Notes:
-- - |leetcode-ui-net.request()| works both inside a coroutine (yields until the
--   request finishes) and on the main thread (uses blocking `vim.system`).
-- - Transient failures (403/429/5xx) are retried with short backoff: LeetCode's
--   middleware occasionally returns those for otherwise valid requests.
--------------------------------------------------------------------------------

-- Module design:
local H = {}

-- Helper functionality ==============================================================================================

---Assemble `curl` arguments for a request.
---
---@param opts table Request options (|leetcode-ui-net.request()|).
---@param header_file string Path to store response headers in.
---@param body_file string Path to store response body in.
---@return table Curl argument list.
---@private
H.curl_args = function(opts, header_file, body_file)
  local args = {
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

  for _, header in ipairs(opts.headers or {}) do
    vim.list_extend(args, { '-H', header })
  end

  if opts.body ~= nil and opts.body ~= '' then vim.list_extend(args, { '--data-binary', '@-' }) end

  if opts.cookie_file ~= nil then vim.list_extend(args, { '-b', opts.cookie_file }) end

  table.insert(args, opts.url)
  return args
end

---Parse raw response header stream (`-D` file) into status and headers.
---
---@param text string Raw header file contents.
---@return number status
---@return table headers Lowercased name -> value.
---@private
H.parse_headers = function(text)
  local status, headers = 0, {}

  for _, line in ipairs(vim.split(text, '[\r\n]+')) do
    if line:find('^HTTP/') then
      status = tonumber(line:match('^HTTP/%S+%s+(%d+)') or '') or status
      headers = {}
    elseif line ~= '' then
      local name, value = line:match('^([%w%-]+):%s*(.*)')
      if name ~= nil then headers[name:lower()] = value end
    else
      break
    end
  end

  return status, headers
end

---Read response files and clean them up.
---
---@param header_file string
---@param body_file string
---@return table|nil Response with `status`, `headers`, `body`; nil when no valid
---   HTTP response was produced (transport failure).
---@private
H.read_response = function(header_file, body_file)
  local ok, header_text = pcall(vim.fn.readblob, header_file)
  local body_lines = vim.fn.readfile(body_file)
  local body = table.concat(body_lines, '\n')

  vim.fn.delete(header_file)
  vim.fn.delete(body_file)

  if not ok or header_text == nil then return nil end

  local status, headers = H.parse_headers(header_text)
  if status == 0 then return nil end

  return { status = status, headers = headers, body = body }
end

-- Public API ========================================================================================================

---Perform an HTTP request.
---
---Options:
--- - `url` (string, required)
--- - `method` (`'GET'|'POST'|'PUT'|'DELETE'`, default `'GET'`)
--- - `headers` (array of raw `'Name: value'` strings)
--- - `body` (string|nil raw request body)
--- - `timeout` (number seconds, default 30)
--- - `retries` (number of transient-failure retries, default 3)
---
---Returns `{status, headers, body}` and an error string on transport failure.
---Inside a coroutine, yields until the request completes.
---
---@param opts table Request options.
---@return table|nil Response
---@return string|nil Error
H.request = function(opts)
  if coroutine.running() then return H.request_async(opts) end
  return H.request_sync(opts)
end

---JSON request shorthand (`POST` with JSON headers and body).
---
---@param url string
---@param body string Encoded JSON.
---@param headers table|nil Extra raw header strings.
---@param cookie_file string|nil Cookie jar path passed through to curl.
---@return table|nil Response
---@return string|nil Error
H.request_json = function(url, body, headers, cookie_file)
  return H.request({
    url = url,
    method = 'POST',
    headers = headers or {},
    body = body,
    cookie_file = cookie_file,
  })
end

---Blocking request used on the main thread.
---
---@private
H.request_sync = function(opts)
  local retries = opts.retries or 3
  local res = nil

  for attempt = 0, retries do
    res = H.request_once(opts)
    if res ~= nil and not H.should_retry(res.status) then return res, nil end
    if attempt < retries then vim.wait(200 * (attempt + 1)) end
  end

  return res, (res == nil and 'curl failed' or nil)
end

---One request attempt, blocking.
---
---@param opts table
---@return table|nil Response
---@private
H.request_once = function(opts)
  local header_file = vim.fn.tempname() .. '.headers'
  local body_file = vim.fn.tempname() .. '.body'

  local out = vim
    .system(H.curl_args(opts, header_file, body_file), {
      text = true,
      stdin = opts.body,
    })
    :wait()

  if out.code ~= 0 then
    local res = H.read_response(header_file, body_file)
    if res ~= nil then return res end
    return nil
  end

  return H.read_response(header_file, body_file)
end

---Coroutine-compatible retrying request.
---
---@private
H.request_async = function(opts)
  local co = coroutine.running()
  local retries = opts.retries or 3
  local attempt = 0

  local resume = function(res, err)
    vim.schedule(function() coroutine.resume(co, res, err) end)
  end

  local try
  try = function()
    attempt = attempt + 1

    local header_file = vim.fn.tempname() .. '.headers'
    local body_file = vim.fn.tempname() .. '.body'

    vim.system(H.curl_args(opts, header_file, body_file), {
      text = true,
      stdin = opts.body,
    }, function(out)
      local res = H.read_response(header_file, body_file)

      local transient = res ~= nil and H.should_retry(res.status)
      if transient and attempt <= retries then
        vim.defer_fn(try, 200 * attempt)
        return
      end

      if res == nil then
        resume(nil, out.code ~= 0 and ('curl %s'):format(out.code) or 'curl failed')
        return
      end

      resume(res, nil)
    end)
  end

  try()
  return coroutine.yield()
end

---Whether a status should trigger a retry.
---
---@param status number
---@return boolean
H.should_retry = function(status) return status == 403 or status == 429 or status >= 500 end

return H
