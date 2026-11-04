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

local view_buffer_id = 0

local function make_view()
  local view = helpers.fake_view()
  view_buffer_id = view_buffer_id + 1
  view.code_bufnr =
    helpers.mod('buffer').scratch(('leetcode-ui://test-%s-%d'):format(view.slug, view_buffer_id), { ft = 'text' })
  helpers.fake_console(view)
  return view
end

T['module'] = new_set()

T['module']['rejects unloaded code buffers'] = function()
  local question = helpers.mod('question')
  for _, action in ipairs({ 'run', 'submit', 'reset_code' }) do
    local view = make_view()
    question.active = view
    vim.cmd(('silent! bunload! %d'):format(view.code_bufnr))
    eq(vim.api.nvim_buf_is_loaded(view.code_bufnr), false)

    local called = false
    helpers.with_stub('leetcode-ui.api.runner', 'interpret', function() called = true end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function() called = true end, function()
        helpers.with_stub('leetcode-ui.solution', 'reset', function()
          called = true
          return true
        end, function() question[action](view) end)
      end)
    end)
    eq(called, false)
  end
end

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
  local text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, '1. Two Sum'), true)
  eq(helpers.contains(text, 'Premium'), true)
  eq(helpers.contains(text, '50.5%'), true)
  eq(helpers.contains(text, 'find two indices'), true)
  eq(helpers.contains(text, 'first hint'), false)
  eq(helpers.contains(text, 'Hints (2) hidden'), true)

  view.show_hints = true
  text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, 'Hints'), true)
  eq(helpers.contains(text, '1. first hint'), true)
end

T['describe']['uses the cached solved status'] = function()
  local view = make_view()
  view.entry.status = 'solved'
  view.detail.status = nil
  local lines = helpers.mod('question').description_lines(view)
  local text = table.concat(helpers.mod('buffer').spans_to_texts(lines), '\n')
  eq(helpers.contains(text, '✔'), true)
end

T['describe']['normalizes API status values'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.entry.status = nil
  view.detail.status = 'ac'
  local text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, '✔'), true)

  view.detail.status = 'notac'
  text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, '✘'), true)

  view.entry.status = 'attempted'
  view.detail.status = 'ac'
  text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, '✔'), true)
end

T['describe']['ignores empty hints'] = function()
  local view = make_view()
  view.detail.hints = { '', '   ', '<!-- comment -->', '<img src="x"/>', '<p>real hint</p>' }
  local text = table.concat(helpers.mod('buffer').spans_to_texts(helpers.mod('question').description_lines(view)), '\n')
  eq(helpers.contains(text, 'Hints (1) hidden'), true)
  view.show_hints = true
  text = table.concat(helpers.mod('buffer').spans_to_texts(helpers.mod('question').description_lines(view)), '\n')
  eq(helpers.contains(text, '1. real hint'), true)
end

T['describe']['handles missing fields'] = function()
  local view = make_view()
  view.detail = {}
  local question = helpers.mod('question')
  local text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, 'no description'), true)
end

T['info'] = new_set()

