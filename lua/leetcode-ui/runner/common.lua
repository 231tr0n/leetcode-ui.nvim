-- |leetcode-ui-runner-common| Local runner plumbing.
--------------------------------------------------------------------------------
-- Machinery shared by language harnesses:
--   - decode the question `metaData` (params, return type, systemDesign form),
--   - split testcase `data_input` into raw parameter lines,
--   - resolve the language harness module and its availability,
--   - spawn the local run and normalize results.
--
-- Language harness contract (modules under `runner/langs/<slug>`):
--   H.available()        -> boolean, note
--   H.run(dir, question, code, params, data_input) -> argv
--     Create all workspace files under `dir`; return argv for vim.system().
--     Both `params` (decoded meta) and `data_input` (raw testcase lines) are
--     passed; harnesses may weave either into their files.
--------------------------------------------------------------------------------

local H = {}

local config = require('leetcode-ui.config')

-- Helper functionality =============================================================================================

---Decode the normalized question `meta` into a runner description.
---
---@param question table
---@return table { mode = 'normal'|'systemdesign'|'manual', name, params, return_type, class_name, methods }
H.meta = function(question)
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

---Split the `data_input` testcase into raw parameter lines.
---
---@param data_input string|nil Multi-line testcase string.
---@return table|nil raw lines; nil for an empty input.
H.data_lines = function(data_input)
  if data_input == nil or data_input == '' then return nil end
  local lines = vim.split(vim.trim(data_input), '\n')
  for i, line in ipairs(lines) do
    lines[i] = line:gsub('%s+$', '')
  end
  return lines
end

---Resolve the local harness for a language.
---
---@param lang_slug string
---@param question table
---@return table|nil harness module, when locally applicable.
---@return string|nil note Why no local run is offered.
H.harness = function(lang_slug, question)
  local local_runner = config.config.local_runner
  if local_runner == false then return nil, 'local runner disabled' end

  local meta = H.meta(question)
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

---Asynchronously run the local harness over a testcase.
---
---@param question table Question detail.
---@param lang_slug string
---@param code string User typed code.
---@param data_input string|nil Testcase (nil = empty params).
---@param on_done fun(result: table|nil, err: string|nil) Callback in the main loop.
H.run_local = function(question, lang_slug, code, data_input, on_done)
  local harness, note = H.harness(lang_slug, question)
  if harness == nil then return on_done(nil, note or 'no local runner') end

  local meta = H.meta(question)
  local params = H.data_lines(data_input)

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
      on_done(H.normalize(out, started), nil)
    end)
  end)
end

---Normalize a `vim.system` result.
---
---@param out table vim.system callback result.
---@param started number uv.hrtime() at spawn.
---@return table { status = 'ran'|'error', message, runtime_ms, raw }
H.normalize = function(out, started)
  local stdout = out.stdout or ''
  local stderr = out.stderr or ''
  local text = vim.trim(stderr ~= '' and stderr or stdout)

  local elapsed_ms = 0
  if type(started) == 'number' then elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1e6) end

  local ok = out.code ~= nil and out.code == 0
  if out.code == 124 or out.code == -1 then
    ok = false
    text = vim.trim(('Timed out after %d s; partial output:\n%s'):format(config.config.runner_timeout, stdout))
  end

  if not ok and text == '' then text = vim.trim(('exit code %s'):format(tostring(out.code or 'nil'))) end

  return { status = ok and 'ran' or 'error', message = text, runtime_ms = elapsed_ms, raw = out }
end

return H
