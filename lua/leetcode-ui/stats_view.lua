--- *leetcode-ui-stats-view* Statistics view
---
--- Progress meters by difficulty, language breakdown, skill tags, and session
--- information. Rendered in the central |LeetCodeUI| window.
---@tag LeetCodeStatsView
---@toc_entry Statistics view

local LeetCodeStatsView = {}

local async = require('leetcode-ui.async')
local auth = require('leetcode-ui.auth')
local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')
local parser = require('leetcode-ui.parser')
local stats = require('leetcode-ui.api.stats')
local ui = require('leetcode-ui.ui')

-- Helper data =======================================================================================================

local generation = 0

-- Helper functionality =============================================================================================

local function finite_non_negative(value)
  value = tonumber(value)
  if value == nil or value ~= value or value == math.huge or value == -math.huge then return 0 end
  return math.min(2147483647, math.floor(math.max(0, value)))
end

local function is_auth_error(message)
  if type(message) ~= 'string' then return false end
  return message:find('Not signed in', 1, true) ~= nil
    or message:find('Authentication failed', 1, true) ~= nil
    or message:find('Session expired', 1, true) ~= nil
end

local function sorted_rows(rows, name_field)
  local sorted = {}
  for _, row in ipairs(type(rows) == 'table' and rows or {}) do
    if type(row) == 'table' then table.insert(sorted, row) end
  end
  table.sort(sorted, function(a, b)
    local a_solved = tonumber(a.problems_solved) or 0
    local b_solved = tonumber(b.problems_solved) or 0
    if a_solved ~= b_solved then return a_solved > b_solved end
    return tostring(a[name_field] or '') < tostring(b[name_field] or '')
  end)
  return sorted
end

--- Build one difficulty progress meter.
---
---@param label string
---@param solved number
---@param total number
---@param width number|nil
---@return table spans
LeetCodeStatsView.meter = function(label, solved, total, width)
  width = width or 24
  solved, total = finite_non_negative(solved), finite_non_negative(total)
  local ratio = total > 0 and math.min(solved / total, 1) or 0
  local filled = math.floor(ratio * width + 0.5)

  local hl = config.difficulty_highlights[label] or 'LeetCodeTitle'
  return {
    { text = ('%-10s'):format(label), hl = hl },
    { text = ('%4d/%4d'):format(solved, total), hl = 'LeetCodeTitle' },
    { text = '  ', hl = nil },
    { text = ('█'):rep(filled), hl = hl },
    { text = ('░'):rep(width - filled), hl = 'LeetCodeDim' },
    { text = (' %3d%%'):format(math.floor(ratio * 100 + 0.5)), hl = 'LeetCodeDim' },
  }
end

--- Build language breakdown lines.
---
---@param rows table|nil
---@return table lines
LeetCodeStatsView.language_lines = function(rows)
  local sorted = sorted_rows(rows, 'language_name')
  if #sorted == 0 then return {} end

  local lines = { { { text = 'Languages', hl = 'LeetCodeTitle' } } }
  for _, row in ipairs(sorted) do
    local name = type(row.language_name) == 'string' and row.language_name or ''
    table.insert(lines, {
      { text = ('  %-12s '):format(name), hl = 'LeetCodeCode' },
      { text = ('%d'):format(math.floor(finite_non_negative(row.problems_solved))), hl = 'LeetCodeTitle' },
    })
  end
  return lines
end

--- Build skill-tag lines.
---
---@param tags table|nil
---@return table lines
LeetCodeStatsView.skills_lines = function(tags)
  tags = type(tags) == 'table' and tags or {}
  local sections = {
    { 'Advanced', tags.advanced or {} },
    { 'Intermediate', tags.intermediate or {} },
    { 'Fundamental', tags.fundamental or {} },
  }

  local lines, first_section = {}, true
  for _, section in ipairs(sections) do
    local name, rows = section[1], sorted_rows(section[2], 'tag_name')
    if #rows > 0 then
      if not first_section then table.insert(lines, {}) end
      first_section = false
      table.insert(lines, { { text = ('  %s'):format(name), hl = 'LeetCodeLink' } })
      for index, row in ipairs(rows) do
        if index > 10 then break end
        local tag_name = type(row.tag_name) == 'string' and row.tag_name or ''
        table.insert(lines, {
          { text = ('    %-28s '):format(tag_name), hl = nil },
          { text = ('%d'):format(math.floor(finite_non_negative(row.problems_solved))), hl = 'LeetCodeTitle' },
        })
      end
    end
  end
  if #lines == 0 then return {} end
  table.insert(lines, 1, { { text = 'Skills', hl = 'LeetCodeTitle' } })
  return lines
