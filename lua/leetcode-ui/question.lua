--- *leetcode-ui-question* Question view
---
---@tag LeetCodeQuestionView
---

-- |leetcode-ui-question| Question view: description, code, console, and info in a
-- single window with a winbar tab strip (no separate splits or floating panes).
--
-- Tabs (switch via the winbar or <Tab>/<S-Tab>):
--   Description | Code | Console | Info
--
-- State for open views lives in |LeetCodeQuestionView.views| keyed by slug.

-- Module design:
local LeetCodeQuestionView = {}

local config = require('leetcode-ui.config')
local api = require('leetcode-ui.api.question')
local runner = require('leetcode-ui.api.runner')
local parser = require('leetcode-ui.parser')
local buffer = require('leetcode-ui.buffer')
local solution = require('leetcode-ui.solution')
local storage = require('leetcode-ui.storage')
local Console = require('leetcode-ui.console')

-- Helper data =======================================================================================================

LeetCodeQuestionView.views = {}

LeetCodeQuestionView.tabs = { 'description', 'code', 'console', 'info' }
LeetCodeQuestionView.tab_labels = {
  description = 'Description',
  code = 'Code',
  console = 'Console',
  info = 'Info',
}

-- Helper functionality =============================================================================================

LeetCodeQuestionView.as = function(fn) return require('leetcode-ui.async').run(fn) end

LeetCodeQuestionView.describe = function(view)
  local detail = view.detail
  local icons = config.config.icons.status

  local header = { { text = ('%s.%s'):format(detail.frontend_id or '0', detail.title or ''), hl = 'LeetCodeTitle' } }

  local marks = {}
  if detail.is_paid_only then table.insert(marks, 'Premium') end
  local diff_hl = ({ Easy = 'LeetCodeEasy', Medium = 'LeetCodeMedium', Hard = 'LeetCodeHard' })[detail.difficulty]
  table.insert(marks, { text = detail.difficulty or '', hl = diff_hl })
  if detail.status == 'solved' then
    table.insert(marks, { text = icons.solved, hl = 'LeetCodeOk' })
  elseif detail.status ~= nil then
    table.insert(marks, { text = icons.attempted, hl = 'LeetCodeWarn' })
  else
    table.insert(marks, { text = icons.todo, hl = 'LeetCodeDim' })
  end
  if view.entry ~= nil and view.entry.ac_rate ~= nil then
    table.insert(marks, { text = ('%.1f%%'):format(view.entry.ac_rate), hl = 'LeetCodeDim' })
  end

  local info = { { text = '  ' } }
  for i, mark in ipairs(marks) do
    if type(mark) == 'string' then mark = { text = mark, hl = 'LeetCodeDim' } end
    if i > 1 then table.insert(info, { text = '  ', hl = 'LeetCodeDim' }) end
    table.insert(info, mark)
  end

  local lines = { header, info, {} }
  vim.list_extend(lines, parser.render(detail.content))
  return lines
end

LeetCodeQuestionView.render_winbar = function(view)
  if view.winid == nil or not vim.api.nvim_win_is_valid(view.winid) then return end
  local parts = {}
  for _, tab in ipairs(LeetCodeQuestionView.tabs) do
    local label = LeetCodeQuestionView.tab_labels[tab]
    local hl = (tab == view.active) and 'LeetCodeTitle' or 'LeetCodeDim'
    local click = ('%%@v:lua.LeetCodeClick%s@'):format(tab:gsub('^%l', string.upper))
    table.insert(parts, ('%s%%#%s# %s %%X%%#Normal#'):format(click, hl, label))
  end
  vim.api.nvim_set_option_value('winbar', '  ' .. table.concat(parts, ' │ '), { win = view.winid })
end

