if vim.g.loaded_cinder == 1 then
  return
end

vim.g.loaded_cinder = 1

local commands = require("cinder.commands")

vim.api.nvim_create_user_command("Cinder", function(opts)
  commands.dispatch(opts)
end, {
  nargs = "*",
  range = true,
  complete = function(arglead, cmdline, cursorpos)
    return commands.complete(arglead, cmdline, cursorpos)
  end,
  desc = "Cinder command entrypoint",
})
