--- *leetcode-ui-picker* Problem picking
---
--- Problem list browser and generic selection helpers. `mini.pick` is used
--- when configured (or already set up in `auto` mode) and available;
--- otherwise |vim.ui.select()| is used.
---@tag LeetCodePicker
---@toc_entry Picker

local LeetCodePicker = {}

local api = require('leetcode-ui.api.question')
local async = require('leetcode-ui.async')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local ui = require('leetcode-ui.ui')

-- Helper functionality =============================================================================================

local request_generation = 0

local function begin_request()
  request_generation = request_generation + 1
  ui.bump()
  return request_generation
end

local function is_current(generation) return generation == request_generation end

local function overlay_changed(serial) return ui.state.owner_serial ~= serial end

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

--- Build filtered picker lines and entries from the problem list.
---
---@param filter table|nil `{ difficulty, hide_premium, force }`
---@return table lines
---@return table entries
---@return string|nil err
LeetCodePicker.problem_source = function(filter)
  filter = filter or {}
  local hide_premium = filter.hide_premium
  if hide_premium == nil then hide_premium = config.config.hide_premium end

  local list, err = api.get_list({ force = filter.force })
  if err ~= nil or list == nil then return {}, {}, err or 'Empty response' end

  local lines, entries = {}, {}
  for _, entry in ipairs(list.questions or {}) do
    local skip = filter.difficulty ~= nil and entry.difficulty ~= filter.difficulty
    skip = skip or (hide_premium and entry.is_paid_only)
    if not skip then
      table.insert(lines, LeetCodePicker.format_entry(entry))
      table.insert(entries, entry)
    end
  end
  return lines, entries, nil
end

-- Public API ========================================================================================================

--- Generic select: `mini.pick` when configured and available, else
--- |vim.ui.select()|.
---
---@param items table
---@param title string|nil
---@param on_choice function|nil Called with `(item, index)`; nil on cancel.
LeetCodePicker.select = function(items, title, on_choice)
  local callback = on_choice or function(_, _) end
  local backend = config.config.picker

  local use_mini = backend == 'mini' or (backend == 'auto' and _G.MiniPick ~= nil)
  if use_mini then
    local ok, mini_pick = pcall(require, 'mini.pick')
    if ok and type(mini_pick.ui_select) == 'function' then
      mini_pick.ui_select(items, { prompt = title }, callback)
      return
    end

    if backend == 'mini' then log.warn('mini.pick is not available; using the builtin picker') end
  end

  vim.ui.select(items, { prompt = title }, callback)
end

--- Browse the problem list.
---
---@param opts table|nil { difficulty = 'Easy'|'Medium'|'Hard' }
LeetCodePicker.problem = function(opts)
  opts = opts or {}
  local generation = begin_request()
  local overlay_serial = ui.state.owner_serial
  local url_epoch, auth_epoch = config.url_epoch, config.auth_epoch

  async.run(function()
    local lines, entries, err = LeetCodePicker.problem_source(opts)
    if not is_current(generation) or overlay_changed(overlay_serial) then return end
    if config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch then return end
    if err ~= nil then return end
    if #lines == 0 then
      log.warn('No questions matched the current filters')
      return
    end

    vim.schedule(function()
      if not is_current(generation) or overlay_changed(overlay_serial) then return end
      if config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch then return end
      LeetCodePicker.select(lines, ' LeetCode Problems ', function(choice, index)
        -- Custom |vim.ui.select()| implementations may omit the index.
        local entry = entries[index] or LeetCodePicker.pick_entry(lines, entries, choice)
        LeetCodePicker.launch(entry)
      end)
    end)
  end)
end

--- Open today's daily challenge.
LeetCodePicker.daily = function()
  log.info('Fetching the daily challenge…')
  local generation = begin_request()
  local overlay_serial = ui.state.owner_serial
  local url_epoch, auth_epoch = config.url_epoch, config.auth_epoch
  async.run(function()
    local slug, err = api.get_daily()
    if not is_current(generation) or overlay_changed(overlay_serial) then return end
    if config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch then return end
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
  local generation = begin_request()
  local overlay_serial = ui.state.owner_serial
  local url_epoch, auth_epoch = config.url_epoch, config.auth_epoch
  async.run(function()
    local slug, err = api.get_random(opts)
    if not is_current(generation) or overlay_changed(overlay_serial) then return end
    if config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch then return end
    if err ~= nil or slug == nil then
      log.error('Failed to fetch a random question: ' .. (err or 'Empty response'))
      return
    end
    log.info(('Opening random question `%s`…'):format(slug))
    require('leetcode-ui.question').open(slug)
  end)
end

return LeetCodePicker
