local h = require("tests.helpers")

return {
  {
    name = "runner builds argv with prompt",
    run = function()
      h.reset()
      local argv = require("cinder.runner").build_argv({
        harness_command = "opencode",
        harness_args = { "run" },
        model = "openai/gpt-5.4",
      }, "task")

      h.eq(argv[1], "opencode")
      h.eq(argv[2], "run")
      h.eq(argv[3], "--model")
      h.eq(argv[4], "openai/gpt-5.4")
      h.eq(argv[5], "task")
    end,
  },
  {
    name = "runner uses opencode continue for buffer sessions",
    run = function()
      h.reset()
      local argv = require("cinder.runner").build_argv({
        harness_command = "opencode",
        harness_args = { "run" },
        model = "openai/gpt-5.4",
      }, "task", { session_file = require("cinder.runner").opencode_continue_session() })

      h.expect(vim.tbl_contains(argv, "--continue"), "expected continue flag")
      h.eq(argv[#argv], "task")
    end,
  },
  {
    name = "runner does not duplicate explicit model args",
    run = function()
      h.reset()
      local argv = require("cinder.runner").build_argv({
        harness_command = "opencode",
        harness_args = { "run", "-m", "custom/model" },
        model = "openai/gpt-5.4",
      }, "task")

      h.eq(argv[1], "opencode")
      h.eq(argv[2], "run")
      h.eq(argv[3], "-m")
      h.eq(argv[4], "custom/model")
      h.eq(argv[5], "task")
    end,
  },
  {
    name = "runner chooses job backend outside tmux",
    run = function()
      h.reset()
      local saved_tmux = vim.env.TMUX
      vim.env.TMUX = nil
      local backend = require("cinder.runner").choose_backend({ execution_mode = "auto" })
      vim.env.TMUX = saved_tmux
      h.eq(backend, "job")
    end,
  },
  {
    name = "tmux script includes harness args",
    run = function()
      h.reset()
      local lines = require("cinder.runner")._build_tmux_script_lines(
        { "opencode", "run", "--model", "openai/gpt-5.4", "task text" },
        "/tmp/stdout",
        "/tmp/stderr",
        "/tmp/exit"
      )

      local script = table.concat(lines, "\n")
      h.contains(script, "'opencode' 'run' '--model' 'openai/gpt-5.4' 'task text'")
      h.contains(script, "/tmp/stdout")
      h.contains(script, "/tmp/stderr")
      h.contains(script, "/tmp/exit")
    end,
  },
}
