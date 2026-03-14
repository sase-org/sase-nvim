# sase-neovim

Neovim plugin for [sase](https://github.com/sase-org/sase) integration.

## Features

- **Filetype detection** for project spec files (`~/.sase/projects/<project>/<project>.gp`)
- **Syntax highlighting** with colors matching the `sase ace` TUI:
  - Field labels (`NAME:`, `STATUS:`, `HOOKS:`, `RUNNING:`, etc.)
  - Status values with distinct colors (WIP, Draft, Ready, Mailed, Submitted, Reverted, Archived)
  - Entry numbers, proposed entries, and sub-entries
  - Inline process states (PASSED, FAILED, RUNNING, DEAD, KILLED, STARTING)
  - Suffix badges with background colors for errors, running agents/processes, and other markers
  - Timestamps, durations, URLs, file paths, and test targets
  - Hook command prefixes, reviewer types, and draft markers

## Requirements

- Neovim >= 0.8

## Installation

### lazy.nvim

```lua
-- Remote
{ "sase-org/sase-nvim" }

-- Local
{
  name = "sase-neovim",
  dir = "~/projects/github/sase-org/sase-neovim",
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
