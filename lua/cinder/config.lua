local M = {}

local defaults = {
  harness_command = "opencode",
  harness_args = { "run" },
  model = "openai/gpt-5.4",
  models = { "openai/gpt-5.4" },
  session_mode = "buffer",
  result_buffer = {
    name = "Cinder Results",
    open = true,
    enter = false,
    height = 12,
  },
  long_prompt_buffer = {
    name = "Cinder Prompt",
    height = 12,
  },
  selection_behavior = "auto",
  notifications = "normal",
}

local state = {
  options = vim.deepcopy(defaults),
  setup_called = false,
}

local function type_error(path, expected, actual)
  error(string.format("cinder.nvim config error: %s must be %s, got %s", path, expected, actual), 0)
end

local function ensure_type(path, value, expected)
  if type(value) ~= expected then
    type_error(path, expected, type(value))
  end
end

local function validate_string(path, value)
  ensure_type(path, value, "string")
  if value == "" then
    error(string.format("cinder.nvim config error: %s must not be empty", path), 0)
  end
end

local function validate_array(path, value)
  ensure_type(path, value, "table")
  for key, item in pairs(value) do
    if type(key) ~= "number" then
      error(string.format("cinder.nvim config error: %s must be a list", path), 0)
    end
    if type(item) ~= "string" then
      error(string.format("cinder.nvim config error: %s[%s] must be a string", path, key), 0)
    end
  end
end

local function validate_enum(path, value, allowed)
  validate_string(path, value)
  for _, item in ipairs(allowed) do
    if value == item then
      return
    end
  end

  error(string.format(
    "cinder.nvim config error: %s must be one of %s",
    path,
    table.concat(allowed, ", ")
  ), 0)
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end

  return false
end

local function normalize_models(options)
  if #options.models == 0 then
    options.models = { options.model }
    return options
  end

  if not contains(options.models, options.model) then
    table.insert(options.models, 1, options.model)
  end

  return options
end

local function validate(options)
  validate_string("harness_command", options.harness_command)
  validate_array("harness_args", options.harness_args)
  validate_string("model", options.model)
  validate_array("models", options.models)
  validate_enum("session_mode", options.session_mode, { "off", "buffer" })
  ensure_type("result_buffer", options.result_buffer, "table")
  validate_string("result_buffer.name", options.result_buffer.name)
  if type(options.result_buffer.open) ~= "boolean" then
    type_error("result_buffer.open", "a boolean", type(options.result_buffer.open))
  end
  if type(options.result_buffer.enter) ~= "boolean" then
    type_error("result_buffer.enter", "a boolean", type(options.result_buffer.enter))
  end
  if type(options.result_buffer.height) ~= "number" or options.result_buffer.height <= 0 then
    error("cinder.nvim config error: result_buffer.height must be a positive number", 0)
  end
  ensure_type("long_prompt_buffer", options.long_prompt_buffer, "table")
  validate_string("long_prompt_buffer.name", options.long_prompt_buffer.name)
  if type(options.long_prompt_buffer.height) ~= "number" or options.long_prompt_buffer.height <= 0 then
    error("cinder.nvim config error: long_prompt_buffer.height must be a positive number", 0)
  end
  validate_enum("selection_behavior", options.selection_behavior, { "auto", "agent", "replace" })
  validate_enum("notifications", options.notifications, { "normal", "silent" })
  return normalize_models(options)
end

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.get()
  return state.options
end

function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  state.options = validate(merged)
  state.setup_called = true
  return state.options
end

function M.ensure()
  if not state.setup_called then
    return M.setup()
  end

  return state.options
end

function M.models()
  return vim.deepcopy(state.options.models)
end

function M.set_model(model)
  validate_string("model", model)
  state.options.model = model
  if not contains(state.options.models, model) then
    table.insert(state.options.models, 1, model)
  end
  return state.options.model
end

function M.reset()
  state.options = vim.deepcopy(defaults)
  state.setup_called = false
end

return M
