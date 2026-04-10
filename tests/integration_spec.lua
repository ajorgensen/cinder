local h = require("tests.helpers")

local function fake_harness()
  return h.repo_root() .. "/tests/fixtures/fake-harness.sh"
end

local function fake_json_harness()
  return h.repo_root() .. "/tests/fixtures/fake-json-harness.py"
end

local function fake_opencode()
  return h.repo_root() .. "/tests/fixtures/opencode"
end

local function configure(opts)
  local cinder = h.reset()
  cinder.setup(vim.tbl_deep_extend("force", {
    harness_command = fake_harness(),
    harness_args = {},
    result_buffer = {
      name = "Cinder Results",
      open = false,
    },
    notifications = "silent",
  }, opts or {}))
  return cinder
end

local function submit_prompt(cinder, lines)
  local ui = require("cinder.ui")
  local prompt_bufnr = ui.state().prompt_bufnr
  h.expect(prompt_bufnr ~= nil, "expected prompt buffer")
  vim.api.nvim_buf_set_lines(prompt_bufnr, ui.state().prompt_header_lines, -1, false, lines)
  cinder.submit_long_prompt()
end

local function jobs_buffer_text()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) == "Cinder Jobs" then
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end
  end

  return ""
end

local function log_buffer_text()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) == "Cinder Log" then
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end
  end

  return ""
end

local function tail_buffer_text()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)) == "Cinder Tail" then
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end
  end

  return ""
end