T['info']['wraps long tag lists with a continuation indent'] = function()
  local view = make_view()
  local tags = {}
  for index = 1, 20 do
    tags[index] = { name = 'VeryLongTag' .. index, slug = 'tag-' .. index }
  end
  view.entry.topic_tags = tags
  local lines = helpers.mod('question').info_lines(view)
  local tag_lines = {}
  for _, line in ipairs(lines) do
    local text = helpers.mod('buffer').spans_to_texts({ line })[1]
    if helpers.contains(text, 'VeryLongTag') then table.insert(tag_lines, text) end
  end
  eq(#tag_lines > 1, true)
  local label = 'Tags:        '
  for index, text in ipairs(tag_lines) do
    eq(#text <= 78, true)
    local prefix = index == 1 and label or string.rep(' ', #label)
    eq(text:sub(1, #prefix), prefix)
  end
end

T['info']['renders question metadata and command help'] = function()
  local view = make_view()
  local question = helpers.mod('question')
  local lines = question.info_lines(view)
  local text = table.concat(helpers.mod('buffer').spans_to_texts(lines), '\n')
  local flat = text:gsub('%s+', ' ')
  eq(helpers.contains(text, 'LeetCode API'), true)
  eq(helpers.contains(text, 'Array'), true)
  eq(helpers.contains(text, 'Language:    Python3'), true)
  eq(helpers.contains(text, ':LeetCode question run'), true)
  eq(helpers.contains(flat, 'Run all testcases or one testcase'), true)

  local sections = {}
  local current = nil
  for _, line in ipairs(lines) do
    local command, description = line[1], line[2]
    if command ~= nil and command.text == 'Commands' then
      current = {}
      sections.Commands = current
    elseif command ~= nil and command.text == 'Testcases' and command.hl == 'LeetCodeHeader' then
      current = {}
      sections.Testcases = current
    elseif current ~= nil and command ~= nil and description ~= nil and helpers.contains(command.text, ':LeetCode') then
      table.insert(current, #command.text)
    end
  end

  eq(vim.tbl_count(sections), 2)
  for _, columns in pairs(sections) do
    eq(#columns > 0, true)
    for _, column in ipairs(columns) do
      eq(column, columns[1])
    end
  end
end

T['open'] = new_set()

T['open']['fetches and opens a question'] = function()
  local question, view = opened_view()
  local ui = helpers.mod('ui')
  eq(view.slug, 'two-sum')
  eq(view.active, 'code')
  eq(view.show_hints, false)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, 1, false)[1], 'class Solution:')
  eq(vim.api.nvim_get_current_buf(), view.code_bufnr)
  eq(vim.api.nvim_get_option_value('signcolumn', { win = ui.state.winid }), 'auto')
  eq(
    helpers.contains(
      vim.api.nvim_get_option_value('winhighlight', { win = ui.state.winid }),
      'Normal:LeetCodeCodeNormal'
    ),
    true
  )
  eq(vim.api.nvim_get_option_value('statuscolumn', { win = ui.state.winid }), '%s%C%l ')
  eq(vim.api.nvim_get_option_value('foldcolumn', { win = ui.state.winid }), '1')
  eq(vim.api.nvim_get_option_value('foldenable', { win = ui.state.winid }), true)
  eq(question.views['two-sum'], view)
  question.close(view)
end

T['open']['falls back to an available configured language'] = function()
  helpers.configure({ lang = 'cpp' })
  local question, view = opened_view()
  eq(view.lang, 'golang')
  eq(view.detail.snippets[view.lang] ~= nil, true)
  question.close(view)
end

T['open']['honors the show_hints default'] = function()
  helpers.configure({ show_hints = true })
  local question = helpers.mod('question')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_detail',
    function() return helpers.fake_detail({ hints = { '<p>visible hint</p>' } }), nil end,
    function() question.open('two-sum') end
  )

  local view = question.views['two-sum']
  eq(view.show_hints, true)
  local text = table.concat(helpers.mod('buffer').spans_to_texts(question.description_lines(view)), '\n')
  eq(helpers.contains(text, 'visible hint'), true)
  question.close(view)
end

T['open']['loads persisted testcases'] = function()
  local storage = helpers.mod('storage')
  storage.write_testcases('two-sum', { 'saved one', 'saved two' })

  local question, view = opened_view()
  eq(#view.console.cases, 2)
  eq(view.console.cases[1].input, 'saved one')
  eq(view.console.cases[2].input, 'saved two')
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

T['open']['does not fetch the same question twice'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local fetches, thread = 0, nil
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    fetches = fetches + 1
    thread = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('two-sum')
    question.open('two-sum')
    eq(fetches, 1)
    eq(type(question.loading_slugs['two-sum']), 'number')
    eq(async.resume(thread), true)
  end)
  eq(question.loading_slugs['two-sum'], nil)
  eq(question.views['two-sum'] ~= nil, true)
  question.close(question.views['two-sum'])
end

T['open']['starts a fresh load after navigation changes'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local ui = helpers.mod('ui')
  local threads, calls = {}, 0
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    calls = calls + 1
    local call = calls
    local thread = coroutine.running()
    table.insert(threads, thread)
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug, title = 'Load ' .. call }), nil
  end, function()
    question.open('two-sum')
    ui.bump()
    question.open('two-sum')
    eq(#threads, 2)
    eq(async.resume(threads[2]), true)
    eq(question.views['two-sum'].detail.title, 'Load 2')
    eq(question.loading_slugs['two-sum'], nil)
    eq(async.resume(threads[1]), true)
    eq(question.views['two-sum'].detail.title, 'Load 2')
  end)
  question.close(question.views['two-sum'])
end

T['open']['ignores stale question loads'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local threads = {}
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    threads[slug] = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('question-a')
    question.open('question-b')
    eq(async.resume(threads['question-b']), true)
    eq(async.resume(threads['question-a']), true)
  end)

  eq(question.views['question-a'], nil)
  eq(question.views['question-b'] ~= nil, true)
  eq(question.active.slug, 'question-b')
  question.close(question.views['question-b'])
end

T['open']['does not replace a newer statistics view'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local ui = helpers.mod('ui')
  local thread
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    thread = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('two-sum')
    ui.claim('stats')
    ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })
    eq(async.resume(thread), true)
  end)

  eq(question.views['two-sum'], nil)
  eq(question.active, nil)
  eq(ui.state.owner, 'stats')
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 1, 2, false)[1], 'stats')
  ui.close()
end

T['open']['replaces an older statistics view'] = function()
  local question = helpers.mod('question')
  local ui = helpers.mod('ui')
  helpers.with_stub(
    'leetcode-ui.api.question',
    'get_detail',
    function(slug) return helpers.fake_detail({ title_slug = slug }), nil end,
    function()
      ui.claim('stats')
      ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })
      question.open('two-sum')
    end
  )

  local view = question.views['two-sum']
  eq(view ~= nil, true)
  eq(question.active, view)
  eq(ui.state.owner, 'question')
  question.close(view)
  ui.close()
