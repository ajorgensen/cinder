local config = require("cinder.config")
local context = require("cinder.context")
local prompt = require("cinder.prompt")
local runner = require("cinder.runner")
local ui = require("cinder.ui")

local M = {}

local function notify(message, level, opts)
  local active = config.get()
  if active.notifications == "silent" and level ~= vim.log.levels.ERROR then
    return
  end

  vim.notify(message, level or vim.log.levels.INFO, vim.tbl_extend("force", {
    title = "cinder.nvim",
  }, opts or {}))
end

local function is_visual_command(command)
  return command.range > 0 and vim.fn.getpos("'<")[2] > 0 and vim.fn.getpos("'>")[2] > 0
end

local function build_invocation(command, prompt_kind)
  return {
    bufnr = vim.api.nvim_get_current_buf(),
    prompt_kind = prompt_kind,
    visual = is_visual_command(command),
    visual_mode = vim.fn.visualmode(),
  }
end

local function refresh_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= "" and not vim.bo[bufnr].modified then
      pcall(vim.cmd, string.format("silent checktime %d", bufnr))
    end
  end
end

local function has_selection_context(ctx)
  return ctx and ctx.selection and type(ctx.selection.text) == "string" and ctx.selection.text ~= ""
end

local function has_task(task)
  return type(task) == "string" and vim.trim(task) ~= ""
end

local function is_pi_command(command)
  return vim.fs.basename(command or "") == "pi"
end

local function selection_mode(active, ctx, task)
  if not has_selection_context(ctx) then
    return "agent"
  end

  if active.selection_behavior == "agent" then
    return "agent"
  end

  if active.selection_behavior == "replace" then
    return ctx.selection.mode == "block" and "agent" or "replace"
  end

  if not has_task(task) and ctx.selection.mode ~= "block" then
    return "replace"
  end

  return "agent"
end

local function strip_code_fences(text)
  if type(text) ~= "string" then
    return text
  end

  local fenced = text:match("^```[%w_-]*\n([%s%S]*)\n```%s*$")
  return fenced or text
end

local function replacement_output(meta)
  if meta.final_output and meta.final_output ~= "" then
    return strip_code_fences(meta.final_output)
  end
  if meta.stdout and meta.stdout ~= "" then
    return strip_code_fences(meta.stdout)
  end
  return nil
end

local function session_enabled(active)
  return active.session_mode == "buffer" and is_pi_command(active.harness_command)
end

local function new_session_file()
  return vim.fn.tempname() .. ".jsonl"
end

local function result_prompt_text(task, composed_prompt, continued)
  if continued then
    return task
  end

  return composed_prompt
end

local function replace_extra_args(active)
  if is_pi_command(active.harness_command) then
    return { "--no-tools" }
  end

  return {}
end

local function run_task(task, invocation)
  local active = config.ensure()
  local ctx = invocation.context or context.collect(invocation)
  local session_file = invocation.session_file
  if not session_file and session_enabled(active) then
    session_file = new_session_file()
  end

  ui.set_result_session(session_file, ctx and ctx.bufnr or nil)
  local result_bufnr
  if invocation.continue_session then
    result_bufnr = ui.open_result_buffer(active)
    ui.set_status(result_bufnr, string.format("running (%s)", invocation.prompt_kind))
  else
    result_bufnr = ui.prepare_result_buffer(active, invocation.prompt_kind)
  end
  local composed_prompt = prompt.compose(ctx, task)
  ui.append_transcript(result_bufnr, "User", result_prompt_text(task, composed_prompt, invocation.continue_session))

  notify("Cinder run started", vim.log.levels.INFO)

  return runner.run({
    config = active,
    prompt = composed_prompt,
    session_file = session_file,
    on_stdout = function(data)
      ui.append_output(result_bufnr, data)
    end,
    on_stderr = function(data)
      ui.append_output(result_bufnr, data, { prefix = "[stderr] " })
    end,
    on_complete = function(meta)
      local success = meta.code == 0
      refresh_buffers()
      if meta.final_output and meta.final_output ~= "" then
        ui.append_transcript(result_bufnr, "Assistant", meta.final_output)
      elseif meta.output_mode == "json" and meta.stdout and meta.stdout ~= "" then
        ui.append_output(result_bufnr, meta.stdout)
      end
      ui.set_status(result_bufnr, success and "completed" or string.format("failed (%d)", meta.code))
      ui.append_summary(result_bufnr, success and "Run completed successfully." or string.format("Run failed with exit code %d.", meta.code))
      if active.result_buffer.open then
        ui.open_result_buffer(active)
      end
      notify(success and "Cinder run finished" or "Cinder run failed", success and vim.log.levels.INFO or vim.log.levels.ERROR)
    end,
  })
end

