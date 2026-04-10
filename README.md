# cinder.nvim

Tiny Neovim glue for running a coding harness against the current editing context.

The goal is to keep the first version extremely small: capture context from the editor, launch a harness, let it do real agent work in the repo, and give just enough feedback to trust what is happening.

## What We Are Building First

An MVP Neovim plugin with two entry points:

- a prompt command for short or multiline instructions
- a long prompt command that opens a temporary buffer for writing a larger task

The plugin will gather editor context and launch the configured harness with that context.

## MVP Decisions

### Core behavior

- the harness is allowed to edit files in the repo directly
- the plugin is mainly a context collector and process launcher
- after the harness finishes, the plugin should refresh changed buffers so edits made on disk show up in Neovim
- the plugin should always have a scratch result buffer for readable final output

### Context model

By default, the plugin sends:

- current file path
- current cursor line when there is no selection
- selected line range when there is a visual selection
- selected text when there is a visual selection
- the user instruction

We are not sending the entire file by default.

Reasoning:

- large files can blow up context size
- `opencode` is an agent and can read files from the repo when needed
- file path plus range plus selected text gives the agent a precise starting point without overstuffing the prompt

### Prompt entry

We want two ways to start a task:

- quick prompt: a scratch prompt buffer for most requests, including multiline tasks
- long prompt: a scratch-style buffer for writing a longer instruction

### Execution model

- launch the harness as a background Neovim job
- stream output into a scratch result buffer

Reasoning:

- the editor integration should behave the same regardless of whether Neovim is inside tmux
- background jobs keep the flow visible without stealing screen space

### Output model

- the result buffer is the canonical place for readable harness output
- question-style tasks should write their answer into the result buffer
- edit-style tasks should still write a summary into the result buffer

Reasoning:

- some tasks return an answer rather than a file edit
- long answers are easier to read in a buffer than in notifications
- a consistent output destination keeps the UX simple

### Project rules

- do not auto-load `AGENT.md`, `README.md`, or other project instruction files in the first version
- keep context explicit and local to the command invocation

### Session model

- prefer stateless editor-triggered runs for MVP
- start with plain text output by default unless a structured format is specifically needed

## Initial UX

The first usable version should feel like this:

1. Put the cursor on a file or make a visual selection.
2. Run a command.
3. Enter a short or long instruction.
4. The plugin launches the configured harness with file-aware context.
5. The harness edits one or more files in the repo.
6. Neovim refreshes buffers and shows the result buffer.

## Proposed Initial Commands

Exact names can change, but the first shape should be:

- `:CinderPrompt` - open a prompt buffer using current file or selection context
- `:CinderPromptLong` - open a temporary prompt buffer for a longer instruction

Both commands should work from normal mode and visual mode.

## Result Buffer

The plugin should maintain a scratch result buffer for harness output.

Expected behavior:

- open or reuse a result buffer for each run
- stream background-job output there while the task is running
- append the final answer or summary there when the run completes
- keep it readable for question-style prompts and edit-style prompts alike

Example uses:

- "how many instances of Foo are in this file?" -> answer appears in the result buffer
- "replace all instances of Foo with Bar in this file" -> files may change on disk and the result buffer explains what happened

## Prompt Composition

The plugin should build a structured prompt that gives `opencode` enough context to begin work.

Example shape:

```text
You are working in a Neovim editing session.

Current file: path/to/file.lua
Cursor line: 42

Selected range: 40-48
Selected text:
...

Task:
Replace all instances of Foo with Bar in this file.
```

Notes:

- if there is no selection, omit selected range and selected text
- the file path should be repo-relative when possible
- the prompt should make it clear that `opencode` may inspect other files if needed

## Harness Integration Plan

Start simple.

- launch the harness as a background job and capture stdout/stderr into the scratch result buffer
- prefer passing prompt content as arguments rather than relying on stdin for the main flow
- use `opencode run` by default for editor-triggered runs

The important rule is that the final readable output should end up in Neovim.

Possible initial command shape:

```sh
opencode run "<composed prompt>"
```

If we need structured integration later, we can opt into `opencode --format json` for those specific flows.

We should not start with RPC unless the simpler path proves too limiting.

## Out Of Scope For MVP

- chat history
- multi-turn sessions inside Neovim
- automatic project rule loading
- search/quickfix workflows inspired by `99`
- diff review UI
- approval gates for tool calls
- fancy status UI beyond a result buffer

## Implementation Sketch

Use Lua and keep the code split by responsibility.

