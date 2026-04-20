# cinder

`cinder` is a Neovim plugin for kicking off background LLM agent tasks.

The current state of the repo is a proof-of-concept focused on validating:
- `Ask` as a scratch-buffer conversation flow
- `Do` as a background task flow
- run discovery and cancellation mechanics
- provider abstraction shape before real backend integration

Current provider state:
- `Ask` goes through a real `pi --mode rpc` adapter
- `Do` still uses the fake provider
- tests use a mock Pi RPC process for deterministic headless coverage

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ajorgensen/cinder",
  config = function()
    require("cinder").setup()
  end,
}
```

## Commands

Command surface:

```vim
:Cinder
:Cinder send
:Cinder do refactor this file to use table tests
:Cinder runs
:Cinder kill 3
:Cinder doctor
:Cinder new
```

## Current Behavior

- Bare `:Cinder` opens a scratch composer buffer.
- Running bare `:Cinder` again reuses the most recent composer buffer.
- The composer buffer contains a draft section; type there and submit with `:Cinder send`.
- `:Cinder send` reuses the current Pi session and appends the turn to the transcript.
- `Do` runs in the background and shows inline progress via virtual text.
- `runs` opens a scratch buffer with the in-memory run registry.
- `kill` cancels an active run by id.
- `kill` without an id in the composer aborts the active Pi run for that session.
- `doctor` opens a scratch report with local provider/config validation.
- `new` discards the current composer session and starts a fresh one in the same buffer, stopping any active Pi RPC process.

## Configuration

```lua
require("cinder").setup({
  provider = "pi",
  model = nil,

  profiles = {
    fake = { provider = "fake", model = "fake-do" },
  },

  ask = {
    profile = nil,
  },

  inline = {
    profile = "fake",
  },

  providers = {
    pi = {
      cmd = "pi",
      args = { "--mode", "rpc", "--no-session" },
    },
    fake = {
      interval_ms = 30,
      total_ticks = 4,
    },
  },
})
```

## Development

Run the headless smoke test with:

```sh
make test
```
