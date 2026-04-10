local M = {}

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local function unload(name)
  package.loaded[name] = nil
end

function M.repo_root()
  return repo_root
end

function M.runtime()
  vim.opt.runtimepath:prepend(repo_root)
  vim.cmd.runtime({ "plugin/cinder.lua", bang = true })
end

function M.reload()
  unload("cinder")
  return require("cinder")
end

function M.reset()
  pcall(vim.cmd, "silent! %bwipeout!")
  pcall(vim.cmd, "enew")
  pcall(vim.cmd, "silent! delcommand CinderHello")
  pcall(vim.cmd, "silent! delcommand CinderPrompt")
  pcall(vim.cmd, "silent! delcommand CinderPromptLong")
  pcall(vim.cmd, "silent! delcommand CinderPromptSubmit")
  pcall(vim.cmd, "silent! delcommand CinderPromptCancel")
  pcall(vim.cmd, "silent! delcommand CinderContinue")
  pcall(vim.cmd, "silent! delcommand CinderJobs")
  pcall(vim.cmd, "silent! delcommand CinderLog")
  pcall(vim.cmd, "silent! delcommand CinderTail")
  pcall(vim.cmd, "silent! delcommand CinderSessionReset")
  pcall(vim.cmd, "silent! delcommand CinderModel")
  pcall(vim.cmd, "silent! delcommand CinderModelSelect")
  M.runtime()
  return M.reload()
end

function M.expect(condition, message)
  if not condition then
    error(message or "expectation failed", 0)
  end
end

function M.eq(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)), 0)
  end
end

return M
