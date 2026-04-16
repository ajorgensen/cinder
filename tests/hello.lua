local cinder = require("cinder")
local state = require("cinder.state")
local cwd = vim.fn.getcwd()
local mock_pi = cwd .. "/tests/mock_pi_rpc.js"

local function set_composer_draft(bufnr, lines)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local draft_start = nil

  for index, line in ipairs(buffer_lines) do
    if line == "Draft (use :Cinder send):" then
      draft_start = index
      break
    end
  end

  assert(draft_start ~= nil, "expected composer draft label to exist")
  vim.api.nvim_buf_set_lines(bufnr, draft_start, -1, false, lines)
end

local function get_composer_draft(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local draft_start = nil

  for index, line in ipairs(buffer_lines) do
    if line == "Draft (use :Cinder send):" then
      draft_start = index + 1
      break
    end
  end

  assert(draft_start ~= nil, "expected composer draft label to exist")
  return table.concat(vim.list_slice(buffer_lines, draft_start, #buffer_lines), "\n")
end

cinder.setup({
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
      interval_ms = 10,
      total_ticks = 3,
    },
    pi = {
      command = { "node", mock_pi },
      agent_dir = cwd .. "/.tmp/pi-agent",
    },
  },
})

local commands = vim.api.nvim_get_commands({ builtin = false })

assert(commands.Cinder, "expected Cinder command to be registered")
assert(not commands.CinderAsk, "did not expect CinderAsk alias to be registered")
assert(not commands.CinderDo, "did not expect CinderDo alias to be registered")
assert(not commands.CinderRuns, "did not expect CinderRuns alias to be registered")
assert(not commands.CinderKill, "did not expect CinderKill alias to be registered")
assert(not commands.CinderAsk, "did not expect CinderAsk alias to be registered")

local original_buf = vim.api.nvim_get_current_buf()
vim.cmd("Cinder")

local composer_buf = vim.api.nvim_get_current_buf()
local composer_lines = vim.api.nvim_buf_get_lines(composer_buf, 0, -1, false)
local composer_text = table.concat(composer_lines, "\n")

assert(composer_buf ~= original_buf, "expected bare :Cinder to open a composer buffer")
assert(vim.b[composer_buf].cinder_session_id == "composer-1", "expected bare :Cinder to create the first composer session")
assert(composer_text:find("Draft %(use :Cinder send%):", 1), "expected composer to include a draft section")

vim.api.nvim_set_current_buf(original_buf)
vim.cmd("Cinder")
assert(vim.api.nvim_get_current_buf() == composer_buf, "expected bare :Cinder to reuse the existing composer buffer")

vim.api.nvim_set_current_buf(original_buf)

local example_path = vim.fn.tempname() .. ".lua"
vim.api.nvim_set_option_value("swapfile", false, { buf = 0 })
vim.api.nvim_buf_set_name(0, example_path)
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "local M = {}",
  "function M.answer()",
  "  return 42",
  "end",
})

vim.cmd("Cinder")
assert(vim.api.nvim_get_current_buf() == composer_buf, "expected bare :Cinder to reuse composer after editing source")
vim.api.nvim_set_current_buf(original_buf)

vim.cmd("Cinder do rename this function")

assert(vim.wait(200, function()
  local run = state.get_run(1)
  return run and run.status == "done"
end, 10), "expected first do run to finish")

local first_run = state.get_run(1)
assert(first_run.kind == "do", "expected first run to be a do run")

vim.api.nvim_set_current_buf(composer_buf)
set_composer_draft(composer_buf, {
  "what is wrong with this program?",
})
vim.cmd("Cinder send")

assert(vim.wait(200, function()
  local run = state.get_run(2)
  return run and run.status == "done"
end, 10), "expected first composer send to finish")

local send_run = state.get_run(2)
local send_lines = vim.api.nvim_buf_get_lines(send_run.display_bufnr, 0, -1, false)
local send_text = table.concat(send_lines, "\n")

assert(send_run.kind == "composer", "expected second run to be a composer run")
assert(send_text:find("Session: composer%-1", 1), "expected composer header to include the session id")
assert(send_text:find("Backend: pi/%-", 1), "expected composer header to include provider and model")
assert(send_text:find("> what is wrong with this program%?", 1), "expected transcript to include the composer prompt")
assert(send_text:find("mock pi response turn 1", 1, true), "expected transcript to include the first mock pi response")
assert(send_text:find("Current file:", 1, true), "expected prompt sent to pi to include a current file block")
assert(send_text:find(example_path, 1, true), "expected prompt sent to pi to include the source file path")

local send_session = state.get_session(send_run.session_id)
assert(send_session.pending_response == nil, "expected pending_response to clear after completion")
assert(send_session.spinner_timer == nil, "expected spinner to stop after completion")

