-- Tests for leetcode-ui.question.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
    post_case = function() helpers.reset_ui() end,
  },
})

local function opened_view()
  local question = helpers.mod('question')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_detail',
    function(slug) return helpers.fake_detail({ title_slug = slug }), nil end,
    function()
      helpers.with_stub(
        'leetcode-ui.api.question',
        'find_in_list',
        function() return { ac_rate = 50.5, topic_tags = { { name = 'Array', slug = 'array' } }, status = nil } end,
        function() question.open('two-sum') end
      )
    end
  )
  eq(helpers.wait_for(function() return question.current() ~= nil end), true)
  return question, question.current()
end

local function make_view()
  local Console = helpers.mod('console')
  local view = helpers.fake_view()
  view.console = Console.new(view)
  view.console:set_cases(view.detail.testcases)
  return view
end

T['module'] = new_set()

T['module']['exposes the tab API'] = function()
  local question = helpers.mod('question')
  eq(type(question), 'table')
  for _, name in ipairs({ 'open', 'current', 'close', 'reset_code', 'show_tab', 'cycle_tab', 'run', 'submit' }) do
    eq(type(question[name]), 'function')
  end
  eq(#question.tabs, 4)
end

T['describe'] = new_set()

T['describe']['renders metadata, content, and hints'] = function()
  local view = make_view()
  view.detail.hints = { '<p>first hint</p>', '<p>second hint</p>' }
  view.detail.is_paid_only = true
  local question = helpers.mod('question')
  local text = table.concat(helpers.mod('buffer').spans_to_texts(question.describe(view)), '\n')
  eq(helpers.contains(text, '1. Two Sum'), true)
  eq(helpers.contains(text, 'Premium'), true)
  eq(helpers.contains(text, '50.5%'), true)
  eq(helpers.contains(text, 'find two indices'), true)
  eq(helpers.contains(text, 'first hint'), false)
  eq(helpers.contains(text, 'Hints (2) hidden'), true)

  view.show_hints = true
  text = table.concat(helpers.mod('buffer').spans_to_texts(question.describe(view)), '\n')
  eq(helpers.contains(text, 'Hints'), true)
  eq(helpers.contains(text, '1. first hint'), true)
end

T['describe']['handles missing fields'] = function()
  local view = make_view()
  view.detail = {}
  local question = helpers.mod('question')
  local text = table.concat(helpers.mod('buffer').spans_to_texts(question.describe(view)), '\n')
  eq(helpers.contains(text, 'no description'), true)
end

T['info'] = new_set()

T['info']['renders question metadata and command help'] = function()
  local view = make_view()
  local question = helpers.mod('question')
  local lines = question.info(view)
  local text = table.concat(helpers.mod('buffer').spans_to_texts(lines), '\n')
  eq(helpers.contains(text, 'LeetCode API'), true)
  eq(helpers.contains(text, 'Array'), true)
  eq(helpers.contains(text, ':LeetCode question run'), true)

  local description_columns = {}
  for _, line in ipairs(lines) do
    local command, description = line[1], line[2]
    if command ~= nil and description ~= nil and helpers.contains(command.text, ':LeetCode') then
      table.insert(description_columns, #command.text)
    end
  end
  eq(#description_columns > 0, true)
  for _, column in ipairs(description_columns) do
    eq(column, description_columns[1])
  end
end

T['open'] = new_set()

T['open']['fetches and opens a question'] = function()
  local question, view = opened_view()
  eq(view.slug, 'two-sum')
  eq(view.active, 'code')
  eq(view.show_hints, false)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, 1, false)[1], '')
  eq(vim.api.nvim_get_current_buf(), view.code_bufnr)
  eq(question.views['two-sum'], view)
  question.close(view)
end

T['open']['reuses an existing view without fetching'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://existing', { ft = 'python' })
  view.active = 'description'
  question.views[view.slug] = view

  local fetched = false
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_detail',
    function() fetched = true end,
    function() question.open(view.slug) end
  )
  eq(fetched, false)
  eq(question.active, view)
  question.close(view)
end

T['open']['rejects empty slugs'] = function()
  local question = helpers.mod('question')
  question.open(nil)
  question.open('')
  eq(question.current(), nil)
end

T['open']['reports fetch failures'] = function()
  local question = helpers.mod('question')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_detail',
    function() return nil, 'not found' end,
    function() question.open('missing') end
  )
  eq(question.current(), nil)
  eq(question.views.missing, nil)
