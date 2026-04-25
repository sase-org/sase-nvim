-- Opt-in <C-t> completion dispatcher. The keymap is NOT bound unless
-- the user calls `require("sase").setup({ complete = { keymap = true } })`,
-- so this file on its own is a no-op — the module is simply made available.
--
-- Keep this file separate from plugin/sase_xprompt.lua so users can
-- disable either the <C-t> completion or the #@ trigger independently.

if vim.g.loaded_sase_complete then
  return
end
vim.g.loaded_sase_complete = true

-- :SaseFileHistoryRefresh — drop the cached recent-files list so the
-- next <C-t> pick refetches from `sase file-history list`.
vim.api.nvim_create_user_command("SaseFileHistoryRefresh", function()
  require("sase.complete.file_history").refresh()
  vim.notify("file-history cache refreshed", vim.log.levels.INFO)
end, { desc = "Refresh sase file-history cache" })