LeetCodeQuestionView.show_tab = function(view, name)
  if view.winid == nil or not vim.api.nvim_win_is_valid(view.winid) then return end
  if LeetCodeQuestionView.tab_labels[name] == nil then return end

  local bufnr = nil
  if name == 'description' then
    bufnr = view.desc_bufnr
  elseif name == 'code' then
    bufnr = view.code_bufnr
  elseif name == 'console' then
    if view.console == nil then return end
    view.console:open()
    bufnr = view.console.bufnr
  elseif name == 'info' then
    LeetCodeQuestionView.populate_info(view)
    bufnr = view.info_bufnr
  end
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then return end

  view.active = name
  vim.api.nvim_win_set_buf(view.winid, bufnr)
  pcall(vim.api.nvim_set_option_value, 'number', name == 'code', { win = view.winid })
  LeetCodeQuestionView.render_winbar(view)
end

LeetCodeQuestionView.cycle_tab = function(view, delta)
  local idx = 1
  for i, tab in ipairs(LeetCodeQuestionView.tabs) do
    if tab == view.active then
      idx = i
      break
    end
  end
  idx = idx + (delta or 1)
  if idx > #LeetCodeQuestionView.tabs then idx = 1 end
  if idx < 1 then idx = #LeetCodeQuestionView.tabs end
  LeetCodeQuestionView.show_tab(view, LeetCodeQuestionView.tabs[idx])
end

-- Click handlers for the winbar tab strip (mouse support).
for _, tab in ipairs(LeetCodeQuestionView.tabs) do
  LeetCodeQuestionView['click_' .. tab] = function()
    local view = LeetCodeQuestionView.current()
    if view ~= nil then LeetCodeQuestionView.show_tab(view, tab) end
  end

  local global_name = 'LeetCodeClick' .. tab:gsub('^%l', string.upper)
  _G[global_name] = function()
    local view = LeetCodeQuestionView.current()
    if view ~= nil then LeetCodeQuestionView.show_tab(view, tab) end
  end
end

LeetCodeQuestionView.prepare_buffers = function(view)
  if view.desc_bufnr == nil or not vim.api.nvim_buf_is_valid(view.desc_bufnr) then
    view.desc_bufnr = buffer.scratch('leetcode-ui://question/' .. view.slug, { ft = 'markdown' })
    vim.api.nvim_set_option_value('modifiable', false, { buf = view.desc_bufnr })
    buffer.spans_write(view.desc_bufnr, LeetCodeQuestionView.describe(view), false)

    buffer.keymaps(view.desc_bufnr, {
      close = { rhs = function() LeetCodeQuestionView.close(view) end, desc = 'Close question' },
    })
    vim.keymap.set(
      'n',
      '<Tab>',
      function() LeetCodeQuestionView.cycle_tab(view, 1) end,
      { buffer = view.desc_bufnr, silent = true }
    )
    vim.keymap.set(
      'n',
      '<S-Tab>',
      function() LeetCodeQuestionView.cycle_tab(view, -1) end,
      { buffer = view.desc_bufnr, silent = true }
    )
  end

  if view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then
    local draft = storage.read_draft(view.slug, view.lang)
    local content = draft ~= nil and draft or (solution.snippet(view) or '')

    view.code_bufnr = buffer.scratch(
      'leetcode-ui://' .. view.slug .. '.' .. view.lang,
      { ft = solution.filetype(view.lang), listed = true }
    )
    vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(content, '\n'))
  end

  buffer.keymaps(view.code_bufnr, {
    run = { rhs = function() LeetCodeQuestionView.run(view) end, desc = 'Run test case' },
    submit = { rhs = function() LeetCodeQuestionView.submit(view) end, desc = 'Submit solution' },
    reset_code = { rhs = function() LeetCodeQuestionView.reset_code(view) end, desc = 'Reset code' },
    format_code = { rhs = function() solution.format(view) end, desc = 'Format code' },
    switch_language = { rhs = function() LeetCodeQuestionView.switch_language(view) end, desc = 'Switch language' },
    add_test = {
      rhs = function()
        local input = vim.fn.input('New testcase input: ')
        if input ~= '' then view.console:add_case(input) end
      end,
      desc = 'Add testcase',
    },
    close = { rhs = function() LeetCodeQuestionView.close(view) end, desc = 'Close question' },
  })

  vim.keymap.set('n', '<C-l>', function() LeetCodeQuestionView.switch_language(view) end, {
    buffer = view.code_bufnr,
    silent = true,
    desc = 'Switch language (fallback)',
  })
  vim.keymap.set('i', '<C-l>', function() LeetCodeQuestionView.switch_language(view) end, {
    buffer = view.code_bufnr,
    silent = true,
    desc = 'Switch language (fallback)',
  })
  vim.keymap.set(
    'n',
    '<Tab>',
    function() LeetCodeQuestionView.cycle_tab(view, 1) end,
    { buffer = view.code_bufnr, silent = true }
  )
  vim.keymap.set(
    'n',
    '<S-Tab>',
    function() LeetCodeQuestionView.cycle_tab(view, -1) end,
    { buffer = view.code_bufnr, silent = true }
  )

  if view.console == nil then view.console = Console.new(view) end
  view.console:open()
  if view.info_bufnr == nil or not vim.api.nvim_buf_is_valid(view.info_bufnr) then
    view.info_bufnr = buffer.scratch('leetcode-ui://info/' .. view.slug, { ft = 'txt' })
    vim.api.nvim_set_option_value('modifiable', false, { buf = view.info_bufnr })
  end
  LeetCodeQuestionView.populate_info(view)
