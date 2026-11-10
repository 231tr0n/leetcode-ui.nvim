-- Tests for leetcode-ui.solution.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

local function with_code_buffer(view, content)
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch(('leetcode-ui://test-%s'):format(view.slug), { ft = 'text' })
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(content or '', '\n'))
  return view
end

T['filetype'] = new_set()

T['filetype']['maps known and unknown slugs'] = function()
  local solution = helpers.mod('solution')
  eq(solution.filetype('python3'), 'python')
  eq(solution.filetype('golang'), 'go')
  eq(solution.filetype('javascript'), 'javascript')
  eq(solution.filetype('cpp'), 'cpp')
  eq(solution.filetype('unknown-slug'), 'unknown-slug')
end

T['label'] = new_set()

T['label']['uses display names and falls back to the slug'] = function()
  local solution = helpers.mod('solution')
  eq(solution.label('python3'), 'Python3')
  eq(solution.label('golang'), 'Go')
  eq(solution.label('unknown-slug'), 'unknown-slug')
end

T['snippet'] = new_set()

T['snippet']['returns starter code or an empty string'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  eq(helpers.contains(solution.snippet(view), 'twoSum'), true)
  eq(solution.snippet(helpers.fake_view({ detail = { snippets = {} } })), '')
  eq(solution.snippet({ detail = { snippets = { python3 = 'invalid' } }, lang = 'python3' }), '')
end

T['languages'] = new_set()

T['languages']['puts the active language first'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  local languages = solution.languages(view)
  eq(languages[1], 'python3')
  eq(#languages, 2)
end

T['languages']['respects the configured allow-list'] = function()
  helpers.configure({ languages = { 'golang' } })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  eq(solution.languages(view), { 'golang' })
end

T['languages']['preferred order is honoured'] = function()
  helpers.configure({ languages = { 'golang', 'python3' } })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view({ lang = 'cpp' })
  local languages = solution.languages(view)
  eq(languages, { 'golang', 'python3' })
end

T['prepare'] = new_set()

T['prepare']['loads the starter snippet'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'class Solution:')
  eq(vim.api.nvim_get_option_value('filetype', { buf = view.code_bufnr }), 'python')
  eq(vim.api.nvim_get_option_value('buftype', { buf = view.code_bufnr }), '')
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), false)
end

T['prepare']['prefers an existing draft'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('two-sum', 'python3', 'draft code')
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'draft code')
end

T['prepare']['does not reuse the central panel buffer'] = function()
  local solution = helpers.mod('solution')
  local panel = helpers.mod('ui').panel()
  local view = helpers.fake_view({ detail = helpers.fake_detail({ title_slug = 'panel' }) })
  solution.prepare(view)
  eq(view.code_bufnr ~= panel, true)
  eq(vim.api.nvim_buf_get_name(view.code_bufnr), 'leetcode-ui://question/panel')
end

T['prepare']['uses an empty draft instead of the snippet'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('two-sum', 'python3', '')
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(solution.code(view), '')
end

T['prepare']['recreates an invalid code buffer'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  local old = view.code_bufnr
  vim.api.nvim_buf_delete(old, { force = true })
  solution.prepare(view)
  eq(view.code_bufnr ~= old, true)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
end

T['prepare']['adds non-editable top padding'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(solution.code(view), solution.snippet(view))
  local marks = vim.api.nvim_buf_get_extmarks(view.code_bufnr, solution.padding_namespace, 0, -1, { details = true })
  eq(#marks, 1)
  eq(marks[1][2], 0)
  eq(marks[1][4].virt_lines_above, true)
  eq(#marks[1][4].virt_lines, 1)
end

T['prepare']['reapplies top padding on cursor movement'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  solution.open(view)
  local ui = helpers.mod('ui')
  ui.show(view.code_bufnr, {})
  vim.api.nvim_buf_clear_namespace(view.code_bufnr, solution.padding_namespace, 0, -1)
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = view.code_bufnr })
  local marks = vim.api.nvim_buf_get_extmarks(view.code_bufnr, solution.padding_namespace, 0, -1, { details = true })
  eq(#marks, 1)
  ui.close()
end

T['prepare']['recreates an unloaded buffer from its draft'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = helpers.fake_view()
  solution.prepare(view)
  storage.write_draft('two-sum', 'python3', 'saved draft')
  local original = view.code_bufnr
  vim.cmd(('silent! bunload! %d'):format(original))
  eq(vim.api.nvim_buf_is_loaded(original), false)

  solution.prepare(view)
  eq(view.code_bufnr ~= original, true)
  eq(solution.code(view), 'saved draft')
end

T['prepare']['save_draft skips an unloaded buffer'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = helpers.fake_view()
  solution.prepare(view)
  storage.write_draft('two-sum', 'python3', 'saved draft')
  vim.cmd(('silent! bunload! %d'):format(view.code_bufnr))

  eq(solution.save_draft(view), true)
  eq(storage.read_draft('two-sum', 'python3'), 'saved draft')
end

T['prepare']['clears undo so leaving preserves the loaded draft'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = helpers.fake_view()
  storage.write_draft('two-sum', 'python3', 'saved draft')
  solution.prepare(view)
  solution.open(view)

  vim.api.nvim_buf_call(view.code_bufnr, function() vim.cmd('silent! undo') end)
  eq(solution.code(view), 'saved draft')
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'new draft' })
  vim.api.nvim_exec_autocmds('BufLeave', { buffer = view.code_bufnr })
  eq(storage.read_draft('two-sum', 'python3'), 'new draft')
end

T['prepare']['reuses an existing buffer'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  local first = view.code_bufnr
  solution.prepare(view)
  eq(view.code_bufnr, first)
end

T['open'] = new_set()

T['open']['marks the buffer listed and installs the draft autocmd once'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  solution.open(view)
  eq(vim.api.nvim_get_option_value('buflisted', { buf = view.code_bufnr }), true)
  eq(vim.api.nvim_get_option_value('modifiable', { buf = view.code_bufnr }), true)
  eq(vim.b[view.code_bufnr].leetcode_ui_draft_enabled, true)

  local events = { 'BufLeave', 'BufWriteCmd', 'QuitPre', 'VimLeavePre' }
  for _, event in ipairs(events) do
    eq(#vim.api.nvim_get_autocmds({ event = event, buffer = view.code_bufnr }), 1)
  end

  solution.open(view)
  for _, event in ipairs(events) do
    eq(#vim.api.nvim_get_autocmds({ event = event, buffer = view.code_bufnr }), 1)
  end
end

T['open']['leaving the buffer saves the draft and clears modified'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  solution.open(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'draft', 'code' })
  vim.api.nvim_set_option_value('modified', true, { buf = view.code_bufnr })
  vim.api.nvim_set_current_buf(view.code_bufnr)
  vim.api.nvim_set_current_buf(helpers.mod('buffer').scratch('leetcode-ui://leave-target'))

  eq(storage.read_draft('two-sum', 'python3'), 'draft\ncode')
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), false)
end

T['open']['quit events save the draft and clear modified'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  solution.open(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'quit draft' })
  vim.api.nvim_set_option_value('modified', true, { buf = view.code_bufnr })
  vim.api.nvim_exec_autocmds('QuitPre', { buffer = view.code_bufnr })

  eq(storage.read_draft('two-sum', 'python3'), 'quit draft')
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), false)
end

T['open_with_normal_buftype'] = new_set()

T['open_with_normal_buftype']['rejects writing the solution buffer to another file'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  solution.open(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'code' })
  vim.api.nvim_set_option_value('modified', true, { buf = view.code_bufnr })
  local path = helpers.tmpdir() .. '/solution.py'
  local calls = 0

  local ok, messages = nil, nil
  helpers.with_stub('leetcode-ui.storage', 'write_draft', function()
    calls = calls + 1
    return true
  end, function()
    messages = helpers.capture_notify(function()
      ok = pcall(vim.api.nvim_buf_call, view.code_bufnr, function() vim.cmd('write ' .. vim.fn.fnameescape(path)) end)
    end)
  end)
  eq(ok, false)
  eq(calls, 0)
  eq(vim.fn.filereadable(path), 0)
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), true)
  assert(messages ~= nil)
  eq(helpers.contains(messages[#messages].message, 'Writing the solution buffer to a file is not supported'), true)
end

T['open_with_normal_buftype']['reports draft failures and keeps the buffer modified'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  solution.open(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'code' })
  vim.api.nvim_set_option_value('modified', true, { buf = view.code_bufnr })

  local calls = 0
  local messages = nil
  helpers.with_stub('leetcode-ui.storage', 'write_draft', function()
    calls = calls + 1
    return false
  end, function()
    messages = helpers.capture_notify(function()
      local ok = pcall(vim.api.nvim_buf_call, view.code_bufnr, function() vim.cmd('write') end)
      eq(ok, false)
    end)
  end)
  eq(calls, 1)
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), true)
  assert(messages ~= nil)
  eq(helpers.contains(messages[#messages].message, 'Failed to save the solution draft'), true)
end

T['open_with_normal_buftype']['write saves the draft and clears modified'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = helpers.fake_view()
  solution.prepare(view)
  solution.open(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'draft', 'code' })
  vim.api.nvim_set_option_value('modified', true, { buf = view.code_bufnr })

  vim.api.nvim_buf_call(view.code_bufnr, function() vim.cmd('write') end)

  eq(storage.read_draft('two-sum', 'python3'), 'draft\ncode')
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), false)
end

T['drafts'] = new_set()

T['drafts']['save_draft writes buffer contents'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'hello\nworld')
  solution.save_draft(view)
  eq(storage.read_draft('two-sum', 'python3'), 'hello\nworld')
end

T['drafts']['saving unchanged starter code removes the draft'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), solution.snippet(helpers.fake_view()))
  storage.write_draft('two-sum', 'python3', 'old draft')
  solution.save_draft(view)
  eq(storage.read_draft('two-sum', 'python3'), nil)
end

T['drafts']['save_draft ignores missing buffers'] = function()
  local solution = helpers.mod('solution')
  eq(solution.save_draft(nil), true)
  eq(solution.save_draft({ slug = 'x' }), true)
  eq(solution.save_draft({ slug = 'x', code_bufnr = 999999 }), true)
end

T['code'] = new_set()

T['code']['reads the buffer and tolerates invalid buffers'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'a\nb')
  eq(solution.code(view), 'a\nb')
  eq(solution.code({ code_bufnr = nil }), '')
  eq(solution.code({ code_bufnr = 999999 }), '')
end

T['format'] = new_set()

T['format']['uses LeetCode formatter first'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'def f():\n  pass')
  local requests = 0
  helpers.with_stub('leetcode-ui.net', 'request', function()
    requests = requests + 1
    return { status = 200, body = vim.json.encode({ code = 'def f():\n    pass\n' }) }, nil
  end, function()
    solution.format(view)
    local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
    eq(requests, 1)
    eq(#lines, 2)
    eq(lines[1], 'def f():')
    eq(lines[2], '    pass')
    eq(view.busy, false)
    eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), false)
    eq(storage.read_draft('two-sum', 'python3'), 'def f():\n    pass')
  end)
end

T['format']['reports draft failures after formatting'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'x=1' })
  local messages = nil
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = vim.json.encode({ code = 'x = 1' }) }, nil end,
    function()
      helpers.with_stub('leetcode-ui.storage', 'write_draft', function() return false end, function()
        messages = helpers.capture_notify(function() solution.format(view) end)
      end)
    end
  )

  eq(solution.code(view), 'x = 1')
  assert(messages ~= nil)
  eq(helpers.contains(messages[#messages].message, 'Failed to save the formatted code'), true)
  eq(vim.api.nvim_get_option_value('modified', { buf = view.code_bufnr }), true)
  eq(view.busy, false)
end

T['format']['accepts plain-text LeetCode formatter responses'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = 'formatted', headers = { ['Content-Type'] = 'text/plain' } }, nil end,
    function()
      solution.format(view)
      eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'formatted')
    end
  )
end

T['format']['accepts alternate formatter JSON fields'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = vim.json.encode({ formattedCode = 'formatted' }) }, nil end,
    function()
      solution.format(view)
      eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'formatted')
    end
  )
end

T['format']['ignores error and HTML responses and sends the current code'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  local requests = {}
  helpers.with_field(vim.lsp, 'get_clients', function() return {} end, function()
    helpers.with_stub(
      'leetcode-ui.async',
      'system',
      function() return { code = 1, stdout = '', stderr = '' } end,
      function()
        helpers.with_stub('leetcode-ui.net', 'request', function(opts)
          table.insert(requests, opts)
          if #requests == 1 then return { status = 500, body = '<html>down</html>' }, nil end
          return { status = 200, body = '<html>down</html>' }, nil
        end, function()
          solution.format(view)
          solution.format(view)
        end)
      end
    )
  end)

  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'x')
  eq(view.busy, false)
  eq(#requests, 2)
  eq(vim.json.decode(requests[1].body).code, 'x')
end

T['format']['uses the canonical remote formatter for language aliases'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python' }), 'x')
  local urls, retries = {}, nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    table.insert(urls, opts.url)
    retries = opts.retries
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function() solution.format(view) end)
  eq(urls[1], 'https://lsp-py3.leetcode.com/format')
  eq(retries, 0)
end

T['format']['uses the configured domain for remote formatting'] = function()
  helpers.configure({ url = 'leetcode.cn' })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python' }), 'x')
  local url = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    url = opts.url
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function() solution.format(view) end)
  eq(url, 'https://lsp-py3.leetcode.cn/format')
end

T['format']['uses the configured formatter for code'] = function()
  local seen = nil
  helpers.configure({
    formatter = function(text, filetype)
      seen = filetype
      if filetype == 'kotlin' then return text .. '\n// ' .. filetype end
      return nil
    end,
  })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  solution.format(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], '// kotlin')
  eq(seen, 'kotlin')
