# sase-neovim

Neovim plugin for [sase](https://github.com/sase-org/sase_101) integration.

## Features

- Syntax highlighting for project spec files (`~/.sase/projects/<project>/<project>.gp`)
  - Colors match the `sase ace` TUI display

## Installation

### lazy.nvim (local)

```lua
{
  name = "sase-neovim",
  dir = "~/projects/github/sase-org/sase-neovim",
}
```

### lazy.nvim (remote)

```lua
{ "sase-org/sase-nvim" }
```
