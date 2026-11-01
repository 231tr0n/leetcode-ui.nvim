-- Tests for leetcode-ui.picker helpers.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['format_entry'] = new_set()

T['format_entry']['includes id and title'] = function()
  local picker = helpers.mod('picker')
  local entry = { frontend_id = '1', title = 'Two Sum', difficulty = 'Easy', is_paid_only = false }
  local line = picker.format_entry(entry)
  eq(type(line), 'string')
  eq(helpers.contains(line, 'Two Sum'), true)
  eq(helpers.contains(line, '1'), true)
end

T['format_entry']['marks premium'] = function()
  local picker = helpers.mod('picker')
  local entry = { frontend_id = '123', title = 'Premium Problem', difficulty = 'Hard', is_paid_only = true }
  local line = picker.format_entry(entry)
  eq(type(line), 'string')
  eq(#line > 0, true)
end

T['format_entry']['marks status icons'] = function()
  local picker = helpers.mod('picker')
  local entry = { frontend_id = '1', title = 'X', difficulty = 'Easy', is_paid_only = false, status = 'solved' }
  local line = picker.format_entry(entry)
  eq(type(line), 'string')
end

return T
