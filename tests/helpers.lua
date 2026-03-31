local M = {}

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local default_input = vim.ui.input
local default_select = vim.ui.select

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
  unload("cinder.config")
  unload("cinder.context")
  unload("cinder.prompt")
  unload("cinder.runner")
  unload("cinder.ui")
  return require("cinder")
end

function M.reset()
  pcall(vim.cmd, "silent! %bwipeout!")
  pcall(vim.cmd, "enew")
  pcall(vim.cmd, "silent! delcommand CinderPrompt")
  pcall(vim.cmd, "silent! delcommand CinderPromptLong")
  pcall(vim.cmd, "silent! delcommand CinderPromptSubmit")
  pcall(vim.cmd, "silent! delcommand CinderPromptCancel")
  pcall(vim.cmd, "silent! delcommand CinderContinue")
  pcall(vim.cmd, "silent! delcommand CinderSessionReset")
  pcall(vim.cmd, "silent! delcommand CinderModel")
  pcall(vim.cmd, "silent! delcommand CinderModelSelect")
  M.runtime()

  local cinder = M.reload()
  require("cinder.config").reset()
  vim.env.CINDER_TEST_STDOUT = nil
  vim.env.CINDER_TEST_STDERR = nil
  vim.env.CINDER_TEST_EXIT_CODE = nil
  vim.env.CINDER_TEST_EDIT_FILE = nil
  vim.env.CINDER_TEST_EDIT_CONTENT = nil
  vim.env.CINDER_TEST_JSON_TEXT = nil
  vim.env.CINDER_TEST_ECHO_PROMPT = nil
  vim.ui.input = default_input
  vim.ui.select = default_select
  vim.notify = function(...) end
  return cinder
end

function M.make_temp_file(lines)
  local path = vim.fn.tempname() .. ".lua"
  vim.fn.writefile(lines, path)
  return vim.uv.fs_realpath(path) or path
end

function M.open_file(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

function M.buffer_text(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
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

function M.contains(haystack, needle, message)
  if not haystack:find(needle, 1, true) then
    error(message or string.format("expected %q to contain %q", haystack, needle), 0)
  end
end

function M.wait(predicate, timeout, message)
  local ok = vim.wait(timeout or 3000, predicate, 20)
  if not ok then
    error(message or "timed out waiting for condition", 0)
  end
end

function M.result_text()
  local ui = require("cinder.ui")
  local state = ui.state()
  if not state.result_bufnr or not vim.api.nvim_buf_is_valid(state.result_bufnr) then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(state.result_bufnr, 0, -1, false), "\n")
end

return M
