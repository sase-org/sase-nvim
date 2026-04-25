# sase-nvim — Neovim Plugin for sase

## Overview

Neovim plugin for [sase](https://github.com/sase-org/sase) integration. Provides filetype detection and syntax
highlighting for project spec files, plus YAML language server schema configuration for sase config and xprompt files.

## Features

### Filetype Detection & Syntax Highlighting

Automatic detection and syntax highlighting for project spec files (`~/.sase/projects/<project>/<project>.gp`) with
colors matching the `sase ace` TUI:

- Field labels (`NAME:`, `STATUS:`, `HOOKS:`, `RUNNING:`, `WORKSPACE_DIR:`, etc.)
- Status values with distinct colors (WIP, Draft, Ready, Mailed, Submitted, Reverted, Archived)
- Entry numbers, proposed entries, and sub-entries
- Inline process states (PASSED, FAILED, RUNNING, DEAD, KILLED, STARTING)
- Suffix badges with background colors for errors, running agents/processes, and other markers
- Timestamps, durations, URLs, file paths, and test targets
- Hook command prefixes, reviewer types, and draft markers

### `<C-t>` Completion Dispatcher (opt-in)

Insert-mode `<C-t>` opens a context-sensitive picker that mirrors the `sase ace` TUI:

| Cursor on…                                   | Opens…                                 |
| -------------------------------------------- | -------------------------------------- |
| `#token` (xprompt reference)                 | xprompt picker                         |
| path-like token (`~/foo`, `./bar`, `a/b.c`…) | file-system picker *(coming in Phase 5)* |
| empty / no token                             | recent files picker                    |

The keymap is **opt-in** — add this to your config to enable it:

```lua
require("sase").setup({
  complete = { keymap = true },  -- or keymap = "<C-t>"
})
```

The xprompt and recent-files branches are wired today; the file-system branch notifies "not yet implemented".

In the recent-files picker, `<C-l>` (or `<Enter>`) inserts the highlighted path and `<C-d>`
removes the highlighted entry from `~/.sase/file_reference_history.json` and refreshes the
picker in place. Run `:SaseFileHistoryRefresh` to drop the cached list so the next `<C-t>`
re-fetches from `sase file-history list`.

### YAML Language Server Schemas

Automatically configures `yamlls` with schema associations for sase YAML files:

- **Config schema** — Applied to `sase.yml` and `sase_*.yml` files
- **XPrompt workflow schema** — Applied to files under `xprompts/` and `.xprompts/` directories
- **XPrompt collection schema** — Applied to `xprompts.yml` / `xprompts.yaml` files

Schema paths are resolved asynchronously via `sase path` to avoid blocking Neovim startup.

## Requirements

- Neovim >= 0.8

## Installation

### lazy.nvim

```lua
-- Remote
{ "sase-org/sase-nvim" }

-- Local
{
  name = "sase-nvim",
  dir = "~/projects/github/sase-org/sase-nvim",
}
```

### packer.nvim

```lua
use "sase-org/sase-nvim"
```

### vim-plug

```vim
Plug 'sase-org/sase-nvim'
```

## Project Structure

```
├── ftdetect/
│   └── sase_gp.lua         # Filetype detection for .gp files
├── plugin/
│   └── sase_yamlls.lua     # YAML language server schema configuration
└── syntax/
    └── sase_gp.vim         # Syntax highlighting rules
```

## License

MIT
