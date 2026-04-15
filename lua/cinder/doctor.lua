local M = {}

local function push(lines, value)
  lines[#lines + 1] = value
end

local function sorted_keys(tbl)
  local keys = {}

  for key in pairs(tbl or {}) do
    keys[#keys + 1] = key
  end

  table.sort(keys)

  return keys
end

local function inspect_profile(section_title, profile, provider_config)
  local ok, provider = pcall(require, string.format("cinder.providers.%s", profile.provider))

  if not ok then
    return {
      section_title,
      string.format("Provider: %s", tostring(profile.provider)),
      "Status: error",
      string.format("Problem: failed to load provider module: %s", provider),
      "",
    }
  end

  if provider.doctor then
    local lines = provider.doctor(section_title, profile, provider_config or {})
    lines[1] = section_title
    return lines
  end

  return {
    section_title,
    string.format("Provider: %s", tostring(profile.provider)),
    "Status: warning",
    "Problem: provider does not implement doctor checks",
    "",
  }
end

local function describe_model(model)
  return model or "-"
end

local function describe_selection(config, mode_name)
  local label = mode_name == "ask" and "Ask" or "Inline"
  local mode = config[mode_name] or {}
  local ok, resolved = pcall(require("cinder.providers").resolve, mode_name)

  if not ok then
    return string.format("%s: invalid profile selection (%s)", label, resolved)
  end

  if mode.profile and mode.profile ~= "" then
    return string.format(
      "%s: profile %s -> %s/%s",
      label,
      mode.profile,
      resolved.provider,
      describe_model(resolved.model)
    )
  end

  return string.format("%s: default fallback -> %s/%s", label, resolved.provider, describe_model(resolved.model))
end

function M.report()
  local config = require("cinder").get_config()
  local lines = {
    "Cinder Doctor",
    "",
  }
  local default_profile = {
    provider = config.provider,
    model = config.model,
  }
  local default_provider_config = config.providers[default_profile.provider] or {}
  local default_section = inspect_profile("Default fallback", default_profile, default_provider_config)

  for _, line in ipairs(default_section) do
    push(lines, line)
  end

  local profile_names = sorted_keys(config.profiles)

  for _, profile_name in ipairs(profile_names) do
    local profile = config.profiles[profile_name]
    local provider_config = config.providers[profile.provider] or {}
    local section = inspect_profile(string.format("Profile: %s", profile_name), profile, provider_config)

    for _, line in ipairs(section) do
      push(lines, line)
    end
  end

  push(lines, "Selections:")
  push(lines, describe_selection(config, "ask"))
  push(lines, describe_selection(config, "inline"))
  push(lines, "")

  push(lines, "Notes:")
  push(lines, "- Checks are local and best-effort.")
  push(lines, "- Auth token validity is not verified without a live provider request.")

  return lines
end

return M
