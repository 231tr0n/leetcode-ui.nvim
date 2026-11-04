--- *leetcode-ui-ui* Central UI window
---
--- All plugin views (question tabs, statistics, and command help) are shown
--- in one central floating window. Read-only views use a shared scratch
--- buffer; the code tab swaps in the editable solution buffer inside the same
--- window.
---@tag LeetCodeUI
---@toc_entry Central UI

local LeetCodeUI = {}

local buffer = require('leetcode-ui.buffer')
local config = require('leetcode-ui.config')

-- Helper data =======================================================================================================

LeetCodeUI.state = {
  bufnr = nil,
  close_autocmd = nil,
  cursor_hidden = false,
  fold_bufnr = nil,
  fold_signature = nil,
  fold_winid = nil,
  owner = nil,
  owner_serial = 0,
  winid = nil,
}

local saved_guicursor = nil
local cursor_is_hidden = false
local cursor_autocmd = nil
local resize_autocmd = nil

local function fold_signature(folds)
  local parts = {}
  for _, fold in ipairs(folds or {}) do
    table.insert(parts, ('%d:%d'):format(fold.start_line, fold.end_line))
  end
  return table.concat(parts, ',')
end

local function restore_cursor()
  if not cursor_is_hidden then return end
  if saved_guicursor ~= nil then vim.o.guicursor = saved_guicursor end
  saved_guicursor = nil
  cursor_is_hidden = false
end

local function cmdline_cursor(value)
  local parts = {}
  for part in value:gmatch('[^,]+') do
    if part:match('^c[ir]?:') ~= nil then table.insert(parts, part) end
  end
  if #parts == 0 then return 'c:ver25,ci:ver25,cr:ver25' end
  return table.concat(parts, ',')
end

local function hide_cursor()
  if cursor_is_hidden then return end
  saved_guicursor = vim.o.guicursor
  vim.o.guicursor = 'a:LeetCodeCursor,' .. cmdline_cursor(saved_guicursor)
  cursor_is_hidden = true
end

local function update_cursor()
  local in_central = LeetCodeUI.is_open() and vim.api.nvim_get_current_win() == LeetCodeUI.state.winid
  if in_central and LeetCodeUI.state.cursor_hidden then
    hide_cursor()
  else
    restore_cursor()
  end
end

local function ensure_cursor_autocmd()
  if cursor_autocmd ~= nil then return end
  cursor_autocmd = vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, { callback = update_cursor })
end

local function apply_folds(winid, folds)
  vim.api.nvim_win_call(winid, function()
    vim.cmd('silent! normal! zE')
    for _, fold in ipairs(folds or {}) do
      if fold.start_line <= fold.end_line then vim.cmd(('%d,%dfold'):format(fold.start_line, fold.end_line)) end
    end
  end)
end

local function resize_window()
  if not LeetCodeUI.is_open() then return end
  local float = buffer.float_config({
    width = config.config.float_width,
    height = config.config.float_height,
    border = config.config.float_border,
  })
  pcall(vim.api.nvim_win_set_config, LeetCodeUI.state.winid, {
    relative = 'editor',
    row = float.row,
    col = float.col,
    width = float.width,
    height = float.height,
  })
end

local function winhighlight(cursorline_hl, normal_hl)
  local groups = {
    'Normal:' .. (normal_hl or 'LeetCodeNormalFloat'),
    'FloatBorder:LeetCodeFloatBorder',
    'WinBar:LeetCodeWinBar',
    'WinBarNC:LeetCodeWinBarNC',
  }
  if cursorline_hl ~= nil then table.insert(groups, 'CursorLine:' .. cursorline_hl) end
  return table.concat(groups, ',')
end

-- Helper functionality =============================================================================================

--- Whether the central window is currently open.
---
---@return boolean
LeetCodeUI.is_open = function()
  return LeetCodeUI.state.winid ~= nil and vim.api.nvim_win_is_valid(LeetCodeUI.state.winid)
end

--- Mark the start of a new central-window view.
---
--- In-flight question loads compare the serial captured when they start, so a
--- newer statistics or help view is not replaced by older results.
---
---@param owner string
LeetCodeUI.claim = function(owner)
  LeetCodeUI.state.owner = owner
  LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1
