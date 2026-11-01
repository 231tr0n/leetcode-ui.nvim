-- |leetcode-ui| Root module of the |leetcode-ui| plugin.
--------------------------------------------------------------------------------
-- Usage:
--   require('leetcode-ui').setup({...})
--   require('leetcode-ui').menu()
--   require('leetcode-ui').daily()
--------------------------------------------------------------------------------

local M = {}

-- Modules ============================================================================================================

M.config = require('leetcode-ui.config')

-- Public API ========================================================================================================

---Set up options (full docs in |leetcode-ui.setup()|).
---
---@param opts table|nil Setup options.
M.setup = function(opts) M.config.setup(opts) end

---Ensure a default setup happened once (for one-off commands).
M.ensure_setup = function()
  if M.config.is_setup ~= true then M.setup({}) end
end

---Open the main menu.
M.menu = function()
  M.ensure_setup()
  require('leetcode-ui.menu').open()
end

---Open today's daily question.
M.daily = function()
  M.ensure_setup()
  require('leetcode-ui.picker').daily()
end

---Open a random question.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
M.random = function(opts)
  M.ensure_setup()
  require('leetcode-ui.picker').random(opts)
end

---Browse the problem list.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
M.list = function(opts)
  M.ensure_setup()
  require('leetcode-ui.picker').problem(opts)
end

---Open the statistics view.
M.stats = function()
  M.ensure_setup()
  require('leetcode-ui.stats_view').open()
end

---Show current session info.
M.session = function()
  M.ensure_setup()
  require('leetcode-ui.stats_view').session()
end

---Close the focused question view.
M.close = function()
  local view = require('leetcode-ui.question').current()
  if view ~= nil then require('leetcode-ui.question').close(view) end
end

return M