end

LeetCodeQuestionView.populate_info = function(view)
  if view.info_bufnr == nil or not vim.api.nvim_buf_is_valid(view.info_bufnr) then return end
  local detail = view.detail
  local lines = {
    {
      { text = 'Question:  ', hl = 'LeetCodeDim' },
      { text = ('%s.%s'):format(detail.frontend_id, detail.title), hl = 'LeetCodeTitle' },
    },
    {
      { text = 'Difficulty: ', hl = 'LeetCodeDim' },
      {
        text = detail.difficulty,
        hl = ({ Easy = 'LeetCodeEasy', Medium = 'LeetCodeMedium', Hard = 'LeetCodeHard' })[detail.difficulty]
          or 'LeetCodeTitle',
      },
    },
    { { text = 'Language: ', hl = 'LeetCodeDim' }, { text = view.lang, hl = 'LeetCodeCode' } },
  }
  local local_run = (config.config.no_local or {})[view.lang]
  table.insert(lines, {
    { text = 'Local runner: ', hl = 'LeetCodeDim' },
    {
      text = (local_run == true or config.config.local_runner == false) and 'online only' or 'enabled',
      hl = (local_run == true or config.config.local_runner == false) and 'LeetCodeWarn' or 'LeetCodeOk',
    },
  })
  local entry = view.entry
  if entry ~= nil then
    local tags = {}
    for _, tag in ipairs(entry.topic_tags or {}) do
      table.insert(tags, tag.name)
    end
    table.insert(
      lines,
      { { text = 'Tags:        ', hl = 'LeetCodeDim' }, { text = table.concat(tags, ', '), hl = 'LeetCodeLink' } }
    )
  end

  local keys = config.config.keys or {}
  table.insert(lines, {})
  table.insert(lines, { { text = 'Keys:', hl = 'LeetCodeTitle' } })
  local key_rows = {
    { 'Run tests', keys.run },
    { 'Submit', keys.submit },
    { 'Reset code', keys.reset_code },
    { 'Format code', keys.format_code },
    { 'Switch language', keys.switch_language },
    { 'Add testcase', keys.add_test },
    { 'Close', keys.close },
  }
  for _, row in ipairs(key_rows) do
    table.insert(lines, {
      { text = ('  %-18s'):format(row[1]), hl = 'LeetCodeDim' },
      { text = row[2] or '', hl = 'LeetCodeCode' },
    })
  end
  buffer.spans_write(view.info_bufnr, lines, false)
  buffer.keymaps(view.info_bufnr, {
    close = { rhs = function() LeetCodeQuestionView.close(view) end, desc = 'Close question' },
  })
  vim.keymap.set(
    'n',
    '<Tab>',
    function() LeetCodeQuestionView.cycle_tab(view, 1) end,
    { buffer = view.info_bufnr, silent = true }
  )
  vim.keymap.set(
    'n',
    '<S-Tab>',
    function() LeetCodeQuestionView.cycle_tab(view, -1) end,
    { buffer = view.info_bufnr, silent = true }
  )
