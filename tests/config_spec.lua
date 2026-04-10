local h = require("tests.helpers")

return {
  {
    name = "config merges defaults",
    run = function()
      h.reset()
      local cfg = require("cinder.config").setup()

      h.eq(cfg.harness_command, "opencode")
      h.eq(cfg.model, "openai/gpt-5.4")
      h.eq(cfg.models[1], "openai/gpt-5.4")
      h.eq(cfg.session_mode, "buffer")
      h.eq(cfg.harness_args[1], "run")
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