end

--- Record a navigation without changing view ownership.
---
--- Used by actions that fetch before rendering so earlier in-flight requests
--- can detect that newer navigation happened.
LeetCodeUI.bump = function() LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1 end

--- Get the shared read-only scratch buffer, creating it if needed.
---
---@return number bufnr
LeetCodeUI.panel = function()
  local bufnr = LeetCodeUI.state.bufnr
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = buffer.scratch('leetcode-ui://panel', { ft = 'txt', modifiable = false })
    LeetCodeUI.state.bufnr = bufnr
  end
  return bufnr
end

--- Ensure the central window is open and return its id.
---
---@param focus boolean|nil Whether to focus a newly opened window.
---@return number winid
LeetCodeUI.ensure = function(focus)
  if LeetCodeUI.is_open() then return LeetCodeUI.state.winid end

  local winid = buffer.open_float(LeetCodeUI.panel(), {
    width = config.config.float_width,
    height = config.config.float_height,
    border = config.config.float_border,
    focus = focus ~= false,
  })

  LeetCodeUI.state.winid = winid
  LeetCodeUI.state.close_autocmd = vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(winid),
    once = true,
    callback = function()
      local owner = LeetCodeUI.state.owner
      LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1
      LeetCodeUI.state.close_autocmd = nil
      LeetCodeUI.state.winid = nil
      LeetCodeUI.state.cursor_hidden = false
      LeetCodeUI.state.owner = nil
      LeetCodeUI.state.fold_winid, LeetCodeUI.state.fold_bufnr, LeetCodeUI.state.fold_signature = nil, nil, nil
      restore_cursor()

      if owner == 'question' then
        local question = require('leetcode-ui.question')
        local view = question.active
        if view ~= nil then question.close(view) end
      end
    end,
  })
  ensure_cursor_autocmd()
  if resize_autocmd == nil then
    resize_autocmd = vim.api.nvim_create_autocmd('VimResized', { callback = resize_window })
  end
  return winid
end