end

LeetCodeQuestionView.open = function(title_slug)
  LeetCodeQuestionView.as(function()
    local fetch, fetch_err = api.get_detail(title_slug)
    if fetch_err ~= nil or fetch == nil then
      vim.notify('(leetcode-ui) ' .. (fetch_err or 'Empty response'), vim.log.levels.ERROR)
      return
    end

    local view = LeetCodeQuestionView.views[title_slug]
    if view == nil then
      view = {
        slug = title_slug,
        detail = fetch,
        entry = api.find_in_list(title_slug),
        lang = config.config.lang,
        console = nil,
      }
      LeetCodeQuestionView.views[title_slug] = view
    else
      view.detail = fetch
    end

    view.console = view.console or Console.new(view)
    view.console:set_cases(fetch.testcases)

    LeetCodeQuestionView.prepare_buffers(view)
    solution.open(view)

    if view.winid == nil or not vim.api.nvim_win_is_valid(view.winid) then
      view.winid = buffer.open_float(view.code_bufnr, {
        width = config.config.float_width,
        height = config.config.float_height,
        focus = true,
        title = ' LeetCode ',
      })
    else
      vim.api.nvim_win_set_buf(view.winid, view.code_bufnr)
    end
    view.desc_winid = view.winid
    view.code_winid = view.winid
    view.active = 'code'
    pcall(vim.api.nvim_set_option_value, 'number', true, { win = view.winid })
    LeetCodeQuestionView.render_winbar(view)
    vim.api.nvim_set_current_win(view.winid)
  end)
end

LeetCodeQuestionView.toggle_description = function(view) LeetCodeQuestionView.show_tab(view, 'description') end
LeetCodeQuestionView.toggle_info = function(view) LeetCodeQuestionView.show_tab(view, 'info') end

LeetCodeQuestionView.reset_code = function(view)
  if view.console ~= nil then view.console:render() end
  solution.reset(view)
  vim.notify('(leetcode-ui) Code reset to starter snippet', vim.log.levels.INFO)
end

LeetCodeQuestionView.switch_language = function(view)
  local langs = solution.languages(view)
  local picker = require('leetcode-ui.picker')
  picker.select(langs, ' Switch language ', function(choice)
    if choice ~= nil then solution.switch_language(view, choice) end
  end)
end

-- Public API ========================================================================================================

LeetCodeQuestionView.get_view = function(slug) return LeetCodeQuestionView.views[slug] end

LeetCodeQuestionView.current = function()
  local bufnr = vim.api.nvim_get_current_buf()
  for _, view in pairs(LeetCodeQuestionView.views) do
    if
      bufnr == view.code_bufnr
      or bufnr == view.desc_bufnr
      or bufnr == view.info_bufnr
      or (view.console ~= nil and bufnr == view.console.bufnr)
    then
      return view
    end
  end
  return nil
end

