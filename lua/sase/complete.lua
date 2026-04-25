-- <C-t> completion dispatcher.
--
-- Reads the token under the cursor, classifies it (xprompt / file /
-- file_history / nil), and hands off to the right per-mode picker.
-- Phase 2: only the xprompt branch is wired; file and file_history
-- branches notify "not yet implemented" and fall through to a no-op.

local M = {}

local _token = require("sase.complete._token")

--- Dispatch <C-t> completion based on what's under the cursor.
function M.trigger()
  local info = _token.token_under_cursor()
  local token_text = info and info.text or nil
  local kind = _token.classify(token_text)

  if kind == "xprompt" then
    local origin_win = vim.api.nvim_get_current_win()
    local was_insert = vim.fn.mode() == "i" or vim.fn.mode() == "ic"
    require("sase.complete.xprompt").pick({
      origin_win = origin_win,
      was_insert = was_insert,
      token = info,
    })
    return
  end

  if kind == "file" then
    vim.notify("sase: file completion not yet implemented", vim.log.levels.WARN)
    return
  end

  if kind == "file_history" then
    local origin_win = vim.api.nvim_get_current_win()
    local was_insert = vim.fn.mode() == "i" or vim.fn.mode() == "ic"
    require("sase.complete.file_history").pick({
      origin_win = origin_win,
      was_insert = was_insert,
    })
    return
  end

  -- Unrecognised token — no-op, same as the TUI.
end

--- Register the <C-t> completion keymap.
---
--- Opt-in: pass `keymap = true` (or a string like "<C-t>") to install
--- the binding. The default is *no* keymap so users who installed the
--- plugin only for syntax highlighting don't have their keys clobbered.
--- @param opts? { keymap?: boolean|string }
function M.setup(opts)
  opts = opts or {}
  if opts.keymap then
    local lhs = type(opts.keymap) == "string" and opts.keymap or "<C-t>"
    vim.keymap.set("i", lhs, function()
      M.trigger()
    end, { silent = true, desc = "sase completion (xprompt / file / file-history)" })
  end
end

return M
