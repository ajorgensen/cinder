local h = require("tests.helpers")

return {
  {
    name = "result buffer is reused",
    run = function()
      h.reset()
      local cfg = require("cinder.config").ensure()
      local ui = require("cinder.ui")
      local first = ui.ensure_result_buffer(cfg)
      local second = ui.ensure_result_buffer(cfg)

      h.eq(first, second)
    end,
  },
  {
    name = "result buffer opens in a separate split",
    run = function()
      h.reset()
      local path = h.make_temp_file({ "local value = 1" })
      h.open_file(path)
      local source_bufnr = vim.api.nvim_get_current_buf()

      local cfg = require("cinder.config").setup({
        result_buffer = {
          name = "Cinder Results",
          open = true,
          enter = false,
          height = 8,
        },
      })
      local ui = require("cinder.ui")
      local result_bufnr = ui.prepare_result_buffer(cfg, "quick prompt")

      h.eq(vim.api.nvim_get_current_buf(), source_bufnr)
      h.expect(#vim.api.nvim_list_wins() == 2, "expected result buffer split to open")
      h.expect(#vim.fn.win_findbuf(result_bufnr) > 0, "expected result buffer to be visible in its own window")
    end,
  },
  {
    name = "result buffer reuses existing named buffer",
    run = function()
      h.reset()
      local cfg = require("cinder.config").ensure()
      local existing = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(existing, cfg.result_buffer.name)

      local ui = require("cinder.ui")
      ui.state().result_bufnr = nil
      local bufnr = ui.ensure_result_buffer(cfg)

      h.eq(bufnr, existing)
    end,
  },
  {
    name = "long prompt opens in a separate split",
    run = function()
      h.reset()
      local path = h.make_temp_file({ "local value = 1" })
      h.open_file(path)
      local source_bufnr = vim.api.nvim_get_current_buf()

      local cfg = require("cinder.config").setup({
        long_prompt_buffer = {
          name = "Cinder Prompt",
          height = 8,
        },
      })
      local ui = require("cinder.ui")
      local prompt_bufnr = ui.open_long_prompt(cfg, { file_path = path })

      h.expect(vim.api.nvim_get_current_buf() == prompt_bufnr, "expected prompt buffer to be focused")
      h.expect(#vim.api.nvim_list_wins() == 2, "expected prompt split to open")
      h.expect(source_bufnr ~= prompt_bufnr, "expected prompt buffer to be separate from source buffer")
      h.expect(vim.fn.exists(":CinderPromptSubmit") == 2, "expected global submit command")
      h.expect(vim.fn.exists(":CinderPromptCancel") == 2, "expected global cancel command")
      h.expect(vim.fn.exists(":CinderJobs") == 2, "expected jobs command")
      h.expect(vim.fn.exists(":CinderLog") == 2, "expected log command")
      h.expect(vim.fn.exists(":CinderTail") == 2, "expected tail command")
    end,
  },
}
