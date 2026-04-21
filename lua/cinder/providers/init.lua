local M = {}

local function resolve_profile(config, profile_name)
  if not profile_name or profile_name == "" then
    return nil
  end

  local profile = config.profiles[profile_name]

  assert(profile, string.format("unknown cinder profile: %s", tostring(profile_name)))

  return profile
end

function M.resolve(mode_name)
  local config = require("cinder").get_config()
  local mode = config[mode_name] or {}
  local profile = resolve_profile(config, mode.profile) or {}
  local resolved = {
    provider = profile.provider or config.provider,
    model = profile.model,
    profile = mode.profile,
  }

  if resolved.model == nil then
    resolved.model = config.model
  end

  assert(resolved.provider, string.format("no provider configured for cinder mode: %s", tostring(mode_name)))

  return resolved
end

function M.start(run, callbacks)
  local config = require("cinder").get_config()
  local provider = require(string.format("cinder.providers.%s", run.provider))
  local provider_config = config.providers[run.provider] or {}

  return provider.start(run, provider_config, callbacks)
end

function M.stop_session(session)
  if not session or not session.provider then
    return
  end

  local ok, provider = pcall(require, string.format("cinder.providers.%s", session.provider))

  if ok and provider.stop_session then
    provider.stop_session(session)
  end
end

return M
