local M = {}

local function push(lines, value)
  lines[#lines + 1] = value
end

local function append_block(lines, title, body_lines)
  push(lines, title)

  for _, line in ipairs(body_lines) do
    push(lines, line)
  end

  push(lines, "")
end

function M.build_ask_prompt(prompt, context)
  local lines = {}
  local file_path = context.file_path

  if not file_path or file_path == "" then
    file_path = "[No Name]"
  end

  append_block(lines, "User request:", {
    prompt,
  })

  append_block(lines, "Current file:", {
    file_path,
  })

  if context.selection then
    append_block(lines, string.format(
      "Selected lines (%d-%d):",
      context.selection.start_line,
      context.selection.end_line
    ), context.selection.lines)
  end

  push(lines, "Use the editor context above if it is relevant.")

  return table.concat(lines, "\n")
end

return M
