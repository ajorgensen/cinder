local M = {}

local function split_lines(text)
  return vim.split(text, "\n", { plain = true, trimempty = false })
end

local function has_task(task)
  return type(task) == "string" and vim.trim(task) ~= ""
end

function M.compose(context, task)
  local task_present = has_task(task)

  if not task_present and not (context and context.selection) then
    error("cinder.nvim requires a non-empty task", 0)
  end

  if not context or not context.file_path then
    return task
  end

  local lines = {
    "You are working in a Neovim editing session.",
    "",
    string.format("Current file: %s", context.file_path),
  }

  if context.selection then
    lines[#lines + 1] = string.format(
      "Selected range: %d-%d",
      context.selection.start_line,
      context.selection.end_line
    )
    lines[#lines + 1] = "Selected text:"
    vim.list_extend(lines, split_lines(context.selection.text))
  else
    lines[#lines + 1] = string.format("Cursor line: %d", context.cursor_line)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "You may inspect other files in the repository if needed."

  if task_present then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Task:"
    vim.list_extend(lines, split_lines(task))
  elseif context.selection then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "No separate task was provided. Treat the selected text as the primary request."
  end

  return table.concat(lines, "\n")
end

function M.compose_replacement(context, task)
  if not context or not context.selection then
    error("cinder.nvim replacement mode requires a selection", 0)
  end

  local task_present = has_task(task)
  local lines = {
    "You are generating replacement text for a selected range in a Neovim buffer.",
    "",
  }

  if context.file_path then
    lines[#lines + 1] = string.format("Current file: %s", context.file_path)
  end

  lines[#lines + 1] = string.format(
    "Selected range: %d-%d",
    context.selection.start_line,
    context.selection.end_line
  )
  lines[#lines + 1] = "Selected text:"
  vim.list_extend(lines, split_lines(context.selection.text))
  lines[#lines + 1] = ""

  if task_present then
    lines[#lines + 1] = "Instruction:"
    vim.list_extend(lines, split_lines(task))
  else
    lines[#lines + 1] = "Instruction:"
    lines[#lines + 1] = "Treat the selected text itself as the request and replace only that selected range."
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Return only the replacement text for the selected range."
  lines[#lines + 1] = "Do not include markdown fences, explanations, or surrounding file content."
  lines[#lines + 1] = "Preserve indentation when appropriate."

  return table.concat(lines, "\n")
end

return M
