local doctor = require("cinder.doctor")
local providers = require("cinder.providers")
local prompt_builder = require("cinder.prompt_builder")
local state = require("cinder.state")
local ui = require("cinder.ui")

local M = {}

local subcommands = { "do", "send", "runs", "kill", "doctor" }

local MAX_INLINE_CONTEXT_LINES = 10

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

local function join_args(args)
  return table.concat(args or {}, " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function capture_context_from_buf(bufnr, opts)
  opts = opts or {}

  local context = {
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
    file_path = vim.api.nvim_buf_get_name(bufnr),
    row = 0,
  }

  if vim.api.nvim_buf_is_valid(bufnr) then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    context.row = math.min(math.max((opts.line1 or 1) - 1, 0), math.max(line_count - 1, 0))
  end

  if opts.range and opts.range > 0 then
    context.selection = {
      start_line = opts.line1,
      end_line = opts.line2,
      lines = vim.api.nvim_buf_get_lines(bufnr, opts.line1 - 1, opts.line2, false),
    }
    context.row = opts.line1 - 1
  end

  return context
end

local function capture_context(opts)
  return capture_context_from_buf(vim.api.nvim_get_current_buf(), opts)
end

local function format_context_block(context)
  if not context then
    return nil
  end

  local file_path = context.file_path or ""

  if file_path == "" and not context.selection then
    return nil
  end

  if file_path == "" then
    file_path = "[No Name]"
  else
    file_path = vim.fn.fnamemodify(file_path, ":.")
  end

  if not context.selection then
    return { file_path }
  end

  local header = string.format(
    "%s:%d-%d",
    file_path,
    context.selection.start_line,
    context.selection.end_line
  )

  if #context.selection.lines > MAX_INLINE_CONTEXT_LINES then
    return { header }
  end

  local block = { header }

  for _, line in ipairs(context.selection.lines) do
    block[#block + 1] = line
  end

  return block
end

local function stop_composer_spinner(active_run)
  if active_run.kind ~= "composer" then
    return
  end

  local session = state.get_session(active_run.session_id)

  if session then
    ui.stop_composer_spinner(session)
  end
end

local function callbacks_for(run)
  return {
    on_progress = function(active_run, frame)
      if active_run.kind == "composer" then
        ui.update_composer_header(active_run.display_bufnr, string.format("running %s", frame))
      else
        state.update_run(active_run, {
          status = "running",
        })
        ui.set_do_progress(active_run, string.format("running %s", frame))
      end
    end,
    on_message_delta = function(active_run, text)
      if active_run.kind == "composer" then
        ui.set_composer_pending_response(active_run.display_bufnr, text)
      end
    end,
    on_message_final = function(active_run, text)
      ui.append_composer_response(active_run.display_bufnr, text)
    end,
    on_complete = function(active_run, result)
      state.update_run(active_run, {
        status = "done",
        result = result,
      })

      if active_run.kind == "composer" then
        stop_composer_spinner(active_run)
        ui.update_composer_header(active_run.display_bufnr, "done")
      else
        ui.set_do_progress(active_run, "done", "String")
        vim.defer_fn(function()
          ui.clear_do_progress(active_run)
        end, 120)
        notify(string.format("Cinder run %s finished", active_run.id))
      end
    end,
    on_cancelled = function(active_run)
      state.update_run(active_run, {
        status = "cancelled",
      })

      if active_run.kind == "composer" then
        stop_composer_spinner(active_run)
        ui.clear_composer_pending_response(active_run.display_bufnr)
        ui.update_composer_header(active_run.display_bufnr, "cancelled")
        ui.append_composer_response(active_run.display_bufnr, "[cancelled]")
      else
        ui.clear_do_progress(active_run)
        notify(string.format("Cinder run %s cancelled", active_run.id), vim.log.levels.WARN)
      end
    end,
    on_error = function(active_run, message)
      state.update_run(active_run, {
        status = "failed",
        error = message,
      })

      if active_run.kind == "composer" then
        stop_composer_spinner(active_run)
        ui.clear_composer_pending_response(active_run.display_bufnr)
        ui.update_composer_header(active_run.display_bufnr, "failed")
        ui.append_composer_response(active_run.display_bufnr, string.format("[error] %s", message))
      else
        ui.clear_do_progress(active_run)
        notify(string.format("Cinder run %s failed: %s", active_run.id, message), vim.log.levels.ERROR)
      end
    end,
  }
end

local function start_run(run)
  state.update_run(run, {
    status = "running",
  })

  local controller = providers.start(run, callbacks_for(run))
  state.attach_controller(run, controller)

  return run
end

local function ensure_composer_buffer(opts)
  opts = opts or {}

  local current_buf = vim.api.nvim_get_current_buf()
  local source_bufnr = opts.source_bufnr or current_buf

  if vim.b[current_buf].cinder_session_id ~= nil then
    local session = state.get_session(vim.b[current_buf].cinder_session_id)

    if session and source_bufnr ~= current_buf then
      state.update_session(session, {
        source_bufnr = source_bufnr,
        pending_context = opts.context or session.pending_context,
      })
    elseif session and opts.context and opts.context.selection then
      state.update_session(session, {
        pending_context = opts.context,
      })
    end

    return current_buf
  end

  local existing = state.find_latest_session()

  if existing then
    state.update_session(existing, {
      source_bufnr = source_bufnr,
      pending_context = opts.context or existing.pending_context,
    })
    ui.show_composer_buffer(existing.bufnr)
    return existing.bufnr
  end

  local profile = providers.resolve("ask")
  local display_bufnr = ui.open_composer_buffer()

  state.create_session(display_bufnr, {
    provider = profile.provider,
    model = profile.model,
    source_bufnr = source_bufnr,
    pending_context = opts.context,
  })
  ui.update_composer_header(display_bufnr, "idle")

  return display_bufnr
end

local function open_composer(opts)
  local display_bufnr = ensure_composer_buffer(opts)
  local context = opts and opts.context
  local from_composer = context and context.bufnr == display_bufnr
  local block = not from_composer and format_context_block(context) or nil

  if block then
    ui.append_to_composer_draft(display_bufnr, block)

    local session = state.get_session(vim.b[display_bufnr].cinder_session_id)

    if session and session.pending_context then
      session.pending_context.selection = nil
    end
  end
end

local function run_composer_prompt(prompt, source_context, display_bufnr, source_bufnr)
  if prompt == "" then
    notify("prompt is empty", vim.log.levels.WARN)
    return
  end

  local session = state.get_session(vim.b[display_bufnr].cinder_session_id)

  if not session then
    notify("no active composer session", vim.log.levels.ERROR)
    return
  end

  if state.get_session_active_run(session.session_id) then
    notify("a composer request is already running in this session", vim.log.levels.WARN)
    return
  end

  state.update_session(session, {
    source_bufnr = source_bufnr or session.source_bufnr,
    pending_context = nil,
  })

  ui.update_composer_header(display_bufnr, "running")
  ui.append_composer_prompt(display_bufnr, prompt)
  ui.start_composer_spinner(display_bufnr)

  local run = state.create_run({
    kind = "composer",
    prompt = prompt,
    provider_prompt = prompt_builder.build_ask_prompt(prompt, source_context),
    provider = session.provider,
    model = session.model,
    source_bufnr = source_bufnr or session.source_bufnr,
    display_bufnr = display_bufnr,
    session_id = session.session_id,
    context = source_context,
  })

  start_run(run)
end

local function send_from_composer()
  local display_bufnr = vim.api.nvim_get_current_buf()

  if vim.b[display_bufnr].cinder_session_id == nil then
    notify("open the composer with :Cinder before sending", vim.log.levels.WARN)
    return
  end

  local session = state.get_session(vim.b[display_bufnr].cinder_session_id)

  if not session then
    notify("no active composer session", vim.log.levels.ERROR)
    return
  end

  local prompt = ui.get_composer_draft(display_bufnr)

  if prompt == "" then
    notify("composer draft is empty", vim.log.levels.WARN)
    return
  end

  if state.get_session_active_run(session.session_id) then
    notify("a composer request is already running in this session", vim.log.levels.WARN)
    return
  end

  local source_bufnr = session.source_bufnr or display_bufnr
  local source_context = session.pending_context or capture_context_from_buf(source_bufnr, {})

  ui.clear_composer_draft(display_bufnr)

  return run_composer_prompt(prompt, source_context, display_bufnr, source_bufnr)
end

local function do_task(opts)
  local prompt = join_args(opts.fargs)

  if prompt == "" then
    notify("usage: :Cinder do <prompt>", vim.log.levels.WARN)
    return
  end

  local profile = providers.resolve("inline")
  local run = state.create_run({
    kind = "do",
    prompt = prompt,
    provider = profile.provider,
    model = profile.model,
    source_bufnr = opts.source_bufnr,
    display_bufnr = opts.source_bufnr,
    context = opts.context,
  })

  ui.set_do_progress(run, "queued")
  notify(string.format("Cinder run %s started", run.id))
  start_run(run)
end

local function show_runs()
  ui.open_runs_buffer(state.list_runs())
end

local function show_doctor()
  ui.open_doctor_buffer(doctor.report())
end

local function kill(opts)
  local run_id = opts.fargs and opts.fargs[1]

  if (not run_id or run_id == "") and opts.source_bufnr and vim.b[opts.source_bufnr].cinder_session_id then
    local session_id = vim.b[opts.source_bufnr].cinder_session_id
    local active_run = state.get_session_active_run(session_id)
    run_id = active_run and active_run.id or nil
  end

  if not run_id or run_id == "" then
    notify("usage: :Cinder kill <run_id>", vim.log.levels.WARN)
    return
  end

  local _, err = state.cancel_run(run_id)

  if err then
    notify(err, vim.log.levels.WARN)
  end
end

function M.complete(arglead, cmdline, _)
  if cmdline:match("^%s*%S+%s+kill%s+") then
    local matches = {}

    for _, run in ipairs(state.list_runs()) do
      if vim.startswith(run.id, arglead) then
        matches[#matches + 1] = run.id
      end
    end

    return matches
  end

  local matches = {}

  for _, subcommand in ipairs(subcommands) do
    if vim.startswith(subcommand, arglead) then
      matches[#matches + 1] = subcommand
    end
  end

  return matches
end

function M.execute(subcommand, opts)
  local command_opts = vim.tbl_extend("force", {
    fargs = {},
    source_bufnr = vim.api.nvim_get_current_buf(),
    context = capture_context(opts),
  }, opts or {})

  if subcommand == "send" then
    return send_from_composer()
  end

  if subcommand == "do" then
    return do_task(command_opts)
  end

  if subcommand == "runs" then
    return show_runs()
  end

  if subcommand == "kill" then
    return kill(command_opts)
  end

  if subcommand == "doctor" then
    return show_doctor()
  end

  notify(string.format("unknown subcommand: %s", tostring(subcommand)), vim.log.levels.ERROR)
end

function M.dispatch(opts)
  local fargs = vim.deepcopy(opts.fargs or {})
  local subcommand = table.remove(fargs, 1)

  if not subcommand or subcommand == "" then
    return open_composer({
      source_bufnr = vim.api.nvim_get_current_buf(),
      context = capture_context(opts),
    })
  end

  local forwarded = vim.tbl_extend("force", opts, {
    fargs = fargs,
  })

  return M.execute(subcommand, forwarded)
end

return M
