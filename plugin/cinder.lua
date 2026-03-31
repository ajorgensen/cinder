if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_echo({ { "cinder.nvim requires Neovim 0.11+", "ErrorMsg" } }, true, {})
  return
end

vim.api.nvim_create_user_command("CinderPrompt", function(command)
  require("cinder").command_prompt(command)
end, {
  desc = "Run a short Cinder prompt for the current context",
  range = true,
})

vim.api.nvim_create_user_command("CinderPromptLong", function(command)
  require("cinder").command_prompt_long(command)
end, {
  desc = "Open a long-form Cinder prompt buffer",
  range = true,
})

vim.api.nvim_create_user_command("CinderPromptSubmit", function()
  require("cinder").submit_long_prompt()
end, {
  desc = "Submit the current long-form Cinder prompt",
})

vim.api.nvim_create_user_command("CinderPromptCancel", function()
  require("cinder").cancel_long_prompt()
end, {
  desc = "Cancel the current long-form Cinder prompt",
})

vim.api.nvim_create_user_command("CinderContinue", function()
  require("cinder").continue_session()
end, {
  desc = "Continue the current Cinder session from the result buffer draft",
})

vim.api.nvim_create_user_command("CinderSessionReset", function()
  require("cinder").reset_session()
end, {
  desc = "Reset the current Cinder session",
})

vim.api.nvim_create_user_command("CinderModel", function(command)
  require("cinder").command_model(command)
end, {
  desc = "Show or set the active Cinder model",
  nargs = "?",
  complete = function()
    return require("cinder").complete_models()
  end,
})

vim.api.nvim_create_user_command("CinderModelSelect", function()
  require("cinder").select_model()
end, {
  desc = "Pick the active Cinder model from the configured list",
})
