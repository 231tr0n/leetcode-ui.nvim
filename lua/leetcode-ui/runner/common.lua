--- *leetcode-ui-runner-common* Local runner plumbing
---
--- Machinery shared by language harnesses:
--- - decode question `metaData` (params, return type, system-design form),
--- - split testcase `data_input` into raw parameter lines,
--- - resolve a language harness and its availability,
--- - spawn the local run and normalize results.
---
--- Language harness contract (modules under `runner/langs/<slug>`):
--- - `available()` returns a boolean and an optional note.
--- - `run(dir, question, code, meta, params, data_input)` creates workspace
---   files under `dir` and returns argv for |vim.system()|.
---
---@tag LeetCodeRunner
---@toc_entry Local runner

local LeetCodeRunner = {}

local config = require('leetcode-ui.config')

-- Helper functionality =============================================================================================

LeetCodeRunner.meta = function(question)
  local meta = question.meta or {}
  if meta.manual then return { mode = 'manual' } end

  if meta.classname ~= nil then
    return {
      mode = 'systemdesign',
      class_name = meta.classname,
      methods = meta.methods or {},
    }
  end

  local params = {}
  for _, param in ipairs(meta.params or {}) do
    table.insert(params, { name = param.name, type = param.type })
  end
  return {
    mode = 'normal',
    name = meta.name,
    params = params,
    return_type = (meta['return'] ~= nil and meta['return'].type) or nil,
  }
end

LeetCodeRunner.data_lines = function(data_input)
  if data_input == nil or data_input == '' then return nil end
  local lines = vim.split(vim.trim(data_input), '\n')
  for i, line in ipairs(lines) do
    lines[i] = line:gsub('%s+$', '')
  end
  return lines
end

LeetCodeRunner.harness = function(lang_slug, question)
  local local_runner = config.config.local_runner
  if local_runner == false then return nil, 'local runner disabled' end

  local meta = LeetCodeRunner.meta(question)
  if meta.mode == 'manual' then return nil, 'manual testcase problem' end

  local no_local = config.config.no_local or {}
  if type(no_local) == 'table' and vim.tbl_contains(no_local, lang_slug) then
    return nil, ('%s runs online'):format(lang_slug)
  end

  local has, harness = pcall(require, ('leetcode-ui.runner.langs.%s'):format(lang_slug))
  if not has or type(harness) ~= 'table' then return nil, ('no local runner for %s'):format(lang_slug) end

  local can, can_err = harness.available()
  if can == false then return nil, can_err end
  return harness, nil
end

LeetCodeRunner.run_local = function(question, lang_slug, code, data_input, on_done)
  local harness, note = LeetCodeRunner.harness(lang_slug, question)
  if harness == nil then return on_done(nil, note or 'no local runner') end

  local meta = LeetCodeRunner.meta(question)
  local params = LeetCodeRunner.data_lines(data_input)

  local dir = vim.fn.tempname() .. '-lcrun'
  vim.fn.mkdir(dir, 'p')

  local ok, argv = pcall(harness.run, dir, question, code, meta, params, data_input)
  if not ok or type(argv) ~= 'table' then
    vim.fn.delete(dir, 'rf')
    return on_done(nil, ('%s harness failed: %s'):format(lang_slug, tostring(argv)))
  end

  local started = vim.uv.hrtime()
  vim.system(argv, { text = true, timeout = config.config.runner_timeout * 1000 }, function(out)
    vim.schedule(function()
      vim.fn.delete(dir, 'rf')
      on_done(LeetCodeRunner.normalize(out, started), nil)
    end)
  end)
end

LeetCodeRunner.normalize = function(out, started)
  local stdout = out.stdout or ''
  local stderr = out.stderr or ''
  local ok = out.code ~= nil and out.code == 0
  local text = vim.trim((ok or stderr == '') and stdout or stderr)

  local elapsed_ms = 0
  if type(started) == 'number' then elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1e6) end

  if out.code == 124 or out.code == -1 then
    ok = false
    text = vim.trim(('Timed out after %d s; partial output:\n%s'):format(config.config.runner_timeout, stdout))
  end

  if not ok and text == '' then text = vim.trim(('exit code %s'):format(tostring(out.code or 'nil'))) end

  return { status = ok and 'ran' or 'error', message = text, runtime_ms = elapsed_ms, raw = out }
end

return LeetCodeRunner
