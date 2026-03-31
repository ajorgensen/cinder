local tests = {
  "tests.config_spec",
  "tests.context_spec",
  "tests.prompt_spec",
  "tests.ui_spec",
  "tests.runner_spec",
  "tests.integration_spec",
}

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h"))

local passed = 0
local failed = 0

for _, module_name in ipairs(tests) do
  local cases = require(module_name)
  for _, case in ipairs(cases) do
    local ok, err = pcall(case.run)
    if ok then
      passed = passed + 1
      print("PASS " .. case.name)
    else
      failed = failed + 1
      print("FAIL " .. case.name)
      print(err)
    end
  end
end

print(string.format("%d passed, %d failed", passed, failed))

if failed > 0 then
  vim.cmd.cquit({ count = 1 })
else
  vim.cmd("qa!")
end
