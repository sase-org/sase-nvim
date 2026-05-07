-- <C-t> completion dispatcher.
--
-- Reads the token under the cursor, classifies it (xprompt / file /
-- file_history / nil), and hands off to the right per-mode picker.

local M = {}

local _token = require("sase.complete._token")

local config = {
  completion_backend = "legacy",
}

local function legacy_trigger()
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
    local origin_win = vim.api.nvim_get_current_win()
    local was_insert = vim.fn.mode() == "i" or vim.fn.mode() == "ic"
    require("sase.complete.file").pick({
      origin_win = origin_win,
      was_insert = was_insert,
      token = info,
    })
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

--- Dispatch <C-t> completion based on what's under the cursor.
function M.trigger()
  if config.completion_backend == "lsp" then
    if require("sase.lsp").complete() then
      return
    end
    legacy_trigger()
    return
  end

  if config.completion_backend == "auto" and require("sase.lsp").complete() then
    return
  end

  legacy_trigger()
end

--- Register the <C-t> completion keymap.
---
--- Opt-in: pass `keymap = true` (or a string like "<C-t>") to install
--- the binding. The default is *no* keymap so users who installed the
--- plugin only for syntax highlighting don't have their keys clobbered.
--- @param opts? { keymap?: boolean|string, completion_backend?: "auto"|"lsp"|"legacy" }
function M.setup(opts)
  opts = opts or {}
  config.completion_backend = opts.completion_backend or "legacy"
  if opts.keymap then
    local lhs = type(opts.keymap) == "string" and opts.keymap or "<C-t>"
    vim.keymap.set("i", lhs, function()
      M.trigger()
    end, { silent = true, desc = "sase completion (xprompt / file / file-history)" })
  end
end

function M._config()
  return config
end

return M