end

T['format']['trims trailing newlines from formatter output'] = function()
  helpers.configure({
    formatter = function(text) return text .. '\n' end,
  })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  solution.format(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false), { 'x=1' })
end

T['format']['does not call the API for unsupported languages'] = function()
  helpers.configure({ notifications = true, formatter = function() return nil end })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  local requests = 0
  helpers.with_stub('leetcode-ui.net', 'request', function()
    requests = requests + 1
    return nil, 'offline'
  end, function()
    local messages = helpers.capture_notify(function() solution.format(view) end)
    eq(requests, 0)
    eq(helpers.contains(messages[#messages].message, 'No formatter is available'), true)
  end)
end

T['format']['uses the user formatter before the API for supported languages'] = function()
  helpers.configure({ formatter = function() return 'user formatted' end })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x=1')
  local requests = 0
  helpers.with_stub('leetcode-ui.net', 'request', function()
    requests = requests + 1
    return nil, 'offline'
  end, function() solution.format(view) end)
  eq(requests, 0)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'user formatted')
end

T['format']['falls back to the LeetCode API when the formatter returns nil'] = function()
  helpers.configure({ formatter = function() return nil end })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x=1')
  local remote_url = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    remote_url = opts.url
    return { status = 200, body = '{"code":"remote formatted"}' }, nil
  end, function() solution.format(view) end)
  eq(helpers.contains(remote_url, 'lsp-py3'), true)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'remote formatted')
