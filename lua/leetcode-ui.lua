--- *leetcode-ui* LeetCode UI for Neovim
---
--- MIT License Copyright (c) 2024-2026 231tr0n

--- A command-driven LeetCode client. The whole interface lives in one central
--- window: problem description, solution editor, test console, and information
--- are tabs in that window. Statistics use the same window.
---
--- # Setup ~
---
--- Call |LeetCode.setup()| with your options. All settings are optional; see
--- |leetcode-ui-config| for every option and the defaults. Every call replaces
--- the complete configuration: options omitted from the new table return to
--- their defaults instead of keeping values from an earlier call.
---
--- Changing `url`, `storage_path`, or credential-related options closes the
--- central window (question, statistics, and help views) after drafts are
--- saved. `storage_path` changes may migrate saved data; `url` and credential
--- changes also reset cached authentication. If a draft cannot be saved, setup
--- raises an error.
---
--- >lua
---   require('leetcode-ui').setup({})
--- <
---
--- No action keymaps are created by the plugin. Every action is available as a
--- `:LeetCode` subcommand, so you can map exactly the actions you use:
---
--- >lua
---   vim.keymap.set('n', '<leader>lr', '<cmd>LeetCode question run<cr>',
---     { desc = 'LeetCode: run' })
---   vim.keymap.set('n', '<leader>ls', '<cmd>LeetCode question submit<cr>',
---     { desc = 'LeetCode: submit' })
--- <
---
--- # Features ~
---
--- - Browse problems with `mini.pick` or |vim.ui.select()|.
--- - Read parsed descriptions, with hints hidden by default.
--- - Edit solutions with draft and testcase persistence.
--- - Run and submit solutions through LeetCode's API.
--- - Format with the remote formatter when available, otherwise CLI
---   formatters or LSP.
--- - Show progress statistics and session information.
--- - Show inline progress while the problem list loads.
--- - Render Description, Info, Statistics, and Help as Markdown when
---   `render-markdown.nvim` is loaded and enabled.
--- - Import session cookies from supported browsers (disabled by default).
---
--- # Commands ~
---
--- Browsing and account views:
---
--- - `:LeetCode` or `:LeetCode list [difficulty]` - browse problems.
--- - `:LeetCode daily` - open the daily challenge.
--- - `:LeetCode random [difficulty]` - open a random problem.
--- - `:LeetCode open <slug>` - open a problem by its title slug.
--- - `:LeetCode stats` - show progress statistics.
--- - `:LeetCode session` - show the current session.
--- - `:LeetCode refresh [difficulty]` - fetch a fresh problem list and reopen.
--- - `:LeetCode help` - show a command summary in the central window.
---
--- Question-window actions live under `:LeetCode question`:
---
--- - `:LeetCode question description`, `:LeetCode question code`,
---   `:LeetCode question console`, `:LeetCode question info` - show a tab.
--- - `:LeetCode question hints [show|hide]` - show, hide, or toggle hints
---   when no argument is given (hidden by default).
--- - `:LeetCode question next`, `:LeetCode question prev` - cycle tabs.
--- - `:LeetCode question run [index]` - run all testcases or one testcase.
--- - `:LeetCode question submit` - submit the current solution.
--- - `:LeetCode question reset` - restore the starter snippet.
--- - `:LeetCode question format` - format the current solution.
--- - `:LeetCode question language [slug]` - switch language.
--- - `:LeetCode question case add <input>`,
---   `:LeetCode question case edit <index> <input>`,
---   `:LeetCode question case delete <index>`,
---   `:LeetCode question case reset`,
---   `:LeetCode question case next`, `:LeetCode question case prev`
---   - manage testcases. Use `\n` for newlines in one-line command input.
--- - `:LeetCode question close` - close the question window.
---
--- # Requirements ~
---
--- - Neovim stable (0.12 or newer; `vim.system`, `vim.uv`, and `vim.lsp`).
--- - `curl` - required for all LeetCode API and remote formatting requests.
--- - `python3` - required only for browser cookie import; SQLite-backed
---   browsers also need the `sqlite3` module.
--- - `openssl` - optional; used for supported Chromium-family `v10` and `v11`
---   cookie decryption.
--- - `secret-tool` on Linux or `security` on macOS - optional; used for
---   keyring-protected cookies (Linux `v11`, macOS `v10`/`v11`).
--- - `mini.nvim` - optional; run `require('mini.pick').setup()` for the
---   picker backend and `require('mini.clue').setup()` for key hints. Clue
---   triggers are enabled inside the central window when it is set up.
--- - `render-markdown.nvim` - optional; renders Markdown views in the central
---   window when it is loaded and enabled.
--- - `npm`/`npx` - optional; enables `prettier = true` to format JavaScript
---   and TypeScript through `npx prettier`.
--- - A language server such as `lua-language-server`, `clangd`, or `ruff` -
---   optional; provides diagnostics and completion, plus LSP formatting when
---   the server supports it.
--- - Optional CLI formatters: `prettier`, `black`, `clang-format`, `gofmt`,
---   `rustfmt`, or `google-java-format`.
---
--- No LuaRocks or external Lua packages are required.
---
--- # Browser cookie caution ~
---
--- Browser cookie import is disabled by default (`browser = 'none'`). When
--- enabled, the plugin reads LeetCode cookies directly from your browser's
--- on-disk cookie database and may decrypt Chromium-family values using system
--- keyring tools and `openssl`. These cookies grant access to your LeetCode
--- account; only enable this if you understand the risk. Prefer `cookie_file`
--- or environment variables when possible. Linux is the tested Chromium
--- decryption path; macOS uses the Keychain and PBKDF2 and is covered by mocked
--- unit tests, not a native macOS CI runner. Encrypted Chromium cookies on
--- Windows are not supported.
---
--- Table of contents:
---
---@tag LeetCode
---@toc_entry Overview
---@toc