end

--- Build all statistics lines.
---
--- `data` may contain `solved`, `languages`, `skills`, `err`, `auth_err`,
--- `session`, and `streak` values; every field is optional.
---
---@param data table
---@return table lines
LeetCodeStatsView.lines = function(data)
  data = type(data) == 'table' and data or {}
  local session = type(data.session) == 'table' and data.session or {}
  local solved = type(data.solved) == 'table' and data.solved or nil
  local languages = type(data.languages) == 'table' and data.languages or nil
  local skills = type(data.skills) == 'table' and data.skills or nil
  local streak = type(data.streak) == 'table' and data.streak or nil
  local err = type(data.err) == 'string' and data.err or nil
  local explicit_auth_err = type(data.auth_err) == 'string' and data.auth_err or nil

  local lines = {
    {
      { text = 'Progress   ', hl = 'LeetCodeTitle' },
      { text = config.config.url, hl = 'LeetCodeDim' },
    },
  }

  local signed_in = session.signed_in == true
  local auth_error = explicit_auth_err ~= nil or is_auth_error(err)
  if signed_in and not auth_error then
    local session_text = session.name or 'unknown'
    if session.is_premium then session_text = session_text .. ' (premium)' end
    local row = {
      { text = 'Signed in  ', hl = 'LeetCodeDim' },
      { text = session_text, hl = 'LeetCodeOk' },
    }
    if streak ~= nil then
      table.insert(row, {
        text = ('  streak: %d day(s)'):format(tonumber(streak.streak_count) or 0),
        hl = 'LeetCodeDim',
      })
    end
    table.insert(lines, row)
  elseif signed_in and auth_error then
    table.insert(lines, { { text = 'Session expired (check cookies)', hl = 'LeetCodeWarn' } })
  elseif err == nil or auth_error then
    table.insert(
      lines,
      { { text = 'Not signed in (see :h leetcode-ui-config for cookie options)', hl = 'LeetCodeWarn' } }
    )
  end

  if solved ~= nil then
    local counts = type(solved.solved) == 'table' and solved.solved or {}
    local totals = type(solved.total) == 'table' and solved.total or {}
    table.insert(lines, {})
    for _, difficulty in ipairs({ 'Easy', 'Medium', 'Hard' }) do
      table.insert(lines, LeetCodeStatsView.meter(difficulty, counts[difficulty] or 0, totals[difficulty] or 0))
    end
  end

  if languages ~= nil then
    local language_section = LeetCodeStatsView.language_lines(languages)
    if #language_section > 0 then
      table.insert(lines, {})
      vim.list_extend(lines, language_section)
    end
  end
  if skills ~= nil then
    local skill_section = LeetCodeStatsView.skills_lines(skills)
    if #skill_section > 0 then
      table.insert(lines, {})
      vim.list_extend(lines, skill_section)
    end
  end

  if err ~= nil and not is_auth_error(err) then
    table.insert(lines, {})
    local label = 'Statistics unavailable: '
    for index, line in ipairs(vim.split(err, '\n', { plain = true })) do
      local prefix = index == 1 and label or string.rep(' ', #label)
      table.insert(lines, {
        { text = prefix, hl = index == 1 and 'LeetCodeErr' or 'LeetCodeDim' },
        { text = line, hl = 'LeetCodeDim' },
      })
    end
  end
  return lines
end

--- Build all statistics as Markdown.
---
---@param data table Same shape as |LeetCodeStatsView.lines()|.
---@return string markdown
LeetCodeStatsView.markdown = function(data)
  data = type(data) == 'table' and data or {}
  local session = type(data.session) == 'table' and data.session or {}
  local solved = type(data.solved) == 'table' and data.solved or nil
  local languages = type(data.languages) == 'table' and data.languages or nil
  local skills = type(data.skills) == 'table' and data.skills or nil
  local streak = type(data.streak) == 'table' and data.streak or nil
  local err = type(data.err) == 'string' and data.err or nil
  local auth_err = type(data.auth_err) == 'string' and data.auth_err or nil
  local auth_error = auth_err ~= nil or is_auth_error(err)

  local lines = { '# Progress', '', config.config.url, '' }

  local signed_in = session.signed_in == true
  if signed_in and not auth_error then
    local text = ('**Signed in:** %s'):format(parser.markdown_escape(session.name or 'unknown'))
    if session.is_premium then text = text .. ' (premium)' end
    if streak ~= nil then text = text .. (' · streak: %d day(s)'):format(tonumber(streak.streak_count) or 0) end
    table.insert(lines, text)
  elseif signed_in and auth_error then
    table.insert(lines, '> Session expired (check cookies)')
  elseif err == nil or auth_error then
    table.insert(lines, '> Not signed in (see `:h leetcode-ui-config` for cookie options)')
  end

  if solved ~= nil then
    local counts = type(solved.solved) == 'table' and solved.solved or {}
    local totals = type(solved.total) == 'table' and solved.total or {}
    table.insert(lines, '')
    table.insert(lines, '## Solved')
    table.insert(lines, '')
    table.insert(lines, '| Difficulty | Solved | Total | Progress |')
    table.insert(lines, '| --- | ---: | ---: | ---: |')
    for _, difficulty in ipairs({ 'Easy', 'Medium', 'Hard' }) do
      local solved_count = finite_non_negative(counts[difficulty])
      local total_count = finite_non_negative(totals[difficulty])
      local percent = total_count > 0 and math.min(solved_count / total_count * 100, 100) or 0
      table.insert(lines, ('| %s | %d | %d | %.1f%% |'):format(difficulty, solved_count, total_count, percent))
    end
  end

  if languages ~= nil then
    local rows = sorted_rows(languages, 'language_name')
    if #rows > 0 then
      table.insert(lines, '')
      table.insert(lines, '## Languages')
      table.insert(lines, '')
      table.insert(lines, '| Language | Solved |')
      table.insert(lines, '| --- | ---: |')
      for _, row in ipairs(rows) do
        table.insert(
          lines,
          ('| %s | %d |'):format(
            parser.markdown_escape(tostring(row.language_name or '')),
            math.floor(finite_non_negative(row.problems_solved))
          )
        )
      end
    end
  end

  if skills ~= nil then
    local sections = {
      { 'Advanced', skills.advanced or {} },
      { 'Intermediate', skills.intermediate or {} },
      { 'Fundamental', skills.fundamental or {} },
    }
    local wrote_heading = false
    for _, section in ipairs(sections) do
      local rows = sorted_rows(section[2], 'tag_name')
      if #rows > 0 then
        if not wrote_heading then
          table.insert(lines, '')
          table.insert(lines, '## Skills')
          wrote_heading = true
        end
        table.insert(lines, '')
        table.insert(lines, '### ' .. section[1])
        table.insert(lines, '')
        table.insert(lines, '| Skill | Solved |')
        table.insert(lines, '| --- | ---: |')
        for index, row in ipairs(rows) do
          if index > 10 then break end
          table.insert(
            lines,
            ('| %s | %d |'):format(
              parser.markdown_escape(tostring(row.tag_name or '')),
              math.floor(finite_non_negative(row.problems_solved))
            )
          )
        end
      end
    end
  end

  if err ~= nil and not is_auth_error(err) then
    table.insert(lines, '')
    table.insert(lines, '> **Statistics unavailable:** ' .. parser.markdown_escape(err):gsub('\n', '\n> '))
  end
  return table.concat(lines, '\n')
end

-- Public API ========================================================================================================

--- Open the statistics view.
LeetCodeStatsView.open = function()
  generation = generation + 1
  local current_generation = generation
  local url_epoch = config.url_epoch
  ui.claim('stats')
  if ui.markdown_enabled() then
    ui.render_markdown('# Loading statistics…', { pad_top = true, owner = 'stats' })
  else
    ui.render({ { { text = 'Loading statistics…', hl = 'LeetCodeDim' } } }, { pad_top = true, owner = 'stats' })
  end
  log.info('Loading statistics…')

  async.run(function()
    local session, auth_err = auth.verify()
    local user_key = auth.cache_key()
    local solved, err = nil, auth_err
    if auth_err == nil then
      if session ~= nil and session.signed_in then
        solved, err = stats.solved()
      else
        err = 'Not signed in (check cookies)'
      end
    end

    local languages, skills, streak = nil, nil, nil
    local errors = { err }
    local solved_auth_error = err ~= nil and is_auth_error(err)

    if current_generation ~= generation or ui.state.owner ~= 'stats' then return end

    if auth_err == nil and session ~= nil and session.signed_in and not solved_auth_error then
      local language_err, skills_err, streak_err
      languages, language_err = stats.languages()
      skills, skills_err = stats.skills()
      streak, streak_err = stats.streak()
      if language_err ~= nil then table.insert(errors, language_err) end
      if skills_err ~= nil then table.insert(errors, skills_err) end
      if streak_err ~= nil then table.insert(errors, streak_err) end
    end

    if current_generation ~= generation then return end
    local auth_error = false
    local auth_messages, other_messages = {}, {}
    for _, message in ipairs(errors) do
      if message ~= nil then
        if is_auth_error(message) then
          auth_error = true
          table.insert(auth_messages, message)
        else
          table.insert(other_messages, message)
        end
      end
    end
    local key_changed = auth.cache_key() ~= user_key
    if current_generation ~= generation then return end
    if config.url_epoch ~= url_epoch or (key_changed and not auth_error) then
      if ui.state.owner == 'stats' then ui.close() end
      return
    end
    if ui.state.owner ~= 'stats' then return end
    if key_changed then
      solved, languages, skills, streak = nil, nil, nil, nil
    end

    local display_err = #other_messages > 0 and table.concat(other_messages, '; ') or nil
    local display_auth_err = #auth_messages > 0 and table.concat(auth_messages, '; ') or nil
    local data = {
      solved = solved,
      languages = languages,
      skills = skills,
      err = display_err,
      auth_err = display_auth_err,
      session = session,
      streak = streak,
    }
    if ui.markdown_enabled() then
      ui.render_markdown(LeetCodeStatsView.markdown(data), { pad_top = true, owner = 'stats', focus = false })
    else
      ui.render(LeetCodeStatsView.lines(data), { pad_top = true, owner = 'stats', focus = false })
    end
    ui.set_winbar(' LeetCode Statistics ')

    if err ~= nil then
      log.warn('Statistics unavailable: ' .. err)
    elseif display_err ~= nil or display_auth_err ~= nil then
      log.warn('Some statistics are unavailable: ' .. (display_err or display_auth_err))
    else
      log.info('Statistics loaded')
    end
  end, function()
    if current_generation ~= generation then return end
    if config.url_epoch ~= url_epoch then
      if ui.state.owner == 'stats' then ui.close() end
      return
    end
    if ui.state.owner ~= 'stats' then return end
    if ui.markdown_enabled() then
      ui.render_markdown('# Failed to load statistics', { pad_top = true, owner = 'stats', focus = false })
    else
      ui.render({ { { text = 'Failed to load statistics', hl = 'LeetCodeErr' } } }, {
        pad_top = true,
        owner = 'stats',
        focus = false,
      })
    end
    ui.set_winbar(' LeetCode Statistics ')
  end)
end

--- Show session details in a notification.
LeetCodeStatsView.session = function()
  log.info('Checking session…')
  async.run(function()
    local session, err = auth.verify()
    if err ~= nil or session == nil then
      log.warn('Session check failed: ' .. (err or 'Empty response'))
      return
    end
    local url_epoch = config.url_epoch
    local user_key = auth.cache_key()

    local streak, streak_err = nil, nil
    if session.signed_in then
      streak, streak_err = stats.streak()
    end
    if config.url_epoch ~= url_epoch or auth.cache_key() ~= user_key then return end
    if streak_err ~= nil and is_auth_error(streak_err) then
      log.warn('Session expired (check cookies)')
      return
    end

    local message = session.signed_in and (session.name or 'unknown') or 'anonymous'
    message = message .. (session.is_premium and ' (premium)' or '')
    if streak ~= nil then message = message .. ('  streak: %d'):format(tonumber(streak.streak_count) or 0) end
    log.notify(message, session.signed_in and vim.log.levels.INFO or vim.log.levels.WARN)
    if streak_err ~= nil then log.warn('Could not load the streak: ' .. streak_err) end
  end)
end

return LeetCodeStatsView