end

T['format']['accepts JSON-looking plain text with a text content type'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = '123', headers = { ['Content-Type'] = 'Text/Plain' } }, nil end,
    function() solution.format(view) end
  )
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], '123')
end

T['format']['rejects plain-text responses without a text content type'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = 'Too many requests' }, nil end,
    function()
      local messages = helpers.capture_notify(function() solution.format(view) end)
      eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'x')
      eq(helpers.contains(messages[#messages].message, 'Formatting failed'), true)
    end
  )
end

T['format']['normalizes an uppercase WWW domain'] = function()
  local config = helpers.mod('config')
  local url = config.config.url
  MiniTest.finally(function() config.config.url = url end)
  config.config.url = 'WWW.leetcode.com'
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x')
  local endpoint = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    endpoint = opts.url
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function() solution.format(view) end)
  eq(endpoint, 'https://lsp-py3.leetcode.com/format')
end

T['format']['reports API failures for supported languages'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x')
  helpers.with_stub('leetcode-ui.net', 'request', function() return nil, 'offline' end, function()
    local messages = helpers.capture_notify(function() solution.format(view) end)
    eq(helpers.contains(messages[#messages].message, 'Formatting failed'), true)
  end)
end

T['format']['uses the expected remote endpoint for every supported language'] = function()
  local expected = { c = 'c', cpp = 'cpp', golang = 'go', java = 'java', python3 = 'py3', swift = 'swift' }
  local solution = helpers.mod('solution')
  for lang, endpoint in pairs(expected) do
    local view = with_code_buffer(helpers.fake_view({ lang = lang }), 'x')
    local url = nil
    helpers.with_stub('leetcode-ui.net', 'request', function(opts)
      url = opts.url
      return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
    end, function() solution.format(view) end)
    eq(helpers.contains(url, 'lsp-' .. endpoint), true)
  end
end

T['format']['sends buffer indentation options to the API'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), 'x=1')
  vim.api.nvim_set_option_value('shiftwidth', 2, { buf = view.code_bufnr })
  vim.api.nvim_set_option_value('expandtab', false, { buf = view.code_bufnr })
  local body = nil
  helpers.with_stub('leetcode-ui.net', 'request', function(opts)
    body = vim.json.decode(opts.body)
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function() solution.format(view) end)
  assert(body ~= nil)
  eq(body.tabSize, 2)
  eq(body.insertSpaces, false)
end

T['format']['does nothing for empty code'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'python3' }), '   \n')
  local requests = 0
  helpers.with_stub('leetcode-ui.net', 'request', function()
    requests = requests + 1
    return nil, 'offline'
  end, function() solution.format(view) end)
  eq(requests, 0)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], '   ')
