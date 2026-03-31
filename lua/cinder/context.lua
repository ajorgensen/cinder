local M = {}

local function buf_name(bufnr)
  return vim.api.nvim_buf_get_name(bufnr)
end

local function repo_root(path)
  local start = vim.fs.dirname(path)
  local git_dir = vim.fs.find(".git", {
    upward = true,
    path = start,
    type = "directory",
  })[1]

  if not git_dir then
    return nil
  end

  return vim.fs.dirname(git_dir)
end

local function relative_path(root, path)
  if not root then
    return path
  end

  local prefix = root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end

  return path
end

local function selection_mode(mode)
  if mode == "V" then
    return "line"
  end
  if mode == vim.api.nvim_replace_termcodes("<C-v>", true, true, true) then
    return "block"
  end
  return "char"
end

local function normalize_marks()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  if start_line == 0 or end_line == 0 then
    return nil
  end

  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  return {
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }
end

local function line_byte_length(bufnr, line_number)
  local line = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1] or ""
  return #line
end

local function get_charwise_text(bufnr, marks)
  local lines = vim.api.nvim_buf_get_text(
    bufnr,
    marks.start_line - 1,
    marks.start_col - 1,
    marks.end_line - 1,
    marks.end_col,
    {}
  )

  return table.concat(lines, "\n")
end

local function get_linewise_text(bufnr, marks)
  local lines = vim.api.nvim_buf_get_lines(bufnr, marks.start_line - 1, marks.end_line, false)
  return table.concat(lines, "\n")
end

local function get_blockwise_text(bufnr, marks)
  local chunks = {}
  for line_number = marks.start_line, marks.end_line do
    local text = vim.api.nvim_buf_get_text(
      bufnr,
      line_number - 1,
      marks.start_col - 1,
      line_number - 1,
      marks.end_col,
      {}
    )
    chunks[#chunks + 1] = text[1] or ""
  end

  return table.concat(chunks, "\n")
end

local function build_selection(bufnr, mode)
  local marks = normalize_marks()
  if not marks then
    return nil
  end

  if mode == "line" then
    marks.start_col = 1
    marks.end_col = line_byte_length(bufnr, marks.end_line)
  end

  local text
  if mode == "line" then
    text = get_linewise_text(bufnr, marks)
  elseif mode == "block" then
    text = get_blockwise_text(bufnr, marks)
  else
    text = get_charwise_text(bufnr, marks)
  end

  return {
    mode = mode,
    start_line = marks.start_line,
    start_col = marks.start_col,
    end_line = marks.end_line,
    end_col = marks.end_col,
    text = text,
  }
end

local function replacement_lines(text)
  if text == "" then
    return {}
  end

  return vim.split(text:gsub("\r", ""), "\n", { plain = true, trimempty = false })
end

function M.collect(opts)
  opts = opts or {}

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local absolute_path = vim.uv.fs_realpath(buf_name(bufnr)) or buf_name(bufnr)
  if absolute_path == "" then
    return nil
  end

  local root = repo_root(absolute_path)
  local mode = opts.visual_mode and selection_mode(opts.visual_mode) or nil
  local selection = opts.visual and build_selection(bufnr, mode or "char") or nil

  return {
    bufnr = bufnr,
    absolute_path = absolute_path,
    file_path = relative_path(root, absolute_path),
    root = root,
    cursor_line = vim.api.nvim_win_get_cursor(0)[1],
    selection = selection,
  }
end

function M.replace_selection(bufnr, selection, text)
  if not selection then
    error("cinder.nvim requires a selection for replacement", 0)
  end

  if selection.mode == "block" then
    error("cinder.nvim replace-selection mode does not support blockwise visual selections", 0)
  end

  local lines = replacement_lines(text)
  if selection.mode == "line" then
    vim.api.nvim_buf_set_lines(bufnr, selection.start_line - 1, selection.end_line, false, lines)
    return
  end

  vim.api.nvim_buf_set_text(
    bufnr,
    selection.start_line - 1,
    selection.start_col - 1,
    selection.end_line - 1,
    selection.end_col,
    lines
  )
end

return M
