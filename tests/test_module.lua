-- Tests for the root module and plugin command registration.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local expect = helpers.expect
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
    post_case = function()
      helpers.reset_ui()
      vim.g.loaded_leetcode_ui = nil
      pcall(vim.api.nvim_del_user_command, 'LeetCode')
    end,
  },
})

T['root'] = new_set()

T['root']['setup delegates to config'] = function()
  local root = require('leetcode-ui')
  local config = require('leetcode-ui.config')
  root.setup({
    browser = 'none',
    cookies = {},
    lang = 'golang',
    notifications = true,
    show_hints = true,
    storage_path = config.config.storage_path,
  })
  eq(config.config.lang, 'golang')
  eq(config.config.notifications, true)
  eq(config.config.show_hints, true)
end

T['root']['ensure_setup sets up once'] = function()
  local root = require('leetcode-ui')
  local config = require('leetcode-ui.config')
  local storage_path = config.config.storage_path
  config.is_setup = false
  root.ensure_setup()
  eq(config.is_setup, true)

  helpers.configure({ lang = 'golang', storage_path = storage_path })
  root.ensure_setup()
  eq(config.config.lang, 'golang')
end

T['root']['setup invalidates cached credentials'] = function()
  local root = require('leetcode-ui')
  local auth = require('leetcode-ui.auth')
  local browser = require('leetcode-ui.browser')
  local storage = require('leetcode-ui.storage')
  auth.session = { checked = true, signed_in = true }
  browser.cache = { value = {}, at = os.time() }
  storage.write_cache({
    domain = 'leetcode.com',
    user = 'anonymous',
    problems = { { title_slug = 'two-sum', status = 'solved' } },
    total = 1,
  })

  root.setup({
    browser = 'none',
    cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' },
    notifications = false,
    storage_path = require('leetcode-ui.config').config.storage_path,
  })
  eq(auth.session, {})
  eq(browser.cache, nil)
  eq(storage.read_cache().problems[1].title_slug, 'two-sum')
end

T['root']['unrelated setup keeps cached credentials'] = function()
  local root = require('leetcode-ui')
  local auth = require('leetcode-ui.auth')
  local browser = require('leetcode-ui.browser')
  auth.session = { checked = true, signed_in = true, name = 'user' }
  browser.cache = { value = {}, at = os.time() }

  root.setup({
    browser = 'none',
    cookies = {},
    notifications = false,
    show_hints = true,
    storage_path = require('leetcode-ui.config').config.storage_path,
  })
  eq(auth.session.name, 'user')
  eq(browser.cache ~= nil, true)
end

T['root']['domain changes close open question views'] = function()
  local root = require('leetcode-ui')
  local question = require('leetcode-ui.question')
  local view = helpers.fake_view()
  question.views[view.slug] = view
  question.active = view

  root.setup({
    url = 'leetcode.cn',
    browser = 'none',
    cookies = {},
    notifications = false,
    storage_path = require('leetcode-ui.config').config.storage_path,
  })
  eq(question.views[view.slug], nil)
  eq(question.active, nil)
  eq(view.closed, true)
end

T['root']['storage path changes close open question views'] = function()
  local root = require('leetcode-ui')
  local question = require('leetcode-ui.question')
  local view = helpers.fake_view()
  question.views[view.slug] = view
  question.active = view

  root.setup({
    browser = 'none',
    cookies = {},
    notifications = false,
    storage_path = helpers.tmpdir(),
  })
  eq(question.views[view.slug], nil)
  eq(question.active, nil)
  eq(view.closed, true)
end

T['root']['storage path changes migrate drafts and testcases'] = function()
  local root = require('leetcode-ui')
  local config = require('leetcode-ui.config')
  local storage = require('leetcode-ui.storage')
  storage.write_draft('two-sum', 'python3', 'saved draft')
  storage.write_testcases('two-sum', { 'saved input' })
  local target = helpers.tmpdir()
  local target_draft = vim.fs.joinpath(target, 'drafts', config.config.url, 'two-sum.python3')
  vim.fn.mkdir(vim.fs.dirname(target_draft), 'p')
  vim.fn.writefile({ 'existing' }, target_draft)

  root.setup({
    browser = 'none',
    cookies = {},
    notifications = false,
    storage_path = target,
  })
  eq(config.config.storage_path, target)
  eq(storage.read_draft('two-sum', 'python3'), 'existing')
  eq(storage.read_testcases('two-sum'), { 'saved input' })
