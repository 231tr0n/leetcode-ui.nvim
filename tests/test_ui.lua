-- Tests for leetcode-ui.ui central window.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
    post_case = function() helpers.reset_ui() end,
  },
})

T['window'] = new_set()

T['window']['ensure opens one reusable window'] = function()
  local ui = helpers.mod('ui')
  eq(ui.is_open(), false)
  local first = ui.ensure()
  local second = ui.ensure()
  eq(first, second)
  eq(ui.is_open(), true)
  eq(vim.api.nvim_win_get_buf(first), ui.panel())
end

T['window']['panel is a read-only scratch buffer'] = function()
  local ui = helpers.mod('ui')
  local panel = ui.panel()
  eq(vim.api.nvim_get_option_value('buftype', { buf = panel }), 'nofile')
  eq(vim.api.nvim_get_option_value('modifiable', { buf = panel }), false)
  eq(vim.api.nvim_get_option_value('buflisted', { buf = panel }), false)
end

T['render'] = new_set()

T['render']['renders spans and keeps the panel read-only'] = function()
  local ui = helpers.mod('ui')
  local winid = ui.render({
    { { text = 'Title', hl = 'LeetCodeTitle' } },
    { { text = 'body', hl = 'LeetCodeDim' } },
  }, { number = false, wrap = true })
  local panel = ui.panel()
  local lines = vim.api.nvim_buf_get_lines(panel, 0, -1, false)
  eq(lines[1], 'Title')
  eq(lines[2], 'body')
  eq(vim.api.nvim_win_get_buf(winid), panel)
  eq(vim.api.nvim_get_option_value('modifiable', { buf = panel }), false)
  eq(vim.api.nvim_get_option_value('wrap', { win = winid }), true)
  eq(vim.api.nvim_get_option_value('number', { win = winid }), false)
end

T['render']['pad_top adds exactly one virtual line above the content'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  local bufnr = buffer.scratch('leetcode-ui://pad-top')
  buffer.spans_write(bufnr, { { { text = 'content' } } })

  ui.show(bufnr, { pad_top = true })
  ui.show(bufnr, { pad_top = true })

  local padded = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    if mark[4].virt_lines ~= nil then padded = padded + 1 end
  end
  eq(padded, 1)
end

T['render']['does not pad by default'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  local bufnr = buffer.scratch('leetcode-ui://no-pad')
  buffer.spans_write(bufnr, { { { text = 'content' } } })

  ui.show(bufnr)
  local padded = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    if mark[4].virt_lines ~= nil then padded = padded + 1 end
  end
  eq(padded, 0)
end

T['render']['shows another buffer in the same window'] = function()
  local ui = helpers.mod('ui')
  local buffer = helpers.mod('buffer')
  local code = buffer.scratch('leetcode-ui://ui-code', { ft = 'python' })
  local window = ui.show(code, { number = true, wrap = false })
  eq(vim.api.nvim_win_get_buf(window), code)
  eq(vim.api.nvim_win_get_buf(ui.ensure()), code)
  eq(vim.api.nvim_get_option_value('number', { win = window }), true)
  eq(vim.api.nvim_get_option_value('wrap', { win = window }), false)
end

T['winbar'] = new_set()

T['winbar']['sets the winbar while open'] = function()
  local ui = helpers.mod('ui')
  ui.set_winbar(' no window ')
  eq(pcall(ui.set_winbar, 'ignored'), true)
  ui.ensure()
  ui.set_winbar(' LeetCode ')
  eq(vim.api.nvim_get_option_value('winbar', { win = ui.state.winid }), ' LeetCode ')
end

T['close'] = new_set()

T['close']['closes and can reopen'] = function()
  local ui = helpers.mod('ui')
  local first = ui.ensure()
  ui.close()
  eq(ui.is_open(), false)
  eq(vim.api.nvim_win_is_valid(first), false)

  local second = ui.ensure()
  eq(ui.is_open(), true)
  eq(second ~= first, true)
end

return T
