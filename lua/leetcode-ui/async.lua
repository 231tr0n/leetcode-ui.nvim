--- *leetcode-ui-async* Tiny coroutine driver
---
---@tag LeetCodeAsync
---

-- |leetcode-ui-async| Tiny coroutine driver for UI actions.
-- Runs a function in a dedicated coroutine. Every yield inside must have its
-- own resumer wired (net.lua resumes via `vim.schedule`, runner.lua via
-- `vim.defer_fn`); the driver only catches errors and final results, so the
-- coroutine can interleave network calls with rendering.

local LeetCodeAsync = {}

LeetCodeAsync.run = function(fn)
  local co = coroutine.create(fn)
  local ok, res = coroutine.resume(co)
  if not ok then vim.schedule(function() vim.notify('(leetcode-ui) ' .. tostring(res), vim.log.levels.ERROR) end) end
  -- When the coroutine is suspended, an internal async callback resumes it.
end

return LeetCodeAsync
