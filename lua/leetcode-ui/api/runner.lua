-- |leetcode-ui-api-runner| Test-run (interpret) and submit flows.
--------------------------------------------------------------------------------
-- Flow: POST local code to LeetCode, then poll `/submissions/detail/{id}/check/`
-- until a `status_code` arrives; normalize into a shared result model consumed
-- by |leetcode-ui-console|.
--
-- Normalized result:
--   { status = 'Accepted'|..., ok = bool, message = string|nil,
--     runtime_ms, memory_mb, correct, total, compare = '1010'|nil,
--     stdouts = { string, ... }, pretty_stdout = string|nil, raw = item }
--------------------------------------------------------------------------------

-- Module design:
local H = {}

local api = require('leetcode-ui.api')

-- Helper data =======================================================================================================

H.status_messages = {
  [10] = 'Accepted',
  [11] = 'Wrong Answer',
  [12] = 'Memory Limit Exceeded',
  [13] = 'Runtime Error',
  [14] = 'Format Error',
  [15] = 'Time Limit Exceeded',
  [16] = 'Output Limit Exceeded',
  [20] = 'Compile Error',
  [21] = 'Compile Error',
}

-- Helper functionality ==============================================================================================

---Non-blocking sleep usable inside coroutines.
---
---@param ms number
H.sleep = function(ms)
  local co = coroutine.running()
  vim.defer_fn(function() coroutine.resume(co) end, ms)
  coroutine.yield()
end

---Normalize a `/check/` response item into the shared result model.
---
---@param item table Raw check response.
---@param is_submit boolean
---@return table Normalized result.
H.normalize = function(item, is_submit)
  local code = item.status_code
  local status = H.status_messages[code] or 'Finished'
  local ok = status == 'Accepted'
  local message = nil

  if code == 20 or code == 21 then
    message = item.full_run_error or item.task_compile_error or item.compile_error or 'Compilation failed'
  elseif code == 13 or code == 15 or code == 16 then
    message = item.full_run_error or item.runtime_error or nil
  elseif not ok then
    message = item.full_run_error or item.runtime_error or nil
  end

  if item.invalid_testcase then status = 'Invalid Testcase' end

  return {
    status = status,
    ok = ok,
    message = message,
    runtime_ms = item.elapsed_time,
    memory_mb = item.memory,
    correct = item.total_correct or 0,
    total = item.total_testcases or 0,
    compare = item.compare_result ~= vim.NIL and item.compare_result or nil,
    stdouts = item.std_output_list ~= vim.NIL and item.std_output_list or {},
    pretty_stdout = item.pretty_stdout ~= vim.NIL and item.pretty_stdout or nil,
    lang = item.lang,
    is_submit = is_submit,
    raw = item,
  }
end

-- Public API ========================================================================================================

---Run a test (interpret request, not counted as a submission).
---
---@param question table Normalized detail (|leetcode-ui-api-question|).
---@param code string User typed code.
---@param data_input string|nil Case input: one testcase string or all joined.
---@return table|nil Normalized result
---@return string|nil err
H.interpret = function(question, code, data_input)
  local path = ('/problems/%s/interpret_solution/'):format(question.title_slug)
  local body = vim.json.encode({
    lang = question.lang_slug or question.lang,
    question_id = question.id,
    typed_code = code,
    data_input = data_input,
  })

  local res, err = api.rest('POST', path, body)
  if err ~= nil or res == nil then return nil, err or 'Empty response' end
  if res.interpret_id == nil then return nil, 'Failed to start test run' end

  return H.listen(res.interpret_id, false)
end

---Submit a solution.
---
---@param question table Normalized detail.
---@param code string User typed code.
---@return table|nil Normalized result
---@return string|nil err
H.submit = function(question, code)
  local path = ('/problems/%s/submit/'):format(question.title_slug)
  local body = vim.json.encode({
    lang = question.lang_slug or question.lang,
    question_id = question.id,
    typed_code = code,
  })

  local res, err = api.rest('POST', path, body)
  if err ~= nil or res == nil then return nil, err or 'Empty response' end
  if res.submission_id == nil then return nil, 'Failed to submit solution' end

  return H.listen(res.submission_id, true)
end

---Poll the check endpoint until judging finishes.
---
---@param id string interpret_id or submission_id.
---@param is_submit boolean
---@return table|nil Normalized result
---@return string|nil err
H.listen = function(id, is_submit)
  local path = ('/submissions/detail/%s/check/'):format(id)
  local interval = (is_submit and 900 or 450)
  local deadline = vim.uv.now() + 120000

  while true do
    local res, err = api.rest('GET', path)
    if err ~= nil then return nil, err end

    if type(res) == 'table' and res.status_code ~= nil then return H.normalize(res, is_submit), nil end

    if vim.uv.now() > deadline then return nil, 'Judging timed out' end

    H.sleep(interval)
  end
end

---Latest stored submission for a question and language.
---
---@param question table Normalized detail.
---@param lang_slug string
---@return table|nil detail
---@return string|nil err
H.latest_submission = function(question, lang_slug)
  local path = ('/submissions/latest/?qid=%s&lang=%s'):format(question.id, lang_slug)
  return api.rest('GET', path)
end

return H
