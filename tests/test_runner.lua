-- Tests for leetcode-ui.runner.common and python3 harness (offline).
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['common'] = new_set()

T['common']['is_local'] = function()
  local common = helpers.mod('runner.common')
  if type(common.is_local) ~= 'function' then return end
  eq(common.is_local('python3'), true)
  eq(common.is_local('javascript'), true)
  eq(common.is_local('golang'), true)
  eq(common.is_local('cpp'), false)
end

T['common']['harness selects python3'] = function()
  local common = helpers.mod('runner.common')
  local h, note = common.harness('python3', {})
  eq(type(h), 'table')
  eq(type(h.run), 'function')
  eq(note, nil)
end

T['common']['harness rejects unknown language'] = function()
  local common = helpers.mod('runner.common')
  local h, note = common.harness('fortran', {})
  eq(h, nil)
  eq(type(note), 'string')
end

T['common']['data_lines parses testcase'] = function()
  local common = helpers.mod('runner.common')
  local lines = common.data_lines('[2,7,11,15]\n9\n')
  eq(lines[1], '[2,7,11,15]')
  eq(lines[2], '9')
end

T['common']['data_lines nil for empty'] = function()
  local common = helpers.mod('runner.common')
  eq(common.data_lines(nil), nil)
  eq(common.data_lines(''), nil)
end

T['common']['meta builds question metadata'] = function()
  local common = helpers.mod('runner.common')
  local question = {
    meta = {
      name = 'twoSum',
      params = { { name = 'nums', type = 'integer[]' }, { name = 'target', type = 'integer' } },
      ['return'] = { type = 'integer[]' },
    },
  }
  local meta = common.meta(question)
  eq(meta.mode, 'normal')
  eq(meta.name, 'twoSum')
  eq(#meta.params, 2)
  eq(meta.params[1].type, 'integer[]')
  eq(meta.return_type, 'integer[]')
end

T['common']['meta systemdesign mode'] = function()
  local common = helpers.mod('runner.common')
  local question = {
    meta = {
      classname = 'MyCalendar',
      methods = {
        {
          name = 'book',
          params = { { name = 'start', type = 'integer' }, { name = 'end', type = 'integer' } },
          ['return'] = {
            type = 'boolean',
          },
        },
      },
    },
  }
  local meta = common.meta(question)
  eq(meta.mode, 'systemdesign')
  eq(meta.class_name, 'MyCalendar')
  eq(meta.methods[1].name, 'book')
end

T['python3'] = new_set()

T['python3']['build assembles main.py'] = function()
  local py = require('leetcode-ui.runner.langs.python3')
  local src = py.build('class Solution: pass', 'normal', { name = 'f', return_type = 'int', class_name = 'Solution' })
  eq(type(src), 'string')
  eq(#src > 10, true)
end

T['python3']['build systemdesign uses class entry'] = function()
  local py = require('leetcode-ui.runner.langs.python3')
  local src = py.build(
    'class MyCalendar: pass',
    'systemdesign',
    { name = 'book', return_type = 'boolean', class_name = 'MyCalendar' }
  )
  eq(type(src), 'string')
  eq(#src > 10, true)
end

T['python3']['run_local two-sum returns json'] = function()
  local common = helpers.mod('runner.common')
  local question = helpers.fake_detail({ title_slug = 'two-sum' })
  question.meta = {
    name = 'twoSum',
    params = { { name = 'nums', type = 'integer[]' }, { name = 'target', type = 'integer' } },
    ['return'] = { type = 'integer[]' },
  }
  local code = table.concat({
    'class Solution:',
    '    def twoSum(self, nums, target):',
    '        for i, x in enumerate(nums):',
    '            for j, y in enumerate(nums):',
    '                if i != j and x + y == target:',
    '                    return [i, j]',
    '        return []',
  }, '\n')
  local result, err = nil, nil
  common.run_local(question, 'python3', code, '[2,7,11,15]\n9', function(r, e)
    result = r
    err = e
  end)
  eq(helpers.wait_for(function() return result ~= nil end), true)
  eq(err, nil)
  eq(result.status, 'ran')
  eq(type(result.message), 'string')
  eq(helpers.contains(result.message, '0'), true)
  eq(helpers.contains(result.message, '1'), true)
end

T['python3']['run_local TreeNode roundtrip'] = function()
  local common = helpers.mod('runner.common')
  local question = helpers.fake_detail({ title_slug = 'invert-binary-tree' })
  question.meta =
    { name = 'invertTree', params = { { name = 'root', type = 'TreeNode' } }, ['return'] = { type = 'TreeNode' } }
  local code = table.concat({
    'class Solution:',
    '    def invertTree(self, root):',
    '        if not root: return None',
    '        root.left, root.right = self.invertTree(root.right), self.invertTree(root.left)',
    '        return root',
  }, '\n')
  local result, err = nil, nil
  common.run_local(question, 'python3', code, '[4,2,7,1,3,6,9]', function(r, e)
    result = r
    err = e
  end)
  eq(helpers.wait_for(function() return result ~= nil end), true)
  eq(err, nil)
  eq(result.status, 'ran')
  eq(helpers.contains(result.message, '4'), true)
end

T['python3']['run_local MyCalendar systemdesign'] = function()
  local common = helpers.mod('runner.common')
  local question = helpers.fake_detail({ title_slug = 'my-calendar-i' })
  question.meta = {
    classname = 'MyCalendar',
    methods = {
      {
        name = 'book',
        params = { { name = 'start', type = 'integer' }, { name = 'end', type = 'integer' } },
        ['return'] = { type = 'boolean' },
      },
    },
  }
  local code = table.concat({
    'class MyCalendar:',
    '    def __init__(self):',
    '        self.events = []',
    '    def book(self, start, end):',
    '        for s, e in self.events:',
    '            if start < e and end > s: return False',
    '        self.events.append((start, end))',
    '        return True',
  }, '\n')
  local result, err = nil, nil
  common.run_local(question, 'python3', code, '["MyCalendar","book","book"]\n[[],[10,20],[12,30]]', function(r, e)
    result = r
    err = e
  end)
  eq(helpers.wait_for(function() return result ~= nil end), true)
  eq(err, nil)
  eq(result.status, 'ran')
  eq(result.message, '[null,true,false]')
end

return T
