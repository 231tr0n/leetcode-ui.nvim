-- |leetcode-ui-picker| Problem picking via mini.pick (or builtin fallback).
--------------------------------------------------------------------------------
-- Two entry points:
--   - |H.problem()|: problem list browser (mini.pick source with preview).
--   - |H.select()|: generic picker used by, e.g., language switching.
-- `mini.pick` is used when available; otherwise `vim.ui.select` handles both.
--------------------------------------------------------------------------------

-- Module design:
local H = {}

local config = require('leetcode-ui.config')
local api = require('leetcode-ui.api.question')

---Run a function in a coroutine (error-safe driver).
---
---@param fn function
H.as = function(fn) return require('leetcode-ui.async').run(fn) end

-- Helper functionality =============================================================================================

---Format one list entry for display.
---
---@param entry table Normalized list entry.
---@return string
H.format_entry = function(entry)
  local icons = config.config.icons.status
  local status = icons.todo
  if entry.status == 'solved' then
    status = icons.solved
  elseif entry.status ~= nil then
    status = icons.attempted
  end
  return ('%-5s %-6s %s %s'):format(entry.frontend_id, entry.difficulty, status, entry.title)
end

---Resolve an entry back from a formatted line.
---
---@param lines table Lines as picker showed them.
---@param entries table Entries in the same order.
---@param choice string|nil
---@return table|nil entry
H.pick_entry = function(lines, entries, choice)
  if choice == nil then return nil end
  for i, line in ipairs(lines) do
    if line == choice then return entries[i] end
  end
  return nil
end

---Open a picked question.
---
---@param entry table|nil
H.launch = function(entry)
  if entry == nil then return end
  local question = require('leetcode-ui.question')
  question.open(entry.title_slug)
end

---mini.pick source over the problem list.
---
---@param filter table|nil { difficulty = string|nil, hide_premium = boolean|nil }
---@return table items Formatted lines.
---@return table entries Parallel normalized entries.
H.problem_source = function(filter)
  filter = filter or {}
  if filter.hide_premium == nil then filter.hide_premium = config.config.hide_premium end

  local list, err = api.get_list()
  if err ~= nil then
    vim.notify('(leetcode-ui) ' .. err, vim.log.levels.ERROR)
    return { err }, {}
  end
  if list == nil then return { 'Empty response' }, {} end

  local lines, entries = {}, {}
  for _, entry in ipairs(list.questions or {}) do
    local skip = filter ~= nil and filter.difficulty ~= nil and entry.difficulty ~= filter.difficulty
    skip = skip or (filter ~= nil and filter.hide_premium and entry.is_paid_only)
    if not skip then
      table.insert(lines, H.format_entry(entry))
      table.insert(entries, entry)
    end
  end
  return lines, entries
end

-- Public API ========================================================================================================

---Generic select: mini.pick when present, else |vim.ui.select()|.
---
---@param items table Choice items.
---@param title string|nil
---@param on_choice function |`(item, idx)`|; both nil on cancellation.
H.select = function(items, title, on_choice)
  local choice = nil
  local used_pick = false

  local ok, mini_pick = pcall(require, 'mini.pick')
  if ok then
    used_pick = true
    choice = mini_pick.start({
      source = { items = type(items) == 'table' and items or {}, name = title or 'Select' },
      matcher = { fuzzy = false, ignore_case = true },
    })
  end

  if not used_pick then
    vim.ui.select(items, { prompt = title }, function(item, idx) on_choice(item, idx) end)
    return
  end

  if choice == nil then
    on_choice(nil, nil)
    return
  end

  if type(on_choice) == 'function' then
    local idx = vim.tbl_indexof(items, choice)
    on_choice(choice, idx)
  end
end

---Problem list browser.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
H.problem = function(opts)
  opts = opts or {}

  local lines, entries = H.problem_source(opts)

  local ok, mini_pick = pcall(require, 'mini.pick')
  if ok then
    local choice = mini_pick.start({
      source = { items = lines, name = 'LeetCode' },
      matcher = { fuzzy = false, ignore_case = true },
    })
    if choice ~= nil then H.launch(H.pick_entry(lines, entries, choice)) end
    return
  end

  -- Fallback: builtin `vim.ui.select`.
  vim.ui.select(lines, { prompt = 'LeetCode' }, function(choice) H.launch(H.pick_entry(lines, entries, choice)) end)
end

---Open today's daily question.
H.daily = function()
  H.as(function()
    local slug, err = api.get_daily()
    if err ~= nil then
      vim.schedule(function() vim.notify('(leetcode-ui) ' .. err, vim.log.levels.ERROR) end)
      return
    end
    local question = require('leetcode-ui.question')
    if slug ~= nil then question.open(slug) end
  end)
end

---Open a random question.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
H.random = function(opts)
  H.as(function()
    local slug, err = api.get_random(opts)
    if err ~= nil then
      vim.schedule(function() vim.notify('(leetcode-ui) ' .. err, vim.log.levels.ERROR) end)
      return
    end
    local question = require('leetcode-ui.question')
    if slug ~= nil then question.open(slug) end
  end)
end

return H
