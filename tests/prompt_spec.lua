local h = require("tests.helpers")

return {
  {
    name = "prompt renders cursor context",
    run = function()
      h.reset()
      local text = require("cinder.prompt").compose({
        file_path = "lua/cinder/init.lua",
        cursor_line = 42,
      }, "Explain this file.")

      h.contains(text, "Current file: lua/cinder/init.lua")
      h.contains(text, "Cursor line: 42")
      h.contains(text, "Task:\nExplain this file.")
    end,
  },
  {
    name = "prompt renders selected text",
    run = function()
      h.reset()
      local text = require("cinder.prompt").compose({
        file_path = "README.md",
        selection = {
          start_line = 5,
          end_line = 7,
          text = "foo\nbar",
        },
      }, "Rewrite this section.")

      h.contains(text, "Selected range: 5-7")
      h.contains(text, "Selected text:\nfoo\nbar")
    end,
  },
  {
    name = "prompt passes raw task without file context",
    run = function()
      h.reset()
      local text = require("cinder.prompt").compose(nil, "Just answer the question.")

      h.eq(text, "Just answer the question.")
    end,
  },
  {
    name = "prompt supports selection-only requests",
    run = function()
      h.reset()
      local text = require("cinder.prompt").compose({
        file_path = "README.md",
        selection = {
          start_line = 5,
          end_line = 5,
          text = "// write a helper",
        },
      }, "")

      h.contains(text, "Selected text:\n// write a helper")
      h.contains(text, "Treat the selected text as the primary request")
      h.expect(text:find("Task:", 1, true) == nil, "selection-only prompt should omit Task section")
    end,
  },
}