local LeetCode = {}

-- Modules ===========================================================================================================

LeetCode.config = require('leetcode-ui.config')

-- Public API ========================================================================================================

local function auth_config_changed(prepared, current)
  for _, key in ipairs({ 'cookies', 'cookie_file', 'browser', 'browser_paths' }) do
    if not vim.deep_equal(prepared[key], current[key]) then return true end
  end
  return false
end

--- Set up plugin options (full docs in |leetcode-ui-config|).
---
--- Each call replaces the complete configuration; omitted options return to
--- their defaults. Changing `url`, `storage_path`, or credential options may
--- close the central window. `url` and credential changes also reset cached
--- authentication; `storage_path` changes may migrate saved drafts and
--- testcases. An error is raised if a draft cannot be saved.
---
---@param opts table|nil Setup options.
LeetCode.setup = function(opts)
  local prepared = LeetCode.config.prepare(opts)
  local current = LeetCode.config.config
  local storage = require('leetcode-ui.storage')
  prepared.storage_path = storage.root_path(prepared.storage_path)
  local function storage_root(value) return storage.root_path(value) end
  local first_setup = not LeetCode.config.is_setup
  local storage_changed =
    not storage.path_equal(storage_root(prepared.storage_path), storage_root(current.storage_path))
  local location_changed = prepared.url ~= current.url or storage_changed
  local credentials_changed = auth_config_changed(prepared, current)

  -- Save drafts before touching the old view/window state or migration target.
  local question = package.loaded['leetcode-ui.question']
  local reason = location_changed and 'url or storage_path' or 'credentials'
  if (location_changed or credentials_changed) and question ~= nil then
    local solution = package.loaded['leetcode-ui.solution']
    for _, view in pairs(question.views) do
      if solution ~= nil and not solution.save_draft(view) then
        LeetCode.config.error(('Cannot change %s while a question view has unsaved changes'):format(reason))
      end
    end
  end

  if not first_setup and storage_changed and not storage.migrate(prepared.storage_path) then
    LeetCode.config.error('Failed to migrate drafts and testcases to the new storage_path')
  end

  if location_changed or credentials_changed then
    if question ~= nil then
      local slugs = vim.tbl_keys(question.views)
      for _, slug in ipairs(slugs) do
        if question.views[slug] ~= nil then question.close(question.views[slug], true, true) end
      end
      if next(question.views) ~= nil then
        LeetCode.config.error(('Cannot change %s while a question view cannot be closed'):format(reason))
      end
      question.close()
    end

    local ui = package.loaded['leetcode-ui.ui']
    if ui ~= nil and ui.is_open() then ui.close() end
  end

  if credentials_changed then LeetCode.config.auth_epoch = LeetCode.config.auth_epoch + 1 end
  LeetCode.config.setup(nil, prepared)

  -- Only changes that alter the auth identity (first setup, credentials, or
  -- URL) invalidate sessions and cookies.
  if first_setup or credentials_changed or prepared.url ~= current.url then
    for _, name in ipairs({ 'leetcode-ui.auth', 'leetcode-ui.browser' }) do
      local loaded = package.loaded[name]
      if loaded ~= nil and type(loaded.reset) == 'function' then loaded.reset() end
    end
  end
end

--- Ensure a default setup has happened once.
LeetCode.ensure_setup = function()
  if LeetCode.config.is_setup ~= true then LeetCode.setup({}) end
end

--- Run a `:LeetCode` subcommand.
---
---@param fargs table Argument list, like `{ 'question', 'run', '1' }`.
LeetCode.command = function(fargs) require('leetcode-ui.commands').run(fargs) end

--- Open today's daily coding challenge.
LeetCode.daily = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').daily()
end

--- Open a random question.
---
---@param opts table|nil { difficulty = 'Easy', 'Medium', or 'Hard' }
LeetCode.random = function(opts)
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').random(opts)
end

--- Browse the problem list.
---
---@param opts table|nil { difficulty = 'Easy', 'Medium', or 'Hard' }
LeetCode.list = function(opts)
  LeetCode.ensure_setup()
  require('leetcode-ui.picker').problem(opts)
end

--- Open a question by slug.
---
---@param title_slug string
LeetCode.open = function(title_slug)
  LeetCode.ensure_setup()
  require('leetcode-ui.question').open(title_slug)
end

--- Open the statistics view.
LeetCode.stats = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.stats_view').open()
end

--- Show current session information.
LeetCode.session = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.stats_view').session()
end

--- Close the active question view.
LeetCode.close = function()
  LeetCode.ensure_setup()
  require('leetcode-ui.question').close()
end

return LeetCode
