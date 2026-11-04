--- *leetcode-ui-async* Tiny coroutine driver
---
--- Runs a function in a dedicated coroutine. Network code resumes the
--- coroutine via |vim.schedule()|, so actions can interleave requests with
--- rendering. Errors are reported as notifications instead of escaping into
--- Neovim's event loop.
---@tag LeetCodeAsync
---@toc_entry Async driver

local LeetCodeAsync = {}

local log = require('leetcode-ui.log')

--- Resume a coroutine and report errors.
---
---@param thread thread
---@param ... any Arguments passed to the coroutine.
---@return boolean ok
---@return string|nil err
LeetCodeAsync.resume = function(thread, ...)
  local ok, err = coroutine.resume(thread, ...)
  if not ok then log.error(tostring(err)) end
  return ok, err
end

--- Run `fn` inside a coroutine.
---
---@param fn function
---@param on_error function|nil Called before reporting a failure.
LeetCodeAsync.run = function(fn, on_error)
  local thread = coroutine.create(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      if on_error ~= nil then pcall(on_error, err) end
      error(err, 0)
    end
  end)
  LeetCodeAsync.resume(thread)
end

--- Sleep without blocking when called inside a coroutine.
---
---@param ms number
LeetCodeAsync.sleep = function(ms)
  local thread, is_main = coroutine.running()
  if thread == nil or is_main then
    vim.wait(ms)
    return
  end

  vim.defer_fn(function() LeetCodeAsync.resume(thread) end, ms)
  coroutine.yield()
end

--- Run a system command, yielding for completion inside a coroutine.
---
---@param command table
---@param opts table|nil
---@return table result Command result or spawn-failure result.
LeetCodeAsync.system = function(command, opts)
  local thread, is_main = coroutine.running()
  if thread == nil or is_main then
    local ok, result = pcall(function() return vim.system(command, opts):wait() end)
    if ok then return result end
    return { code = -1, stdout = '', stderr = tostring(result) }
  end

  local ok, err = pcall(vim.system, command, opts, function(result)
    vim.schedule(function() LeetCodeAsync.resume(thread, result) end)
  end)
  if not ok then return { code = -1, stdout = '', stderr = tostring(err) } end
  return coroutine.yield()
end

return LeetCodeAsync