end

T['root']['location changes abort when a view cannot be closed'] = function()
  local root = require('leetcode-ui')
  local question = require('leetcode-ui.question')
  local view = helpers.fake_view()
  question.views[view.slug] = view
  question.active = view
  local config = require('leetcode-ui.config')
  local auth = require('leetcode-ui.auth')
  local browser = require('leetcode-ui.browser')
  local old_url, old_storage = config.config.url, config.config.storage_path
  auth.session = { checked = true, signed_in = true, name = 'user' }
  browser.cache = { value = {}, at = os.time() }

  local saved = 0
  helpers.with_stub('leetcode-ui.solution', 'save_draft', function()
    saved = saved + 1
    return false
  end, function()
    expect.error(
      function()
        root.setup({
          url = 'leetcode.cn',
          browser = 'none',
          cookies = {},
          notifications = false,
          storage_path = config.config.storage_path,
        })
      end,
      'Cannot change url or storage_path'
    )
  end)
  eq(saved, 1)
  eq(question.views[view.slug], view)
  eq(question.active, view)
  eq(config.config.url, old_url)
  eq(config.config.storage_path, old_storage)
  eq(auth.session.name, 'user')
  eq(browser.cache ~= nil, true)
end

T['root']['domain changes close statistics overlays'] = function()
  local root = require('leetcode-ui')
  local ui = require('leetcode-ui.ui')
  ui.claim('stats')
  ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })

  root.setup({
    url = 'leetcode.cn',
    browser = 'none',
    cookies = {},
    notifications = false,
    storage_path = require('leetcode-ui.config').config.storage_path,
  })
  eq(ui.is_open(), false)
end

T['root']['storage path changes close statistics overlays'] = function()
  local root = require('leetcode-ui')
  local ui = require('leetcode-ui.ui')
  ui.claim('stats')
  ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })

  root.setup({
    browser = 'none',
    cookies = {},
    notifications = false,
    storage_path = helpers.tmpdir(),
  })
  eq(ui.is_open(), false)
end

T['root']['credential changes close question views'] = function()
  local root = require('leetcode-ui')
  local question = require('leetcode-ui.question')
  local view = helpers.fake_view()
  question.views[view.slug] = view
  question.active = view

  root.setup({
    browser = 'none',
    cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' },
    notifications = false,
    storage_path = require('leetcode-ui.config').config.storage_path,
  })
  eq(question.views[view.slug], nil)
  eq(view.closed, true)
end

T['root']['credential changes close statistics overlays'] = function()
  local root = require('leetcode-ui')
  local ui = require('leetcode-ui.ui')
  ui.claim('stats')
  ui.render({ { { text = 'stats' } } }, { pad_top = true, owner = 'stats' })

  root.setup({
    browser = 'none',
    cookies = { LEETCODE_SESSION = 's', csrftoken = 'c' },
    notifications = false,
    storage_path = require('leetcode-ui.config').config.storage_path,
  })
  eq(ui.is_open(), false)
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

  local completions = vim.fn.getcompletion('LeetCode st', 'cmdline')
  eq(vim.tbl_contains(completions, 'stats'), true)
  local all = vim.fn.getcompletion('LeetCode ', 'cmdline')
  eq(vim.tbl_contains(all, 'list'), true)
  eq(vim.tbl_contains(all, 'question'), true)

  vim.cmd('LeetCode help')
  local panel = require('leetcode-ui.ui').panel()
  local text = table.concat(vim.api.nvim_buf_get_lines(panel, 0, -1, false), '\n')
  eq(helpers.contains(text, ':LeetCode question run'), true)
end

T['plugin']['does not register twice'] = function()
  vim.g.loaded_leetcode_ui = nil
  dofile('plugin/leetcode.lua')
  pcall(vim.api.nvim_del_user_command, 'LeetCode')
  vim.g.loaded_leetcode_ui = true
  dofile('plugin/leetcode.lua')
  eq(vim.fn.exists(':LeetCode'), 0)
end

return T