```text
plugin/cinder.lua          user commands
lua/cinder/init.lua        setup entrypoint
lua/cinder/config.lua      defaults and validation
lua/cinder/context.lua     file, cursor, selection context collection
lua/cinder/prompt.lua      prompt composition
lua/cinder/runner.lua      background job launch
lua/cinder/ui.lua          prompt buffers and result buffer
```

## Development Order

1. Create plugin skeleton and setup function.
2. Add quick prompt command.
3. Collect file, cursor, and visual selection context.
4. Compose the prompt.
5. Implement background job launch with a scratch result buffer.
6. Refresh changed buffers when the run completes.
7. Add the long prompt buffer command.

## Open Questions For Later

- Should we add a dedicated search command that fills quickfix, similar to `99`?
- Should small files optionally be inlined into the prompt?
- Should we support auto-loading project rules once the base flow feels solid?
- Should we switch the runner to JSON or RPC mode for richer progress updates?

## Installation

Minimum supported Neovim version: `0.11`.

Lazy.nvim:

```lua
{
  "ajorgensen/llm-plugin",
  config = function()
    require("cinder").setup()
  end,
}
```

## Setup

Default configuration:

```lua
require("cinder").setup({
  harness_command = "opencode",
  harness_args = { "run" },
  model = "openai/gpt-5.4",
  models = {
    "openai/gpt-5.4",
  },
  session_mode = "buffer",
  result_buffer = {
    name = "Cinder Results",
    open = true,
    enter = false,
    height = 12,
  },
  long_prompt_buffer = {
    name = "Cinder Prompt",
    height = 12,
  },
  selection_behavior = "auto",
  notifications = "normal",
})
```

## Commands

- `:CinderPrompt` opens a prompt buffer for the current file context.
- `:CinderPromptLong` opens a scratch buffer in its own split for a longer task.
- `:CinderContinue` sends the result buffer draft back into the active session.
- `:CinderJobs` opens a scratch buffer showing running and completed Cinder jobs.
- `:CinderSessionReset` clears the current session association.
- `:CinderModel` shows the active model, or sets it when passed an argument.
- `:CinderModelSelect` opens a picker for the configured model list.
- In the long prompt buffer:
  - `<C-s>` or `:CinderPromptSubmit` submits the task.
  - `q` or `:CinderPromptCancel` cancels the task.

Both commands work from normal mode and visual mode.

## Behavior

- The plugin sends the current file path and either the cursor line or the current visual selection.
- If the current buffer is not file-backed, the plugin skips editor context and sends only the user task.
- With `selection_behavior = "auto"`, an empty prompt plus a non-block visual selection uses the selected text as the request and replaces only that selected range with the model output.
- The whole file is not inlined by default.
- The harness runs as a background Neovim job and streams output into the result buffer.
- After the harness exits, `cinder.nvim` refreshes changed file-backed buffers with `:checktime` and appends a short completion summary.
- The default invocation is `opencode run`.
- The default model is `openai/gpt-5.4` and is passed as `--model` when the harness supports it.

## Models

- `model` is the currently active model.
- `models` is the list used by `:CinderModelSelect` and command completion for `:CinderModel`.
- Changing the active model updates future runs immediately.

## Sessions

- `session_mode = "buffer"` keeps an `opencode` session attached to the result buffer.
- The result buffer includes a `## Draft` section you can edit for follow-up messages.
- Use `:CinderContinue` or `<C-s>` in the result buffer to send that draft back into the same session.
- Use `:CinderSessionReset` to drop the current session and start fresh on the next run.

## Result Buffer

- The result buffer is the canonical place for readable output.
- When auto-open is enabled, the result buffer opens in its own split instead of replacing your current editing buffer.
- With the default `opencode run` setup, the result buffer shows captured plain-text output instead of raw event JSON.
- Background stderr is prefixed with `[stderr]`.

## Diagnostics

- Cinder writes debug lifecycle logs to `stdpath("state") .. "/cinder.log"`.
- The log includes prompt submission, job launch, stdout/stderr callbacks, and process exit events.
- Use `:CinderJobs` to inspect currently running and completed runs from inside Neovim.

## Selection Behavior

- `auto` uses replace-selection mode when you submit an empty prompt with a non-block visual selection.
- `agent` always keeps the current full-agent editing flow.
- `replace` always treats visual selections as replacement targets.

Replace-selection mode asks the model for replacement text only and applies it directly to the selected range in Neovim.

## Development

Run the headless test suite with:

```sh
nvim --headless -u NONE -c "lua dofile('tests/run.lua')"
```

## Known MVP Limits

- No chat history or persistent editor-side sessions.
- No automatic loading of `AGENT.md`, `README.md`, or other project rules.
- No diff UI, approval workflow, or quickfix/search integration.
- The result buffer summarizes completion generically; richer structured responses can come later.
