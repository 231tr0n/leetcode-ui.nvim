--- *leetcode-ui-question* Question view
---
---@tag LeetCodeQuestionView
---

-- |leetcode-ui-question| Question view: description + code + console panes.
-- Layout:
--   ┌──────────────────┬─────────────────────┐
--   │  description     │  code (editable)    │
--   │  (spans, ro)     │  draft-backed       │
--   └──────────────────┴─────────────────────┘
--                       │  console (toggle X) │
-- State for open views lives in |LeetCodeQuestionView.views| keyed by slug; key handlers are
-- closures bound to their view. Run/submit/judging runs inside a coroutine.

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

LeetCodeQuestionView.open_description = function(view)
  if view.desc_winid ~= nil and vim.api.nvim_win_is_valid(view.desc_winid) then return end

  view.desc_winid = buffer.open_split(view.desc_bufnr, {
    pos = 'left',
    width = config.config.description_width,
    focus = false,
  })
  vim.api.nvim_set_option_value('cursorline', true, { win = view.desc_winid })
end

LeetCodeQuestionView.prepare_buffers = function(view)
  if view.desc_bufnr == nil or not vim.api.nvim_buf_is_valid(view.desc_bufnr) then
    view.desc_bufnr = buffer.scratch('leetcode-ui://question/' .. view.slug, { ft = 'markdown' })
    buffer.spans_write(view.desc_bufnr, LeetCodeQuestionView.describe(view), false)

    buffer.keymaps(view.desc_bufnr, {
      toggle_question = {
        rhs = function() LeetCodeQuestionView.toggle_description(view) end,
        desc = 'Toggle description',
      },
      close = {
        rhs = function() LeetCodeQuestionView.close(view) end,
        desc = 'Close question',
      },
    })
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
    run = {
      rhs = function() LeetCodeQuestionView.run(view) end,
      desc = 'Run test case',
    },
    submit = {
      rhs = function() LeetCodeQuestionView.submit(view) end,
      desc = 'Submit solution',
    },
    toggle_question = {
      rhs = function() LeetCodeQuestionView.toggle_description(view) end,
      desc = 'Toggle description',
    },
    toggle_console = {
      rhs = function() view.console:toggle() end,
      desc = 'Toggle console',
    },
    toggle_information = {
      rhs = function() LeetCodeQuestionView.toggle_info(view) end,
      desc = 'Toggle information',
    },
    reset_code = {
      rhs = function() LeetCodeQuestionView.reset_code(view) end,
      desc = 'Reset code',
    },
    format_code = {
      rhs = function() solution.format(view) end,
      desc = 'Format code',
    },
    switch_language = {
      rhs = function() LeetCodeQuestionView.switch_language(view) end,
      desc = 'Switch language',
    },
    add_test = {
      rhs = function()
        local input = vim.fn.input('New testcase input: ')
        if input ~= '' then view.console:add_case(input) end
      end,
      desc = 'Add testcase',
    },
    close = {
      rhs = function() LeetCodeQuestionView.close(view) end,
      desc = 'Close question',
    },
  })
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
    LeetCodeQuestionView.open_description(view)
    vim.api.nvim_set_current_win(view.code_winid)
  end)
end

LeetCodeQuestionView.toggle_description = function(view)
  if view.desc_winid ~= nil then
    buffer.close(view.desc_winid)
    view.desc_winid = nil
  else
    LeetCodeQuestionView.open_description(view)
  end
end

LeetCodeQuestionView.open_info = function(view)
  if view.info_winid ~= nil and vim.api.nvim_win_is_valid(view.info_winid) then return end

  view.info_bufnr = view.info_bufnr or buffer.scratch('leetcode-ui://info/' .. view.slug, { ft = 'txt' })

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
    table.insert(lines, {
      { text = 'Tags:        ', hl = 'LeetCodeDim' },
      { text = table.concat(tags, ', '), hl = 'LeetCodeLink' },
    })
  end

  buffer.spans_write(view.info_bufnr, lines, false)

  local anchor = view.code_winid ~= nil and vim.api.nvim_win_get_position(view.code_winid) or { 0, 0 }
  local width = math.min(60, vim.o.columns - 4)
  local height = #lines

  view.info_winid = vim.api.nvim_open_win(view.info_bufnr, false, {
    relative = 'editor',
    row = anchor[1],
    col = math.max(vim.o.columns - width - 2, 0),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Info ',
    title_pos = 'left',
  })
end

LeetCodeQuestionView.close_info = function(view)
  if view.info_winid ~= nil and vim.api.nvim_win_is_valid(view.info_winid) then
    local bufnr = vim.api.nvim_win_get_buf(view.info_winid)
    vim.api.nvim_win_close(view.info_winid, false)
    buffer.maybe_delete(bufnr)
  end
  view.info_winid = nil
