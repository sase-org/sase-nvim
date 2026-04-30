-- Thin wrapper around the existing xprompt picker so the <C-t>
-- dispatcher has a uniform per-mode entry point. Translates a
-- SaseTokenInfo (the `#token` under cursor) into a `replace_range`
-- so the chosen `#name` overwrites the existing token instead of
-- being appended next to it (Phase 3 behaviour).

local M = {}

--- Open the xprompt picker.
--- @param opts? { origin_win?: integer, was_insert?: boolean, token?: SaseTokenInfo }
function M.pick(opts)
  opts = opts or {}
  local replace_range = nil
  local token = opts.token
  if token then
    replace_range = {
      row = token.row,
      col_start = token.col_start,
      col_end = token.col_end,
    }
  end
  require("sase.xprompt").pick({
    origin_win = opts.origin_win,
    was_insert = opts.was_insert,
    replace_range = replace_range,
    token = token,
  })
end

return M
