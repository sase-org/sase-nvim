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
--- @param opts? { complete?: { keymap?: boolean|string, completion_backend?: "auto"|"lsp"|"legacy" }, lsp?: { enabled?: boolean, cmd?: string|string[] } }
function M.setup(opts)
  opts = opts or {}
  require("sase.lsp").setup(opts.lsp or {})
  if opts.complete ~= nil then
    require("sase.complete").setup(opts.complete)
  end
end

return M
