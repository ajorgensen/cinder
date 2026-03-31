local M = {}

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
    if argv[index] == "--mode" then
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

local function shell_join(argv)
  local escaped = vim.tbl_map(vim.fn.shellescape, argv)
  return table.concat(escaped, " ")
end

local function write_file(path, lines)
  local file = assert(io.open(path, "w"))
  file:write(table.concat(lines, "\n"))
  file:write("\n")
  file:close()
end

local function build_tmux_script_lines(argv, stdout_file, stderr_file, exit_file)
  return {
    "#!/usr/bin/env bash",
    string.format("%s > >(tee %s) 2> >(tee %s >&2)", shell_join(argv), vim.fn.shellescape(stdout_file), vim.fn.shellescape(stderr_file)),
    "status=$?",
    string.format("printf '%s\\n' \"$status\" > %s", "%s", vim.fn.shellescape(exit_file)),
  }
end

local function write_tmux_script(argv, stdout_file, stderr_file, exit_file)
  local script_file = vim.fn.tempname()
  write_file(script_file, build_tmux_script_lines(argv, stdout_file, stderr_file, exit_file))
  vim.fn.setfperm(script_file, "rwx------")
  return script_file
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
  if vim.fs.basename(config.harness_command) == "pi" then
    local has_model = false
    for index = 1, #argv do
      if argv[index] == "--model" then
        has_model = true
        break
      end
    end
    if not has_model then
      vim.list_extend(argv, { "--model", config.model })
    end
  end
  if opts.session_file then
    vim.list_extend(argv, { "--session", opts.session_file })
  elseif opts.force_no_session then
    local has_session_flag = false
    for _, arg in ipairs(argv) do
      if arg == "--no-session" or arg == "--session" then
        has_session_flag = true
        break
      end
    end
    if not has_session_flag then
      argv[#argv + 1] = "--no-session"
    end
  end
  if opts.extra_args and #opts.extra_args > 0 then
    vim.list_extend(argv, opts.extra_args)
  end
  argv[#argv + 1] = prompt
  return argv
end

local function is_tmux_available()
  return vim.env.TMUX and vim.fn.executable("tmux") == 1
end

local function choose_backend(config)
  if config.execution_mode == "job" then
    return "job"
  end
  if config.execution_mode == "tmux" then
    if not is_tmux_available() then
      error("cinder.nvim could not launch tmux: Neovim is not running inside tmux or tmux is unavailable", 0)
    end
    return "tmux"
  end
  if is_tmux_available() then
    return "tmux"
  end
  return "job"
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
        callbacks.on_stdout(text)
      end
    end,
    on_stderr = function(_, data)
      local text = collect_data(stderr_chunks, data)
      if text then
        callbacks.on_stderr(text)
      end
    end,
    on_exit = function(_, code)
      callbacks.on_complete(finalize_output(vim.tbl_extend("force", meta, {
        code = code,
      }), stdout_chunks, stderr_chunks))
    end,
  })

  if job_id <= 0 then
    error(string.format("cinder.nvim failed to launch %s", argv[1]), 0)
  end

  meta.job_id = job_id
  return meta
end

local function tmux_flag(config)
  if config.tmux.orientation == "horizontal" then
    return "-v"
  end
  return "-h"
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local content = file:read("*a") or ""
  file:close()
  return content
end

local function start_tmux_poll(config, meta, callbacks)
  local timer = assert(vim.uv.new_timer())
  timer:start(config.tmux.poll_interval, config.tmux.poll_interval, vim.schedule_wrap(function()
    local exit_stat = vim.uv.fs_stat(meta.exit_file)
    if not exit_stat then
      return
    end

    timer:stop()
    timer:close()

    local code = tonumber(vim.trim(read_file(meta.exit_file))) or 1
    callbacks.on_complete(finalize_output(vim.tbl_extend("force", meta, {
      code = code,
    }), { read_file(meta.stdout_file) }, { read_file(meta.stderr_file) }))
  end))
end

local function run_tmux(config, argv, callbacks)
  local stdout_file = vim.fn.tempname()
  local stderr_file = vim.fn.tempname()
  local exit_file = vim.fn.tempname()
  local script_file = write_tmux_script(argv, stdout_file, stderr_file, exit_file)

  local command = {
    "tmux",
    "split-window",
    "-P",
    "-F",
    "#{pane_id}",
    tmux_flag(config),
    "-l",
    tostring(config.tmux.size),
    vim.fn.shellescape(script_file),
  }

  local pane_id = vim.trim(vim.fn.system(command))
  if vim.v.shell_error ~= 0 or pane_id == "" then
    error("cinder.nvim could not create a tmux split for the harness run", 0)
  end

  local meta = {
    backend = "tmux",
    command = argv,
    pane_id = pane_id,
    stdout_file = stdout_file,
    stderr_file = stderr_file,
    exit_file = exit_file,
    script_file = script_file,
  }

  start_tmux_poll(config, meta, callbacks)
  return meta
end

function M.run(opts)
  local config = opts.config
  local argv = opts.argv or build_argv(config, opts.prompt, {
    extra_args = opts.extra_args,
    session_file = opts.session_file,
    force_no_session = opts.force_no_session,
  })
  local backend = choose_backend(config)
  local callbacks = {
    on_stdout = opts.on_stdout or function() end,
    on_stderr = opts.on_stderr or function() end,
    on_complete = opts.on_complete or function() end,
  }

  if backend == "tmux" then
    return run_tmux(config, argv, callbacks)
  end

  return run_job(argv, callbacks)
end

function M.choose_backend(config)
  return choose_backend(config)
end

function M.build_argv(config, prompt, opts)
  return build_argv(config, prompt, opts)
end

function M._build_tmux_script_lines(argv, stdout_file, stderr_file, exit_file)
  return build_tmux_script_lines(argv, stdout_file, stderr_file, exit_file)
end

return M
