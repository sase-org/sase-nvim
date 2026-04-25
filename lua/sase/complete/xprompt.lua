-- Thin wrapper around the existing xprompt picker so the <C-t>
-- dispatcher has a uniform per-mode entry point. Phase 2 only needs
-- to open the existing Telescope picker — token-replacement polish
-- is Phase 3.

local M = {}

--- Open the xprompt picker.
--- @param opts? { origin_win?: integer, was_insert?: boolean, token?: SaseTokenInfo }
function M.pick(opts)
  opts = opts or {}
  require("sase.xprompt").pick({
    origin_win = opts.origin_win,
    was_insert = opts.was_insert,
  })
end

return M
