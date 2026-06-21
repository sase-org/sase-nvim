-- Top-level entry point for sase-nvim: `require("sase").setup{...}`.

local M = {}

--- Configure sase-nvim.
---
--- Example:
--- ```lua
--- require("sase").setup({
---   complete = { keymap = true },  -- bind <C-t> in insert mode
--- })
--- ```
--- @param opts? { complete?: { keymap?: boolean|string, completion_backend?: "auto"|"lsp"|"legacy" }, lsp?: { enabled?: boolean, cmd?: string|string[], native_completion?: "auto"|boolean, allow_all_markdown?: boolean }, alt_highlight?: { enabled?: boolean, allow_all_markdown?: boolean, filetypes?: string[] }, alt_editing?: { enabled?: boolean, allow_all_markdown?: boolean, filetypes?: string[] }, xprompt_spacer?: { enabled?: boolean, allow_all_markdown?: boolean, filetypes?: string[] } }
function M.setup(opts)
  opts = opts or {}
  require("sase.lsp").setup(opts.lsp or {})
  require("sase.alt_highlight").setup(opts.alt_highlight or {})
  require("sase.alt_edit").setup(opts.alt_editing or {})
  require("sase.xprompt_spacer").setup(opts.xprompt_spacer or {})
  if opts.complete ~= nil then
    require("sase.complete").setup(opts.complete)
  end
end

return M
