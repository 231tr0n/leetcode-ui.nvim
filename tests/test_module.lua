-- Tests for the root module and plugin command registration.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
    post_case = function() helpers.reset_ui() end,
  },
})

T['root'] = new_set()

T['root']['setup delegates to config'] = function()
  local root = require('leetcode-ui')
  local config = require('leetcode-ui.config')
  root.setup({ notifications = false })
  eq(config.config.notifications, false)
end

T['root']['ensure_setup sets up once'] = function()
  local root = require('leetcode-ui')
  local config = require('leetcode-ui.config')
  config.is_setup = false
  root.ensure_setup()
  eq(config.is_setup, true)
end

T['root']['command delegates after ensuring setup'] = function()
  local root = require('leetcode-ui')
  ---@type any
  local called = nil
  helpers.with_stub(
    'leetcode-ui.commands',
    'run',
    function(args) called = args end,
    function() root.command({ 'help' }) end
  )
  eq(called[1], 'help')
end

T['root']['view helpers delegate to their modules'] = function()
  local root = require('leetcode-ui')
  local calls = {}

  helpers.with_stub('leetcode-ui.picker', 'daily', function() table.insert(calls, 'daily') end, function()
    helpers.with_stub('leetcode-ui.picker', 'random', function() table.insert(calls, 'random') end, function()
      helpers.with_stub(
        'leetcode-ui.picker',
        'problem',
        function(opts) table.insert(calls, 'list:' .. tostring(opts and opts.difficulty)) end,
        function()
          helpers.with_stub(
            'leetcode-ui.question',
            'open',
            function(slug) table.insert(calls, 'open:' .. slug) end,
            function()
              helpers.with_stub('leetcode-ui.question', 'close', function() table.insert(calls, 'close') end, function()
                helpers.with_stub(
                  'leetcode-ui.stats_view',
                  'open',
                  function() table.insert(calls, 'stats') end,
                  function()
                    helpers.with_stub(
                      'leetcode-ui.stats_view',
                      'session',
                      function() table.insert(calls, 'session') end,
                      function()
                        root.daily()
                        root.random({ difficulty = 'Easy' })
                        root.list({ difficulty = 'Hard' })
                        root.open('two-sum')
                        root.stats()
                        root.session()
                        root.close()
                      end
                    )
                  end
                )
              end)
            end
          )
        end
      )
    end)
  end)

  eq(table.concat(calls, ','), 'daily,random,list:Hard,open:two-sum,stats,session,close')
end

T['plugin'] = new_set()

T['plugin']['registers the LeetCode command and completion'] = function()
  vim.g.loaded_leetcode_ui = nil
  dofile('plugin/leetcode.lua')
  eq(vim.fn.exists(':LeetCode'), 2)
  eq(vim.fn.exists(':Leetcode'), 2)

  local completions = vim.fn.getcompletion('LeetCode c', 'cmdline')
  eq(vim.tbl_contains(completions, 'case'), true)
  eq(vim.tbl_contains(completions, 'close'), true)

  vim.cmd('LeetCode help')
  local panel = require('leetcode-ui.ui').panel()
  local text = table.concat(vim.api.nvim_buf_get_lines(panel, 0, -1, false), '\n')
  eq(helpers.contains(text, ':LeetCode run'), true)
end

T['plugin']['does not register twice'] = function()
  vim.g.loaded_leetcode_ui = nil
  dofile('plugin/leetcode.lua')
  local ok = pcall(dofile, 'plugin/leetcode.lua')
  eq(ok, true)
  eq(vim.fn.exists(':LeetCode'), 2)
  eq(vim.fn.exists(':Leetcode'), 2)
end

return T
