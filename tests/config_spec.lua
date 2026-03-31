local h = require("tests.helpers")

return {
  {
    name = "config merges defaults",
    run = function()
      h.reset()
      local cfg = require("cinder.config").setup({
        execution_mode = "job",
      })

      h.eq(cfg.harness_command, "pi")
      h.eq(cfg.model, "openai-codex/gpt-5.3-codex-spark")
      h.eq(cfg.models[1], "openai-codex/gpt-5.3-codex-spark")
      h.eq(cfg.session_mode, "buffer")
      h.eq(cfg.execution_mode, "job")
      h.eq(cfg.harness_args[1], "-p")
      h.eq(cfg.harness_args[2], "--mode")
      h.eq(cfg.harness_args[3], "json")
      h.eq(cfg.harness_args[4], "--no-session")
    end,
  },
  {
    name = "config rejects invalid execution mode",
    run = function()
      h.reset()
      local ok, err = pcall(function()
        require("cinder.config").setup({ execution_mode = "bad" })
      end)

      h.expect(not ok, "expected config validation to fail")
      h.contains(err, "execution_mode")
    end,
  },
  {
    name = "config keeps model list in sync",
    run = function()
      h.reset()
      local cfg = require("cinder.config").setup({
        model = "model/beta",
        models = { "model/alpha" },
      })

      h.eq(cfg.models[1], "model/beta")
      h.eq(cfg.models[2], "model/alpha")

      require("cinder.config").set_model("model/gamma")
      h.eq(require("cinder.config").get().model, "model/gamma")
      h.eq(require("cinder.config").models()[1], "model/gamma")
    end,
  },
}
