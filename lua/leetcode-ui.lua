--- *leetcode-ui* LeetCode UI for Neovim
---
---@tag LeetCode
---

-- |leetcode-ui| Root module of the |leetcode-ui| plugin.
-- Usage:
--   require('leetcode-ui').setup({...})
--   require('leetcode-ui').menu()
--   require('leetcode-ui').daily()

local LeetCode = {}

-- Modules ============================================================================================================

LeetCode.config = require('leetcode-ui.config')

-- Public API ========================================================================================================

---Set up plugin options (full docs in |leetcode-ui.setup()|).
---
---@param opts table|nil Setup options.
LeetCode.setup = function(opts) LeetCode.config.setup(opts) end

---Ensure a default setup has happened once (for one-off commands).
LeetCode.ensure_setup = function()
  if LeetCode.config.is_setup ~= true then LeetCode.setup({}) end
end

---Open the main menu view.
LeetCode.menu = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.menu').open()
end

---Open today's daily coding challenge question.
LeetCode.daily = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').daily()
end

---Open a random question.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCode.random = function(opts)
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').random(opts)
end

---Browse the problem list.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCode.list = function(opts)
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').problem(opts)
end

---Open the statistics view.
LeetCode.stats = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.stats_view').open()
end

---Show current session information.
LeetCode.session = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.stats_view').session()
end

---Close the focused question view.
LeetCode.close = function()
  local view = require('leetcode-ui.question').current()
  if view ~= nil then require('leetcode-ui.question').close(view) end
end

return LeetCode
