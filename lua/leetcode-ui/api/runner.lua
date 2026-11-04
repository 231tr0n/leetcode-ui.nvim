--- *leetcode-ui-api-runner* Test-run and submit flows
---
--- Flow: POST code to LeetCode, then poll `/submissions/detail/{id}/v2/check/`
--- until a status code arrives; `SUCCESS` without one is an error. Normalize
--- the result for |leetcode-ui-console|.
---
--- Normalized result:
--- `{ status, ok, message, runtime_ms, memory_bytes, correct, total, compare,
--- stdouts, pretty_stdout, answers, expected_answers, input, expected_output,
--- code_output, lang, is_submit, raw }`.
---@tag LeetCodeRunnerApi
---@toc_entry Runner API

local LeetCodeRunnerApi = {}

local api = require('leetcode-ui.api')
local async = require('leetcode-ui.async')

-- Helper data =======================================================================================================

local status_labels = {
  [10] = 'Accepted',
  [11] = 'Wrong Answer',
  [12] = 'Memory Limit Exceeded',
  [13] = 'Time Limit Exceeded',
  [14] = 'Output Limit Exceeded',
  [15] = 'Runtime Error',
  [16] = 'Internal Error',
  [20] = 'Compile Error',
  [21] = 'Compile Error',
  [50] = 'Rejected',
}

-- Helper functionality ==============================================================================================

local function first_nonempty(...)
  for index = 1, select('#', ...) do
    local value = select(index, ...)
    if type(value) == 'string' and value ~= '' then return value end
  end
end

local function is_valid_id(value) return type(value) == 'number' or (type(value) == 'string' and value ~= '') end

local function field(value, fallback)
  if value == nil or value == vim.NIL then return fallback end
  return value
end

local function start_request(path, body, id_field, failure)
  local res, err = api.rest('POST', path, body, nil, { retries = 0 })
  if err ~= nil or res == nil then return nil, err or 'Empty response' end
  if type(res.error) == 'string' and res.error ~= '' then return nil, res.error end
  if not is_valid_id(res[id_field]) then return nil, failure end
  return res[id_field], nil
end

--- Normalize one judging response for the console.
---
---@param item table|nil Raw judging response.
---@param is_submit boolean
---@return table result
LeetCodeRunnerApi.normalize = function(item, is_submit)
  if type(item) ~= 'table' then item = {} end
  local code = item.status_code
  local status = first_nonempty(item.status_msg, status_labels[code]) or 'Finished'
  local ok = status == 'Accepted'
  local message = nil

  if code == 20 or code == 21 then
    message = first_nonempty(item.full_compile_error, item.full_run_error, item.task_compile_error, item.compile_error)
      or 'Compilation failed'
  elseif code == 50 then
    message = first_nonempty(item.ai_judge_message, item.status_msg) or 'Submission rejected'
  elseif not ok then
    message = first_nonempty(item.full_runtime_error, item.full_run_error, item.runtime_error)
  end

  local invalid_testcase = item.invalid_testcase == true
  if invalid_testcase then
    status = 'Invalid Testcase'
    ok = false
  end

  local compare = field(item.compare_result)
  if invalid_testcase then compare = nil end

  local stdouts = field(item.std_output_list, {})
  if type(stdouts) ~= 'table' then stdouts = {} end

  return {
    status = status,
    ok = ok,
    message = message,
    runtime_ms = field(item.elapsed_time),
    memory_bytes = field(item.memory),
    correct = item.total_correct or 0,
    total = item.total_testcases or 0,
    compare = compare,
    stdouts = stdouts,
    pretty_stdout = field(item.pretty_stdout),
    answers = field(item.code_answer),
    expected_answers = field(item.expected_code_answer),
    input = field(item.input_formatted, field(item.last_testcase)),
    expected_output = field(item.expected_output),
    code_output = field(item.code_output),
    lang = field(item.lang),
    is_submit = is_submit,
    raw = item,
  }
end

-- Public API ========================================================================================================

--- Run a test (interpret request, not counted as a submission).
---
---@param question table `{ id, title_slug, lang_slug }`.
---@param code string User typed code.
---@param data_input string|nil Case input: one testcase string or all joined.
---@param cancelled? fun(): boolean Poll cancellation predicate.
---@return table|nil Normalized result
---@return string|nil err
LeetCodeRunnerApi.interpret = function(question, code, data_input, cancelled)
  local path = ('/problems/%s/interpret_solution/'):format(question.title_slug)
  local body = vim.json.encode({
    lang = question.lang_slug or question.lang,
    question_id = question.id,
    typed_code = code,
    data_input = data_input,
  })

  local id, err = start_request(path, body, 'interpret_id', 'Failed to start test run')
  if id == nil then return nil, err end
  return LeetCodeRunnerApi.poll(id, false, cancelled)
end

--- Submit a solution.
---
---@param question table `{ id, title_slug, lang_slug }`.
---@param code string User typed code.
---@param cancelled? fun(): boolean Poll cancellation predicate.
---@return table|nil Normalized result
---@return string|nil err
LeetCodeRunnerApi.submit = function(question, code, cancelled)
  local path = ('/problems/%s/submit/'):format(question.title_slug)
  local body = vim.json.encode({
    lang = question.lang_slug or question.lang,
    question_id = question.id,
    typed_code = code,
  })

  local id, err = start_request(path, body, 'submission_id', 'Failed to submit solution')
  if id == nil then return nil, err end
  return LeetCodeRunnerApi.poll(id, true, cancelled)
end

--- Poll the check endpoint until judging finishes.
---
---@param id string|number interpret_id or submission_id.
---@param is_submit boolean
---@param cancelled? fun(): boolean Poll cancellation predicate.
---@return table|nil Normalized result
---@return string|nil err
LeetCodeRunnerApi.poll = function(id, is_submit, cancelled)
  local path = ('/submissions/detail/%s/v2/check/'):format(id)
  local interval = is_submit and 900 or 450
  local deadline = vim.uv.now() + 300000

  while true do
    if vim.uv.now() >= deadline then return nil, 'Judging timed out' end
    if cancelled ~= nil and cancelled() then return nil, 'Cancelled' end

    local res, err = api.rest('GET', path)
    if err ~= nil then return nil, err end
    if res == nil then return nil, 'Empty response' end

    if type(res.error) == 'string' and res.error ~= '' then return nil, res.error end

    local ai_pending = res.ai_state == 'PENDING' or res.ai_state == 'STARTED'
    local status_code = res.status_code
    if not ai_pending and not api.is_null(status_code) then
      if type(status_code) ~= 'number' then return nil, 'Malformed judging response' end
      if api.is_null(res.state) or res.state == 'SUCCESS' then
        return LeetCodeRunnerApi.normalize(res, is_submit), nil
      end
    elseif not ai_pending and res.state == 'SUCCESS' then
      return nil, 'Judging finished without a status'
    end

    if vim.uv.now() > deadline then return nil, 'Judging timed out' end
    if cancelled ~= nil and cancelled() then return nil, 'Cancelled' end
    async.sleep(interval)
  end
end

return LeetCodeRunnerApi
