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
--- @param opts? { complete?: { keymap?: boolean|string } }
function M.setup(opts)
  opts = opts or {}
  if opts.complete ~= nil then
    require("sase.complete").setup(opts.complete)
  end
end

return M