end

T['open']['does not open after closing during a load'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local ui = helpers.mod('ui')
  local thread
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    thread = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('late-question')
    question.close(nil)
    eq(async.resume(thread), true)
  end)

  eq(question.views['late-question'], nil)
  eq(question.loading_slugs['late-question'], nil)
  eq(ui.is_open(), false)
end

T['open']['does not reopen after an overlay is opened and closed during a load'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local ui = helpers.mod('ui')
  local thread
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    thread = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('late-question')
    ui.claim('stats')
    ui.close()
    eq(async.resume(thread), true)
  end)

  eq(question.views['late-question'], nil)
  eq(question.active, nil)
  eq(ui.is_open(), false)
end

T['open']['does not replace newer picker navigation'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local thread
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    thread = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('late-question')
    helpers.with_stub(
      'leetcode-ui.api.question',
      'get_daily',
      function() return nil, 'offline' end,
      function() helpers.mod('picker').daily() end
    )
    eq(async.resume(thread), true)
  end)

  eq(question.views['late-question'], nil)
  eq(question.active, nil)
end

T['open']['does not open after a credential change'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local keys = 0
  local thread
  helpers.with_stub('leetcode-ui.auth', 'cache_key', function()
    keys = keys + 1
    return keys == 1 and 'old-user' or 'new-user'
  end, function()
    helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
      thread = coroutine.running()
      coroutine.yield()
      return helpers.fake_detail({ title_slug = slug }), nil
    end, function()
      question.open('late-question')
      eq(async.resume(thread), true)
    end)
  end)

  eq(question.views['late-question'], nil)
  eq(question.loading_slugs['late-question'], nil)
end

T['open']['does not open after a domain change'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local ui = helpers.mod('ui')
  local thread
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    thread = coroutine.running()
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('late-question')
    helpers.configure({ url = 'leetcode.cn' })
    eq(async.resume(thread), true)
  end)

  eq(question.views['late-question'], nil)
  eq(question.loading_slugs['late-question'], nil)
  eq(ui.is_open(), false)
end

