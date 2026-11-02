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

T['snippet'] = new_set()

T['snippet']['returns starter code or an empty string'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  eq(helpers.contains(solution.snippet(view), 'twoSum'), true)
  eq(solution.snippet(helpers.fake_view({ detail = { snippets = {} } })), '')
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
  local config = require('leetcode-ui.config')
  config.setup({ languages = { 'golang' } })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  eq(solution.languages(view), { 'golang' })
end

T['languages']['preferred order is honoured'] = function()
  local config = require('leetcode-ui.config')
  config.setup({ languages = { 'golang', 'python3' } })
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  local languages = solution.languages(view)
  eq(languages[1], 'python3')
  eq(languages[2], 'golang')
end

T['prepare'] = new_set()

T['prepare']['loads the starter snippet'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(vim.api.nvim_buf_is_valid(view.code_bufnr), true)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'class Solution:')
  eq(vim.api.nvim_get_option_value('filetype', { buf = view.code_bufnr }), 'python')
end

T['prepare']['prefers an existing draft'] = function()
  local storage = helpers.mod('storage')
  storage.write_draft('two-sum', 'python3', 'draft code')
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'draft code')
end

T['prepare']['strips the visual top padding from code'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  solution.prepare(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, 1, false)[1], '')
  eq(solution.code(view), solution.snippet(view))
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
  eq(vim.b[view.code_bufnr].lc_draft_enabled, true)

  local first = #vim.api.nvim_get_autocmds({ buffer = view.code_bufnr })
  solution.open(view)
  local second = #vim.api.nvim_get_autocmds({ buffer = view.code_bufnr })
  eq(second, first)
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
  eq(pcall(solution.save_draft, nil), true)
  eq(pcall(solution.save_draft, { slug = 'x' }), true)
  eq(pcall(solution.save_draft, { slug = 'x', code_bufnr = 999999 }), true)
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
  local view = with_code_buffer(helpers.fake_view(), 'def f():\n  pass')
  local original_cli = solution.cli_formatters.python3
  solution.cli_formatters.python3 = { 'printf', 'cli fallback' }
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = vim.json.encode({ code = 'def f():\n    pass\n' }) }, nil end,
    function()
      solution.format(view)
      local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
      eq(lines[2], 'def f():')
      eq(lines[3], '    pass')
      eq(view.busy, false)
    end
  )
  solution.cli_formatters.python3 = original_cli
end

T['format']['accepts plain-text LeetCode formatter responses'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return { status = 200, body = 'formatted' }, nil end,
    function()
      solution.format(view)
      eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'formatted')
    end
  )
end

T['format']['falls back to a CLI formatter'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  solution.cli_formatters.kotlin = { 'printf', 'formatted' }
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return nil, 'offline' end,
    function() solution.format(view) end
  )
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'formatted')
  solution.cli_formatters.kotlin = nil
end

T['format']['falls back to LSP'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  local original_clients = vim.lsp.get_clients
  local original_format = vim.lsp.buf.format
  vim.lsp.get_clients = function() return { {} } end
  vim.lsp.buf.format = function() vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'lsp formatted' }) end
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function() return nil, 'offline' end,
    function() solution.format(view) end
  )
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'lsp formatted')
  vim.lsp.get_clients = original_clients
  vim.lsp.buf.format = original_format
end

T['format']['reports when no formatter exists'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view({ lang = 'kotlin' }), 'x=1')
  local original_clients = vim.lsp.get_clients
  vim.lsp.get_clients = function() return {} end
  helpers.with_stub('leetcode-ui.net', 'request', function() return nil, 'offline' end, function()
    local ok = pcall(solution.format, view)
    eq(ok, true)
    eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[1], 'x=1')
    eq(view.busy, false)
  end)
  vim.lsp.get_clients = original_clients
end

T['format']['ignores busy views and invalid code buffers'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  view.busy = true
  solution.format(view)
  eq(view.busy, true)

  view.busy = false
  view.code_bufnr = nil
  eq(pcall(solution.format, view), true)
  eq(pcall(solution.format, nil), true)
end

T['reset'] = new_set()

T['reset']['restores the snippet and removes the draft'] = function()
  local solution = helpers.mod('solution')
  local storage = helpers.mod('storage')
  local view = with_code_buffer(helpers.fake_view(), 'junk')
  storage.write_draft('two-sum', 'python3', 'junk')
  solution.reset(view)
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'class Solution:')
  eq(storage.read_draft('two-sum', 'python3'), nil)
  eq(pcall(solution.reset, { code_bufnr = 999999 }), true)
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
  eq(vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)[2], 'my go')
  eq(storage.read_draft('two-sum', 'python3'), 'my python')
end

T['switch_language']['ignores the active or unknown languages'] = function()
  local solution = helpers.mod('solution')
  local view = with_code_buffer(helpers.fake_view(), 'x')
  solution.switch_language(view, 'python3')
  eq(view.lang, 'python3')
  solution.switch_language(view, 'java')
  eq(view.lang, 'python3')
  eq(pcall(solution.switch_language, nil, 'golang'), true)
end

return T
