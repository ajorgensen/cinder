local h = require("tests.helpers")

return {
  {
    name = "jobs tracks running and completed runs",
    run = function()
      h.reset()
      local jobs = require("cinder.jobs")

      local run = jobs.create({
        prompt_kind = "quick prompt",
        result_bufnr = 7,
      })
      jobs.mark_running(run.id, {
        job_id = 42,
        backend = "job",
        command = { "opencode", "run", "task" },
      })
      jobs.mark_complete(run.id, {
        job_id = 42,
        code = 0,
        command = { "opencode", "run", "task" },
      })

      local summary = jobs.summary()
      h.eq(summary.running, 0)
      h.eq(summary.completed, 1)

      local text = table.concat(jobs.render_lines(), "\n")
      h.contains(text, "[completed] run 1")
      h.contains(text, "Prompt: quick prompt")
      h.contains(text, "Job ID: 42")
      h.contains(text, "Command: opencode run task")
    end,
  },
  {
    name = "jobs reconcile missing neovim job as lost",
    run = function()
      h.reset()
      local jobs = require("cinder.jobs")

      local run = jobs.create({
        prompt_kind = "quick prompt",
        result_bufnr = 8,
      })
      jobs.mark_running(run.id, {
        job_id = 999999,
        pid = 12345,
        backend = "job",
        command = { "opencode", "run", "task" },
      })

      jobs.reconcile()

      local summary = jobs.summary()
      h.eq(summary.running, 0)
      h.eq(summary.lost, 1)

      local text = table.concat(jobs.render_lines(), "\n")
      h.contains(text, "[lost] run 1")
      h.contains(text, "PID: 12345")
      h.contains(text, "Job is no longer tracked by Neovim")
    end,
  },
}
