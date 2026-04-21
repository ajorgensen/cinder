local state = require("cinder.state")

local M = {}

local DRAFT_LABEL = "Draft (use :Cinder send):"
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_INTERVAL_MS = 80

local function scratch_buffer(name, filetype, opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", opts.bufhidden or "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", filetype, { buf = bufnr })
  vim.api.nvim_buf_set_name(bufnr, string.format("%s/%d", name, vim.loop.hrtime()))

  return bufnr
end

local function append_lines(bufnr, lines)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
end

local function split_text(text)
  return vim.split(text, "\n", { plain = true })
end

local function find_draft_start(lines)
  for index, line in ipairs(lines) do
    if line == DRAFT_LABEL then
      return index + 1
    end
  end

  return nil
end

local function status_line(session)
  local status = session and session.status or "idle"

  if session and session.spinner_timer then
    local frame = SPINNER_FRAMES[(session.spinner_frame or 0) + 1] or SPINNER_FRAMES[1]
    return string.format("Status: %s %s", frame, status)
  end

  return string.format("Status: %s", status)
end

local function render_composer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local session_id = vim.b[bufnr].cinder_session_id or "unassigned"
  local session = session_id ~= "unassigned" and state.get_session(session_id) or nil
  local provider = session and session.provider or "unknown"
  local model = session and session.model or "-"
  local transcript = session and session.transcript or {}
  local draft_lines = session and session.draft_lines or { "" }
  local pending_response = session and session.pending_response or nil
  local lines = {
    "Cinder",
    string.format("Session: %s", session_id),
    string.format("Backend: %s/%s", provider, model),
    status_line(session),
    "",
    "Transcript:",
  }

  for _, line in ipairs(transcript) do
    lines[#lines + 1] = line
  end

  if pending_response and pending_response ~= "" then
    for _, line in ipairs(split_text(pending_response)) do
      lines[#lines + 1] = line
    end

    lines[#lines + 1] = ""
  elseif #transcript == 0 then
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = DRAFT_LABEL

  for _, line in ipairs(draft_lines) do
    lines[#lines + 1] = line
  end

  if #draft_lines == 0 then
    lines[#lines + 1] = ""
  end

  vim.b[bufnr].cinder_rendering = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.b[bufnr].cinder_rendering = false
end

function M.open_composer_buffer()
  local config = require("cinder").get_config()

  vim.cmd(config.ui.composer_open_cmd)

  local bufnr = scratch_buffer("cinder://composer", "cinder", {
    bufhidden = "hide",
  })
  vim.api.nvim_win_set_buf(0, bufnr)
  render_composer(bufnr)

  return bufnr
end

function M.show_composer_buffer(bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  local config = require("cinder").get_config()

  vim.cmd(config.ui.composer_open_cmd)
  vim.api.nvim_win_set_buf(0, bufnr)
end

function M.sync_composer_draft(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].cinder_rendering then
    return
  end

  local session_id = vim.b[bufnr].cinder_session_id

  if not session_id then
    return
  end

  local session = state.get_session(session_id)

  if not session then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local draft_start = find_draft_start(lines)

  if not draft_start then
    return
  end

  session.draft_lines = vim.list_slice(lines, draft_start, #lines)

  if #session.draft_lines == 0 then
    session.draft_lines = { "" }
  end
end

function M.update_composer_header(bufnr, status)
  local session_id = vim.b[bufnr].cinder_session_id

  if session_id then
    local session = state.get_session(session_id)

    if session then
      state.update_session(session, {
        status = status,
      })
    end
  end

  render_composer(bufnr)
end

function M.append_composer_prompt(bufnr, prompt)
  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return
  end

  local lines = split_text(prompt)

  session.transcript[#session.transcript + 1] = string.format("> %s", lines[1] or "")

  for index = 2, #lines do
    session.transcript[#session.transcript + 1] = lines[index]
  end

  session.transcript[#session.transcript + 1] = ""
  render_composer(bufnr)
end

function M.append_composer_response(bufnr, text)
  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return
  end

  local lines = split_text(text)

  for _, line in ipairs(lines) do
    session.transcript[#session.transcript + 1] = line
  end

  session.transcript[#session.transcript + 1] = ""
  session.pending_response = nil
  render_composer(bufnr)
end

function M.set_composer_pending_response(bufnr, text)
  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return
  end

  session.pending_response = text
  render_composer(bufnr)
end

function M.clear_composer_pending_response(bufnr)
  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return
  end

  session.pending_response = nil
  render_composer(bufnr)
end

function M.start_composer_spinner(bufnr)
  local session_id = vim.b[bufnr].cinder_session_id

  if not session_id then
    return
  end

  local session = state.get_session(session_id)

  if not session or session.spinner_timer then
    return
  end

  session.spinner_frame = 0

  local uv = vim.uv or vim.loop
  local timer = uv.new_timer()
  session.spinner_timer = timer

  timer:start(SPINNER_INTERVAL_MS, SPINNER_INTERVAL_MS, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.stop_composer_spinner(session)
      return
    end

    session.spinner_frame = ((session.spinner_frame or 0) + 1) % #SPINNER_FRAMES
    render_composer(bufnr)
  end))
end

function M.stop_composer_spinner(session)
  if type(session) == "number" then
    session = state.get_session(vim.b[session].cinder_session_id)
  end

  if not session or not session.spinner_timer then
    return
  end

  local timer = session.spinner_timer
  session.spinner_timer = nil
  session.spinner_frame = 0

  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end

  if session.bufnr and vim.api.nvim_buf_is_valid(session.bufnr) then
    render_composer(session.bufnr)
  end
end

function M.get_composer_draft(bufnr)
  M.sync_composer_draft(bufnr)

  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return ""
  end

  return table.concat(session.draft_lines or {}, "\n"):gsub("%s+$", "")
end

function M.clear_composer_draft(bufnr)
  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return
  end

  session.draft_lines = { "" }
  render_composer(bufnr)
end

function M.append_to_composer_draft(bufnr, lines)
  if not lines or #lines == 0 then
    return
  end

  M.sync_composer_draft(bufnr)

  local session = state.get_session(vim.b[bufnr].cinder_session_id)

  if not session then
    return
  end

  local draft = session.draft_lines or { "" }
  local is_empty = #draft == 0 or (#draft == 1 and draft[1] == "")

  if is_empty then
    draft = {}
  elseif draft[#draft] ~= "" then
    draft[#draft + 1] = ""
  end

  for _, line in ipairs(lines) do
    draft[#draft + 1] = line
  end

  session.draft_lines = draft
  render_composer(bufnr)
end

function M.set_do_progress(run, text, highlight)
  local bufnr = run.source_bufnr

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local row = run.context.row or math.max(vim.api.nvim_win_get_cursor(0)[1] - 1, 0)

  run.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.namespace, row, 0, {
    id = run.extmark_id,
    virt_text = {
      { string.format("Cinder: %s", text), highlight or "Comment" },
    },
    virt_text_pos = "eol",
  })
end

function M.clear_do_progress(run)
  if run.extmark_id and run.source_bufnr and vim.api.nvim_buf_is_valid(run.source_bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, run.source_bufnr, state.namespace, run.extmark_id)
  end

  run.extmark_id = nil
end

function M.open_runs_buffer(runs)
  local config = require("cinder").get_config()

  vim.cmd(config.ui.runs_open_cmd)

  local bufnr = scratch_buffer("cinder://runs", "cinder-runs")
  vim.api.nvim_win_set_buf(0, bufnr)

  local lines = {
    "Cinder Runs",
    "",
  }

  if vim.tbl_isempty(runs) then
    lines[#lines + 1] = "No runs yet."
  else
    for _, run in ipairs(runs) do
      local prompt = (run.prompt or ""):gsub("%s+", " ")
      lines[#lines + 1] = string.format(
        "[%s] %-9s %-3s %s (%s/%s)",
        run.id,
        run.status,
        run.kind,
        prompt,
        run.provider,
        run.model or "-"
      )
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  return bufnr
end

function M.open_doctor_buffer(lines)
  local config = require("cinder").get_config()

  vim.cmd(config.ui.runs_open_cmd)

  local bufnr = scratch_buffer("cinder://doctor", "cinder-doctor")
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  return bufnr
end

return M
