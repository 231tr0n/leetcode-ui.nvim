--- *leetcode-ui-question* Question view
---
--- The question view is a set of tabs rendered in the central |LeetCodeUI|
--- window: Description, Code, Console, and Info. The code tab is the only
--- editable buffer; all other tabs use the shared read-only scratch buffer.
---
--- Open views live in `LeetCodeQuestionView.views` keyed by slug.
---@tag LeetCodeQuestionView
---@toc_entry Question view

local LeetCodeQuestionView = {}

local api = require('leetcode-ui.api')
local async = require('leetcode-ui.async')
local auth = require('leetcode-ui.auth')
local questions = require('leetcode-ui.api.question')
local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')
local Console = require('leetcode-ui.console')
local log = require('leetcode-ui.log')
local format = require('leetcode-ui.format')
local parser = require('leetcode-ui.parser')
local runner = require('leetcode-ui.api.runner')
local solution = require('leetcode-ui.solution')
local storage = require('leetcode-ui.storage')
local ui = require('leetcode-ui.ui')

-- Helper data =======================================================================================================

LeetCodeQuestionView.views = {}
LeetCodeQuestionView.loading_slugs = {}
LeetCodeQuestionView.active = nil
LeetCodeQuestionView.tabs = { 'description', 'code', 'console', 'info' }

local open_generation = 0

local function invalidate_loads()
  open_generation = open_generation + 1
  LeetCodeQuestionView.loading_slugs = {}
end

-- Helper functionality =============================================================================================

local function clear_busy(view)
  view.busy = false
  if view.console ~= nil then
    for _, case in ipairs(view.console.cases) do
      case.running = false
    end
    view.console:stop_spinner()
  end
  if ui.is_open() then LeetCodeQuestionView.refresh(view) end
end

local function usable_view(view)
  view = view or LeetCodeQuestionView.current()
  if view == nil then
    log.error('No question is open')
    return nil
  end
  if view.busy then
    log.warn('Another action is already running')
    return nil
  end
  return view
end

local function tab_label(tab) return (tab:gsub('^%l', string.upper)) end

local function tab_index(tab)
  for index, name in ipairs(LeetCodeQuestionView.tabs) do
    if name == tab then return index end
  end
  return nil
end

local function escape_statusline(text) return (tostring(text):gsub('%%', '%%%%')) end

local function difficulty_highlight(difficulty) return config.difficulty_highlights[difficulty] or 'LeetCodeTitle' end

local function detail_id(detail)
  local frontend_id = detail.frontend_id
  return frontend_id ~= nil and frontend_id ~= '' and frontend_id or '?'
end

local function detail_title(detail)
  local title = detail.title
  return title ~= nil and title ~= '' and title or 'Unknown question'
end

local function question_payload(view) return { id = view.detail.id, title_slug = view.slug, lang_slug = view.lang } end

local function format_html(text) return format.format(text, 'html') or text end

local function raw_hints(view)
  local value = (view.detail or {}).hints
  if type(value) ~= 'table' then return {} end
  local hints = {}
  for _, hint in ipairs(value) do
    if type(hint) == 'string' and vim.trim(hint) ~= '' then table.insert(hints, hint) end
  end
  return hints
end

local function hint_visible(formatted)
  return #parser.render(formatted) > 0 and vim.trim(parser.markdown(formatted)) ~= ''
end

local function visible_hint_html(view)
  local cache = view._hint_cache
  if cache ~= nil and cache.detail == view.detail and cache.formatter == config.config.formatter then
    return cache.hints
  end
  local hints = {}
  for _, hint in ipairs(raw_hints(view)) do
    local formatted = format_html(hint)
    if hint_visible(formatted) then table.insert(hints, formatted) end
  end
  view._hint_cache = { detail = view.detail, formatter = config.config.formatter, hints = hints }
  return hints
end

local function click_tab(tab)
  local view = LeetCodeQuestionView.current()
  if view ~= nil then LeetCodeQuestionView.show_tab(view, tab) end
end

for _, tab in ipairs(LeetCodeQuestionView.tabs) do
  _G['LeetCodeClick' .. tab_label(tab)] = function() click_tab(tab) end
end

