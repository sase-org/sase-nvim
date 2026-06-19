# sase-nvim — Neovim Plugin for sase

## Overview

Neovim plugin for [sase](https://github.com/sase-org/sase) integration. Provides filetype detection and syntax
highlighting for project spec files, plus YAML language server schema configuration for sase config and xprompt files.

## Features

### Filetype Detection & Syntax Highlighting

Automatic detection and syntax highlighting for project spec files
(`~/.sase/projects/<project>/<project>.sase`; legacy `.gp` files are also
detected) with colors matching the `sase ace` TUI:

- Field labels (`NAME:`, `STATUS:`, `HOOKS:`, `RUNNING:`, `WORKSPACE_DIR:`, etc.)
- Status values with distinct colors (WIP, Draft, Ready, Mailed, Submitted, Reverted, Archived)
- Entry numbers, proposed entries, and sub-entries
- Inline process states (PASSED, FAILED, RUNNING, DEAD, KILLED, STARTING)
- Suffix badges with background colors for errors, running agents/processes, and other markers
- Timestamps, durations, URLs, file paths, and test targets
- Hook command prefixes, reviewer types, and draft markers

### `<C-t>` Completion Dispatcher (opt-in)

Insert-mode `<C-t>` asks the SASE xprompt LSP for completion when available, then falls back to the legacy picker
dispatcher when the server command is unavailable or disabled:

| Cursor on…                                   | Opens…                                 |
| -------------------------------------------- | -------------------------------------- |
| `#token` / `#!token` (xprompt reference)     | LSP completion, or legacy xprompt picker |
| `/skill` / `/partial` (slash skill)          | LSP completion, or skill-filtered picker |
| `%directive`                                 | LSP directive completion                |
| bare snippet trigger prefix (`foo`)          | LSP SASE snippet completion             |
| path-like token (`~/foo`, `./bar`, `a/b.c`…) | LSP file completion, or file picker     |
| empty / no token                             | LSP recent-file completion, or recent files picker |

The keymap is **opt-in** — add this to your config to enable it:

```lua
require("sase").setup({
  complete = {
    keymap = true,                 -- or keymap = "<C-t>"
    completion_backend = "auto",   -- "auto", "lsp", or "legacy"
  },
  lsp = {
    enabled = true,
    cmd = nil, -- string/table override; otherwise SASE_XPROMPT_LSP_CMD, `sase lsp`, or `sase-xprompt-lsp`
    allow_all_markdown = false, -- set true to attach to every Markdown buffer
    native_completion = "auto", -- true, false, or "auto"
  },
  highlights = {
    xprompt_separator = { fg = "#D75FFF", bold = true, ctermfg = 171 },
  },
})
```

`completion_backend = "auto"` is the default. It uses the LSP when `sase lsp --version` succeeds or
`sase-xprompt-lsp` is executable, and otherwise keeps the existing picker behavior. Set
`completion_backend = "legacy"` or `lsp.enabled = false` to keep the old picker-only path.
`lsp.native_completion = "auto"` enables Neovim's native `vim.lsp.completion` frontend unless `nvim-cmp` /
`cmp_nvim_lsp` is detected. Set it to `false` when `nvim-cmp` should own LSP completion and snippet expansion.

The legacy xprompt picker uses `sase xprompt list` insertion metadata. Inline xprompts
and embeddable workflows insert as `#name`; standalone workflows insert as
`#!name`. Typing `#!` before `<C-t>` filters the picker to standalone workflows.
Typing `/` or `/partial` before `<C-t>` filters the picker to entries where
`sase xprompt list` reports `is_skill = true`, and inserts the selected skill as
`/name`. When `sase xprompt list` includes descriptions, fallback picker rows show
the xprompt description, local picker filtering matches xprompt and input
descriptions, and Telescope previews include described inputs above the existing
content preview.

In the recent-files picker, `<C-l>` (or `<Enter>`) inserts the highlighted path and `<C-d>`
removes the highlighted entry from `~/.sase/file_reference_history.json` and refreshes the
picker in place. Run `:SaseFileHistoryRefresh` to drop the cached list so the next `<C-t>`
re-fetches from `sase file-history list`.

In the fallback file-system picker, candidates come from `sase file list --path <cwd> --token <token>`. Selecting a file
inserts the full path; selecting a directory drills down and re-opens the picker rooted at the chosen directory.

### XPrompt Picker

Typing `#@` opens the xprompt picker in insert mode. Picker entries show the
same reference text that will be inserted, so standalone workflows appear as
`#!sync` while inline-capable prompts and workflows appear as `#commit`. Closing
the picker without a selection restores the original single `#`.

### YAML Language Server Schemas

Automatically configures `yamlls` with schema associations for sase YAML files:

- **Config schema** — Applied to `sase.yml`, `sase_*.yml`, and `src/sase/default_config.yml` files
- **XPrompt workflow schema** — Applied to files under `xprompts/` and `.xprompts/` directories
- **XPrompt collection schema** — Applied to `xprompts.yml` / `xprompts.yaml` files

Schema paths are resolved asynchronously via `sase path` to avoid blocking Neovim startup.

### XPrompt LSP

The plugin can start the SASE xprompt language server for git commit, `sase`, `sase_prompt`, and prompt-oriented
Markdown buffers. Plain Markdown prose files are skipped by default. Markdown buffers are eligible when they are under an
`xprompts/` or `.xprompts/` directory, or when their filename matches SASE prompt editor temporary files such as
`sase_ace_prompt_*.md` or `sase_prompt_*.md`. LSP-backed completion is the normal path after `setup()`:

```lua
require("sase").setup({
  complete = {
    keymap = true,
    completion_backend = "auto", -- default: uses LSP when available, legacy picker otherwise
  },
  lsp = {
    enabled = true, -- default
    -- cmd = { "sase", "lsp" },
    -- allow_all_markdown = false, -- set true for legacy all-Markdown attachment
    -- native_completion = "auto", -- true, false, or "auto"
  },
  highlights = {
    -- Used for LSP semantic tokens on multi-agent prompt `---` separators.
    xprompt_separator = { fg = "#D75FFF", bold = true, ctermfg = 171 },
  },
})
```

Command resolution prefers `lsp.cmd`, then `SASE_XPROMPT_LSP_CMD`, then a verified `sase lsp`, then
`sase-xprompt-lsp`. Set `lsp.allow_all_markdown = true` only if you want the legacy behavior where every Markdown buffer
can attach to the xprompt LSP. The LSP client uses `.sase` or `.git` as the project root when available. The `#@` trigger and
`:SaseXPrompts` picker commands remain picker-based browse surfaces. They keep using `sase xprompt list` until the LSP
exposes a browse/catalog request, and file-history deletion keeps using `sase file-history delete`.

When the LSP is attached, normal Neovim go-to-definition works for disk-backed xprompt references. Use your existing
LSP mapping, such as `gd`, or call `vim.lsp.buf.definition()` on `#foo`, `#!workflow`, namespaced references like
`#gh__review`, or slash skills like `/sase_plan`. The plugin does not parse source paths in Lua; it relies on the
server's standard `textDocument/definition` response.

The LSP client advertises snippet-capable completion, using `cmp_nvim_lsp.default_capabilities()` when available and a
snippet-capable fallback otherwise. Bare SASE snippet trigger prefixes can complete to `CompletionItemKind.Snippet`
items supplied by the server. Snippets come from the same Python helper-backed registry as the ACE prompt widget,
including `ace.snippets` and xprompts marked with `snippet: true` or `snippet: <trigger>`. The Lua plugin does not shell
out to load that registry.

When the server advertises semantic tokens, multi-agent prompt `---` separators use the Neovim highlight group
`@lsp.type.xpromptSeparator`. The default is luminous violet (`#D75FFF`, bold, cterm `171`). Override it with
`highlights.xprompt_separator` in `setup()`, or set that option to `false` and define the highlight group yourself.

Manual smoke check:

1. Add a local `sase.yml` with an `ace.snippets` entry and an xprompt with `snippet: true`.
2. Open an eligible Markdown or SASE prompt buffer under that project and type the snippet trigger prefix.
3. Invoke LSP completion, accept the snippet item, and verify Neovim expands the `$1`/`$0` tabstops.

For troubleshooting, check Neovim's LSP log (`:lua print(vim.lsp.get_log_path())`) and verify the server command with
`sase lsp --version` or `sase-xprompt-lsp --version`.

## Requirements

- Neovim >= 0.8
- `sase` on `PATH` for picker fallback, file-history deletion, schema discovery, and the default LSP wrapper
- `sase lsp` support or a standalone `sase-xprompt-lsp` binary for LSP-backed completion
- Optional: `nvim-telescope/telescope.nvim` for the richer picker UI. Without Telescope, pickers fall back to `vim.ui.select`.
- Optional: `yamlls` / `yaml-language-server` if you want automatic sase YAML schema associations.

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

## Setup

Most plugin files load automatically when Neovim starts:

- `.sase` (and legacy `.gp`) filetype detection and syntax highlighting
- `#@` insert-mode xprompt picker trigger
- `:SaseXPrompts`, `:SaseXPromptsRefresh`, and `:SaseFileHistoryRefresh`
- YAML schema registration for `yamlls`

The `<C-t>` completion dispatcher is opt-in:

```lua
require("sase").setup({
  complete = {
    keymap = true, -- binds <C-t>
  },
})
```

To use a different insert-mode mapping:

```lua
require("sase").setup({
  complete = {
    keymap = "<C-x><C-s>",
  },
})
```

To force the picker-only fallback:

```lua
require("sase").setup({
  complete = {
    keymap = true,
    completion_backend = "legacy",
  },
  lsp = {
    enabled = false,
  },
})
```

## Commands

| Command                    | Description                                      |
| -------------------------- | ------------------------------------------------ |
| `:SaseXPrompts`            | Open the xprompt picker manually                 |
| `:SaseXPromptsRefresh`     | Refresh the cached `sase xprompt list` results   |
| `:SaseFileHistoryRefresh`  | Refresh the cached `sase file-history list` data |

## Project Structure

```
├── ftdetect/
│   └── sase_gp.lua              # Filetype detection for .sase (and legacy .gp) files under .sase/projects/
├── lua/
│   ├── sase/
│   │   ├── init.lua             # require("sase").setup entry point
│   │   ├── lsp.lua              # xprompt LSP client setup
│   │   ├── xprompt.lua          # #@ xprompt picker core
│   │   └── complete/
│   │       ├── _picker.lua      # shared insertion and insert-mode restore helpers
│   │       ├── _token.lua       # legacy fallback token classification
│   │       ├── file.lua         # fallback file-system picker
│   │       ├── file_history.lua # fallback recent-file picker
│   │       └── xprompt.lua      # fallback xprompt picker wrapper
│   └── telescope/
│       └── _extensions/sase.lua # Telescope pickers for xprompts, files, and recent files
├── plugin/
│   ├── sase_complete.lua        # completion cache command registration
│   ├── sase_xprompt.lua         # #@ trigger and xprompt commands
│   └── sase_yamlls.lua          # YAML language server schema configuration
└── syntax/
    └── sase_gp.vim              # Syntax highlighting rules
```

## License

MIT
