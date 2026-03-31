local h = require("tests.helpers")

return {
  {
    name = "runner builds argv with prompt",
    run = function()
      h.reset()
      local argv = require("cinder.runner").build_argv({
        harness_command = "pi",
        harness_args = { "-p", "--mode", "json", "--no-session" },
        model = "openai-codex/gpt-5.3-codex-spark",
      }, "task")

      h.eq(argv[1], "pi")
      h.eq(argv[2], "-p")
      h.eq(argv[3], "--mode")
      h.eq(argv[4], "json")
      h.eq(argv[5], "--no-session")
      h.eq(argv[6], "--model")
      h.eq(argv[7], "openai-codex/gpt-5.3-codex-spark")
      h.eq(argv[8], "task")
    end,
  },
  {
    name = "runner uses session file instead of no-session",
    run = function()
      h.reset()
      local argv = require("cinder.runner").build_argv({
        harness_command = "pi",
        harness_args = { "-p", "--mode", "json", "--no-session" },
        model = "openai-codex/gpt-5.3-codex-spark",
      }, "task", { session_file = "/tmp/cinder-session.jsonl" })

      h.expect(vim.tbl_contains(argv, "--session"), "expected session flag")
      h.expect(not vim.tbl_contains(argv, "--no-session"), "expected no-session to be removed")
      h.eq(argv[#argv - 1], "/tmp/cinder-session.jsonl")
      h.eq(argv[#argv], "task")
    end,
  },
  {
    name = "runner does not duplicate explicit model args",
    run = function()
      h.reset()
      local argv = require("cinder.runner").build_argv({
        harness_command = "pi",
        harness_args = { "-p", "--model", "custom/model" },
        model = "openai-codex/gpt-5.3-codex-spark",
      }, "task")

      h.eq(argv[1], "pi")
      h.eq(argv[2], "-p")
      h.eq(argv[3], "--model")
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
        { "pi", "-p", "--mode", "json", "--no-session", "--model", "openai-codex/gpt-5.3-codex-spark", "task text" },
        "/tmp/stdout",
        "/tmp/stderr",
        "/tmp/exit"
      )

      local script = table.concat(lines, "\n")
      h.contains(script, "'pi' '-p' '--mode' 'json' '--no-session' '--model' 'openai-codex/gpt-5.3-codex-spark' 'task text'")
      h.contains(script, "/tmp/stdout")
      h.contains(script, "/tmp/stderr")
      h.contains(script, "/tmp/exit")
    end,
  },
}
