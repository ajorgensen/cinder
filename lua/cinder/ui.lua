local state = require("cinder.state")

local M = {}

local DRAFT_LABEL = "Draft (use :Cinder send):"

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

local function render_composer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local session_id = vim.b[bufnr].cinder_session_id or "unassigned"
  local session = session_id ~= "unassigned" and state.get_session(session_id) or nil
  local provider = session and session.provider or "unknown"
  local model = session and session.model or "-"
  local status = session and session.status or "idle"
  local transcript = session and session.transcript or {}
  local draft_lines = session and session.draft_lines or { "" }
  local lines = {
    "Cinder",
    string.format("Session: %s", session_id),
    string.format("Backend: %s/%s", provider, model),
    string.format("Status: %s", status),
    "",
    "Transcript:",
  }

  for _, line in ipairs(transcript) do
    lines[#lines + 1] = line
  end

  if #transcript == 0 then
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
  render_composer(bufnr)
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
