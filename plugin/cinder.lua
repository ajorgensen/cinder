if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_echo({ { "cinder.nvim requires Neovim 0.11+", "ErrorMsg" } }, true, {})
  return
end

vim.api.nvim_create_user_command("CinderHello", function()
  require("cinder").hello()
end, {
  desc = "Print hello world",
})
