local M = {}

M.config = {
  provider = "pi",
  model = nil,
  profiles = {
    fake = {
      provider = "fake",
      model = "fake-do",
    },
  },
  ask = {
    profile = nil,
  },
  inline = {
    profile = "fake",
  },
  providers = {
    fake = {
      interval_ms = 30,
      total_ticks = 4,
    },
    pi = {
      cmd = "pi",
      args = {
        "--mode",
        "rpc",
        "--no-session",
      },
      cwd = nil,
      env = {},
      session_dir = nil,
    },
  },
  ui = {
    composer_open_cmd = "botright split",
    runs_open_cmd = "botright 10split",
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.get_config()
  return M.config
end

function M.dispatch(opts)
  return require("cinder.commands").dispatch(opts)
end

function M.execute(subcommand, opts)
  return require("cinder.commands").execute(subcommand, opts or {})
end

function M.statusline()
  return require("cinder.state").statusline()
end

return M