end

T['tabs'] = new_set()

T['tabs']['switches between all tabs'] = function()
  local question, view = opened_view()
  local ui = helpers.mod('ui')

  question.show_tab(view, 'description')
  eq(view.active, 'description')
  eq(vim.api.nvim_win_get_buf(ui.state.winid), ui.panel())
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 0, 1, false)[1], '')
  local text = table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'Two Sum'), true)

  question.show_tab(view, 'console')
  eq(view.active, 'console')
  eq(helpers.contains(table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n'), 'Testcases'), true)

  question.show_tab(view, 'info')
  eq(view.active, 'info')
  eq(helpers.contains(table.concat(vim.api.nvim_buf_get_lines(ui.panel(), 0, -1, false), '\n'), 'Commands'), true)

  question.show_tab(view, 'code')
  eq(view.active, 'code')
  eq(vim.api.nvim_win_get_buf(ui.state.winid), view.code_bufnr)

  question.show_tab(view, 'unknown')
  eq(view.active, 'code')
  question.close(view)
end

T['tabs']['cycles and wraps'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://cycle', { ft = 'python' })
  question.views[view.slug] = view
  question.active = view
  view.active = 'code'

  question.cycle_tab(view, 1)
  eq(view.active, 'console')
  question.cycle_tab(view, -1)
  eq(view.active, 'code')
  question.cycle_tab(view, -1)
  eq(view.active, 'description')
  question.cycle_tab(view, 1)
  eq(view.active, 'code')
  question.close(view)
end

T['tabs']['refresh selects the active tab and tolerates missing views'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://refresh', { ft = 'python' })
  question.views[view.slug] = view
  question.active = view

  view.active = 'description'
  question.refresh(view)
  eq(vim.api.nvim_get_current_buf(), helpers.mod('ui').panel())

  view.active = 'code'
  question.refresh(view)
  eq(vim.api.nvim_get_current_buf(), view.code_bufnr)

  question.refresh(nil)
  question.refresh(make_view())
  question.close(view)
end

T['tabs']['show_tab prepares a missing code buffer'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.views[view.slug] = view
  question.active = view
  question.show_tab(view, 'code')
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
  question.close(view)
end

T['winbar'] = new_set()

T['winbar']['click handlers switch tabs'] = function()
  local question = helpers.mod('question')
  local buffer = helpers.mod('buffer')
  local view = make_view()
  view.code_bufnr = buffer.scratch('leetcode-ui://click', { ft = 'python' })
  question.views[view.slug] = view
  question.active = view

  for _, item in ipairs({
    { name = 'Description', active = 'description' },
    { name = 'Console', active = 'console' },
    { name = 'Info', active = 'info' },
    { name = 'Code', active = 'code' },
  }) do
    local click = _G['LeetCodeClick' .. item.name]
    eq(type(click), 'function')
    click()
    eq(view.active, item.active)
  end

  question.close(view)
end

T['winbar']['renders tabs and busy state'] = function()
  local question = helpers.mod('question')
  local ui = helpers.mod('ui')
  local view = make_view()
  question.views[view.slug] = view
  question.active = view
  view.active = 'code'
  view.busy = true

  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://winbar', { ft = 'python' })
  ui.ensure()
  question.render_winbar(view)
  local winbar = vim.api.nvim_get_option_value('winbar', { win = ui.state.winid })
  eq(helpers.contains(winbar, '%#LeetCodeHeader#LeetCode Two Sum %#LeetCodeWinBar#'), true)
  eq(helpers.contains(winbar, 'LeetCode'), true)
  eq(helpers.contains(winbar, 'Description'), true)
  eq(helpers.contains(winbar, 'Code (python3)'), true)
  eq(helpers.contains(winbar, '…'), true)
  eq(helpers.contains(winbar, '%#LeetCodeTab# Description %X%#LeetCodeWinBar#'), true)
  eq(helpers.contains(winbar, '%#LeetCodeTabActive# Code (python3) %X%#LeetCodeWinBar#'), true)
  for _, tab in ipairs({ 'Description', 'Code', 'Console', 'Info' }) do
    eq(helpers.contains(winbar, ('%%@v:lua.LeetCodeClick%s@'):format(tab)), true)
  end

  ui.close()
  question.render_winbar(view)
  question.close(view)
end

T['current'] = new_set()

T['current']['uses the code buffer or the active view'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://current', { ft = 'python' })
  question.views[view.slug] = view
  vim.api.nvim_set_current_buf(view.code_bufnr)
  eq(question.current(), view)

  vim.api.nvim_set_current_buf(buffer.scratch('leetcode-ui://other'))
  question.active = view
  eq(question.current(), view)

  question.views = {}
  question.active = nil
  eq(question.current(), nil)
end

T['close'] = new_set()

T['close']['saves the draft and removes buffers and state'] = function()
  local question, view = opened_view()
  local storage = helpers.mod('storage')
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'draft' })
  question.close(view)
  eq(storage.read_draft('two-sum', 'python3'), 'draft')
  eq(question.views['two-sum'], nil)
  eq(question.active, nil)
  eq(helpers.mod('ui').is_open(), false)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), false)
end

T['close']['tolerates a view without a console'] = function()
  local question = helpers.mod('question')
  local ok = pcall(question.close, { slug = 'without-console' })
  eq(ok, true)
end

T['close']['closes the central window without a view'] = function()
  local question = helpers.mod('question')
  local ui = helpers.mod('ui')
  ui.ensure()
  question.close(nil)
  eq(ui.is_open(), false)
  eq(question.active, nil)
end

T['hints'] = new_set()

T['hints']['shows, hides, and toggles hints'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.detail.hints = { '<p>first hint</p>', '<p>second hint</p>' }
  view.show_hints = false
  question.views[view.slug] = view
  question.active = view

  question.set_hints(view, true)
  eq(view.show_hints, true)
  eq(view.active, 'description')
  local text = table.concat(vim.api.nvim_buf_get_lines(helpers.mod('ui').panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'first hint'), true)

  question.set_hints(view, false)
  eq(view.show_hints, false)
  text = table.concat(vim.api.nvim_buf_get_lines(helpers.mod('ui').panel(), 0, -1, false), '\n')
  eq(helpers.contains(text, 'first hint'), false)
  eq(helpers.contains(text, 'Hints (2) hidden'), true)

  question.set_hints(view, nil)
  eq(view.show_hints, true)
  question.close(view)
end

T['hints']['does nothing when a question has no hints'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.show_hints = false
  question.set_hints(view, true)
  eq(view.show_hints, false)
  eq(pcall(question.set_hints, nil, true), true)
end

T['reset_code'] = new_set()

T['reset_code']['delegates to the solution and guards busy views'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  local reset = 0
  question.active = view
  helpers.with_stub('leetcode-ui.solution', 'reset', function(target)
    eq(target, view)
    reset = reset + 1
  end, function()
    question.reset_code(view)
    view.busy = true
    question.reset_code(view)
  end)
  eq(reset, 1)
end

T['switch_language'] = new_set()

T['switch_language']['uses the picker and switches'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  local switched = nil
  local refreshed = 0

  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3', 'golang' } end, function()
    helpers.with_stub(
      'leetcode-ui.picker',
      'select',
      function(_items, _title, on_choice) on_choice('golang', 2) end,
      function()
        helpers.with_stub('leetcode-ui.solution', 'switch_language', function(target, slug)
          eq(target, view)
          switched = slug
        end, function()
          helpers.with_stub(
            'leetcode-ui.question',
            'refresh',
            function() refreshed = refreshed + 1 end,
            function() question.switch_language(view) end
          )
        end)
      end
    )
  end)
  eq(switched, 'golang')
  eq(refreshed, 1)
end

T['switch_language']['handles cancellation, missing languages, and busy views'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3' } end, function()
    local ok = pcall(question.switch_language, view)
    eq(ok, true)
  end)

  helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3', 'golang' } end, function()
    helpers.with_stub(
      'leetcode-ui.picker',
      'select',
      function(_items, _title, on_choice) on_choice(nil, nil) end,
      function()
        local ok = pcall(question.switch_language, view)
        eq(ok, true)
      end
    )
  end)

  view.busy = true
  local ok = pcall(question.switch_language, view)
  eq(ok, true)
  eq(pcall(question.switch_language, nil), true)
end

T['run'] = new_set()

local function with_runner_stubs(interpret, fn)
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub(
      'leetcode-ui.solution',
      'code',
      function() return 'code' end,
      function() helpers.with_stub('leetcode-ui.api.runner', 'interpret', interpret, fn) end
    )
  end)
end

T['run']['runs all cases through the LeetCode API'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  with_runner_stubs(
    function()
      return {
        status = 'Accepted',
        runtime_ms = 5,
        compare = '10',
        correct = 1,
        total = 2,
        stdouts = { 'a', 'b' },
        pretty_stdout = 'pretty',
      },
        nil
    end,
    function() question.run(view) end
  )

  eq(view.console.cases[1].status, 'passed')
  eq(view.console.cases[2].status, 'failed')
  eq(view.console.cases[1].result.stdout, 'a')
  eq(view.busy, false)
  eq(view.active, 'console')
end

T['run']['runs one case through the LeetCode API'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  local captured_input = nil

  with_runner_stubs(function(_question, _code, input)
    captured_input = input
    return { status = 'Accepted', runtime_ms = 5, compare = '1', stdouts = { 'single output' } }, nil
  end, function() question.run(view, '2') end)

  eq(captured_input, '[3,2,4]\n6')
  eq(view.console.cases[2].status, 'passed')
  eq(view.console.cases[2].result.stdout, 'single output')
  eq(view.console.cases[1].status, 'unknown')
end

T['run']['uses result messages when no compare bits are returned'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  with_runner_stubs(
    function() return { status = 'Compile Error', message = 'syntax error', runtime_ms = 2 }, nil end,
    function() question.run(view, 1) end
  )

  eq(view.console.cases[1].status, 'error')
  eq(view.console.cases[1].result.message, 'syntax error')
end

T['run']['reports API failures'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  with_runner_stubs(function() return nil, 'boom' end, function() question.run(view) end)

  eq(view.console.cases[1].status, 'error')
  eq(view.console.cases[2].status, 'error')
  eq(view.console.cases[1].result.message, 'boom')
  eq(view.busy, false)
end

T['run']['guards missing views, busy views, and invalid indexes'] = function()
  local question = helpers.mod('question')
  eq(pcall(question.run, nil), true)

  local view = make_view()
  question.active = view
  view.busy = true
  eq(pcall(question.run, view), true)

  view.busy = false
  eq(pcall(question.run, view, 99), true)
  eq(pcall(question.run, view, 'nope'), true)
end

T['submit'] = new_set()

T['submit']['submits and marks the question solved'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  ---@type any
  ---@type any
  local updated = nil

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub(
        'leetcode-ui.api.runner',
        'submit',
        function() return { ok = true, status = 'Accepted', runtime_ms = 5, memory_mb = 1024 * 1024 }, nil end,
        function()
          helpers.with_stub(
            'leetcode-ui.api.question',
            'update_list_status',
            function(slug, status) updated = { slug, status } end,
            function() question.submit(view) end
          )
        end
      )
    end)
  end)

  eq(view.console.submission_result.status, 'Accepted')
  eq(view.active, 'console')
  eq(updated[1], 'two-sum')
  eq(updated[2], 'solved')
  eq(view.entry.status, 'solved')
  eq(view.busy, false)
end

T['submit']['marks a previously solved question attempted on failure'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.entry.status = 'solved'
  question.active = view
  ---@type any
  ---@type any
  local updated = nil

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub(
        'leetcode-ui.api.runner',
        'submit',
        function()
          return {
            ok = false,
            status = 'Wrong Answer',
            message = 'wrong',
            input = 'in',
            expected_output = 'out',
            code_output = 'got',
            runtime_ms = 1,
            memory_mb = 2,
          },
            nil
        end,
        function()
          helpers.with_stub(
            'leetcode-ui.api.question',
            'update_list_status',
            function(slug, status) updated = { slug, status } end,
            function() question.submit(view) end
          )
        end
      )
    end)
  end)
  eq(updated[2], 'attempted')
  eq(view.entry.status, 'attempted')
end

T['submit']['reports submission errors'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub(
        'leetcode-ui.api.runner',
        'submit',
        function() return nil, 'failed' end,
        function() question.submit(view) end
      )
    end)
  end)
  eq(view.busy, false)
  eq(view.console.submission_result, nil)

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function() return nil, nil end, function()
        local called = pcall(question.submit, view)
        eq(called, true)
      end)
    end)
  end)
  eq(pcall(question.submit, nil), true)

  view.busy = true
  eq(pcall(question.submit, view), true)
end

return T
