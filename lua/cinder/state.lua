local M = {
  namespace = vim.api.nvim_create_namespace("cinder"),
  next_run_id = 1,
  next_session_id = 1,
  runs = {},
  sessions = {},
}

local function now()
  return vim.loop.hrtime()
end

local function sorted_runs()
  local runs = {}

  for _, run in pairs(M.runs) do
    runs[#runs + 1] = run
  end

  table.sort(runs, function(left, right)
    return left.numeric_id < right.numeric_id
  end)

  return runs
end

function M.create_session(bufnr, fields)
  local session_id = vim.b[bufnr].cinder_session_id

  if session_id and M.sessions[session_id] then
    return M.sessions[session_id]
  end

  local numeric_id = M.next_session_id
  session_id = string.format("composer-%d", numeric_id)
  M.next_session_id = numeric_id + 1

  local session = vim.tbl_extend("force", {
    session_id = session_id,
    numeric_id = numeric_id,
    bufnr = bufnr,
    active_run_id = nil,
    profile = nil,
    source_bufnr = nil,
    pending_context = nil,
    transcript = {},
    pending_response = nil,
    spinner_frame = 0,
    spinner_timer = nil,
    draft_lines = { "" },
    status = "idle",
  }, fields or {})

  M.sessions[session_id] = session
  vim.b[bufnr].cinder_session_id = session_id

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      require("cinder.providers").stop_session(session)
      require("cinder.ui").stop_composer_spinner(session)
      M.sessions[session.session_id] = nil
    end,
  })

  return session
end

function M.get_session(session_id)
  return M.sessions[session_id]
end

function M.update_session(session, fields)
  for key, value in pairs(fields or {}) do
    session[key] = value
  end

  return session
end

function M.find_latest_session()
  local latest = nil

  for _, session in pairs(M.sessions) do
    if session.bufnr and vim.api.nvim_buf_is_valid(session.bufnr) then
      if not latest or session.numeric_id > latest.numeric_id then
        latest = session
      end
    end
  end

  return latest
end

function M.create_run(fields)
  local numeric_id = M.next_run_id
  local run_id = tostring(numeric_id)

  M.next_run_id = numeric_id + 1

  local run = vim.tbl_extend("force", {
    id = run_id,
    numeric_id = numeric_id,
    kind = "do",
    status = "queued",
    prompt = "",
    provider = "fake",
    created_at = now(),
    updated_at = now(),
    context = {},
  }, fields or {})

  M.runs[run_id] = run

  if run.session_id and M.sessions[run.session_id] then
    M.sessions[run.session_id].active_run_id = run_id
  end

  return run
end

function M.get_run(run_id)
  return M.runs[tostring(run_id)]
end

function M.list_runs()
  return sorted_runs()
end

function M.get_session_active_run(session_id)
  local session = M.sessions[session_id]

  if not session or not session.active_run_id then
    return nil
  end

  return M.get_run(session.active_run_id)
end

function M.attach_controller(run, controller)
  run.controller = controller
end

function M.update_run(run, fields)
  for key, value in pairs(fields or {}) do
    run[key] = value
  end

  run.updated_at = now()

  if run.session_id and run.status ~= "running" then
    local session = M.sessions[run.session_id]

    if session and session.active_run_id == run.id then
      session.active_run_id = nil
    end
  end

  return run
end

function M.cancel_run(run_id)
  local run = M.get_run(run_id)

  if not run then
    return nil, string.format("unknown run id: %s", tostring(run_id))
  end

  if run.status ~= "queued" and run.status ~= "running" then
    return nil, string.format("run %s is already %s", run.id, run.status)
  end

  if run.controller and run.controller.cancel then
    run.controller.cancel()
    return run
  end

  M.update_run(run, {
    status = "cancelled",
  })

  return run
end

function M.statusline()
  local running = 0

  for _, run in pairs(M.runs) do
    if run.status == "queued" or run.status == "running" then
      running = running + 1
    end
  end

  if running == 0 then
    return ""
  end

  return string.format("Cinder[%d]", running)
end

return M
