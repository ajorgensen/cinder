# cinder.nvim Manual QA Checklist

## Background job flow

- [ ] Open a file outside tmux.
- [ ] Run `:CinderPrompt` from normal mode and verify the result buffer streams output.
- [ ] Make a visual selection, run `:CinderPrompt`, and verify the selection appears in the composed prompt/output.
- [ ] Run `:CinderPromptLong`, submit with `<C-s>`, and verify the task completes.
- [ ] Run `:CinderPromptLong`, cancel with `q`, and verify the prompt buffer closes.
- [ ] Use a harness task that edits the current file and verify Neovim refreshes the buffer on completion.
- [ ] Use a harness task that prints stderr and verify stderr lines are prefixed with `[stderr]`.

## tmux flow

- [ ] Start Neovim inside tmux with `execution_mode = "auto"` or `"tmux"`.
- [ ] Run `:CinderPrompt` and verify a tmux split opens.
- [ ] Verify the harness output is visible live in the tmux pane.
- [ ] Verify the final output is imported back into the `Cinder Results` buffer.
- [ ] Verify failures in tmux mode show a readable failure summary in Neovim.

## Config and error handling

- [ ] Set an invalid `execution_mode` and verify setup raises a readable error.
- [ ] Set a missing `harness_command` and verify launch failures are surfaced clearly.
- [ ] Open an unnamed buffer, run a prompt command, and verify the plugin reports that a file-backed buffer is required.
