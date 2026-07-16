# sase-nvim — Neovim Plugin for sase

## Overview

Neovim plugin for [sase](https://github.com/sase-org/sase) integration. Provides filetype detection and syntax
highlighting for project spec files, plus YAML language server schema configuration for sase config and xprompt files.

## Features

### Filetype Detection & Syntax Highlighting

Automatic detection and syntax highlighting for project spec files (`~/.sase/projects/<project>/<project>.sase`; legacy
`.gp` files are also detected) with colors matching the `sase ace` TUI:

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

| Cursor on…                                   | Opens…                                                   |
| -------------------------------------------- | -------------------------------------------------------- |
| `#token` / `#!token` (xprompt reference)     | LSP completion, or legacy xprompt picker                 |
| `/skill` / `/partial` (slash skill)          | LSP completion, or skill-filtered picker                 |
| `%directive`                                 | LSP directive completion                                 |
| `#+` / `#+project` (VCS project trigger)     | LSP VCS project completion (expands to `#gh:sase …`)     |
| `#gh:` / `#git:` (VCS ref root)              | LSP VCS ref completion for projects, PRs, and namespaces |
| `#gh:owner/` / `#gh(owner/` (VCS repo ref)   | LSP VCS repository completion                            |
| bare snippet trigger prefix (`foo`)          | LSP SASE snippet completion                              |
| inside `<placeholder>`                       | LSP document-local placeholder completion                |
| path-like token (`~/foo`, `./bar`, `a/b.c`…) | LSP file completion, or file picker                      |
| empty / no token                             | LSP recent-file completion, or recent files picker       |

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
})
```

`completion_backend = "auto"` is the default. It uses the LSP when `sase lsp --version` succeeds or `sase-xprompt-lsp`
is executable, and otherwise keeps the existing picker behavior. Set `completion_backend = "legacy"` or
`lsp.enabled = false` to keep the old picker-only path. `lsp.native_completion = "auto"` enables Neovim's native
`vim.lsp.completion` frontend unless `nvim-cmp` / `cmp_nvim_lsp` is detected. Set it to `false` when `nvim-cmp` should
own LSP completion and snippet expansion.

The legacy xprompt picker uses `sase xprompt list` insertion metadata. Inline xprompts and embeddable workflows insert
as `#name`; standalone workflows insert as `#!name`. Typing `#!` before `<C-t>` filters the picker to standalone
workflows. Typing `/` or `/partial` before `<C-t>` filters the picker to entries where `sase xprompt list` reports
`is_skill = true`, and inserts the selected skill as `/name`. When `sase xprompt list` includes descriptions, fallback
picker rows show the xprompt description, local picker filtering matches xprompt and input descriptions, and Telescope
previews include described inputs above the existing content preview.

In the recent-files picker, `<C-l>` (or `<Enter>`) inserts the highlighted path and `<C-d>` removes the highlighted
entry from `~/.sase/file_reference_history.json` and refreshes the picker in place. Run `:SaseFileHistoryRefresh` to
drop the cached list so the next `<C-t>` re-fetches from `sase file-history list`.

In the fallback file-system picker, candidates come from `sase file list --path <cwd> --token <token>`. Selecting a file
inserts the full path; selecting a directory drills down and re-opens the picker rooted at the chosen directory.

### XPrompt Picker

Typing `#@` opens the xprompt picker in insert mode. Picker entries show the same reference text that will be inserted,
so standalone workflows appear as `#!sync` while inline-capable prompts and workflows appear as `#commit`. Closing the
picker without a selection restores the original single `#`.

### YAML Language Server Schemas

Automatically configures `yamlls` with schema associations for sase YAML files:

- **Config schema** — Applied to project `sase/sase.yml`, global `sase_*.yml`, `src/sase/default_config.yml`, and legacy
  project `sase.yml` files during the compatibility window
