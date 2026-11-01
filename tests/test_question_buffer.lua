-- Tests for leetcode-ui.buffer utilities.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['spans_to_texts'] = new_set()

T['spans_to_texts']['concatenates spans per line'] = function()
  local buffer = helpers.mod('buffer')
  local lines = {
    { { text = 'a' }, { text = 'b' } },
    { { text = 'cd' } },
  }
  eq(buffer.spans_to_texts(lines)[1], 'ab')
  eq(buffer.spans_to_texts(lines)[2], 'cd')
end

T['spans_to_texts']['empty lines preserved'] = function()
  local buffer = helpers.mod('buffer')
  local lines = { { { text = 'x' } }, {} }
  local texts = buffer.spans_to_texts(lines)
  eq(texts[1], 'x')
  eq(texts[2], '')
end

T['get_current_view'] = new_set()

T['get_current_view']['nil outside views'] = function()
  local question = require('leetcode-ui.question')
  local ok = pcall(function() return question.get_current_view and question.get_current_view() end)
  eq(ok, true)
end

return T
