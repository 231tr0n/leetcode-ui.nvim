--- *leetcode-ui-log* User notifications
---
--- Small wrapper around |vim.notify()| used by all user-facing actions.
--- Notifications can be disabled with `notifications = false` in
--- |LeetCode.setup()|.
---@tag LeetCodeLog
---@toc_entry Notifications

local LeetCodeLog = {}

local config = require('leetcode-ui.config')

-- Helper functionality =============================================================================================

--- Show a notification unless notifications are disabled.
---
---@param msg string
---@param level number|nil Notification level (default: `vim.log.levels.INFO`).
LeetCodeLog.notify = function(msg, level)
  if config.config.notifications == false then return end
  vim.notify('(leetcode-ui) ' .. msg, level or vim.log.levels.INFO)
end

--- Show an informational notification.
---
---@param msg string
LeetCodeLog.info = function(msg) LeetCodeLog.notify(msg, vim.log.levels.INFO) end

--- Show a warning notification.
---
---@param msg string
LeetCodeLog.warn = function(msg) LeetCodeLog.notify(msg, vim.log.levels.WARN) end

--- Show an error notification.
---
---@param msg string
LeetCodeLog.error = function(msg) LeetCodeLog.notify(msg, vim.log.levels.ERROR) end

return LeetCodeLog