--- Show a buffer in the central window.
---
---@param bufnr number
---@param opts table|nil Options: `number`, `wrap`, `cursorline`,
--- `cursorline_hl`, `normal_hl`, `topfill`, `hide_cursor`, `signcolumn`,
--- `foldenable`, `foldmethod`, `foldcolumn`, `statuscolumn`, `folds`,
--- `focus`, and `owner` (logical view name stored for stale-render checks).
---@return number winid
LeetCodeUI.show = function(bufnr, opts)
  opts = opts or {}
  local winid = LeetCodeUI.ensure(opts.focus ~= false)

  local previous_buf = vim.api.nvim_win_get_buf(winid)
  local current_foldmethod = vim.api.nvim_get_option_value('foldmethod', { win = winid })
  if previous_buf ~= bufnr then
    vim.b[previous_buf].leetcode_ui_foldmethod = current_foldmethod
    vim.api.nvim_win_set_buf(winid, bufnr)
  end
  if opts.focus ~= false then vim.api.nvim_set_current_win(winid) end
  if opts.owner ~= nil then LeetCodeUI.state.owner = opts.owner end

  vim.api.nvim_set_option_value('number', opts.number == true, { win = winid })
  vim.api.nvim_set_option_value('wrap', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('linebreak', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('breakindent', opts.wrap ~= false, { win = winid })
  vim.api.nvim_set_option_value('cursorline', opts.cursorline == true, { win = winid })
  vim.api.nvim_set_option_value('winhighlight', winhighlight(opts.cursorline_hl, opts.normal_hl), { win = winid })
  vim.api.nvim_set_option_value('signcolumn', opts.signcolumn or 'no', { win = winid })
  vim.api.nvim_set_option_value('foldenable', opts.foldenable == true, { win = winid })
  local foldmethod = opts.foldmethod
  if foldmethod == nil and previous_buf ~= bufnr then
    foldmethod = vim.b[bufnr].leetcode_ui_foldmethod or vim.go.foldmethod
  end
  if foldmethod ~= nil and foldmethod ~= current_foldmethod then
    vim.api.nvim_set_option_value('foldmethod', foldmethod, { win = winid })
    vim.b[bufnr].leetcode_ui_foldmethod = foldmethod
  end
  vim.api.nvim_set_option_value('foldcolumn', tostring(opts.foldcolumn or 0), { win = winid })
  vim.api.nvim_set_option_value('statuscolumn', opts.statuscolumn or '', { win = winid })
  if opts.folds ~= nil then
    local signature = fold_signature(opts.folds)
    local state = LeetCodeUI.state
    if state.fold_winid ~= winid or state.fold_bufnr ~= bufnr or state.fold_signature ~= signature then
      apply_folds(winid, opts.folds)
      state.fold_winid, state.fold_bufnr, state.fold_signature = winid, bufnr, signature
    end
  else
    LeetCodeUI.state.fold_winid, LeetCodeUI.state.fold_bufnr, LeetCodeUI.state.fold_signature = nil, nil, nil
  end

  vim.api.nvim_win_call(winid, function()
    local view = vim.fn.winsaveview()
    if view.topfill ~= (opts.topfill or 0) then
      view.topfill = opts.topfill or 0
      vim.fn.winrestview(view)
    end
  end)

  LeetCodeUI.state.cursor_hidden = opts.hide_cursor == true
  update_cursor()
  return winid
end

--- Render read-only span lines in the central window.
---
---@param lines table Array of lines, each an array of `{ text, hl }` spans.
---@param opts table|nil All |LeetCodeUI.show()| options plus `pad_top`.
---@return number winid
LeetCodeUI.render = function(lines, opts)
  opts = opts or {}
  if opts.pad_top == true then
    lines = vim.list_extend({ {} }, lines)

    local folds = {}
    for _, fold in ipairs(opts.folds or {}) do
      table.insert(folds, { start_line = fold.start_line + 1, end_line = fold.end_line + 1 })
    end
    opts = vim.tbl_extend('force', {}, opts, { folds = folds })
  end

  local previous_view = nil
  if LeetCodeUI.is_open() then previous_view = vim.api.nvim_win_call(LeetCodeUI.state.winid, vim.fn.winsaveview) end

  local render_opts = vim.tbl_extend('force', {
    cursorline = true,
    cursorline_hl = 'LeetCodeCursorLine',
    hide_cursor = true,
    folds = {},
  }, opts)

  local bufnr = LeetCodeUI.panel()
  buffer.spans_write(bufnr, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  local winid = LeetCodeUI.show(bufnr, render_opts)
  LeetCodeUI.set_winbar('')

  if render_opts.focus == false and previous_view ~= nil then
    pcall(vim.api.nvim_win_call, winid, function() vim.fn.winrestview(previous_view) end)
  else
    local first_content = render_opts.pad_top == true and 2 or 1
    if vim.api.nvim_buf_line_count(bufnr) >= first_content then
      pcall(vim.api.nvim_win_set_cursor, winid, { first_content, 0 })
    end
  end
  return winid
end

--- Set the central window's winbar.
---
---@param text string
LeetCodeUI.set_winbar = function(text)
  if not LeetCodeUI.is_open() then return end
  vim.api.nvim_set_option_value('winbar', text or '', { win = LeetCodeUI.state.winid })
end

--- Close the central window.
LeetCodeUI.close = function()
  LeetCodeUI.state.owner_serial = LeetCodeUI.state.owner_serial + 1
  if LeetCodeUI.state.close_autocmd ~= nil then
    pcall(vim.api.nvim_del_autocmd, LeetCodeUI.state.close_autocmd)
    LeetCodeUI.state.close_autocmd = nil
  end
  if LeetCodeUI.is_open() then pcall(vim.api.nvim_win_close, LeetCodeUI.state.winid, false) end
  LeetCodeUI.state.cursor_hidden = false
  LeetCodeUI.state.owner = nil
  LeetCodeUI.state.fold_winid, LeetCodeUI.state.fold_bufnr, LeetCodeUI.state.fold_signature = nil, nil, nil
  LeetCodeUI.state.winid = nil
  restore_cursor()
end

return LeetCodeUI
