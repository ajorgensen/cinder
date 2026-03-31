local M = {}

local state = {
  result_bufnr = nil,
  result_winid = nil,
  result_session_file = nil,
  result_session_enabled = false,
  result_source_bufnr = nil,
  prompt_bufnr = nil,
  prompt_winid = nil,
  prompt_header_lines = 0,
  prompt_context = nil,
}

local function is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function is_valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function name_matches(actual, expected)
  return actual == expected or vim.fs.basename(actual) == expected
end

local function find_named_buffer(name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and name_matches(vim.api.nvim_buf_get_name(bufnr), name) then
      return bufnr
    end
  end

  return nil
end

local function configure_scratch_buffer(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"
end

local function configure_long_prompt_buffer(bufnr)
  configure_scratch_buffer(bufnr)
  vim.bo[bufnr].filetype = "gitcommit"
end

local function prompt_header_lines(context)
  local lines = {
    "Write the task below.",
    "Submit with <C-s> or :CinderPromptSubmit.",
    "Cancel with q or :CinderPromptCancel.",
  }

  if context and context.file_path then
    lines[#lines + 1] = string.format("Context file: %s", context.file_path)
  else
    lines[#lines + 1] = "Context file: none (sending only the task text)"
  end

  if context and context.selection then
    lines[#lines + 1] = string.format("Selected range: %d-%d", context.selection.start_line, context.selection.end_line)
    lines[#lines + 1] = "Selected text:"
    vim.list_extend(lines, vim.split(context.selection.text, "\n", { plain = true, trimempty = false }))
  end

  return lines
end

local function find_section_line(bufnr, heading)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for index, line in ipairs(lines) do
    if line == heading then
      return index
    end
  end

  return nil
end

local function insert_before_draft(bufnr, lines)
  local draft_line = find_section_line(bufnr, "## Draft") or (#vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) + 1)
  vim.api.nvim_buf_set_lines(bufnr, draft_line - 1, draft_line - 1, false, lines)
end

local function set_lines(bufnr, lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

local function append_lines(bufnr, lines)
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
end

function M.ensure_result_buffer(config)
  if not is_valid_buffer(state.result_bufnr) then
    state.result_bufnr = find_named_buffer(config.result_buffer.name) or vim.api.nvim_create_buf(false, true)
  end

  configure_scratch_buffer(state.result_bufnr)
  if not name_matches(vim.api.nvim_buf_get_name(state.result_bufnr), config.result_buffer.name) then
    vim.api.nvim_buf_set_name(state.result_bufnr, config.result_buffer.name)
  end
  return state.result_bufnr
end

local function show_result_buffer(config)
  local bufnr = M.ensure_result_buffer(config)

  if is_valid_window(state.result_winid) and vim.api.nvim_win_get_buf(state.result_winid) == bufnr then
    return state.result_winid
  end

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if is_valid_window(winid) then
      state.result_winid = winid
      return winid
    end
  end

  local current_win = vim.api.nvim_get_current_win()
  vim.cmd(string.format("botright %dsplit", config.result_buffer.height))
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  state.result_winid = winid

  if not config.result_buffer.enter and is_valid_window(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end

  return winid
end

local function ensure_prompt_buffer(config)
  if not is_valid_buffer(state.prompt_bufnr) then
    state.prompt_bufnr = find_named_buffer(config.long_prompt_buffer.name) or vim.api.nvim_create_buf(false, true)
  end

  configure_long_prompt_buffer(state.prompt_bufnr)
  if not name_matches(vim.api.nvim_buf_get_name(state.prompt_bufnr), config.long_prompt_buffer.name) then
    vim.api.nvim_buf_set_name(state.prompt_bufnr, config.long_prompt_buffer.name)
  end

  return state.prompt_bufnr
end

local function show_prompt_buffer(config)
  local bufnr = ensure_prompt_buffer(config)

  if is_valid_window(state.prompt_winid) and vim.api.nvim_win_get_buf(state.prompt_winid) == bufnr then
    vim.api.nvim_set_current_win(state.prompt_winid)
    return state.prompt_winid
  end

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if is_valid_window(winid) then
      state.prompt_winid = winid
      vim.api.nvim_set_current_win(winid)
      return winid
    end
  end

  vim.cmd(string.format("botright %dsplit", config.long_prompt_buffer.height))
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  state.prompt_winid = winid
  return winid
end

function M.open_result_buffer(config)
  local bufnr = M.ensure_result_buffer(config)
  if config.result_buffer.open then
    show_result_buffer(config)
  end
  vim.keymap.set("n", "<C-s>", function()
    require("cinder").continue_session()
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("i", "<C-s>", function()
    require("cinder").continue_session()
  end, { buffer = bufnr, silent = true })
  return bufnr
end

function M.prepare_result_buffer(config, prompt_kind)
  local bufnr = M.ensure_result_buffer(config)
  local timestamp = os.date("!%Y-%m-%d %H:%M:%S UTC")
  set_lines(bufnr, {
    string.format("# %s", config.result_buffer.name),
    "",
    string.format("Status: running (%s)", prompt_kind),
    string.format("Session: %s", state.result_session_enabled and state.result_session_file or "off"),
    string.format("Updated: %s", timestamp),
    "",
    "## Transcript",
    "",
    "## Draft",
    "",
  })

  M.open_result_buffer(config)

  return bufnr
end

function M.append_transcript(bufnr, role, text)
  if not is_valid_buffer(bufnr) or type(text) ~= "string" or text == "" then
    return
  end

  insert_before_draft(bufnr, vim.list_extend({ string.format("## %s", role) }, vim.list_extend(vim.split(text:gsub("\r", ""), "\n", { plain = true, trimempty = false }), { "" })))
end

function M.get_result_draft_text()
  if not is_valid_buffer(state.result_bufnr) then
    return nil
  end

  local draft_line = find_section_line(state.result_bufnr, "## Draft")
  if not draft_line then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(state.result_bufnr, draft_line, -1, false)
  return vim.trim(table.concat(lines, "\n"))
end

function M.set_result_draft(text)
  if not is_valid_buffer(state.result_bufnr) then
    return
  end

  local draft_line = find_section_line(state.result_bufnr, "## Draft")
  if not draft_line then
    return
  end

  vim.api.nvim_buf_set_lines(
    state.result_bufnr,
    draft_line,
    -1,
    false,
    text == "" and { "" } or vim.split(text, "\n", { plain = true, trimempty = false })
  )
end

function M.set_result_session(session_file, source_bufnr)
  state.result_session_file = session_file
  state.result_session_enabled = session_file ~= nil
  state.result_source_bufnr = source_bufnr
  if is_valid_buffer(state.result_bufnr) then
    vim.api.nvim_buf_set_lines(state.result_bufnr, 3, 4, false, {
      string.format("Session: %s", state.result_session_enabled and state.result_session_file or "off"),
    })
  end
end

function M.get_result_session()
  if not state.result_session_enabled then
    return nil
  end

  return {
    session_file = state.result_session_file,
    source_bufnr = state.result_source_bufnr,
  }
end

function M.reset_result_session()
  state.result_session_file = nil
  state.result_session_enabled = false
  state.result_source_bufnr = nil
  if is_valid_buffer(state.result_bufnr) then
    vim.api.nvim_buf_set_lines(state.result_bufnr, 3, 4, false, { "Session: off" })
  end
end

function M.append_output(bufnr, text, opts)
  opts = opts or {}
  if not is_valid_buffer(bufnr) or not text or text == "" then
    return
  end

  local prefix = opts.prefix or ""
  local lines = vim.split(text:gsub("\r", ""), "\n", { plain = true, trimempty = false })
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  if #lines == 0 then
    return
  end

  for index, line in ipairs(lines) do
    lines[index] = prefix .. line
  end

  vim.schedule(function()
    if is_valid_buffer(bufnr) then
      insert_before_draft(bufnr, lines)
    end
  end)
end

function M.append_summary(bufnr, summary)
  if not is_valid_buffer(bufnr) then
    return
  end

  vim.schedule(function()
    if is_valid_buffer(bufnr) then
      insert_before_draft(bufnr, { "", summary })
    end
  end)
end

function M.set_status(bufnr, status)
  if not is_valid_buffer(bufnr) then
    return
  end

  vim.schedule(function()
    if not is_valid_buffer(bufnr) then
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { string.format("Status: %s", status) })
    vim.api.nvim_buf_set_lines(bufnr, 4, 5, false, { string.format("Updated: %s", os.date("!%Y-%m-%d %H:%M:%S UTC")) })
  end)
end

function M.open_long_prompt(config, context)
  local bufnr = ensure_prompt_buffer(config)
  state.prompt_bufnr = bufnr
  state.prompt_context = context

  show_prompt_buffer(config)

  vim.bo[bufnr].modifiable = true
  local header = prompt_header_lines(context)
  state.prompt_header_lines = #header
  header[#header + 1] = ""
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, header)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_win_set_cursor(0, { state.prompt_header_lines + 1, 0 })

  vim.keymap.set("n", "<C-s>", function()
    require("cinder").submit_long_prompt()
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("i", "<C-s>", function()
    require("cinder").submit_long_prompt()
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "q", function()
    require("cinder").cancel_long_prompt()
  end, { buffer = bufnr, silent = true })

  return bufnr
end

function M.get_long_prompt_text()
  if not is_valid_buffer(state.prompt_bufnr) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(state.prompt_bufnr, state.prompt_header_lines, -1, false)
  return vim.trim(table.concat(lines, "\n"))
end

function M.get_long_prompt_context()
  return state.prompt_context
end

function M.close_long_prompt()
  if is_valid_buffer(state.prompt_bufnr) then
    vim.api.nvim_buf_delete(state.prompt_bufnr, { force = true })
  end

  state.prompt_bufnr = nil
  state.prompt_winid = nil
  state.prompt_context = nil
  state.prompt_header_lines = 0
end

function M.state()
  return state
end

return M
