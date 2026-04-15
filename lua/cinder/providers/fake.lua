local uv = vim.uv or vim.loop

local M = {}

local spinner_frames = { "-", "\\", "|", "/" }

function M.start(run, opts, callbacks)
  local timer = uv.new_timer()
  local tick = 0
  local total_ticks = math.max(opts.total_ticks or 4, 2)
  local interval_ms = opts.interval_ms or 30
  local finished = false

  local function stop()
    if finished then
      return
    end

    finished = true
    timer:stop()
    timer:close()
  end

  local function cancel()
    stop()

    vim.schedule(function()
      callbacks.on_cancelled(run)
    end)
  end

  timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
    tick = tick + 1

    if tick < total_ticks then
      callbacks.on_progress(run, spinner_frames[((tick - 1) % #spinner_frames) + 1], tick, total_ticks)
      return
    end

    stop()

    if run.kind == "composer" then
      callbacks.on_message_final(run, string.format(
        "Fake response from %s/%s for: %s",
        run.provider,
        run.model or "-",
        run.prompt
      ))
    end

    callbacks.on_complete(run, {
      summary = string.format("Fake provider completed %s run %s", run.kind, run.id),
    })
  end))

  return {
    cancel = cancel,
  }
end

function M.doctor(profile_name, profile, _)
  return {
    string.format("Profile: %s", profile_name),
    "Provider: fake",
    "Status: ok",
    "Binary: not required",
    string.format("Model: %s", profile.model or "-"),
    "Auth: not required",
    "",
  }
end

return M
