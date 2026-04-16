local M = {}

local session_processes = {}
local next_request_id = 1

local function extract_text(message)
  local parts = {}

  if not message or not message.content then
    return ""
  end

  for _, content in ipairs(message.content) do
    if content.type == "text" and content.text ~= nil then
      parts[#parts + 1] = content.text
    end
  end

  return table.concat(parts, "")
end

local function find_last_assistant(messages)
  if not messages then
    return nil
  end

  for index = #messages, 1, -1 do
    local message = messages[index]

    if message.role == "assistant" then
      return message
    end
  end

  return nil
end

local function ensure_directory(path)
  if not path or path == "" then
    return
  end

  vim.fn.mkdir(path, "p")
end

local function resolve_command(opts)
  if opts.command then
    return vim.deepcopy(opts.command)
  end

  local command = { opts.cmd or "pi" }

  for _, item in ipairs(opts.args or {}) do
    command[#command + 1] = item
  end

  return command
end

local function make_request_id(run_id)
  local request_id = string.format("cinder-%s-%d", run_id, next_request_id)
  next_request_id = next_request_id + 1
  return request_id
end

local function append_json_line(process, payload)
  local encoded = vim.json.encode(payload)
  vim.fn.chansend(process.job_id, encoded .. "\n")
end

local function finalize_run(process, run, callbacks, result)
  process.current_run_id = nil
  process.current_run = nil
  process.current_callbacks = nil
  process.last_assistant_message = nil
  callbacks.on_complete(run, result)
end

local function fail_run(process, run, callbacks, message)
  process.current_run_id = nil
  process.current_run = nil
  process.current_callbacks = nil
  process.last_assistant_message = nil
  callbacks.on_error(run, message)
end

local function cancel_run(process, run, callbacks)
  process.current_run_id = nil
  process.current_run = nil
  process.current_callbacks = nil
  process.last_assistant_message = nil
  callbacks.on_cancelled(run)
end

local function handle_event(process, event)
  local run = process.current_run
  local callbacks = process.current_callbacks

  if not run or not callbacks then
    return
  end

  if event.type == "agent_start" then
    callbacks.on_progress(run, "thinking")
    return
  end

  if event.type == "queue_update" then
    callbacks.on_progress(run, "queued")
    return
  end

  if event.type == "message_update" and event.message and event.message.role == "assistant" then
    callbacks.on_progress(run, "streaming")

    if callbacks.on_message_delta then
      local partial = extract_text(event.message)

      if partial ~= "" then
        callbacks.on_message_delta(run, partial)
      end
    end

    return
  end

  if event.type == "message_end" and event.message and event.message.role == "assistant" then
    process.last_assistant_message = event.message
    return
  end

  if event.type ~= "agent_end" then
    return
  end

  local assistant = process.last_assistant_message or find_last_assistant(event.messages)
  local stop_reason = assistant and assistant.stopReason or "stop"
  local text = extract_text(assistant)

  if stop_reason == "aborted" then
    cancel_run(process, run, callbacks)
    return
  end

  if stop_reason == "error" then
    fail_run(process, run, callbacks, assistant.errorMessage or "Pi request failed")
    return
  end

  if text ~= "" then
    callbacks.on_message_final(run, text)
  end

  finalize_run(process, run, callbacks, {
    summary = string.format("Pi session %s completed run %s", process.session.session_id, run.id),
  })
end

local function handle_response(process, response)
  if not response.id then
    return
  end

  local pending = process.pending[response.id]

  if not pending then
    return
  end

  process.pending[response.id] = nil

  if response.success then
    return
  end

  if pending.command == "abort" and process.current_run and process.current_callbacks then
    fail_run(process, process.current_run, process.current_callbacks, response.error or "Pi abort failed")
    return
  end

  if pending.run and process.current_run_id == pending.run.id and process.current_callbacks then
    fail_run(process, pending.run, process.current_callbacks, response.error or "Pi request failed")
  end
end

local function handle_stdout(process, data)
  if not data then
    return
  end

  local lines = {}

  if #data == 0 then
    return
  end

  if #data == 1 then
    process.stdout_partial = process.stdout_partial .. data[1]
    return
  end

  lines[#lines + 1] = process.stdout_partial .. data[1]

  for index = 2, #data - 1 do
    lines[#lines + 1] = data[index]
  end

  process.stdout_partial = data[#data]

  for _, line in ipairs(lines) do
    if line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)

      if ok and type(decoded) == "table" then
        if decoded.type == "response" then
          handle_response(process, decoded)
        elseif decoded.type ~= "extension_ui_request" then
          handle_event(process, decoded)
        end
      elseif process.current_run and process.current_callbacks then
        fail_run(process, process.current_run, process.current_callbacks, string.format("invalid Pi RPC output: %s", line))
      end
    end
  end
end

local function handle_exit(process, code)
  session_processes[process.session.session_id] = nil

  if process.current_run and process.current_callbacks then
    if process.current_run.status == "cancelled" then
      return
    end

    fail_run(process, process.current_run, process.current_callbacks, string.format(
      "Pi process exited unexpectedly with code %s%s",
      tostring(code),
      #process.stderr > 0 and string.format(": %s", process.stderr[#process.stderr]) or ""
    ))
  end
end

local function build_command(run, opts)
  local command = resolve_command(opts)

  if run.model then
    command[#command + 1] = "--model"
    command[#command + 1] = run.model
  end

  return command
end

local function build_env(opts)
  local env = vim.fn.environ()
  local user_env = opts.env or {}

  for key, value in pairs(user_env) do
    env[key] = value
  end

  if not env.PI_CODING_AGENT_DIR then
    local base = opts.agent_dir or vim.fs.joinpath(vim.fn.stdpath("data"), "cinder", "pi")
    ensure_directory(base)
    env.PI_CODING_AGENT_DIR = base
  end

  return env
end

local function create_process(run, opts)
  local session = require("cinder.state").get_session(run.session_id)
  local command = build_command(run, opts)
  local cwd = opts.cwd or run.context.cwd or vim.fn.getcwd()
  local env = build_env(opts)

  if opts.session_dir then
    ensure_directory(opts.session_dir)
  end

  local process = {
    session = session,
    command = command,
    cwd = cwd,
    env = env,
    stdout_partial = "",
    stderr = {},
    pending = {},
    current_run_id = nil,
    current_run = nil,
    current_callbacks = nil,
    last_assistant_message = nil,
  }

  process.job_id = vim.fn.jobstart(command, {
    cwd = cwd,
    env = env,
    stderr_buffered = false,
    stdout_buffered = false,
    on_stdout = function(_, data)
      handle_stdout(process, data)
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end

      for _, line in ipairs(data) do
        if line ~= "" then
          process.stderr[#process.stderr + 1] = line
        end
      end
    end,
    on_exit = function(_, code)
      handle_exit(process, code)
    end,
  })

  if process.job_id <= 0 then
    error(string.format("failed to start Pi process: %s", vim.inspect(command)))
  end

  session_processes[session.session_id] = process

  return process
end

local function ensure_process(run, opts)
  local process = session_processes[run.session_id]

  if process and vim.fn.jobwait({ process.job_id }, 0)[1] == -1 then
    return process
  end

  return create_process(run, opts)
end

local function send_command(process, run, command_type, payload)
  local request_id = make_request_id(run.id)

  process.pending[request_id] = {
    command = command_type,
    run = run,
  }

  append_json_line(process, vim.tbl_extend("force", {
    id = request_id,
    type = command_type,
  }, payload or {}))
end

function M.start(run, opts, callbacks)
  local process = ensure_process(run, opts)

  if process.current_run_id ~= nil then
    error(string.format("Pi session %s already has an active run", run.session_id))
  end

  process.current_run_id = run.id
  process.current_run = run
  process.current_callbacks = callbacks
  process.last_assistant_message = nil

  callbacks.on_progress(run, "starting")
  send_command(process, run, "prompt", {
    message = run.provider_prompt or run.prompt,
  })

  return {
    cancel = function()
      if process.current_run_id ~= run.id then
        return
      end

      send_command(process, run, "abort", {})
    end,
  }
end

function M.stop_session(session)
  local process = session_processes[session.session_id]

  if not process then
    return
  end

  session_processes[session.session_id] = nil
  vim.fn.jobstop(process.job_id)
end

function M.doctor(profile_name, profile, opts)
  local command = resolve_command(opts)
  local executable = command[1]
  local lines = {
    string.format("Profile: %s", profile_name),
    "Provider: pi",
    string.format("Command: %s", table.concat(command, " ")),
  }
  local ok = true

  if vim.fn.executable(executable) == 1 then
    lines[#lines + 1] = string.format("Binary: ok (%s)", executable)
  else
    ok = false
    lines[#lines + 1] = string.format("Binary: missing (%s)", executable)
  end

  if command[2] and executable == "node" then
    if vim.fn.filereadable(command[2]) == 1 then
      lines[#lines + 1] = string.format("Script: ok (%s)", command[2])
    else
      ok = false
      lines[#lines + 1] = string.format("Script: missing (%s)", command[2])
    end
  end

  if profile.model then
    lines[#lines + 1] = string.format("Model: pinned (%s)", profile.model)
  else
    lines[#lines + 1] = "Model: provider default (not pinned)"
  end

  local auth_envs = {
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_OAUTH_TOKEN",
    "GEMINI_API_KEY",
    "AWS_PROFILE",
    "AWS_ACCESS_KEY_ID",
    "OPENCODE_API_KEY",
  }
  local present = {}

  for _, env_name in ipairs(auth_envs) do
    if vim.env[env_name] and vim.env[env_name] ~= "" then
      present[#present + 1] = env_name
    end
  end

  if #present > 0 then
    lines[#lines + 1] = string.format("Auth hints: detected %s", table.concat(present, ", "))
  else
    ok = false
    lines[#lines + 1] = "Auth hints: no known provider auth env vars detected"
  end

  lines[#lines + 1] = string.format("Status: %s", ok and "ok" or "warning")
  lines[#lines + 1] = ""

  return lines
end

return M
