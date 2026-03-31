local h = require("tests.helpers")

return {
  {
    name = "context collects cursor data without selection",
    run = function()
      h.reset()
      local path = h.make_temp_file({ "one", "two", "three" })
      h.open_file(path)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local ctx = require("cinder.context").collect({ bufnr = vim.api.nvim_get_current_buf() })
      h.eq(ctx.absolute_path, path)
      h.eq(ctx.cursor_line, 2)
      h.expect(ctx.selection == nil, "selection should be nil")
    end,
  },
  {
    name = "context collects visual selection text",
    run = function()
      h.reset()
      local path = h.make_temp_file({ "alpha", "beta", "gamma" })
      h.open_file(path)
      vim.fn.setpos("'<", { 0, 1, 1, 0 })
      vim.fn.setpos("'>", { 0, 2, 4, 0 })

      local ctx = require("cinder.context").collect({
        bufnr = vim.api.nvim_get_current_buf(),
        visual = true,
        visual_mode = "v",
      })

      h.eq(ctx.selection.start_line, 1)
      h.eq(ctx.selection.end_line, 2)
      h.contains(ctx.selection.text, "alpha")
      h.contains(ctx.selection.text, "beta")
    end,
  },
  {
    name = "context returns nil for non-file buffers",
    run = function()
      h.reset()
      vim.cmd.enew()

      local ctx = require("cinder.context").collect({ bufnr = vim.api.nvim_get_current_buf() })
      h.expect(ctx == nil, "expected no context for a non-file buffer")
    end,
  },
}