- **XPrompt workflow schema** — Applied to YAML files under canonical `sase/xprompts/` and legacy `xprompts/` or
  `.xprompts/` directories during the compatibility window
- **XPrompt collection schema** — Applied to `xprompts.yml` / `xprompts.yaml` files

The legacy associations are editor read compatibility, not recommended save locations. SASE 0.10 writes project content
only to `sase/sase.yml` and `sase/xprompts/`; no legacy-removal release is assigned. See the
[content-layout migration guide](https://sase.sh/content-layout/) before deleting or consolidating both-path trees.

Schema paths are resolved asynchronously via `sase path` to avoid blocking Neovim startup.

### XPrompt LSP

The plugin can start the SASE xprompt language server for git commit, `sase`, `sase_prompt`, and prompt-oriented
Markdown buffers. Plain Markdown prose files are skipped by default. Markdown buffers are eligible when they are under
the canonical `sase/xprompts/` directory, under a legacy `xprompts/` or `.xprompts/` directory during the compatibility
window, or when their filename matches SASE prompt editor temporary files such as `sase_ace_prompt_*.md` or
`sase_prompt_*.md`. LSP-backed completion is the normal path after `setup()`:

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
})
```

Command resolution prefers `lsp.cmd`, then `SASE_XPROMPT_LSP_CMD`, then a verified `sase lsp`, then `sase-xprompt-lsp`.
Set `lsp.allow_all_markdown = true` only if you want the legacy behavior where every Markdown buffer can attach to the
xprompt LSP. The LSP client uses `.sase` or `.git` as the project root when available. The `#@` trigger and
`:SaseXPrompts` picker commands remain picker-based browse surfaces. They keep using `sase xprompt list` until the LSP
exposes a browse/catalog request, and file-history deletion keeps using `sase file-history delete`.

When the LSP is attached, normal Neovim go-to-definition works for disk-backed xprompt references. Use your existing LSP
mapping, such as `gd`, or call `vim.lsp.buf.definition()` on `#foo`, `#!workflow`, namespaced references like
`#gh__review`, or slash skills like `/sase_plan`. The plugin does not parse source paths in Lua; it relies on the
server's standard `textDocument/definition` response.

The LSP client advertises snippet-capable completion, using `cmp_nvim_lsp.default_capabilities()` when available and a
snippet-capable fallback otherwise. Bare SASE snippet trigger prefixes can complete to `CompletionItemKind.Snippet`
items supplied by the server. Snippets come from the same Python helper-backed registry as the ACE prompt widget,
including `ace.snippets` and xprompts marked with `snippet: true` or `snippet: <trigger>`. The Lua plugin does not shell
out to load that registry.

#### Placeholder completion

Typing `<` inside a prompt offers placeholder texts already used elsewhere in the current buffer. Continue typing to
filter them case-insensitively, then accept a row to replace the current inner text and finish the closing `>`. The menu
stays quiet when the buffer has no reusable placeholders.

The server advertises `<` as a completion trigger, so native `vim.lsp.completion` and `nvim-cmp` open the menu without
extra Lua configuration. A SASE snippet whose first tabstop is immediately inside `<>` also asks the editor to trigger
completion after expansion; for example, accepting a `cbi` snippet such as `` `<$1>`$0 `` moves directly into the
placeholder menu while preserving later snippet tabstops. Use the configured `<C-t>` dispatcher to request the same
completion manually.

The server also advertises `+` as a completion trigger character. Typing `#+` at the start of a line, at end of buffer,
or after whitespace opens a menu of active VCS projects; typing `#+sa` filters by project name. Accepting an item
prepends the project's VCS xprompt workflow tag (e.g. `#gh:sase`) to the start of the prompt and removes the `#+query`
token, replacing any VCS tag already present rather than stacking a second one. This is served entirely by the LSP —
native `vim.lsp.completion` inherits the `+` trigger and applies the prepend/replace as an `additionalTextEdits` edit,
and `nvim-cmp` picks it up the same way through `cmp_nvim_lsp.default_capabilities()`. No extra Lua configuration is
required. The completion catalog is materialized by `sase` at LSP launch and re-read per request, so newly created or
archived projects appear after the catalog is rewritten.

