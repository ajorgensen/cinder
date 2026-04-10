local M = {}
local log = require("cinder.debug")

local state = {
  next_id = 1,
  runs = {},
  watchdog = nil,
}

local WATCHDOG_INTERVAL = 2000

local function timestamp()
  return os.date("!%Y-%m-%d %H:%M:%S UTC")
end

local function find_run(id)
  for _, run in ipairs(state.runs) do
    if run.id == id then
      return run
    end
  end

  return nil
end

local function command_text(command)
  if type(command) ~= "table" or vim.tbl_isempty(command) then
    return nil
  end

  return table.concat(command, " ")
end

local function touch(run)
  run.updated_at = timestamp()
  return run
end

local function append_detail(lines, label, value)
  if value == nil then
    return
  end

  local parts = vim.split(tostring(value), "\n", { plain = true, trimempty = false })
  lines[#lines + 1] = string.format("  %s%s", label, parts[1] or "")
  for index = 2, #parts do
    lines[#lines + 1] = string.format("  %s", parts[index])
  end
end

local function is_active_status(status)
  return status == "starting" or status == "running"
end

local function has_active_runs()
  for _, run in ipairs(state.runs) do
    if is_active_status(run.status) then
      return true
    end
  end

  return false
end

local function pid_alive(pid)
  if not pid or pid <= 0 then
    return nil
  end

  local ok, err = pcall(vim.uv.kill, pid, 0)
  if ok then
    return true
  end
  if type(err) == "string" and err:find("ESRCH", 1, true) then
    return false
  end
  return nil
end

local function stop_watchdog()
  if not state.watchdog then
    return
  end

  state.watchdog:stop()
  state.watchdog:close()
  state.watchdog = nil
end

local function finish_run(run, status, opts)
  opts = opts or {}
  run.status = status
  run.code = opts.code
  run.error = opts.error or run.error
  run.completed_at = timestamp()
  return touch(run)
end

function M.create(opts)
  local run = {
    id = state.next_id,
    prompt_kind = opts.prompt_kind,
    result_bufnr = opts.result_bufnr,
    stream_path = opts.stream_path,
    status = "starting",
    created_at = timestamp(),
    updated_at = timestamp(),
    completed_at = nil,
    command = opts.command,
    job_id = nil,
    code = nil,
    error = nil,
  }

  state.next_id = state.next_id + 1
  table.insert(state.runs, 1, run)
  return vim.deepcopy(run)
end

function M.mark_running(id, meta)
  local run = find_run(id)
  if not run then
    return nil
  end

  run.status = "running"
  run.job_id = meta.job_id
  run.pid = meta.pid or run.pid
  run.command = meta.command or run.command
  run.backend = meta.backend
  M.ensure_watchdog()
  return vim.deepcopy(touch(run))
end

function M.set_stream_path(id, path)
  local run = find_run(id)
  if not run then
    return nil
  end

  run.stream_path = path
  return vim.deepcopy(touch(run))
end

function M.mark_launch_failed(id, err)
  local run = find_run(id)
  if not run then
    return nil
  end

  run.status = "launch_failed"
  run.error = err
  run.completed_at = timestamp()
  return vim.deepcopy(touch(run))
end

function M.mark_complete(id, meta)
  local run = find_run(id)
  if not run then
    return nil
  end

  finish_run(run, meta.code == 0 and "completed" or "failed", {
    code = meta.code,
  })
  run.job_id = meta.job_id or run.job_id
  run.pid = meta.pid or run.pid
  run.command = meta.command or run.command
  if not has_active_runs() then
    stop_watchdog()
  end
  return vim.deepcopy(run)
end

function M.reconcile(log_heartbeat)
  for _, run in ipairs(state.runs) do
    if is_active_status(run.status) and run.job_id then
      local result = vim.fn.jobwait({ run.job_id }, 0)[1]
      if log_heartbeat then
        log.log("jobs.watchdog", {
          run_id = run.id,
          job_id = run.job_id,
          pid = run.pid,
          status = run.status,
          jobwait = result,
          pid_alive = pid_alive(run.pid),
        })
      end
      if result == -1 then
      elseif result == -3 then
        finish_run(run, "lost", {
          error = "Job is no longer tracked by Neovim",
        })
        log.log("jobs.reconciled", {
          run_id = run.id,
          job_id = run.job_id,
          pid = run.pid,
          status = run.status,
          error = run.error,
        })
      else
        finish_run(run, result == 0 and "completed" or "failed", {
          code = result,
        })
        log.log("jobs.reconciled", {
          run_id = run.id,
          job_id = run.job_id,
          pid = run.pid,
          status = run.status,
          code = run.code,
        })
      end
    end
  end

  if not has_active_runs() then
    stop_watchdog()
  end

  return M.list()
end

function M.ensure_watchdog()
  if state.watchdog or not has_active_runs() then
    return
  end

  state.watchdog = assert(vim.uv.new_timer())
  state.watchdog:start(WATCHDOG_INTERVAL, WATCHDOG_INTERVAL, vim.schedule_wrap(function()
    M.reconcile(true)
  end))
end

function M.list()
  return vim.deepcopy(state.runs)
end

function M.summary()
  M.reconcile()
  local running = 0
  local completed = 0
  local failed = 0
  local launch_failed = 0
  local lost = 0

  for _, run in ipairs(state.runs) do
    if is_active_status(run.status) then
      running = running + 1
    elseif run.status == "completed" then
      completed = completed + 1
    elseif run.status == "failed" then
      failed = failed + 1
    elseif run.status == "launch_failed" then
      launch_failed = launch_failed + 1
    elseif run.status == "lost" then
      lost = lost + 1
    end
  end

  return {
    running = running,
    completed = completed,
    failed = failed,
    launch_failed = launch_failed,
    lost = lost,
    total = #state.runs,
  }
end

function M.render_lines()
  local summary = M.summary()
  local lines = {
    "# Cinder Jobs",
    "",
    string.format("Updated: %s", timestamp()),
     string.format("Running: %d", summary.running),
     string.format("Completed: %d", summary.completed),
    string.format("Failed: %d", summary.failed + summary.launch_failed + summary.lost),
     string.format("Total: %d", summary.total),
    "",
    "## Runs",
    "",
  }

  if #state.runs == 0 then
    lines[#lines + 1] = "No Cinder jobs yet."
    return lines
  end

  for _, run in ipairs(state.runs) do
    lines[#lines + 1] = string.format("- [%s] run %d", run.status, run.id)
    append_detail(lines, "Prompt: ", run.prompt_kind or "unknown")
    if run.job_id then
      append_detail(lines, "Job ID: ", run.job_id)
    end
    if run.pid then
      append_detail(lines, "PID: ", run.pid)
    end
    if run.result_bufnr then
      append_detail(lines, "Result buffer: ", run.result_bufnr)
    end
    append_detail(lines, "Started: ", run.created_at)
    if run.completed_at then
      append_detail(lines, "Completed: ", run.completed_at)
    end
    if run.code ~= nil then
      append_detail(lines, "Exit code: ", run.code)
    end
    if run.stream_path then
      append_detail(lines, "Stream log: ", run.stream_path)
    end
    if run.error then
      append_detail(lines, "Error: ", run.error)
    end
    if run.command then
      append_detail(lines, "Command: ", command_text(run.command))
    end
    lines[#lines + 1] = ""
  end

  return lines
end

function M.latest()
  return state.runs[1] and vim.deepcopy(state.runs[1]) or nil
end

function M.reset()
  stop_watchdog()
  state.next_id = 1
  state.runs = {}
end

return M
