local M = {}
local log = require("cinder.debug")

local OPENCODE_CONTINUE_SESSION = "opencode:last"

local function is_pi_command(command)
  return vim.fs.basename(command or "") == "pi"
end

local function is_opencode_command(command)
  return vim.fs.basename(command or "") == "opencode"
end

local function extract_text_parts(message)
  if type(message) ~= "table" or type(message.content) ~= "table" then
    return nil
  end

  local text = {}
  for _, item in ipairs(message.content) do
    if type(item) == "table" and item.type == "text" and type(item.text) == "string" then
      text[#text + 1] = item.text
    end
  end

  if #text == 0 then
    return nil
  end

  return table.concat(text, "")
end

local function extract_json_result(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end

  local final_text
  for _, line in ipairs(vim.split(raw, "\n", { plain = true, trimempty = true })) do
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" then
      if decoded.type == "turn_end" and decoded.message and decoded.message.role == "assistant" then
        final_text = extract_text_parts(decoded.message) or final_text
      elseif decoded.type == "message_end" and decoded.message and decoded.message.role == "assistant" then
        final_text = extract_text_parts(decoded.message) or final_text
      elseif decoded.type == "agent_end" and type(decoded.messages) == "table" then
        for _, message in ipairs(decoded.messages) do
          if type(message) == "table" and message.role == "assistant" then
            final_text = extract_text_parts(message) or final_text
          end
        end
      end
    end
  end

  return final_text
end

local function output_mode(argv)
  for index = 1, #argv do
    if argv[index] == "--mode" or argv[index] == "--format" then
      return argv[index + 1] or "text"
    end
  end

  return "text"
end

local function finalize_output(meta, stdout_chunks, stderr_chunks)
  meta.stdout = table.concat(stdout_chunks, "")
  meta.stderr = table.concat(stderr_chunks, "")
  meta.output_mode = output_mode(meta.command)

  if meta.output_mode == "json" then
    meta.final_output = extract_json_result(meta.stdout)
    if not meta.final_output or meta.final_output == "" then
      meta.final_output = meta.stdout ~= "" and meta.stdout or nil
    end
  end

  return meta
end

local function collect_data(chunks, data)
  if not data or vim.tbl_isempty(data) then
    return nil
  end

  local text = table.concat(data, "\n")
  if text == "" then
    return nil
  end

  chunks[#chunks + 1] = text
  return text
end

local function build_argv(config, prompt, opts)
  opts = opts or {}
  local argv = { config.harness_command }
  local skip_next = false
  for _, arg in ipairs(config.harness_args) do
    if skip_next then
      skip_next = false
    elseif opts.session_file and arg == "--no-session" then
    elseif opts.session_file and arg == "--session" then
      skip_next = true
    else
      argv[#argv + 1] = arg
    end
  end
  if is_pi_command(config.harness_command) or is_opencode_command(config.harness_command) then
    local has_model = false
    for index = 1, #argv do
      if argv[index] == "--model" or argv[index] == "-m" then
        has_model = true
        break
      end
    end
    if not has_model then
      vim.list_extend(argv, { "--model", config.model })
    end
  end
  if opts.session_file then
    if is_opencode_command(config.harness_command) then
      if opts.session_file == OPENCODE_CONTINUE_SESSION then
        argv[#argv + 1] = "--continue"
      else
        vim.list_extend(argv, { "--session", opts.session_file })
      end
    else
      vim.list_extend(argv, { "--session", opts.session_file })
    end
  elseif opts.force_no_session then
    local has_session_flag = false
    for _, arg in ipairs(argv) do
      if arg == "--no-session" or arg == "--session" then
        has_session_flag = true
        break
      end
    end
    if not has_session_flag and is_pi_command(config.harness_command) then
      argv[#argv + 1] = "--no-session"
    end
  end
  if opts.extra_args and #opts.extra_args > 0 then
    vim.list_extend(argv, opts.extra_args)
  end
  argv[#argv + 1] = prompt
  return argv
end

local function run_job(argv, callbacks)
  local meta = {
    backend = "job",
    command = argv,
  }
  local stdout_chunks = {}
  local stderr_chunks = {}
  local json_mode = output_mode(argv) == "json"

  local job_id = vim.fn.jobstart(argv, {
    stdout_buffered = json_mode,
    stderr_buffered = json_mode,
    on_stdout = function(_, data)
      local text = collect_data(stdout_chunks, data)
      if text and not json_mode then
        log.log("runner.stdout", {
          job_id = meta.job_id,
          bytes = #text,
        })
        callbacks.on_stdout(text)
      end
    end,
    on_stderr = function(_, data)
      local text = collect_data(stderr_chunks, data)
      if text then
        log.log("runner.stderr", {
          job_id = meta.job_id,
          bytes = #text,
        })
        callbacks.on_stderr(text)
      end
    end,
    on_exit = function(_, code)
      log.log("runner.exit", {
        job_id = meta.job_id,
        code = code,
      })
      callbacks.on_complete(finalize_output(vim.tbl_extend("force", meta, {
        code = code,
      }), stdout_chunks, stderr_chunks))
    end,
  })

  if job_id <= 0 then
    log.log("runner.launch_failed", {
      command = argv,
    })
    error(string.format("cinder.nvim failed to launch %s", argv[1]), 0)
  end

  meta.job_id = job_id
  meta.pid = vim.fn.jobpid(job_id)
  log.log("runner.started", {
    job_id = job_id,
    pid = meta.pid,
    command = argv,
    json_mode = json_mode,
  })
  return meta
end

function M.run(opts)
  local config = opts.config
  local argv = opts.argv or build_argv(config, opts.prompt, {
    extra_args = opts.extra_args,
    session_file = opts.session_file,
    force_no_session = opts.force_no_session,
  })
  local callbacks = {
    on_stdout = opts.on_stdout or function() end,
    on_stderr = opts.on_stderr or function() end,
    on_complete = opts.on_complete or function() end,
  }

  return run_job(argv, callbacks)
end

function M.build_argv(config, prompt, opts)
  return build_argv(config, prompt, opts)
end

function M.opencode_continue_session()
  return OPENCODE_CONTINUE_SESSION
end

return M
