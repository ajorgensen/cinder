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

function M.build_ask_prompt(prompt, _context)
  local lines = {}

  append_block(lines, "User request:", {
    prompt,
  })

  push(lines, "Use any file paths or code snippets in the request as context if relevant.")

  return table.concat(lines, "\n")
end

return M
