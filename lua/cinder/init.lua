local M = {}

function M.setup(_)
  return M
end

function M.hello()
  local message = "hello world"
  print(message)
  return message
end

return M