return {
  {
    name = "quick prompt runs and writes output",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "one", "two", "three" })
      h.open_file(path)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      submit_prompt(cinder, { "Count the lines.", "Explain your answer." })

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "quick prompt did not finish")

      local text = h.result_text()
      h.contains(text, "Current file:")
      h.contains(text, "Cursor line: 2")
      h.contains(text, "Task:\nCount the lines.\nExplain your answer.")
    end,
  },
  {
    name = "debug log records run lifecycle",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "one", "two" })
      h.open_file(path)

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      submit_prompt(cinder, { "Explain this file." })

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "logged run did not finish")

      local log_path = require("cinder.debug").path()
      local log_text = table.concat(vim.fn.readfile(log_path), "\n")
      h.contains(log_text, "prompt.opened")
      h.contains(log_text, "prompt.submit")
      h.contains(log_text, "runner.started")
      h.contains(log_text, "run.completed")

      vim.cmd("CinderLog")
      local buffer_text = log_buffer_text()
      h.contains(buffer_text, "prompt.opened")
      h.contains(buffer_text, "run.completed")

      local run = require("cinder.jobs").latest()
      h.expect(run and run.stream_path, "expected stream log path")
      local stream_text = table.concat(vim.fn.readfile(run.stream_path), "\n")
      h.contains(stream_text, "stream.start")
      h.contains(stream_text, "[stdout]")

      vim.cmd("CinderTail")
      h.contains(tail_buffer_text(), "[stdout]")
    end,
  },
  {
    name = "model commands show and switch the active model",
    run = function()
      local cinder = configure({
        model = "model/alpha",
        models = { "model/alpha", "model/beta" },
        notifications = "normal",
      })
      local messages = {}
      vim.notify = function(message)
        messages[#messages + 1] = message
      end

      vim.cmd("CinderModel")
      h.eq(messages[#messages], "Active model: model/alpha")

      vim.cmd("CinderModel model/beta")
      h.eq(require("cinder.config").get().model, "model/beta")
      h.eq(messages[#messages], "Active model set to model/beta")

      vim.ui.select = function(items, _, callback)
        h.eq(items[1], "model/alpha")
        h.eq(items[2], "model/beta")
        callback("model/alpha")
      end

      cinder.select_model()
      h.eq(require("cinder.config").get().model, "model/alpha")
      h.eq(messages[#messages], "Active model set to model/alpha")
    end,
  },
  {
    name = "jobs command shows running and completed runs",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "one", "two", "three" })
      h.open_file(path)
      vim.env.CINDER_TEST_STDOUT = "done"
      vim.env.CINDER_TEST_SLEEP = "0.3"

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      submit_prompt(cinder, { "Count the lines." })

      h.wait(function()
        return require("cinder.jobs").summary().running == 1
      end, 3000, "expected a running cinder job")

      vim.cmd("CinderJobs")
      h.contains(jobs_buffer_text(), "[running] run 1")

      h.wait(function()
        local summary = require("cinder.jobs").summary()
        return summary.completed == 1 or summary.lost == 1
      end, 3000, "expected cinder job to finish or be marked lost")

      vim.cmd("CinderJobs")
      local text = jobs_buffer_text()
      h.expect(text:find("[completed] run 1", 1, true) ~= nil or text:find("[lost] run 1", 1, true) ~= nil, "expected completed or lost run status")
      h.contains(text, "Job ID:")
    end,
  },
  {
    name = "result buffer draft can continue a session",
    run = function()
      local cinder = configure({
        harness_command = fake_opencode(),
        harness_args = { "run" },
        session_mode = "buffer",
      })
      local path = h.make_temp_file({ "local value = 1" })
      h.open_file(path)
      vim.env.CINDER_TEST_STDOUT = "First answer"

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      submit_prompt(cinder, { "Explain this file." })

      h.wait(function()
        return h.result_text():find("First answer", 1, true) ~= nil
      end, 3000, "initial session run did not finish")

      local session = require("cinder.ui").get_result_session()
      h.expect(session ~= nil and session.session_file ~= nil, "expected a result session file")

      require("cinder.ui").set_result_draft("Continue the explanation.")
      vim.env.CINDER_TEST_CONTINUE_STDOUT = "Second answer"
      vim.cmd("CinderContinue")

      h.wait(function()
        return h.result_text():find("Second answer", 1, true) ~= nil
      end, 3000, "continued session run did not finish")

      local text = h.result_text()
      h.contains(text, "## User")
      h.contains(text, "Explain this file.")
      h.contains(text, "Continue the explanation.")
      h.contains(text, "First answer")
      h.contains(text, "Second answer")
      h.eq(require("cinder.ui").get_result_draft_text(), "")
    end,
  },
  {
    name = "quick prompt keeps file context in prompt buffer flow",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "one", "two", "three" })
      h.open_file(path)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      cinder.command_prompt({ range = 0 })
      submit_prompt(cinder, { "Count the lines." })

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "quick prompt with prompt buffer did not finish")

      local text = h.result_text()
      h.contains(text, path)
      h.contains(text, "Cursor line: 2")
    end,
  },
  {
    name = "visual prompt includes selected text",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "alpha", "beta", "gamma" })
      h.open_file(path)
      vim.fn.setpos("'<", { 0, 1, 1, 0 })
      vim.fn.setpos("'>", { 0, 2, 4, 0 })

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 1 })
      submit_prompt(cinder, { "Rewrite this." })

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "visual prompt did not finish")

      local text = h.result_text()
      h.contains(text, "Selected range: 1-2")
      h.contains(text, "Selected text:")
      h.contains(text, "alpha")
      h.contains(text, "beta")
    end,
  },
  {
    name = "long prompt can submit and cancel",
    run = function()
      local cinder = configure({
        harness_command = fake_harness(),
        harness_args = {},
      })
      local path = h.make_temp_file({ "local value = 1" })
      h.open_file(path)
      vim.env.CINDER_TEST_STDOUT = "Explain the code."

      cinder.command_prompt_long({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      local ui = require("cinder.ui")
      local prompt_bufnr = ui.state().prompt_bufnr
      h.expect(prompt_bufnr ~= nil, "expected prompt buffer")

      vim.api.nvim_buf_set_lines(prompt_bufnr, ui.state().prompt_header_lines, -1, false, { "Explain the code." })
      vim.cmd("CinderPromptSubmit")

      h.wait(function()
        return h.result_text():find("Explain the code.", 1, true) ~= nil
      end, 3000, "long prompt submit did not finish")

      cinder.command_prompt_long({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      prompt_bufnr = ui.state().prompt_bufnr
      vim.cmd("CinderPromptCancel")
      h.expect(not vim.api.nvim_buf_is_valid(prompt_bufnr), "expected prompt buffer to close")
    end,
  },
  {
    name = "buffer refresh picks up disk edits",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "before" })
      h.open_file(path)
      vim.env.CINDER_TEST_EDIT_FILE = path
      vim.env.CINDER_TEST_EDIT_CONTENT = "after\n"

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      submit_prompt(cinder, { "Update the file." })

      h.wait(function()
        return vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "after"
      end, 3000, "buffer did not refresh after edit")
    end,
  },
  {
    name = "empty quick prompt cancels cleanly",
    run = function()
      local cinder = configure()
      local path = h.make_temp_file({ "noop" })
      h.open_file(path)

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 0 })
      cinder.submit_long_prompt()
      h.eq(h.result_text(), "")
    end,
  },
  {
    name = "empty quick prompt still runs with selection context",
    run = function()
      local cinder = configure({
        harness_command = fake_harness(),
        harness_args = {},
      })
      local path = h.make_temp_file({ "// Write a fibonacci helper" })
      h.open_file(path)
      vim.env.CINDER_TEST_STDOUT = "def first_10_fibonacci():\n    return [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]"
      vim.fn.setpos("'<", { 0, 1, 1, 0 })
      vim.fn.setpos("'>", { 0, 1, 27, 0 })

      cinder.command_prompt({ buf = vim.api.nvim_get_current_buf(), range = 1 })
      cinder.submit_long_prompt()

      h.wait(function()
        return h.result_text():find("Applied replacement to the selected text.", 1, true) ~= nil
      end, 3000, "selection-only quick prompt did not finish")

      h.contains(h.buffer_text(), "def first_10_fibonacci()")
      local text = h.result_text()
      h.contains(text, "Applied replacement to the selected text.")
      h.contains(text, "def first_10_fibonacci()")
    end,
  },
  {
    name = "quick prompt sends raw task from non-file buffers",
    run = function()
      local cinder = configure()
      vim.cmd.enew()

      cinder.command_prompt({ range = 0 })
      submit_prompt(cinder, { "Just answer the question." })

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "non-file quick prompt did not finish")

      local text = h.result_text()
      h.contains(text, "Just answer the question.")
      h.expect(text:find("Current file:", 1, true) == nil, "non-file prompt should not include file context")
    end,
  },
  {
    name = "json mode shows parsed final assistant text",
    run = function()
      local cinder = configure({
        harness_command = fake_json_harness(),
        harness_args = { "--mode", "json" },
      })
      local path = h.make_temp_file({ "one" })
      h.open_file(path)
      vim.env.CINDER_TEST_JSON_TEXT = "Clean final answer"

      cinder.command_prompt({ range = 0 })
      submit_prompt(cinder, { "Summarize this." })

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "json mode prompt did not finish")

      local text = h.result_text()
      h.contains(text, "Clean final answer")
      h.expect(text:find('"type":"turn_end"', 1, true) == nil, "result buffer should not contain raw json events")
    end,
  },
  {
    name = "long prompt sends raw task from non-file buffers",
    run = function()
      local cinder = configure()
      vim.cmd.enew()

      cinder.command_prompt_long({ range = 0 })
      local ui = require("cinder.ui")
      local prompt_bufnr = ui.state().prompt_bufnr
      h.expect(prompt_bufnr ~= nil, "expected prompt buffer")

      local header = table.concat(vim.api.nvim_buf_get_lines(prompt_bufnr, 0, 5, false), "\n")
      h.contains(header, "Context file: none")

      vim.api.nvim_buf_set_lines(prompt_bufnr, ui.state().prompt_header_lines, -1, false, { "Just answer the question." })
      cinder.submit_long_prompt()

      h.wait(function()
        return h.result_text():find("Run completed successfully.", 1, true) ~= nil
      end, 3000, "non-file long prompt did not finish")

      local text = h.result_text()
      h.contains(text, "Just answer the question.")
      h.expect(text:find("Current file:", 1, true) == nil, "non-file long prompt should not include file context")
    end,
  },
  {
    name = "empty long prompt still runs with selection context",
    run = function()
      local cinder = configure({
        harness_command = fake_harness(),
        harness_args = {},
      })
      local path = h.make_temp_file({ "# implement a helper" })
      h.open_file(path)
      vim.env.CINDER_TEST_STDOUT = "def helper():\n    return 42"
      vim.fn.setpos("'<", { 0, 1, 1, 0 })
      vim.fn.setpos("'>", { 0, 1, 20, 0 })

      cinder.command_prompt_long({ buf = vim.api.nvim_get_current_buf(), range = 1 })
      vim.cmd("CinderPromptSubmit")

      h.wait(function()
        return h.result_text():find("Applied replacement to the selected text.", 1, true) ~= nil
      end, 3000, "selection-only long prompt did not finish")

      h.contains(h.buffer_text(), "def helper():")
      local text = h.result_text()
      h.contains(text, "Applied replacement to the selected text.")
      h.contains(text, "def helper():")
    end,
  },
}