--- Build Description tab lines.
---
---@param view table
---@return table lines
LeetCodeQuestionView.description_lines = function(view)
  local detail = view.detail or {}
  local entry = view.entry or {}
  local icons = config.config.icons.status

  local lines = {
    { { text = ('%s. %s'):format(detail_id(detail), detail_title(detail)), hl = 'LeetCodeTitle' } },
  }

  local marks = {}
  if detail.difficulty ~= nil and detail.difficulty ~= '' then
    table.insert(marks, { text = detail.difficulty, hl = difficulty_highlight(detail.difficulty) })
  end
  if detail.is_paid_only then table.insert(marks, { text = 'Premium', hl = 'LeetCodeWarn' }) end
  local status = questions.normalize_status(detail.status) or questions.normalize_status(entry.status)
  if status == 'solved' then
    table.insert(marks, { text = icons.solved, hl = 'LeetCodeOk' })
  elseif status == 'attempted' then
    table.insert(marks, { text = icons.attempted, hl = 'LeetCodeWarn' })
  else
    table.insert(marks, { text = icons.todo, hl = 'LeetCodeDim' })
  end
  local ac_rate = tonumber(entry.ac_rate)
  if ac_rate ~= nil then table.insert(marks, { text = ('%.1f%%'):format(ac_rate), hl = 'LeetCodeDim' }) end

  local metadata = {}
  for index, mark in ipairs(marks) do
    if index > 1 then table.insert(metadata, { text = '  ', hl = 'LeetCodeDim' }) end
    table.insert(metadata, mark)
  end
  table.insert(lines, metadata)
  table.insert(lines, {})

  vim.list_extend(lines, parser.render(format_html(detail.content)))

  local show_hints = view.show_hints == true
  local hint_htmls = visible_hint_html(view)
  local hints = {}
  if show_hints then
    for _, formatted in ipairs(hint_htmls) do
      table.insert(hints, parser.render(formatted))
    end
  end
  local count = #hint_htmls
  if count > 0 then
    table.insert(lines, {})
    if not show_hints then
      table.insert(lines, {
        {
          text = ('Hints (%d) hidden. Use :LeetCode question hints to show them.'):format(count),
          hl = 'LeetCodeDim',
        },
      })
    else
      table.insert(lines, { { text = 'Hints', hl = 'LeetCodeHeader' } })
      for index, hint_lines in ipairs(hints) do
        local prefix = ('%d. '):format(index)
        local indent = string.rep(' ', #prefix)
        for line_index, hint_line in ipairs(hint_lines) do
          table.insert(hint_line, 1, { text = line_index == 1 and prefix or indent, hl = 'LeetCodeDim' })
        end
        vim.list_extend(lines, hint_lines)
      end
    end
  end

  return lines
end

--- Build Info tab lines.
---
---@param view table
---@return table lines
LeetCodeQuestionView.info_lines = function(view)
  local detail = view.detail or {}
  local entry = view.entry or {}
  local topic_tags = type(entry.topic_tags) == 'table' and entry.topic_tags or {}
  local tags = {}
  for _, tag in ipairs(topic_tags) do
    if type(tag) == 'table' and type(tag.name) == 'string' and tag.name ~= '' then table.insert(tags, tag.name) end
  end
  local case_count = view.console ~= nil and #view.console.cases or 0

  local lines = {
    {
      { text = 'Question:    ', hl = 'LeetCodeDim' },
      { text = ('%s. %s'):format(detail_id(detail), detail_title(detail)), hl = 'LeetCodeTitle' },
    },
    {
      { text = 'Difficulty:  ', hl = 'LeetCodeDim' },
      { text = detail.difficulty or 'Unknown', hl = difficulty_highlight(detail.difficulty) },
    },
    { { text = 'Language:    ', hl = 'LeetCodeDim' }, { text = solution.label(view.lang), hl = 'LeetCodeCode' } },
    { { text = 'Testcases:   ', hl = 'LeetCodeDim' }, { text = tostring(case_count), hl = 'LeetCodeCode' } },
    { { text = 'Runner:      ', hl = 'LeetCodeDim' }, { text = 'LeetCode API', hl = 'LeetCodeOk' } },
    {
      { text = 'Link:        ', hl = 'LeetCodeDim' },
      { text = api.problems_url(view.slug), hl = 'LeetCodeLink' },
    },
  }

  if #tags > 0 then
    local label = 'Tags:        '
    local width, first_in_line = #label, true
    local tag_line = { { text = label, hl = 'LeetCodeDim' } }
    for _, tag in ipairs(tags) do
      local piece = (first_in_line and '' or ', ') .. tag
      if not first_in_line and width + #piece > 78 then
        table.insert(lines, tag_line)
        tag_line = { { text = string.rep(' ', #label) } }
        width = #label
        piece = tag
      end
      table.insert(tag_line, { text = piece, hl = 'LeetCodeLink' })
      width = width + #piece
      first_in_line = false
    end
    table.insert(lines, tag_line)
  end

  local commands = require('leetcode-ui.commands')
  local question_rows = commands.help_rows('question', { case = true })
  local case_rows = commands.help_rows('case')
  local width = math.max(commands.help_width(question_rows), commands.help_width(case_rows))

  table.insert(lines, {})
  table.insert(lines, { { text = 'Commands', hl = 'LeetCodeHeader' } })
  table.insert(lines, { { text = '  Map these commands if you want key bindings.', hl = 'LeetCodeDim' } })
  vim.list_extend(lines, commands.help_lines(question_rows, width))

  table.insert(lines, {})
  table.insert(lines, { { text = 'Testcases', hl = 'LeetCodeHeader' } })
  vim.list_extend(lines, commands.help_lines(case_rows, width))
  return lines
end

--- Build Description tab Markdown.
---
---@param view table
---@return string markdown
LeetCodeQuestionView.description_markdown = function(view)
  local detail = view.detail or {}
  local entry = view.entry or {}
  local marks = {}
  if detail.difficulty ~= nil and detail.difficulty ~= '' then
    table.insert(marks, '**Difficulty:** ' .. detail.difficulty)
  end
  if detail.is_paid_only then table.insert(marks, '**Premium**') end
  local status = questions.normalize_status(detail.status) or questions.normalize_status(entry.status)
  if status ~= nil then
    local icon = config.config.icons.status[status]
    table.insert(marks, icon ~= nil and ('**Status:** %s %s'):format(icon, status) or ('**Status:** ' .. status))
  else
    table.insert(marks, config.config.icons.status.todo)
  end
  local ac_rate = tonumber(entry.ac_rate)
  if ac_rate ~= nil then table.insert(marks, ('**Acceptance:** %.1f%%'):format(ac_rate)) end

  local lines = {
    ('# %s. %s'):format(detail_id(detail), detail_title(detail)),
    table.concat(marks, ' · '),
    '',
    parser.markdown(format_html(detail.content)),
  }

  local show_hints = view.show_hints == true
  local hint_htmls = visible_hint_html(view)
  local hints = {}
  if show_hints then
    for _, formatted in ipairs(hint_htmls) do
      table.insert(hints, parser.markdown(formatted))
    end
  end
  local count = #hint_htmls
  if count > 0 then
    table.insert(lines, '')
    if not show_hints then
      table.insert(lines, ('> Hints (%d) hidden. Use `:LeetCode question hints` to show them.'):format(count))
    else
      table.insert(lines, '## Hints')
      for index, hint in ipairs(hints) do
        local prefix = ('%d. '):format(index)
        local indent = string.rep(' ', #prefix)
        table.insert(lines, prefix .. hint:gsub('\n', '\n' .. indent))
      end
    end
  end

  return table.concat(lines, '\n')
end

--- Build Info tab Markdown.
---
---@param view table
---@return string markdown
LeetCodeQuestionView.info_markdown = function(view)
  local detail = view.detail or {}
  local entry = view.entry or {}
  local topic_tags = type(entry.topic_tags) == 'table' and entry.topic_tags or {}
  local tags = {}
  for _, tag in ipairs(topic_tags) do
    if type(tag) == 'table' and type(tag.name) == 'string' and tag.name ~= '' then table.insert(tags, tag.name) end
  end
  local case_count = view.console ~= nil and #view.console.cases or 0
  local link = api.problems_url(view.slug)

  local lines = {
    ('# %s. %s'):format(detail_id(detail), detail_title(detail)),
    '',
    '| Field | Value |',
    '| --- | --- |',
    ('| Difficulty | %s |'):format(parser.markdown_escape(detail.difficulty or 'Unknown')),
    ('| Language | %s |'):format(parser.markdown_escape(solution.label(view.lang))),
    ('| Testcases | %d |'):format(case_count),
    '| Runner | LeetCode API |',
    ('| Link | [%s](%s) |'):format(parser.markdown_escape(link), parser.markdown_escape(link)),
  }
  if #tags > 0 then table.insert(lines, ('| Tags | %s |'):format(parser.markdown_escape(table.concat(tags, ', ')))) end

  local commands = require('leetcode-ui.commands')
  local function command_table(title, rows)
    table.insert(lines, '')
    table.insert(lines, '## ' .. title)
    table.insert(lines, '')
    for _, row in ipairs(rows) do
      table.insert(lines, ('- `:LeetCode %s` - %s'):format(row[1], parser.markdown_escape(row[2])))
    end
  end
  command_table('Commands', commands.help_rows('question', { case = true }))
  table.insert(lines, '')
  table.insert(lines, '> Map these commands if you want key bindings.')
  command_table('Testcases', commands.help_rows('case'))
  return table.concat(lines, '\n')
end

--- Render the question id and clickable tab strip in the winbar.
---
---@param view table
LeetCodeQuestionView.render_winbar = function(view)
  if view == nil or not ui.is_open() then return end

  local detail = view.detail or {}
  local title = ('LeetCode %s'):format(detail_id(detail))
  local parts = {
    ('%%#LeetCodeQuestionTitle#%s %%#LeetCodeWinBar#'):format(escape_statusline(title)),
  }

  for _, tab in ipairs(LeetCodeQuestionView.tabs) do
    local label = tab_label(tab)
    if tab == 'code' then label = ('%s (%s)'):format(label, solution.label(view.lang)) end
    local hl = tab == view.active and 'LeetCodeTabActive' or 'LeetCodeTab'
    local click = ('%%@v:lua.LeetCodeClick%s@'):format(tab_label(tab))
    table.insert(parts, ('%s%%#%s# %s %%X%%#LeetCodeWinBar#'):format(click, hl, label))
  end

  if view.busy then table.insert(parts, '%#LeetCodeWarn# … %#LeetCodeWinBar#') end
  ui.set_winbar(' ' .. table.concat(parts, '│') .. ' ')
end

--- Re-render the active tab.
---
---@param view table|nil
---@param focus boolean|nil Focus the window; read-only tabs reset the viewport.
LeetCodeQuestionView.refresh = function(view, focus)
  view = view or LeetCodeQuestionView.active
  if view == nil or LeetCodeQuestionView.views[view.slug] ~= view then return end
  if focus ~= true and not ui.is_open() then return end
  if LeetCodeQuestionView.active ~= view or (ui.state.owner ~= nil and ui.state.owner ~= 'question') then return end

  if view.active == 'code' then
    local bufnr = view.code_bufnr
    if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      solution.prepare(view)
      solution.open(view)
      bufnr = view.code_bufnr
    end
    if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
      ui.show(bufnr, {
        number = true,
        wrap = false,
        cursorline = vim.go.cursorline,
        normal_hl = 'LeetCodeCodeNormal',
        topfill = 1,
        signcolumn = 'auto',
        foldenable = true,
        foldcolumn = 1,
        statuscolumn = '%s%C%l ',
        focus = focus == true,
        owner = 'question',
      })
    end
  elseif view.active == 'console' then
    if view.console == nil then return end
    local lines, folds = view.console:lines()
    ui.render(lines, {
      number = false,
      wrap = true,
      pad_top = true,
      folds = folds,
      foldenable = true,
      foldmethod = 'manual',
      foldcolumn = 1,
      statuscolumn = '%C ',
      focus = focus == true,
      owner = 'question',
    })
  else
    local lines, markdown
    if view.active == 'description' then
      if ui.markdown_enabled() then
        markdown = LeetCodeQuestionView.description_markdown(view)
      else
        lines = LeetCodeQuestionView.description_lines(view)
      end
    elseif view.active == 'info' then
      if ui.markdown_enabled() then
        markdown = LeetCodeQuestionView.info_markdown(view)
      else
        lines = LeetCodeQuestionView.info_lines(view)
      end
    end
    if markdown ~= nil then
      ui.render_markdown(markdown, { pad_top = true, focus = focus == true, owner = 'question' })
    elseif lines ~= nil then
      ui.render(lines, { number = false, wrap = true, pad_top = true, focus = focus == true, owner = 'question' })
    end
  end

  LeetCodeQuestionView.render_winbar(view)
end

--- Show a tab.
---
---@param view table|nil
---@param name string
LeetCodeQuestionView.show_tab = function(view, name)
  view = view or LeetCodeQuestionView.active
  if view == nil or view.closed or tab_index(name) == nil then return end

  if name == 'code' then
    local bufnr = view.code_bufnr
    if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      solution.prepare(view)
    end
    solution.open(view)
  end

  view.active = name
  LeetCodeQuestionView.active = view
  ui.state.owner = 'question'
  LeetCodeQuestionView.refresh(view, true)
end

--- Cycle through tabs.
---
---@param view table|nil
---@param delta number|nil
LeetCodeQuestionView.cycle_tab = function(view, delta)
  view = view or LeetCodeQuestionView.active
  if view == nil then return end

  local index = tab_index(view.active) or 1
  index = index + (delta or 1)
  if index > #LeetCodeQuestionView.tabs then index = 1 end
  if index < 1 then index = #LeetCodeQuestionView.tabs end
  LeetCodeQuestionView.show_tab(view, LeetCodeQuestionView.tabs[index])
end

-- Public API ========================================================================================================

--- Get the question view belonging to the current buffer, falling back to the
--- most recently active view.
---
---@return table|nil
LeetCodeQuestionView.current = function()
  local bufnr = vim.api.nvim_get_current_buf()
  for _, view in pairs(LeetCodeQuestionView.views) do
    if bufnr == view.code_bufnr then return view end
  end
  return LeetCodeQuestionView.active
end

--- Open a question by slug.
---
---@param title_slug string
LeetCodeQuestionView.open = function(title_slug)
  if title_slug == nil or title_slug == '' then
    log.error('A question slug is required')
    return
  end

  local existing = LeetCodeQuestionView.views[title_slug]
  if existing ~= nil then
    ui.bump()
    invalidate_loads()
    LeetCodeQuestionView.active = existing
    LeetCodeQuestionView.show_tab(existing, existing.active or 'code')
    return
  end

  local loading_serial = LeetCodeQuestionView.loading_slugs[title_slug]
  if loading_serial ~= nil and loading_serial == ui.state.owner_serial then
    log.info(('Question `%s` is already loading'):format(title_slug))
    return
  end

  ui.bump()
  invalidate_loads()
  local generation = open_generation
  local overlay_serial = ui.state.owner_serial
  local url_epoch = config.url_epoch
  LeetCodeQuestionView.loading_slugs[title_slug] = overlay_serial
  log.info(('Loading question `%s`…'):format(title_slug))
  async.run(function()
    local user_key = auth.cache_key()
    local detail, err = questions.get_detail(title_slug)
    if generation ~= open_generation then return end
    LeetCodeQuestionView.loading_slugs[title_slug] = nil
    local current_key = auth.cache_key()
    -- `cache_key()` can yield while importing browser cookies, so another
    -- navigation may have invalidated this load.
    if generation ~= open_generation then return end
    if config.url_epoch ~= url_epoch or current_key ~= user_key then return end
    if err ~= nil or detail == nil then
      log.error('Failed to load question: ' .. (err or 'Empty response'))
      return
    end

    local lang = config.config.lang
    local available = solution.languages({ detail = detail, lang = lang })
    if not vim.tbl_contains(available, lang) then lang = available[1] or lang end
    if #available == 0 then log.warn('No supported solution language is available') end

    local entry = questions.find_in_list(title_slug)
    if generation ~= open_generation then return end
    if ui.state.owner_serial ~= overlay_serial then return end
    if config.url_epoch ~= url_epoch or auth.cache_key() ~= user_key then return end

    local view = {
      slug = title_slug,
      detail = detail,
      entry = entry or {
        ac_rate = detail.ac_rate,
        status = questions.normalize_status(detail.status),
        topic_tags = detail.topic_tags,
      },
      lang = lang,
      console = nil,
      code_bufnr = nil,
      active = 'code',
      busy = false,
      show_hints = config.config.show_hints,
    }
    view.console = Console.new(view)
    local saved_testcases = storage.read_testcases(title_slug)
    view.console:set_cases(saved_testcases or detail.testcases)
    if ui.state.owner_serial ~= overlay_serial then return end

    LeetCodeQuestionView.views[title_slug] = view
    LeetCodeQuestionView.active = view
    LeetCodeQuestionView.show_tab(view, 'code')
    log.info(('Opened %s. %s'):format(detail_id(detail), detail_title(detail)))
  end, function()
    if generation == open_generation then LeetCodeQuestionView.loading_slugs[title_slug] = nil end
  end)
end

--- Close a question view.
---
---@param view table|nil
---@param force boolean|nil Finalize even if the draft cannot be saved.
---@param skip_save boolean|nil Skip saving when the caller already saved the draft.
LeetCodeQuestionView.close = function(view, force, skip_save)
  view = view or LeetCodeQuestionView.current()
  if view == nil then
    invalidate_loads()
    if ui.state.owner == nil or ui.state.owner == 'question' then ui.close() end
    return
  end

  if not skip_save and not solution.save_draft(view) then
    if force ~= true then return end
    log.error('Failed to save the solution draft before closing')
  end
  view.closed = true
  if view.console ~= nil then view.console:stop_spinner() end

  if LeetCodeQuestionView.active == view then
    invalidate_loads()
    if ui.state.owner == nil or ui.state.owner == 'question' then ui.close() end
    LeetCodeQuestionView.active = nil
  end

  buffer.maybe_delete(view.code_bufnr)
  LeetCodeQuestionView.views[view.slug] = nil
  log.info(('Closed question `%s`'):format(view.slug))
end

--- Show or hide hints in the Description tab.
---
---@param view table|nil
---@param show boolean|nil `nil` toggles the current state.
LeetCodeQuestionView.set_hints = function(view, show)
  view = view or LeetCodeQuestionView.current()
  if view == nil then return end

  local count = #visible_hint_html(view)
  if count == 0 then
    log.info('This question has no hints')
    return
  end

  if show == nil then
    view.show_hints = not view.show_hints
  else
    view.show_hints = show
  end
  if view.show_hints then
    if
      view.active == 'description'
      and LeetCodeQuestionView.active == view
      and ui.is_open()
      and ui.state.owner == 'question'
    then
      LeetCodeQuestionView.refresh(view)
    else
      LeetCodeQuestionView.show_tab(view, 'description')
    end
  elseif view.active == 'description' then
    LeetCodeQuestionView.refresh(view)
  end

  if view.show_hints then
    log.info(('Showing %d hint(s)'):format(count))
  else
    log.info('Hints hidden')
  end
end

--- Restore the starter snippet.
---
---@param view table|nil
LeetCodeQuestionView.reset_code = function(view)
  view = usable_view(view)
  if view == nil then return end
  if not solution.has_code_buffer(view) then
    log.error('Solution buffer is missing; reopen the code tab')
    return
  end
  if solution.reset(view) then
    if view.console ~= nil then view.console:clear_results() end
    LeetCodeQuestionView.refresh(view)
  end
end

--- Switch to another available language.
---
---@param view table|nil
LeetCodeQuestionView.switch_language = function(view)
  view = usable_view(view)
  if view == nil then return end
  if not solution.has_code_buffer(view) then
    log.error('Solution buffer is missing; reopen the code tab')
    return
  end

  local languages = solution.languages(view)
  if #languages <= 1 then
    log.info('No other languages are available for this question')
    return
  end

  local labels = {}
  for _, slug in ipairs(languages) do
    table.insert(labels, solution.label(slug))
  end

  local picker = require('leetcode-ui.picker')
  picker.select(labels, ' Select language ', function(choice, index)
    if choice == nil then return end

    local lang_slug = index ~= nil and languages[index] or nil
    if lang_slug == nil then
      for position, label in ipairs(labels) do
        if label == choice then
          lang_slug = languages[position]
          break
        end
      end
    end
    if lang_slug == nil then return end

    if solution.switch_language(view, lang_slug) then
      if view.console ~= nil then view.console:clear_results() end
      LeetCodeQuestionView.refresh(view)
    end
  end)
end

local function mark_running(view, indexes)
  view.console.submission_result = nil
  for _, index in ipairs(indexes) do
    local case = view.console.cases[index]
    if case ~= nil then
      case.running = true
      case.status = 'unknown'
      case.result = nil
    end
  end
  view.console.selected = indexes[1] or view.console.selected
  view.console:start_spinner()
  LeetCodeQuestionView.show_tab(view, 'console')
end

local function case_result_for(result, position, single)
  if result.compare == nil then
    return {
      status = result.status,
      message = result.message,
      runtime_ms = result.runtime_ms,
      stdout = result.pretty_stdout,
      answer = result.code_output,
      expected_answer = result.expected_output,
    }
  end

  local compare = type(result.compare) == 'string' and result.compare or tostring(result.compare)
  local bit = single and compare:sub(1, 1) or compare:sub(position, position)
  if bit == '' then bit = '0' end
  local stdout_index = single and 1 or position
  local stdouts = type(result.stdouts) == 'table' and result.stdouts or {}
  local answers = type(result.answers) == 'table' and result.answers or {}
  local expected_answers = type(result.expected_answers) == 'table' and result.expected_answers or {}

  return {
    status = result.status,
    message = result.message,
    runtime_ms = result.runtime_ms,
    compare = bit,
    correct = bit == '1' and 1 or 0,
    total = 1,
    stdout = stdouts[stdout_index] or result.pretty_stdout,
    answer = answers[stdout_index] or result.code_output,
    expected_answer = expected_answers[stdout_index] or result.expected_output,
    is_submit = false,
  }
end

local function run_cases(view, question, code, indexes, index)
  local cases = view.console.cases
  local result, err
  local cancelled = function() return view.closed == true end

  if index ~= nil then
    result, err = runner.interpret(question, code, cases[index].input, cancelled)
  else
    local inputs = {}
    for _, case in ipairs(cases) do
      table.insert(inputs, case.input)
    end
    result, err = runner.interpret(question, code, table.concat(inputs, '\n'), cancelled)
  end

  if view.closed then
    for _, case_index in ipairs(indexes) do
      local case = cases[case_index]
      if case ~= nil then case.running = false end
    end
    view.console:stop_spinner()
    return
  end

  if err ~= nil or result == nil then
    for _, case_index in ipairs(indexes) do
      local case = cases[case_index]
      case.running = false
      case.status = 'error'
      case.result = { status = 'Error', message = err or 'Empty response' }
    end
    view.console:stop_spinner()
    log.error('Test run failed: ' .. (err or 'Empty response'))
    return
  end

  local passed = 0
  for _, case_index in ipairs(indexes) do
    local case = cases[case_index]
    case.running = false
    view.console:set_case_result(case_index, case_result_for(result, case_index, index ~= nil), false)
    if case.status == 'passed' then passed = passed + 1 end
  end

  view.console:stop_spinner()
  if passed == #indexes then
    log.info(('All %d testcase(s) passed'):format(passed))
  else
    log.warn(('%d of %d testcase(s) passed'):format(passed, #indexes))
  end
end

--- Run all testcases or one testcase.
---
---@param view table|nil
---@param index any Testcase index (number or numeric string).
LeetCodeQuestionView.run = function(view, index)
  view = usable_view(view)
  if view == nil then return end
  if not solution.has_code_buffer(view) then
    log.error('Solution buffer is missing; reopen the code tab')
    return
  end
  if view.console == nil then
    log.error('Test console is missing; reopen the question')
    return
  end

  local cases = view.console.cases
  local indexes = {}
  if index ~= nil then
    index = tonumber(index)
    if not view.console:is_valid_index(index) then
      log.error(('Testcase index must be between 1 and %d'):format(#cases))
      return
    end
    indexes = { index }
  else
    for case_index = 1, #cases do
      table.insert(indexes, case_index)
    end
  end

  if #indexes == 0 then
    log.warn('There are no testcases to run')
    return
  end

  view.busy = true
  async.run(function()
    solution.save_draft(view)
    local code = solution.code(view)

    log.info(('Running %d testcase(s) through LeetCode…'):format(#indexes))
    mark_running(view, indexes)
    run_cases(view, question_payload(view), code, indexes, index)
    view.busy = false
    if ui.is_open() then LeetCodeQuestionView.refresh(view) end
  end, function() clear_busy(view) end)
end

local function submission_message(result)
  local icons = config.config.icons.case
  local icon = result.status == 'Accepted' and icons.passed or icons.failed

  local stats = {}
  if result.runtime_ms ~= nil then table.insert(stats, ('Runtime: %d ms'):format(tonumber(result.runtime_ms) or 0)) end
  if result.memory_bytes ~= nil then
    table.insert(stats, ('Memory: %.2f MB'):format((tonumber(result.memory_bytes) or 0) / (1024 * 1024)))
  end

  local details = {}
  if not result.ok then
    if result.message ~= nil and result.message ~= '' then table.insert(details, result.message) end
    if result.input ~= nil and result.input ~= '' then table.insert(details, 'Input: ' .. tostring(result.input)) end
    if result.expected_output ~= nil and result.expected_output ~= '' then
      table.insert(details, 'Expected: ' .. tostring(result.expected_output))
    end
    if result.code_output ~= nil and result.code_output ~= '' then
      table.insert(details, 'Got: ' .. tostring(result.code_output))
    end
  end

  local message = ('%s %s'):format(icon, result.status or 'Finished')
  if #stats > 0 then message = message .. '  ' .. table.concat(stats, '  ') end
  if #details > 0 then message = message .. '\n' .. table.concat(details, '\n') end
  return message
end

--- Submit the current solution.
---
---@param view table|nil
LeetCodeQuestionView.submit = function(view)
  view = usable_view(view)
  if view == nil then return end
  if not solution.has_code_buffer(view) then
    log.error('Solution buffer is missing; reopen the code tab')
    return
  end
  if view.console == nil then
    log.error('Test console is missing; reopen the question')
    return
  end

  view.console.submission_result = nil
  view.busy = true
  local url_epoch = config.url_epoch
  local auth_epoch = config.auth_epoch
  async.run(function()
    if ui.is_open() then LeetCodeQuestionView.refresh(view) end
    solution.save_draft(view)
    local code = solution.code(view)
    local user_key = auth.cache_key()
    if view.closed or config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch then
      view.busy = false
      return
    end

    log.info('Submitting solution…')
    -- A submitted solution is judged even if the view closes; keep polling so
    -- the attempt is recorded once judging finishes.
    local result, err = runner.submit(
      question_payload(view),
      code,
      function() return config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch end
    )
    if err ~= nil or result == nil then
      view.busy = false
      if view.closed or config.url_epoch ~= url_epoch or config.auth_epoch ~= auth_epoch then return end
      log.error('Submission failed: ' .. (err or 'Empty response'))
      if ui.is_open() then LeetCodeQuestionView.refresh(view) end
      return
    end
    if config.url_epoch ~= url_epoch or auth.cache_key() ~= user_key then
      view.busy = false
      return
    end

    local status = result.ok and 'solved' or 'attempted'
    local already_solved = view.detail.status == 'solved' or (view.entry ~= nil and view.entry.status == 'solved')
    if result.ok or not already_solved then
      questions.update_list_status(view.slug, status)
      if view.entry ~= nil then view.entry.status = status end
      view.detail.status = status
    end
    view.busy = false
    if view.closed then return end

    log.notify(submission_message(result), result.ok and vim.log.levels.INFO or vim.log.levels.WARN)

    view.console.submission_result = result
    if LeetCodeQuestionView.active == view then
      if ui.is_open() and (ui.state.owner == nil or ui.state.owner == 'question') then
        LeetCodeQuestionView.show_tab(view, 'console')
      else
        view.active = 'console'
      end
    end
  end, function() clear_busy(view) end)
end

return LeetCodeQuestionView
