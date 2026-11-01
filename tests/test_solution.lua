-- Tests for leetcode-ui.solution.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      helpers.setup()
    end,
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

return T
