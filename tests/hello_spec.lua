local h = require("tests.helpers")

return {
  {
    name = "CinderHello prints hello world",
    run = function()
      h.reset()
      h.eq(vim.fn.exists(":CinderHello"), 2, "expected CinderHello command to be defined")

      local captured = {}
      local original_print = print
      _G.print = function(...)
        captured[#captured + 1] = table.concat(vim.tbl_map(tostring, { ... }), "\t")
      end

      local ok, err = pcall(vim.cmd, "CinderHello")
      _G.print = original_print

      if not ok then
        error(err, 0)
      end

      h.eq(#captured, 1, "expected one printed message")
      h.eq(captured[1], "hello world")
    end,
  },
}