T['open']['setup invalidates in-flight loads'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local threads = {}
  helpers.with_stub('leetcode-ui.api.question', 'get_detail', function(slug)
    local thread = coroutine.running()
    table.insert(threads, thread)
    coroutine.yield()
    return helpers.fake_detail({ title_slug = slug }), nil
  end, function()
    question.open('two-sum')
    eq(#threads, 1)
    helpers.configure({ cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
    eq(question.loading_slugs['two-sum'], nil)
    question.open('two-sum')
    eq(#threads, 2)
    eq(async.resume(threads[2]), true)
    eq(question.views['two-sum'] ~= nil, true)
    eq(async.resume(threads[1]), true)
  end)
  question.close(question.views['two-sum'])
end

T['open']['rejects empty slugs'] = function()
  local question = helpers.mod('question')
  question.open(nil)
  question.open('')
  eq(question.current(), nil)
end

T['open']['warns when no solution language is available'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local messages = helpers.capture_notify(function()
    helpers.with_stub(
      'leetcode-ui.api.question',
      'get_detail',
      function() return helpers.fake_detail({ snippets = {} }), nil end,
      function() question.open('two-sum') end
    )
  end)

  local view = question.views['two-sum']
  eq(view ~= nil, true)
  eq(view.lang, 'python3')
  eq(helpers.mod('solution').snippet(view), '')
  local warned = false
  for _, message in ipairs(messages) do
    if helpers.contains(message.message, 'No supported solution language') then warned = true end
  end
  eq(warned, true)
  helpers.configure({ notifications = false })
  question.close(view)
end

T['open']['reports fetch failures'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local messages = helpers.capture_notify(function()
    helpers.with_stub(
      'leetcode-ui.api.question',
      'get_detail',
      function() return nil, 'not found' end,
      function() question.open('missing') end
    )
  end)
  eq(question.current(), nil)
  eq(question.views.missing, nil)
  eq(question.loading_slugs.missing, nil)
  eq(helpers.contains(messages[#messages].message, 'not found'), true)
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

  question.show_tab(view, 'info')
  question.cycle_tab(view, 1)
  eq(view.active, 'description')
  question.cycle_tab(view, -1)
  eq(view.active, 'info')
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
  question.refresh(view, true)
  eq(vim.api.nvim_get_current_buf(), helpers.mod('ui').panel())

  view.active = 'code'
  question.refresh(view, true)
  eq(vim.api.nvim_get_current_buf(), view.code_bufnr)

  question.refresh(nil)
  question.refresh(make_view())
  question.close(view)
end

T['tabs']['does not reopen a closed window from a background refresh'] = function()
  local question, view = opened_view()
  local ui = helpers.mod('ui')
  ui.close()
  question.refresh(view)
  eq(ui.is_open(), false)
end

T['tabs']['refresh reloads and reopens an unloaded code buffer'] = function()
  local question = helpers.mod('question')
  local storage = helpers.mod('storage')
  local view = make_view()
  storage.write_draft('two-sum', 'python3', 'saved draft')
  vim.cmd(('silent! bunload! %d'):format(view.code_bufnr))
  question.views[view.slug] = view
  question.active = view
  view.active = 'code'

  question.refresh(view, true)
  eq(vim.api.nvim_buf_is_loaded(view.code_bufnr), true)
  eq(helpers.mod('solution').code(view), 'saved draft')
  eq(#vim.api.nvim_get_autocmds({ event = 'BufLeave', buffer = view.code_bufnr }), 1)
  question.close(view)
end

T['tabs']['show_tab prepares a missing code buffer'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  vim.api.nvim_buf_delete(view.code_bufnr, { force = true })
  view.code_bufnr = nil
  question.views[view.slug] = view
  question.active = view
  question.show_tab(view, 'code')
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
  eq(vim.api.nvim_buf_get_name(view.code_bufnr), 'leetcode-ui://question/two-sum')
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, 1, false)[1], 'class Solution:')
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
  eq(helpers.contains(winbar, '%#LeetCodeQuestionTitle#LeetCode 1 %#LeetCodeWinBar#'), true)
  eq(helpers.contains(winbar, 'LeetCode'), true)
  eq(helpers.contains(winbar, 'Description'), true)
  eq(helpers.contains(winbar, 'Code (Python3)'), true)
  eq(helpers.contains(winbar, '…'), true)
  eq(helpers.contains(winbar, '%#LeetCodeTab# Description %X%#LeetCodeWinBar#'), true)
  eq(helpers.contains(winbar, '%#LeetCodeTabActive# Code (Python3) %X%#LeetCodeWinBar#'), true)
  eq(winbar:find('  ', 1, true), nil)
  for _, tab in ipairs({ 'Description', 'Code', 'Console', 'Info' }) do
    eq(helpers.contains(winbar, ('%%@v:lua.LeetCodeClick%s@'):format(tab)), true)
  end

  ui.close()
  question.render_winbar(view)
  question.close(view)
end

T['current'] = new_set()

T['current']['prefers the code buffer over the active view'] = function()
  local question = helpers.mod('question')
  local active = make_view()
  local other = make_view()
  other.slug = 'other-question'
  other.detail.title_slug = 'other-question'
  question.views[active.slug] = active
  question.views[other.slug] = other
  question.active = active

  vim.api.nvim_set_current_buf(other.code_bufnr)
  eq(question.current(), other)

  vim.api.nvim_set_current_buf(helpers.mod('buffer').scratch('leetcode-ui://other'))
  eq(question.current(), active)

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

T['close']['leaves another overlay open'] = function()
  local question, view = opened_view()
  local ui = helpers.mod('ui')
  ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })

  question.close(view)
  eq(question.views['two-sum'], nil)
  eq(question.active, nil)
  eq(ui.is_open(), true)
  eq(ui.state.owner, 'stats')
  eq(vim.api.nvim_buf_get_lines(ui.panel(), 1, 2, false)[1], 'stats')
  ui.close()
end

T['close']['keeps the view and buffer when draft persistence fails'] = function()
  local question, view = opened_view()
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'unsaved draft' })
  local saved = 0

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function()
    saved = saved + 1
    return false
  end, function()
    question.close(view)
    eq(question.views[view.slug], view)
    eq(question.active, view)
    eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
    eq(helpers.mod('ui').is_open(), true)
  end)
  eq(saved, 1)
end

T['close']['removes an inactive view without closing the active one'] = function()
  local question = helpers.mod('question')
  local first, second = make_view(), make_view()
  second.slug = 'other'
  second.detail.title_slug = 'other'
  question.views[first.slug] = first
  question.views[second.slug] = second
  question.active = second

  question.close(first)
  eq(question.views[first.slug], nil)
  eq(question.views[second.slug], second)
  eq(question.active, second)
  eq(vim.api.nvim_buf_is_valid(second.code_bufnr), true)
end

T['close']['tolerates a view without a console'] = function()
  local question = helpers.mod('question')
  local view = { slug = 'without-console' }
  question.views[view.slug] = view
  question.active = view
  question.close(view)
  eq(view.closed, true)
  eq(question.views[view.slug], nil)
  eq(question.active, nil)
end

T['close']['external window close runs the full close workflow'] = function()
  local question, view = opened_view()
  local ui = helpers.mod('ui')
  local storage = helpers.mod('storage')
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'external close draft' })

  vim.api.nvim_win_close(ui.state.winid, true)

  eq(ui.is_open(), false)
  eq(question.views['two-sum'], nil)
  eq(question.active, nil)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), false)
  eq(storage.read_draft('two-sum', 'python3'), 'external close draft')
end

T['close']['closes the central window without a view'] = function()
  local question = helpers.mod('question')
  local ui = helpers.mod('ui')
  ui.ensure()
  question.close(nil)
  eq(ui.is_open(), false)
  eq(question.active, nil)
end

T['close']['leaves another overlay open without a view'] = function()
  local question = helpers.mod('question')
  local ui = helpers.mod('ui')
  ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })
  question.close(nil)
  eq(ui.is_open(), true)
  eq(ui.state.owner, 'stats')
  ui.close()
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