local draft_after_send = get_composer_draft(composer_buf)
assert(draft_after_send == "", "expected composer draft to clear after send")

set_composer_draft(composer_buf, {
  "what should I change next?",
  "Focus on the return value.",
})
vim.cmd("Cinder send")

assert(vim.wait(200, function()
  local run = state.get_run(3)
  return run and run.status == "done"
end, 10), "expected second composer send to finish")

local follow_up_run = state.get_run(3)
assert(follow_up_run.session_id == send_run.session_id, "expected composer follow-up to reuse the same session")
local follow_up_lines = vim.api.nvim_buf_get_lines(follow_up_run.display_bufnr, 0, -1, false)
local follow_up_text = table.concat(follow_up_lines, "\n")
assert(follow_up_text:find("mock pi response turn 2", 1, true), "expected second composer send to reuse the same mock pi session")
assert(follow_up_text:find("> what should I change next%?", 1), "expected transcript to include the second composer prompt")

vim.api.nvim_set_current_buf(original_buf)
vim.cmd("2,3Cinder")
assert(vim.api.nvim_get_current_buf() == composer_buf, "expected ranged bare :Cinder to reuse the composer buffer")

set_composer_draft(composer_buf, {
  "where is this function used",
})
vim.cmd("Cinder send")

assert(vim.wait(200, function()
  local run = state.get_run(4)
  return run and run.status == "done"
end, 10), "expected ranged composer send to finish")

local ranged_run = state.get_run(4)
local ranged_lines = vim.api.nvim_buf_get_lines(ranged_run.display_bufnr, 0, -1, false)
local ranged_text = table.concat(ranged_lines, "\n")

assert(ranged_text:find("Selected lines %(2%-3%)", 1), "expected ranged composer send to include selected line range")
assert(ranged_text:find("function M.answer%(%)", 1), "expected ranged composer send to include selected lines")
assert(ranged_text:find("  return 42", 1, true), "expected ranged composer send to include selected return line")

cinder.setup({
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
      interval_ms = 20,
      total_ticks = 10,
    },
    pi = {
      command = { "node", mock_pi },
      agent_dir = cwd .. "/.tmp/pi-agent",
    },
  },
})

vim.cmd("Cinder do long running task")
vim.api.nvim_set_current_buf(composer_buf)
set_composer_draft(composer_buf, {
  "slow question",
})
vim.cmd("Cinder send")
vim.cmd("Cinder kill")

assert(vim.wait(200, function()
  local run = state.get_run(6)
  return run and run.status == "cancelled"
end, 10), "expected killed composer run to become cancelled")

local cancelled_lines = vim.api.nvim_buf_get_lines(composer_buf, 0, -1, false)
local cancelled_text = table.concat(cancelled_lines, "\n")
assert(cancelled_text:find("%[cancelled%]"), "expected cancelled composer turn to be rendered in the transcript")

assert(vim.wait(400, function()
  local run = state.get_run(5)
  return run and run.status == "done"
end, 10), "expected final do run to finish")

vim.cmd("Cinder runs")

local current_buf = vim.api.nvim_get_current_buf()
local filetype = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
local text = table.concat(lines, "\n")

assert(filetype == "cinder-runs", "expected runs buffer filetype")
assert(text:find("%[1%]"), "expected runs buffer to list run 1")
assert(text:find("%[5%]"), "expected runs buffer to list run 5")
assert(text:find("%[6%]"), "expected runs buffer to list run 6")

vim.cmd("Cinder doctor")

local doctor_buf = vim.api.nvim_get_current_buf()
local doctor_filetype = vim.api.nvim_get_option_value("filetype", { buf = doctor_buf })
local doctor_lines = vim.api.nvim_buf_get_lines(doctor_buf, 0, -1, false)
local doctor_text = table.concat(doctor_lines, "\n")

assert(doctor_filetype == "cinder-doctor", "expected doctor buffer filetype")
assert(doctor_text:find("Cinder Doctor", 1, true), "expected doctor report header")
assert(doctor_text:find("Default fallback", 1, true), "expected doctor report to include the default fallback")
assert(doctor_text:find("Provider: pi", 1, true), "expected doctor report to include pi provider")
assert(doctor_text:find("Model: provider default %(not pinned%)", 1), "expected doctor report to describe the unpinned composer model")
assert(doctor_text:find("Profile: fake", 1, true), "expected doctor report to include the fake profile")
assert(doctor_text:find("Provider: fake", 1, true), "expected doctor report to include fake provider")
assert(doctor_text:find("Ask: default fallback %-%> pi/%-", 1), "expected doctor report to describe ask selection")
assert(doctor_text:find("Inline: profile fake %-%> fake/fake%-do", 1), "expected doctor report to describe inline selection")

vim.cmd("qa!")
