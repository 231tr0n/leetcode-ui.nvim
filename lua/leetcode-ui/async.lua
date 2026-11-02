--- *leetcode-ui-async* Tiny coroutine driver
---
--- Runs a function in a dedicated coroutine. Network code resumes the
--- coroutine via |vim.schedule()|, so actions can interleave requests with
--- rendering. Errors are reported as notifications instead of escaping into
--- Neovim's event loop.
---
---@tag LeetCodeAsync
---@toc_entry Async driver

local LeetCodeAsync = {}

local log = require('leetcode-ui.log')

--- Run `fn` inside a coroutine.
---
---@param fn function
LeetCodeAsync.run = function(fn)
  local thread = coroutine.create(fn)
  local ok, err = coroutine.resume(thread)
  if not ok then log.error(tostring(err)) end
end

return LeetCodeAsync