end

T['format']['rejects formatter errors and reports when no formatter exists'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  helpers.with_field(vim.lsp, 'get_clients', function() return {} end, function()
    helpers.with_stub('leetcode-ui.net', 'request', function() return nil, 'offline' end, function()
      local messages = helpers.capture_notify(function() solution.format(view) end)
      eq(helpers.contains(messages[#messages].message, 'No formatter is available'), true)
      eq(messages[#messages].level, vim.log.levels.WARN)
      eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'x=1')
      eq(view.busy, false)
    end)

    helpers.with_stub(
      'leetcode-ui.net',
      'request',
      function() return { status = 200, body = '{"error":"format failed"}' }, nil end,
      function()
        local messages = helpers.capture_notify(function() solution.format(view) end)
        eq(helpers.contains(messages[#messages].message, 'No formatter is available'), true)
        eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'x=1')
        eq(view.busy, false)
      end
    )
  end)
end

T['format']['does not report a save failure when nothing was formatted'] = function()
  helpers.configure({ notifications = true })
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  helpers.with_field(vim.lsp, 'get_clients', function() return {} end, function()
    helpers.with_stub('leetcode-ui.net', 'request', function() return nil, 'offline' end, function()
      local saves = 0
      helpers.with_stub('leetcode-ui.storage', 'write_draft', function()
        saves = saves + 1
        return false
      end, function()
        local messages = helpers.capture_notify(function() solution.format(view) end)
        eq(helpers.contains(messages[#messages].message, 'No formatter is available'), true)
        for _, message in ipairs(messages) do
          eq(helpers.contains(message.message, 'Failed to save'), false)
        end
        eq(saves, 0)
      end)
    end)
  end)
end

T['format']['discards results when the buffer is replaced while waiting'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'original')

  helpers.with_stub('leetcode-ui.net', 'request', function()
    coroutine.yield()
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function()
    helpers.with_field(vim.api, 'nvim_buf_get_changedtick', function() return 10 end, function()
      local worker = coroutine.create(function() solution.format(view) end)
      eq(coroutine.resume(worker), true)

      storage.write_draft(view.slug, view.lang, 'new draft')
      vim.api.nvim_buf_delete(view.code_bufnr, { force = true })
      view.code_bufnr = nil
      solution.prepare(view)
      eq(coroutine.resume(worker), true)
    end)
  end)

  eq(solution.code(view), 'new draft')
  eq(helpers.mod('storage').read_draft(view.slug, view.lang), 'new draft')
  eq(view.busy, false)
end

T['format']['does not rewrite or save unchanged formatter output'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x=1')
  local saves = 0
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = vim.json.encode({ code = 'x=1' }) }, nil end,
    function()
      helpers.with_stub('leetcode-ui.storage', 'write_draft', function()
        saves = saves + 1
        return true
      end, function() solution.format(view) end)
    end
  )
  eq(solution.code(view), 'x=1')
  eq(saves, 0)
end

T['format']['stops when the view closes during formatting'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'code')

  helpers.with_stub('leetcode-ui.net', 'request', function()
    coroutine.yield()
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function()
    local worker = coroutine.create(function() solution.format(view) end)
    eq(coroutine.resume(worker), true)
    view.closed = true
    helpers.mod('buffer').maybe_delete(view.code_bufnr)
    eq(coroutine.resume(worker), true)
  end)

  eq(view.busy, false)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), false)
end

T['format']['discards results when the buffer changes while waiting'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'original')

  helpers.with_stub('leetcode-ui.net', 'request', function()
    coroutine.yield()
    return { status = 200, body = vim.json.encode({ code = 'formatted' }) }, nil
  end, function()
    local worker = coroutine.create(function() solution.format(view) end)
    eq(coroutine.resume(worker), true)
    vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'edited' })
    eq(coroutine.resume(worker), true)
  end)

  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'edited')
  eq(view.busy, false)
end

T['format']['ignores busy views and invalid code buffers'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  view.busy = true
  solution.format(view)
  eq(view.busy, true)

  view.busy = false
  view.code_bufnr = nil
  eq(solution.format(view), nil)
  eq(solution.format(nil), nil)

  view.code_bufnr = 999999
  eq(solution.format(view), nil)
  eq(view.busy, false)
end

T['reset'] = new_set()

T['reset']['keeps the buffer when the draft cannot be removed'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'junk')
  local ok
  helpers.with_stub(
    'leetcode-ui.storage',
    'write_draft',
    function() return false end,
    function() ok = solution.reset(view) end
  )
  eq(ok, false)
  eq(solution.code(view), 'junk')
end

T['reset']['restores the snippet and removes the draft'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'junk')
  storage.write_draft('two-sum', 'python3', 'junk')
  solution.reset(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'class Solution:')
  eq(storage.read_draft('two-sum', 'python3'), nil)
  eq(solution.reset({ code_bufnr = 999999 }), false)
end

T['reset']['works with a non-modifiable buffer'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'typed code')
  vim.api.nvim_set_option_value('modifiable', false, { buf = view.code_bufnr })
  eq(solution.reset(view), true)
  eq(solution.code(view), solution.snippet(view))
  eq(vim.api.nvim_get_option_value('modifiable', { buf = view.code_bufnr }), false)
end

T['reset']['clears undo history'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'typed code')
  solution.reset(view)
  vim.api.nvim_buf_call(view.code_bufnr, function() vim.cmd('silent! undo') end)
  eq(solution.code(view), solution.snippet(view))
end

T['switch_language'] = new_set()

T['switch_language']['switches, saves the old draft, and loads the new one'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'my python')
  storage.write_draft('two-sum', 'golang', 'my go')

  solution.switch_language(view, 'golang')
  eq(view.lang, 'golang')
  eq(vim.api.nvim_get_option_value('filetype', { buf = view.code_bufnr }), 'go')
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'my go')
  eq(storage.read_draft('two-sum', 'python3'), 'my python')
end

T['switch_language']['normalizes language aliases'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'golang' }), 'go code')
  eq(solution.switch_language(view, 'python'), true)
  eq(view.lang, 'python3')
  eq(vim.api.nvim_get_option_value('filetype', { buf = view.code_bufnr }), 'python')
end

T['switch_language']['does not switch when the current draft cannot be saved'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'edited')
  local ok
  helpers.with_stub(
    'leetcode-ui.storage',
    'write_draft',
    function() return false end,
    function() ok = solution.switch_language(view, 'golang') end
  )
  eq(ok, false)
  eq(view.lang, 'python3')
  eq(solution.code(view), 'edited')
end

T['switch_language']['works with a non-modifiable buffer'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'python code')
  vim.api.nvim_set_option_value('modifiable', false, { buf = view.code_bufnr })
  eq(solution.switch_language(view, 'golang'), true)
  eq(view.lang, 'golang')
  eq(vim.api.nvim_get_option_value('modifiable', { buf = view.code_bufnr }), false)
end

T['switch_language']['clears undo history'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'python code')
  storage.write_draft('two-sum', 'golang', 'go code')

  solution.switch_language(view, 'golang')
  vim.api.nvim_buf_call(view.code_bufnr, function() vim.cmd('silent! undo') end)
  eq(solution.code(view), 'go code')
end

T['switch_language']['removes an unchanged draft from the old language'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = helpers.fake_view()
  view = with_code_buffer(view, solution.snippet(view))
  storage.write_draft('two-sum', 'python3', 'old draft')

  solution.switch_language(view, 'golang')
  eq(storage.read_draft('two-sum', 'python3'), nil)
end

T['switch_language']['ignores the active or unknown languages'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  solution.switch_language(view, 'python3')
  eq(view.lang, 'python3')
  solution.switch_language(view, 'java')
  eq(view.lang, 'python3')

  view.busy = true
  solution.switch_language(view, 'golang')
  eq(view.lang, 'python3')
  view.busy = false

  local without_buffer = helpers.fake_view()
  eq(solution.switch_language(without_buffer, 'golang'), false)
  eq(without_buffer.lang, 'python3')
  eq(solution.switch_language(nil, 'golang'), false)
end

return T