local function run_replace_task(task, invocation)
  local active = config.ensure()
  local ctx = invocation.context or context.collect(invocation)
  local result_bufnr = ui.prepare_result_buffer(active, invocation.prompt_kind)
  local composed_prompt = prompt.compose_replacement(ctx, task)
  ui.reset_result_session()
  ui.append_transcript(result_bufnr, "User", result_prompt_text(task, composed_prompt, false))

  notify("Cinder run started", vim.log.levels.INFO)

  return runner.run({
    config = active,
    prompt = composed_prompt,
    extra_args = replace_extra_args(active),
    force_no_session = true,
    on_stderr = function(data)
      ui.append_output(result_bufnr, data, { prefix = "[stderr] " })
    end,
    on_complete = function(meta)
      local success = meta.code == 0
      local output = replacement_output(meta)
      if success and meta.final_output and meta.final_output ~= "" then
        context.replace_selection(ctx.bufnr, ctx.selection, output)
      elseif success and output and output ~= "" then
        context.replace_selection(ctx.bufnr, ctx.selection, output)
      end
      refresh_buffers()
      if output and output ~= "" then
        ui.append_transcript(result_bufnr, "Assistant", output)
      elseif meta.output_mode == "json" and meta.stdout and meta.stdout ~= "" then
        ui.append_output(result_bufnr, meta.stdout)
      end
      ui.set_status(result_bufnr, success and "completed" or string.format("failed (%d)", meta.code))
      ui.append_summary(
        result_bufnr,
        success and "Applied replacement to the selected text." or string.format("Run failed with exit code %d.", meta.code)
      )
      if active.result_buffer.open then
        ui.open_result_buffer(active)
      end
      notify(success and "Cinder run finished" or "Cinder run failed", success and vim.log.levels.INFO or vim.log.levels.ERROR)
    end,
  })
end

local function dispatch_task(task, invocation)
  local active = config.ensure()
  if selection_mode(active, invocation.context, task) == "replace" then
    invocation.prompt_kind = invocation.prompt_kind .. " (replace selection)"
    return run_replace_task(task, invocation)
  end

  return run_task(task, invocation)
end

local function prompt_for_task(command, callback)
  local invocation = build_invocation(command, "quick prompt")
  local ctx = context.collect(invocation)

  vim.ui.input({
    prompt = "Cinder task: ",
  }, function(input)
    if (not input or vim.trim(input) == "") and not has_selection_context(ctx) then
      notify("Cinder prompt cancelled", vim.log.levels.INFO)
      return
    end

    callback(input or "", {
      context = ctx,
      prompt_kind = invocation.prompt_kind,
    })
  end)
end

function M.setup(opts)
  return config.setup(opts)
end

function M.complete_models()
  return config.models()
end

function M.command_model(command)
  local ok, err = pcall(function()
    config.ensure()
    if not command.args or vim.trim(command.args) == "" then
      notify(string.format("Active model: %s", config.get().model), vim.log.levels.INFO)
      return
    end

    local model = config.set_model(vim.trim(command.args))
    notify(string.format("Active model set to %s", model), vim.log.levels.INFO)
  end)

  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

function M.select_model()
  local ok, err = pcall(function()
    local active = config.ensure()
    vim.ui.select(config.models(), {
      prompt = "Select Cinder model",
      format_item = function(item)
        if item == active.model then
          return item .. " (current)"
        end
        return item
      end,
    }, function(choice)
      if not choice or choice == "" then
        return
      end
      local model = config.set_model(choice)
      notify(string.format("Active model set to %s", model), vim.log.levels.INFO)
    end)
  end)

  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

function M.command_prompt(command)
  local ok, err = pcall(function()
    prompt_for_task(command, dispatch_task)
  end)

  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

function M.continue_session()
  local ok, err = pcall(function()
    local session = ui.get_result_session()
    if not session then
      notify("No active Cinder session for the result buffer", vim.log.levels.ERROR)
      return
    end

    local draft = ui.get_result_draft_text()
    if not draft or vim.trim(draft) == "" then
      notify("Result buffer draft is empty", vim.log.levels.INFO)
      return
    end

    ui.set_result_draft("")
    run_task(draft, {
      prompt_kind = "continued session",
      continue_session = true,
      session_file = session.session_file,
    })
  end)

  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

function M.reset_session()
  ui.reset_result_session()
  notify("Cinder session reset", vim.log.levels.INFO)
end

function M.command_prompt_long(command)
  local ok, err = pcall(function()
    local invocation = build_invocation(command, "long prompt")
    local ctx = context.collect(invocation)
    ui.open_long_prompt(config.ensure(), ctx)
  end)

  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

function M.submit_long_prompt()
  local ok, err = pcall(function()
    local task = ui.get_long_prompt_text()
    local ctx = ui.get_long_prompt_context()
    if (not task or task == "") and not has_selection_context(ctx) then
      notify("Cinder prompt cancelled", vim.log.levels.INFO)
      ui.close_long_prompt()
      return
    end

    ui.close_long_prompt()
    dispatch_task(task or "", {
      context = ctx,
      prompt_kind = "long prompt",
    })
  end)

  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

function M.cancel_long_prompt()
  ui.close_long_prompt()
  notify("Cinder prompt cancelled", vim.log.levels.INFO)
end

function M._refresh_buffers()
  refresh_buffers()
end

return M