Root ref completion is available inside registered VCS workflow refs before the namespace slash. Typing `:` or `(` after
a workflow tag, such as `#gh:` or `#git(`, opens project and PR-sized ChangeSpec rows for that provider. Providers can
also add local namespace rows; accepting a namespace inserts a trailing slash such as `#gh:sase-org/` and asks the
editor to trigger completion again so repository completion can take over. Accepting a project or ChangeSpec completes
the current ref token, for example `#gh:sase ` or `#gh(sase)`.

Repository-name completion is available inside registered VCS workflow refs after the namespace slash. Typing a ref such
as `#gh:bbugyi200/` or `#gh(bbugyi200/` asks the owning workspace provider for repositories in that namespace. Accepting
a row replaces only the ref value, preserving the workflow prefix and HITL suffix; colon refs receive a trailing space
(`#gh:bbugyi200/sase `), while parenthesized refs receive a closing parenthesis (`#gh(bbugyi200/sase)`).

Manual smoke check (snippets):

1. Add a local `sase/sase.yml` with an `ace.snippets` entry and an xprompt with `snippet: true`.
2. Open an eligible Markdown or SASE prompt buffer under that project and type the snippet trigger prefix.
3. Invoke LSP completion, accept the snippet item, and verify Neovim expands the `$1`/`$0` tabstops.

Manual smoke check (placeholder completion):

1. Open an eligible prompt buffer and enter a reusable placeholder, such as `Review <the plan> first.`
2. On another line, type `<`; verify `the plan` appears. Continue with `<the p` to verify prefix filtering.
3. Accept the row and verify the text becomes `<the plan>` with the cursor after `>`. Press `<C-t>` inside another
   placeholder to verify the manual trigger path.
4. If a snippet such as `` cbi: '`<$1>`$0' `` is configured, accept `cbi` and verify the placeholder menu opens at
   `$1` while normal snippet tabstop navigation remains available.

The headless equivalent of this check lives in `tests/lsp_placeholder_smoke.lua`.

Manual smoke check (`#+` VCS project completion):

1. From an active SASE project, open an eligible buffer (e.g. `sase_prompt_*.md`) under a `.sase`/`.git` root.
2. Type a prompt followed by `#+` (for example `Describe this repo. #+`); the project menu opens. Filter with `#+sa`.
3. Accept a project and verify the prompt becomes `#gh:<project> Describe this repo.` with any prior VCS tag replaced.

The headless equivalent of this check lives in `tests/lsp_vcs_project_smoke.lua`.

Manual smoke check (`#gh:` VCS ref-root completion):

1. From an active SASE project with the relevant workspace-provider plugin installed, open an eligible prompt buffer.
2. Type a registered workflow ref root, such as `#gh:` or `#git:`, and verify projects and active PR-sized ChangeSpecs
   appear. For GitHub, namespace rows such as `sase-org/` may also appear.
3. Accept a project and verify the ref becomes `#gh:sase ` or `#gh(sase)`. Accept a namespace and verify it becomes
   `#gh:sase-org/` without closing the prompt token, ready for repository completion.

The headless equivalent of this check lives in `tests/lsp_vcs_ref_smoke.lua`.

Manual smoke check (`#gh:owner/` VCS repository completion):

1. From an active SASE project with the relevant workspace-provider plugin installed, open an eligible prompt buffer.
2. Type a registered workflow ref and namespace slash, such as `#gh:bbugyi200/`; filter by continuing the repository
   name.
3. Accept a repository and verify only the ref value changes, such as `#gh:bbugyi200/sase ` or `#gh(bbugyi200/sase)`.

The headless equivalent of this check lives in `tests/lsp_vcs_repo_smoke.lua`.