T['hints']['indents continuation lines'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.detail.hints = { '<p>first<br>second</p>' }
  view.show_hints = true
  local lines = helpers.mod('buffer').spans_to_texts(question.description_lines(view))
  local found = {}
  for _, line in ipairs(lines) do
    if helpers.contains(line, 'first') or helpers.contains(line, 'second') then table.insert(found, line) end
  end
  eq(found, { '1. first', '   second' })
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
  view.console.submission_result = { status = 'Accepted' }
  view.console.cases[1].status = 'passed'
  local reset, refreshed = 0, 0
  question.active = view
  helpers.with_stub('leetcode-ui.solution', 'reset', function(target)
    eq(target, view)
    reset = reset + 1
    return true
  end, function()
    helpers.with_stub('leetcode-ui.question', 'refresh', function() refreshed = refreshed + 1 end, function()
      question.reset_code(view)
      eq(view.console.submission_result, nil)
      eq(view.console.cases[1].status, 'unknown')

      view.busy = true
      question.reset_code(view)
    end)
  end)
  eq(reset, 1)
  eq(refreshed, 1)
end

T['reset_code']['rejects a missing code buffer'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.code_bufnr = nil
  question.active = view
  local called = false
  helpers.with_stub('leetcode-ui.solution', 'reset', function()
    called = true
    return true
  end, function() question.reset_code(view) end)
  eq(called, false)
end

T['reset_code']['does not clear results when reset fails'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.console.submission_result = { status = 'Accepted' }
  view.console.cases[1].status = 'passed'
  question.active = view
  local called = 0
  helpers.with_stub('leetcode-ui.solution', 'reset', function()
    called = called + 1
    return false
  end, function() question.reset_code(view) end)
  eq(called, 1)
  eq(view.console.submission_result ~= nil, true)
  eq(view.console.cases[1].status, 'passed')
end

T['switch_language'] = new_set()

T['switch_language']['uses the picker and switches'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  view.console.submission_result = { status = 'Accepted' }
  view.console.cases[1].status = 'passed'
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
          return true
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
  eq(view.console.submission_result, nil)
  eq(view.console.cases[1].status, 'unknown')
end

T['switch_language']['rejects a missing code buffer'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.code_bufnr = nil
  question.active = view
  local called = false
  helpers.with_stub('leetcode-ui.solution', 'languages', function()
    called = true
    return { 'python3', 'golang' }
  end, function() question.switch_language(view) end)
  eq(called, false)
end

T['switch_language']['handles cancellation, missing languages, and busy views'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  local switches = 0

  helpers.with_stub('leetcode-ui.solution', 'switch_language', function() switches = switches + 1 end, function()
    helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3' } end, function()
      question.switch_language(view)
      eq(switches, 0)
    end)

    helpers.with_stub('leetcode-ui.solution', 'languages', function() return { 'python3', 'golang' } end, function()
      helpers.with_stub(
        'leetcode-ui.picker',
        'select',
        function(_items, _title, on_choice) on_choice(nil, nil) end,
        function()
          question.switch_language(view)
          eq(switches, 0)
        end
      )
    end)

    view.busy = true
    question.switch_language(view)
    eq(switches, 0)
    view.busy = false
    question.active = nil
    eq(pcall(question.switch_language, nil), true)
  end)
end

T['run'] = new_set()

local function with_runner_stubs(interpret, fn, save_draft)
  helpers.with_stub('leetcode-ui.solution', 'save_draft', save_draft or function() end, function()
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
  ---@type table|nil
  local captured = nil
  local saves = 0

  with_runner_stubs(function(payload, code, input)
    captured = { payload = payload, code = code, input = input }
    return {
      status = 'Accepted',
      message = 'runtime detail',
      runtime_ms = 5,
      compare = '10',
      correct = 1,
      total = 2,
      stdouts = { 'a', 'b' },
      pretty_stdout = 'pretty',
      answers = { '[0,1]', '[1,0]' },
      expected_answers = { '[0,1]', '[1,0]' },
    },
      nil
  end, function() question.run(view) end, function() saves = saves + 1 end)

  eq(saves, 1)
  assert(captured ~= nil)
  eq(captured.payload.id, '1')
  eq(captured.payload.title_slug, 'two-sum')
  eq(captured.payload.lang_slug, 'python3')
  eq(captured.code, 'code')
  eq(captured.input, '[2,7,11,15]\n9\n[3,2,4]\n6')
  eq(view.console.cases[1].status, 'passed')
  eq(view.console.cases[2].status, 'failed')
  eq(view.console.cases[1].result.stdout, 'a')
  eq(view.console.cases[1].result.answer, '[0,1]')
  eq(view.console.cases[1].result.expected_answer, '[0,1]')
  eq(view.console.cases[1].result.message, 'runtime detail')
  eq(view.console.cases[2].result.stdout, 'b')
  eq(view.console.cases[2].result.answer, '[1,0]')
  eq(view.console.cases[2].result.expected_answer, '[1,0]')
  eq(view.busy, false)
  eq(view.active, 'console')
end

T['run']['defaults missing compare bits to failures'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  with_runner_stubs(
    function() return { status = 'Accepted', compare = '1', stdouts = { 'a' } }, nil end,
    function() question.run(view) end
  )

  eq(view.console.cases[1].status, 'passed')
  eq(view.console.cases[2].status, 'failed')
end

T['run']['runs one case through the LeetCode API'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  local captured_input = nil

  with_runner_stubs(function(_question, _code, input)
    captured_input = input
    return {
      status = 'Accepted',
      runtime_ms = 5,
      compare = '1',
      stdouts = { 'single output' },
      answers = { '[0,1]' },
      expected_answers = { '[0,1]' },
    },
      nil
  end, function() question.run(view, '2') end)

  eq(captured_input, '[3,2,4]\n6')
  eq(view.console.cases[2].status, 'passed')
  eq(view.console.cases[2].result.stdout, 'single output')
  eq(view.console.cases[2].result.answer, '[0,1]')
  eq(view.console.cases[1].status, 'unknown')
  eq(view.console.selected, 2)
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

T['run']['accepts numeric compare results and invalid testcases'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  with_runner_stubs(
    function() return { status = 'Accepted', compare = 1, stdouts = 'ignored' }, nil end,
    function() question.run(view, 1) end
  )
  eq(view.console.cases[1].status, 'passed')

  with_runner_stubs(
    function() return { status = 'Invalid Testcase', message = 'bad input' }, nil end,
    function() question.run(view, 1) end
  )
  eq(view.console.cases[1].status, 'error')
  eq(view.console.cases[1].result.message, 'bad input')

  with_runner_stubs(
    function() return { status = 'Wrong Answer', compare = '' }, nil end,
    function() question.run(view, 1) end
  )
  eq(view.console.cases[1].status, 'failed')
end

T['run']['stops silently when the view closes during polling'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  local interpreted = false
  local messages = helpers.capture_notify(function()
    with_runner_stubs(function(_payload, _code, _input, cancelled)
      interpreted = true
      eq(type(cancelled), 'function')
      view.closed = true
      eq(cancelled(), true)
      return nil, 'Cancelled'
    end, function() question.run(view) end)
  end)

  eq(interpreted, true)
  eq(#messages > 0, true)
  for _, message in ipairs(messages) do
    eq(message.level >= vim.log.levels.WARN, false)
  end
  eq(view.busy, false)
  eq(view.console.timer, nil)
  for _, case in ipairs(view.console.cases) do
    eq(case.status, 'unknown')
    eq(case.result, nil)
    eq(case.running, false)
  end
end

T['run']['rejects a missing code buffer'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local view = make_view()
  view.code_bufnr = nil
  question.active = view
  local calls = 0
  local messages = helpers.capture_notify(function()
    with_runner_stubs(function()
      calls = calls + 1
      return nil, 'should not run'
    end, function() question.run(view) end)
  end)
  eq(calls, 0)
  eq(helpers.contains(messages[1].message, 'Solution buffer is missing'), true)
  eq(view.busy, false)
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
  local view = make_view()
  question.active = view
  local calls = 0

  helpers.with_stub('leetcode-ui.api.runner', 'interpret', function()
    calls = calls + 1
    return nil, 'should not run'
  end, function()
    question.active = nil
    question.run(nil)
    question.active = view
    view.busy = true
    question.run(view)
    view.busy = false
    question.run(view, 99)
    question.run(view, 1.5)
    question.run(view, 'nope')
  end)

  eq(calls, 0)
  eq(view.busy, false)
end

T['run']['clears busy state and running markers when the runner throws'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  with_runner_stubs(function() error('runner boom') end, function() question.run(view) end)

  eq(view.busy, false)
  eq(view.console.cases[1].running, false)
  eq(view.console.cases[2].running, false)
  eq(view.console.timer, nil)
end

T['submit'] = new_set()

T['submit']['submits and marks the question solved'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  ---@type table|nil
  local updated = nil
  ---@type table|nil
  local submitted = nil
  local saves = 0

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() saves = saves + 1 end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function(payload, code)
        submitted = { payload = payload, code = code }
        return { ok = true, status = 'Accepted', runtime_ms = 5, memory_bytes = 1024 * 1024 }, nil
      end, function()
        helpers.with_stub(
          'leetcode-ui.api.question',
          'update_list_status',
          function(slug, status) updated = { slug, status } end,
          function() question.submit(view) end
        )
      end)
    end)
  end)

  eq(saves, 1)
  assert(submitted ~= nil and updated ~= nil)
  eq(submitted.payload.id, '1')
  eq(submitted.payload.title_slug, 'two-sum')
  eq(submitted.payload.lang_slug, 'python3')
  eq(submitted.code, 'code')
  eq(view.console.submission_result.status, 'Accepted')
  eq(view.active, 'console')
  eq(updated[1], 'two-sum')
  eq(updated[2], 'solved')
  eq(view.entry.status, 'solved')
  eq(view.detail.status, 'solved')
  eq(view.busy, false)
end

T['submit']['failed submissions preserve solved status and mark new attempts'] = function()
  local question = helpers.mod('question')
  ---@type any
  local updated = nil

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub(
        'leetcode-ui.api.runner',
        'submit',
        function() return { ok = false, status = 'Wrong Answer', runtime_ms = 1, memory_bytes = 2 }, nil end,
        function()
          helpers.with_stub(
            'leetcode-ui.api.question',
            'update_list_status',
            function(slug, status) updated = { slug, status } end,
            function()
              for _, initially_solved in ipairs({ false, true }) do
                updated = nil
                local view = make_view()
                view.entry.status = initially_solved and 'solved' or nil
                question.active = view
                question.submit(view)

                if initially_solved then
                  eq(updated, nil)
                  eq(view.entry.status, 'solved')
                else
                  eq(updated[2], 'attempted')
                  eq(view.entry.status, 'attempted')
                end
              end

              updated = nil
              local detail_solved = make_view()
              detail_solved.entry = nil
              detail_solved.detail.status = 'solved'
              question.active = detail_solved
              question.submit(detail_solved)
              eq(updated, nil)
              eq(detail_solved.detail.status, 'solved')
            end
          )
        end
      )
    end)
  end)
end

T['submit']['records solved status when the list cache has no entry'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.entry = nil
  question.active = view
  ---@type table|nil
  local updated = nil

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub(
        'leetcode-ui.api.runner',
        'submit',
        function() return { ok = true, status = 'Accepted' }, nil end,
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

  assert(updated ~= nil)
  eq(updated[2], 'solved')
  eq(view.detail.status, 'solved')
end

T['submit']['marks attempts when the list cache has no entry'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  view.entry = nil
  question.active = view
  ---@type any
  local updated = nil

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub(
        'leetcode-ui.api.runner',
        'submit',
        function() return { ok = false, status = 'Wrong Answer' }, nil end,
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

  eq(updated[1], 'two-sum')
  eq(updated[2], 'attempted')
  eq(view.detail.status, 'attempted')
end

T['submit']['does not reopen a closed window after completing'] = function()
  local question = helpers.mod('question')
  local async = helpers.mod('async')
  local ui = helpers.mod('ui')
  local view = make_view()
  question.views[view.slug] = view
  question.active = view
  ui.ensure()

  local thread
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() return true end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function()
        thread = coroutine.running()
        coroutine.yield()
        return { ok = true, status = 'Accepted' }, nil
      end, function()
        question.submit(view)
        question.close(view)
        eq(async.resume(thread), true)
      end)
    end)
  end)

  eq(ui.is_open(), false)
  eq(question.views[view.slug], nil)
  eq(view.console.submission_result, nil)
end

T['submit']['omits absent runtime and memory from notifications'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view

  local messages = helpers.capture_notify(function()
    helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
      helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
        helpers.with_stub(
          'leetcode-ui.api.runner',
          'submit',
          function() return { ok = false, status = 'Wrong Answer' }, nil end,
          function() question.submit(view) end
        )
      end)
    end)
  end)

  local message = messages[#messages].message
  eq(helpers.contains(message, 'Wrong Answer'), true)
  eq(helpers.contains(message, 'Runtime:'), false)
  eq(helpers.contains(message, 'Memory:'), false)
end

T['submit']['updates list status when the view closes during judging'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  ---@type table|nil
  local updated = nil

  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function()
        view.closed = true
        return { ok = true, status = 'Accepted' }, nil
      end, function()
        helpers.with_stub(
          'leetcode-ui.api.question',
          'update_list_status',
          function(slug, status) updated = { slug, status } end,
          function() question.submit(view) end
        )
      end)
    end)
  end)

  assert(updated ~= nil)
  eq(updated[1], 'two-sum')
  eq(updated[2], 'solved')
  eq(view.console.submission_result, nil)
end

T['submit']['rejects a missing code buffer'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local view = make_view()
  view.code_bufnr = nil
  question.active = view
  local calls = 0
  local messages = helpers.capture_notify(function()
    helpers.with_stub('leetcode-ui.api.runner', 'submit', function()
      calls = calls + 1
      return { ok = true, status = 'Accepted' }, nil
    end, function() question.submit(view) end)
  end)
  eq(calls, 0)
  eq(helpers.contains(messages[1].message, 'Solution buffer is missing'), true)
  eq(view.busy, false)
end

T['submit']['discards results after a domain change'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  local thread, cancelled
  ---@type table|nil
  local updated = nil
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function(_payload, _code, predicate)
        cancelled = predicate
        thread = coroutine.running()
        coroutine.yield()
        return { ok = true, status = 'Accepted' }, nil
      end, function()
        helpers.with_stub(
          'leetcode-ui.api.question',
          'update_list_status',
          function(slug, status) updated = { slug, status } end,
          function() question.submit(view) end
        )
      end)
    end)
  end)
  assert(thread ~= nil and cancelled ~= nil)
  eq(cancelled(), false)
  helpers.configure({ url = 'leetcode.cn' })
  eq(cancelled(), true)
  eq(helpers.mod('async').resume(thread), true)
  eq(updated, nil)
  eq(view.busy, false)
  eq(view.console.submission_result, nil)
end

T['submit']['discards results after a credential change'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  ---@type table|nil
  local updated = nil
  local keys, submitted = 0, false

  helpers.with_stub('leetcode-ui.auth', 'cache_key', function()
    keys = keys + 1
    return keys == 1 and 'old-user' or 'new-user'
  end, function()
    helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
      helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
        helpers.with_stub('leetcode-ui.api.runner', 'submit', function()
          submitted = true
          return { ok = true, status = 'Accepted' }, nil
        end, function()
          helpers.with_stub(
            'leetcode-ui.api.question',
            'update_list_status',
            function(slug, status) updated = { slug, status } end,
            function() question.submit(view) end
          )
        end)
      end)
    end)
  end)

  eq(submitted, true)
  eq(updated, nil)
  eq(view.busy, false)
  eq(view.console.submission_result, nil)
end

T['submit']['cancels polling after a credential change'] = function()
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  local thread, cancelled
  ---@type table|nil
  local updated = nil
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function(_payload, _code, predicate)
        cancelled = predicate
        thread = coroutine.running()
        coroutine.yield()
        return { ok = true, status = 'Accepted' }, nil
      end, function()
        helpers.with_stub(
          'leetcode-ui.api.question',
          'update_list_status',
          function(slug, status) updated = { slug, status } end,
          function() question.submit(view) end
        )
      end)
    end)
  end)

  assert(thread ~= nil and cancelled ~= nil)
  eq(cancelled(), false)
  helpers.configure({ cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' } })
  eq(cancelled(), true)
  eq(helpers.mod('async').resume(thread), true)
  eq(updated, nil)
  eq(view.busy, false)
  eq(view.console.submission_result, nil)
end

T['submit']['clears busy when the initial refresh fails'] = function()
  local question, view = opened_view()
  local refreshes = 0
  helpers.with_stub('leetcode-ui.question', 'refresh', function()
    refreshes = refreshes + 1
    if refreshes == 1 then error('refresh boom') end
  end, function() question.submit(view) end)
  eq(view.busy, false)
  eq(refreshes, 2)
  eq(view.console.timer, nil)
end

T['submit']['reports submission errors'] = function()
  helpers.configure({ notifications = true })
  local question = helpers.mod('question')
  local view = make_view()
  question.active = view
  view.console.submission_result = { status = 'Accepted' }

  local messages = helpers.capture_notify(function()
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
  end)
  eq(helpers.contains(messages[#messages].message, 'Submission failed: failed'), true)
  eq(view.busy, false)
  eq(view.console.submission_result, nil)

  messages = helpers.capture_notify(function()
    helpers.with_stub('leetcode-ui.solution', 'save_draft', function() end, function()
      helpers.with_stub('leetcode-ui.solution', 'code', function() return 'code' end, function()
        helpers.with_stub(
          'leetcode-ui.api.runner',
          'submit',
          function() return nil, nil end,
          function() question.submit(view) end
        )
      end)
    end)
  end)
  eq(helpers.contains(messages[#messages].message, 'Submission failed: Empty response'), true)

  question.views = {}
  question.active = nil
  messages = helpers.capture_notify(function() eq(pcall(question.submit, nil), true) end)
  eq(helpers.contains(messages[1].message, 'No question is open'), true)

  helpers.configure({ notifications = false })
  view.busy = true
  local calls = 0
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function() calls = calls + 1 end, function()
    helpers.with_stub('leetcode-ui.solution', 'code', function()
      calls = calls + 1
      return 'code'
    end, function()
      helpers.with_stub('leetcode-ui.api.runner', 'submit', function()
        calls = calls + 1
        return { ok = true, status = 'Accepted' }, nil
      end, function() question.submit(view) end)
    end)
  end)
  eq(calls, 0)
  eq(view.busy, true)
end

return T