LeetCodeQuestionView.run = function(view, index)
  LeetCodeQuestionView.as(function()
    solution.save_draft(view)
    local code = solution.code(view)

    if view.console.bufnr == nil then view.console:open() end

    local question = { id = view.detail.id, title_slug = view.slug, lang_slug = view.lang }

    local cases = view.console.cases
    if index ~= nil then
      if cases[index] == nil then return end
      view.console:case_running(index)
      view.console:render()
      LeetCodeQuestionView.show_tab(view, 'console')

      local result, err = runner.interpret(question, code, cases[index].input)
      if err ~= nil or result == nil then
        cases[index].running = false
        vim.notify('(leetcode-ui) ' .. (err or 'Empty response'), vim.log.levels.ERROR)
        view.console:render()
        return
      end
      view.console:case_result(index, result)
      return
    end

    for _, case in ipairs(cases) do
      case.running = true
    end
    view.console:render()
    LeetCodeQuestionView.show_tab(view, 'console')

    local data_input = table.concat(vim.tbl_map(function(case) return case.input end, cases), '\n')

    local result, err = runner.interpret(question, code, data_input)
    if err ~= nil or result == nil then
      for _, case in ipairs(cases) do
        case.running = false
      end
      vim.notify('(leetcode-ui) ' .. (err or 'Empty response'), vim.log.levels.ERROR)
      view.console:render()
      return
    end

    for i, case in ipairs(cases) do
      case.running = false
      if result.compare ~= nil then
        local bit = result.compare:sub(i, i)
        case.result = {
          status = result.status,
          runtime_ms = result.runtime_ms,
          compare = bit,
          correct = bit == '1' and 1 or 0,
          total = bit == '1' and 1 or 0,
          stdout = (result.stdouts or {})[i] or result.pretty_stdout,
        }
      else
        case.result = { status = result.status, message = result.message, runtime_ms = result.runtime_ms }
      end
      view.console:case_result(i, case.result)
    end
  end)
end

LeetCodeQuestionView.submit = function(view)
  LeetCodeQuestionView.as(function()
    solution.save_draft(view)
    local code = solution.code(view)

    if view.console.bufnr == nil then view.console:open() end

    local question = { id = view.detail.id, title_slug = view.slug, lang_slug = view.lang }

    local result, err = runner.submit(question, code)
    if err ~= nil then
      vim.notify('(leetcode-ui) ' .. err, vim.log.levels.ERROR)
      return
    end
    if result == nil then return end

    local icons = config.config.icons.case
    local icon = ({ Accepted = icons.passed })[result.status] or icons.failed

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
    local extra = #details > 0 and ('\n' .. table.concat(details, '\n')) or ''

    vim.schedule(
      function()
        vim.notify(
          ('leetcode-ui: %s %s  Runtime: %d ms  Memory: %.2f MB%s'):format(
            icon,
            result.status,
            tonumber(result.runtime_ms or 0),
            (result.memory_mb or 0) / (1024 * 1024),
            extra
          ),
          result.ok and vim.log.levels.INFO or vim.log.levels.WARN
        )
      end
    )

    view.console:render()
    if result.ok then
      api.update_list_status(view.slug, 'solved')
    elseif view.entry ~= nil and view.entry.status == 'solved' then
      api.update_list_status(view.slug, 'attempted')
    end
  end)
end

LeetCodeQuestionView.close = function(view)
  solution.save_draft(view)

  if view.console ~= nil then view.console:close() end
  LeetCodeQuestionView.close_info(view)

  if view.winid ~= nil and vim.api.nvim_win_is_valid(view.winid) then
    pcall(vim.api.nvim_win_close, view.winid, false)
  end
  view.winid = nil
  view.desc_winid = nil
  view.code_winid = nil

  buffer.maybe_delete(view.desc_bufnr)
  buffer.maybe_delete(view.info_bufnr)
  -- Code buffer survives intentionally.

  local console = view.console
  if console ~= nil then console.bufnr = nil end

  LeetCodeQuestionView.views[view.slug] = nil
end

LeetCodeQuestionView.close_info = function(view)
  -- info is now a tab; nothing to close separately.
  view.info_winid = nil
end

return LeetCodeQuestionView
