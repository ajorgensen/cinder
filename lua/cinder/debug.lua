local M = {}

local state = {
  log_path = nil,
}

local function ensure_run_log_dir()
  local dir = vim.fn.stdpath("state") .. "/cinder-runs"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function timestamp()
  return os.date("!%Y-%m-%d %H:%M:%S UTC")
end

local function ensure_log_path()
  if state.log_path then
    return state.log_path
  end

  local dir = vim.fn.stdpath("state")
  vim.fn.mkdir(dir, "p")
  state.log_path = dir .. "/cinder.log"
  return state.log_path
end

local function encode(payload)
  local ok, encoded = pcall(vim.json.encode, payload)
  if ok then
    return encoded
  end
  return vim.inspect(payload)
end

function M.path()
  return ensure_log_path()
end

function M.log(event, payload)
  local file = io.open(ensure_log_path(), "a")
  if not file then
    return
  end

  file:write(string.format("%s %s %s\n", timestamp(), event, encode(payload or {})))
  file:close()
end

function M.stream_path(run_id)
  return string.format("%s/run-%d.log", ensure_run_log_dir(), run_id)
end

function M.start_stream(run_id, payload)
  local path = M.stream_path(run_id)
  os.remove(path)
  local file = io.open(path, "a")
  if not file then
    return path
  end

  file:write(string.format("%s stream.start %s\n", timestamp(), encode(payload or {})))
  file:close()
  return path
end

function M.append_stream(run_id, source, text)
  if type(text) ~= "string" or text == "" then
    return
  end

  local file = io.open(M.stream_path(run_id), "a")
  if not file then
    return
  end

  local parts = vim.split(text:gsub("\r", ""), "\n", { plain = true, trimempty = false })
  for _, part in ipairs(parts) do
    if part ~= "" then
      file:write(string.format("%s [%s] %s\n", timestamp(), source, part))
    end
  end
  file:close()
end

function M.reset_for_tests()
  local path = ensure_log_path()
  os.remove(path)
end

return M
