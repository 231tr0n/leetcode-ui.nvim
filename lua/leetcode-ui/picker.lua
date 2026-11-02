--- *leetcode-ui-picker* Problem picking
---
--- Problem list browser and generic selection helpers. `mini.pick` is used when
--- configured and available; otherwise |vim.ui.select()| is used.
---
---@tag LeetCodePicker
---@toc_entry Picker

local LeetCodePicker = {}

local api = require('leetcode-ui.api.question')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')

-- Helper functionality =============================================================================================

LeetCodePicker.as = function(fn) return require('leetcode-ui.async').run(fn) end

--- Format one problem-list entry for the picker.
---
---@param entry table
---@return string
LeetCodePicker.format_entry = function(entry)
  local icons = config.config.icons.status
  local status = icons.todo
  if entry.status == 'solved' then
    status = icons.solved
  elseif entry.status ~= nil then
    status = icons.attempted
  end
  local premium = entry.is_paid_only and ' [premium]' or ''
  return ('%-5s %-6s %s %s%s'):format(
    entry.frontend_id or '',
    entry.difficulty or '',
    status,
    entry.title or '',
    premium
  )
end

--- Find an entry by its rendered picker line.
---
---@param lines table
---@param entries table
---@param choice string|nil
---@return table|nil
LeetCodePicker.pick_entry = function(lines, entries, choice)
  if choice == nil then return nil end
  for index, line in ipairs(lines) do
    if line == choice then return entries[index] end
  end
  return nil
end

--- Open a problem-list entry.
---
---@param entry table|nil
LeetCodePicker.launch = function(entry)
  if entry == nil then return end
  require('leetcode-ui.question').open(entry.title_slug)
end

--- Build filtered picker lines and entries from the cached problem list.
---
---@param filter table|nil { difficulty = string, hide_premium = boolean }
---@return table lines
---@return table entries
---@return string|nil err
LeetCodePicker.problem_source = function(filter)
  filter = filter or {}
  if filter.hide_premium == nil then filter.hide_premium = config.config.hide_premium end

  local list, err = api.get_list()
  if err ~= nil or list == nil then return {}, {}, err or 'Empty response' end

  local lines, entries = {}, {}
  for _, entry in ipairs(list.questions or {}) do
    local skip = filter.difficulty ~= nil and entry.difficulty ~= filter.difficulty
    skip = skip or (filter.hide_premium and entry.is_paid_only)
    if not skip then
      table.insert(lines, LeetCodePicker.format_entry(entry))
      table.insert(entries, entry)
    end
  end
  return lines, entries, nil
end

-- Public API ========================================================================================================

--- Generic select: `mini.pick` when configured and available, else |vim.ui.select()|.
---
---@param items table
---@param title string|nil
---@param on_choice function|nil Called with `(item, index)`; both nil on cancellation.
LeetCodePicker.select = function(items, title, on_choice)
  local callback = on_choice or function(_, _) end
  local backend = config.config.picker

  local use_mini = backend == 'mini' or backend == 'auto'
  if use_mini then
    local ok, mini_pick = pcall(require, 'mini.pick')
    if ok then
      local choice = mini_pick.start({
        source = { items = items, name = title or 'Select' },
        matcher = { fuzzy = false, ignore_case = true },
      })

      if choice == nil then
        callback(nil, nil)
        return
      end

      local index = nil
      for position, item in ipairs(items) do
        if item == choice then
          index = position
          break
        end
      end
      callback(choice, index)
      return
    end

    if backend == 'mini' then log.warn('mini.pick is not available; using the builtin picker') end
  end

  vim.ui.select(items, { prompt = title }, function(item, index) callback(item, index) end)
end

--- Browse the problem list.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCodePicker.problem = function(opts)
  opts = opts or {}

  LeetCodePicker.as(function()
    local lines, entries, err = LeetCodePicker.problem_source(opts)
    if err ~= nil then return end
    if #lines == 0 then
      log.warn('No questions matched the current filters')
      return
    end

    vim.schedule(function()
      LeetCodePicker.select(lines, ' LeetCode Problems ', function(choice, index)
        local entry = entries[index] or LeetCodePicker.pick_entry(lines, entries, choice)
        LeetCodePicker.launch(entry)
      end)
    end)
  end)
end

--- Open today's daily challenge.
LeetCodePicker.daily = function()
  log.info('Fetching the daily challenge…')
  LeetCodePicker.as(function()
    local slug, err = api.get_daily()
    if err ~= nil or slug == nil then
      log.error('Failed to fetch the daily challenge: ' .. (err or 'Empty response'))
      return
    end
    log.info(('Opening daily challenge `%s`…'):format(slug))
    require('leetcode-ui.question').open(slug)
  end)
end

--- Open a random question.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCodePicker.random = function(opts)
  log.info('Fetching a random question…')
  LeetCodePicker.as(function()
    local slug, err = api.get_random(opts)
    if err ~= nil or slug == nil then
      log.error('Failed to fetch a random question: ' .. (err or 'Empty response'))
      return
    end
    log.info(('Opening random question `%s`…'):format(slug))
    require('leetcode-ui.question').open(slug)
  end)
end

return LeetCodePicker
