-- Tests for leetcode-ui.solution.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['filetype'] = new_set()

T['filetype']['maps slugs'] = function()
  local solution = helpers.mod('solution')
  eq(solution.filetype('python3'), 'python')
  eq(solution.filetype('golang'), 'go')
  eq(solution.filetype('javascript'), 'javascript')
  eq(solution.filetype('cpp'), 'cpp')
  eq(solution.filetype('unknown-slug'), 'unknown-slug')
end

T['snippet'] = new_set()

T['snippet']['returns starter code'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  eq(type(solution.snippet(view)), 'string')
  eq(helpers.contains(solution.snippet(view), 'twoSum'), true)
end

T['snippet']['empty when missing'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view({ detail = { snippets = {} } })
  eq(solution.snippet(view), '')
end

T['languages'] = new_set()

T['languages']['ordered with active first'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  local langs = solution.languages(view)
  eq(type(langs), 'table')
  eq(#langs >= 1, true)
  eq(langs[1], view.lang)
end

T['format'] = new_set()

T['format']['applies leetcode formatted code'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://fmt', { ft = 'python' })
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'def f():', '  pass' })
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function(_opts) return { status = 200, body = vim.json.encode({ code = 'def f():\\n    pass\\n' }) }, nil end,
    function()
      solution.format(view)
      local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
      eq(lines[1], 'def f():')
      eq(lines[2], '    pass')
    end
  )
end

T['format']['falls back gracefully on failure'] = function()
  local solution = helpers.mod('solution')
  local view = helpers.fake_view()
  view.lang = 'kotlin'
  local buffer = helpers.mod('buffer')
  view.code_bufnr = buffer.scratch('leetcode-ui://fmt2', { ft = 'kotlin' })
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, { 'x=1' })
  helpers.with_stub(
    'leetcode-ui.net',
    'request',
    function(_opts) return { status = 403, body = '' }, nil end,
    function()
      local ok = pcall(solution.format, view)
      eq(ok, true)
      local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
      eq(lines[1], 'x=1')
    end
  )
end

return T