For troubleshooting, check Neovim's LSP log (`:lua print(vim.lsp.get_log_path())`) and verify the server command with
`sase lsp --version` or `sase-xprompt-lsp --version`.

### Alt Brace Syntax (`%{...}`)

The plugin highlights and helps edit the `%{A | B}` alt fan-out shorthand (sase's preferred spelling for `%alt(A, B)`)
in the same prompt-oriented buffers the LSP attaches to: `gitcommit`, `sase`, `sase_prompt`, and eligible `markdown`
buffers (under canonical `sase/xprompts/`, legacy `xprompts/` / `.xprompts/` during the compatibility window, or
matching SASE prompt temp files), honoring `allow_all_markdown`. Both features are on by default after `setup()` and
inherit the LSP filetype and `allow_all_markdown` settings.

**Highlighting** marks each part of a fan-out with its own highlight group, so delimiters read differently from branch
separators:

| Highlight group     | Spans                            | Default link |
| ------------------- | -------------------------------- | ------------ |
| `SaseAltDelimiter`  | `%{` openers and `}` closers     | `Delimiter`  |
| `SaseAltSeparator`  | top-level `\|` branch separators | `Operator`   |
| `SaseAltBranchName` | `name=` named-branch prefixes    | `Identifier` |
| `SaseAltError`      | unmatched `%{` openers           | `Error`      |

Override the look by linking or defining those groups in your colorscheme (e.g.
`vim.api.nvim_set_hl(0, "SaseAltDelimiter", { link = "Special" })`).

**Editing** mirrors the ACE prompt input for `%{...}` shorthand spacing:

- Typing `{` immediately after a directive-valid `%` inserts two spaces after the opening brace and parks the cursor
  after the first space. The plugin does not insert the closing `}`; use your normal editor auto-pair plugin for brace
  pairing.
- Typing `|` inside a live `%{...}` span inserts a padded ` | ` separator, keeps the cursor before the closing `}`, and
  normalizes comma spacing in the current branch — for example, typing `|` after `%{foo ,bar, and baz` yields
  `%{foo, bar, and baz | }`.

The plugin does not perform paired deletion for an empty `%{}`. The `#@` xprompt picker trigger and ordinary `{` / `|`
typing outside a `%{...}` context are unaffected.

Configure or disable either feature through `setup()`:

```lua
require("sase").setup({
  alt_highlight = {
    enabled = true,             -- default
    allow_all_markdown = false, -- inherits from lsp.allow_all_markdown by default
    -- filetypes = { "markdown", "gitcommit", "sase", "sase_prompt" }, -- inherits from lsp.filetypes
  },
  alt_editing = {
    enabled = true,             -- default
    allow_all_markdown = false, -- inherits from lsp.allow_all_markdown by default
    -- filetypes = { ... },     -- inherits from lsp.filetypes
  },
})
```

The legacy `%(A, B)` shorthand still launches correctly, but new prompts should prefer `%{A | B}`; only the brace form
is highlighted and separator-edited.

## Requirements

- Neovim >= 0.8
- `sase` on `PATH` for picker fallback, file-history deletion, schema discovery, and the default LSP wrapper — install
  it with `uv tool install sase` (see the [SASE install guide](https://github.com/sase-org/sase/blob/master/INSTALL.md))
- `sase lsp` support or a standalone `sase-xprompt-lsp` binary for LSP-backed completion
- Optional: `nvim-telescope/telescope.nvim` for the richer picker UI. Without Telescope, pickers fall back to
  `vim.ui.select`.
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

| Command                   | Description                                      |
| ------------------------- | ------------------------------------------------ |
| `:SaseXPrompts`           | Open the xprompt picker manually                 |
| `:SaseXPromptsRefresh`    | Refresh the cached `sase xprompt list` results   |
| `:SaseFileHistoryRefresh` | Refresh the cached `sase file-history list` data |

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