end

LeetCodeQuestionView.toggle_info = function(view)
  if view.info_winid == nil then
    LeetCodeQuestionView.open_info(view)
  else
    LeetCodeQuestionView.close_info(view)
  end
end

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

---Active or last opened question view for a slug.
---
---@param slug string
---@return table|nil
LeetCodeQuestionView.get_view = function(slug) return LeetCodeQuestionView.views[slug] end

---Currently focused question view (via the code or description buffer).
---
---@return table|nil
LeetCodeQuestionView.current = function()
  local bufnr = vim.api.nvim_get_current_buf()
  for _, view in pairs(LeetCodeQuestionView.views) do
    if bufnr == view.code_bufnr or bufnr == view.desc_bufnr then return view end
  end
  return nil
end

---Run test cases against LeetCode (interpret, not a submission).
---
---No argument runs every known case; `index` runs a single one. Without any
---known cases the first example testcase is used.
---
---@param view table
---@param index number|nil 1-based case index, nil = run all.
LeetCodeQuestionView.run = function(view, index)
  LeetCodeQuestionView.as(function()
    solution.save_draft(view)
    local code = solution.code(view)

    if view.console.bufnr == nil then view.console:open() end

    local question = {
      id = view.detail.id,
      title_slug = view.slug,
      lang_slug = view.lang,
    }

    local cases = view.console.cases
    if index ~= nil then
      if cases[index] == nil then return end
      view.console:case_running(index)
      view.console:render()

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

    -- All cases at once: interpret with joined inputs.
    for _, case in ipairs(cases) do
      case.running = true
    end
    view.console:render()

    local data_input = table.concat(vim.tbl_map(function(case) return case.input end, cases), '\n\n')

    local result, err = runner.interpret(question, code, data_input)
    if err ~= nil or result == nil then
      for _, case in ipairs(cases) do
        case.running = false
      end
      vim.notify('(leetcode-ui) ' .. (err or 'Empty response'), vim.log.levels.ERROR)
      view.console:render()
      return
    end

    -- Distribute per-case outcomes: compare bits and stdouts.
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
        }
      else
        case.result = { status = result.status, message = result.message, runtime_ms = result.runtime_ms }
      end
      view.console:case_result(i, case.result)
    end
  end)
end

---Submit the solution to LeetCode.
---
---@param view table
LeetCodeQuestionView.submit = function(view)
  LeetCodeQuestionView.as(function()
    solution.save_draft(view)
    local code = solution.code(view)

    if view.console.bufnr == nil then view.console:open() end

    local question = {
      id = view.detail.id,
      title_slug = view.slug,
      lang_slug = view.lang,
    }

    local result, err = runner.submit(question, code)
    if err ~= nil then
      vim.notify('(leetcode-ui) ' .. err, vim.log.levels.ERROR)
      return
    end
    if result == nil then return end

    local icons = config.config.icons.case
    local icon = ({ Accepted = icons.passed })[result.status] or icons.failed

    vim.schedule(
      function()
        vim.notify(
          ('leetcode-ui: %s %s  Runtime: %d ms  Memory: %.2f MB'):format(
            icon,
            result.status,
            tonumber(result.runtime_ms or 0),
            (result.memory_mb or 0) / 1024
          ),
          result.ok and vim.log.levels.INFO or vim.log.levels.WARN
        )
      end
    )

    -- Reflect results in the console as a summary line.
    view.console:render()
    if result.ok then
      api.update_list_status(view.slug, 'solved')
    elseif view.entry ~= nil and view.entry.status == 'solved' then
      api.update_list_status(view.slug, 'attempted')
    end
  end)
end

---Close a view: close panes, delete buffers, drop state.
---
---@param view table
LeetCodeQuestionView.close = function(view)
  solution.save_draft(view)

  if view.console ~= nil then view.console:close() end

  LeetCodeQuestionView.close_info(view)

  if view.desc_winid ~= nil then
    buffer.close(view.desc_winid)
    view.desc_winid = nil
  end
  if view.code_winid ~= nil then
    -- Keep the (listed) code buffer alive: a `:w`-draft is still editable.
    pcall(vim.api.nvim_win_close, view.code_winid, false)
    view.code_winid = nil
  end

  buffer.maybe_delete(view.desc_bufnr)
  -- Code buffer survives intentionally: the draft remains reachable via `:b`.

  local console = view.console
  if console ~= nil then console.bufnr = nil end

  LeetCodeQuestionView.views[view.slug] = nil
end

return LeetCodeQuestionView
