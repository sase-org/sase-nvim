-- XPrompt picker triggered by ## in insert mode.
-- Also provides the :SaseXPrompts command for manual invocation.

if vim.g.loaded_sase_xprompt then
  return
end
vim.g.loaded_sase_xprompt = true

-- :SaseXPrompts — open the picker from any mode.
vim.api.nvim_create_user_command("SaseXPrompts", function()
  require("sase.xprompt").pick()
end, { desc = "Open sase xprompt picker" })

-- :SaseXPromptsRefresh — refresh the cached xprompt list.
vim.api.nvim_create_user_command("SaseXPromptsRefresh", function()
  require("sase.xprompt").refresh()
  vim.notify("xprompt cache refreshed", vim.log.levels.INFO)
end, { desc = "Refresh sase xprompt cache" })

-- Insert-mode ## trigger.
-- When the user types # and the character before cursor is already #,
-- remove the first # and open the picker. On cancel, restore a single #.
vim.api.nvim_create_autocmd("InsertCharPre", {
  group = vim.api.nvim_create_augroup("SaseXPromptTrigger", { clear = true }),
  callback = function()
    if vim.v.char ~= "#" then
      return
    end
    local col = vim.fn.col(".") - 1 -- 0-indexed column before cursor
    if col < 1 then
      return
    end
    local line = vim.api.nvim_get_current_line()
    local prev = line:sub(col, col)
    if prev ~= "#" then
      return
    end

    -- Swallow the second # (don't insert it).
    vim.v.char = ""

    vim.schedule(function()
      -- Remove the first # that's already in the buffer.
      local pos = vim.api.nvim_win_get_cursor(0)
      local row = pos[1] - 1 -- 0-indexed row
      vim.api.nvim_buf_set_text(0, row, col - 1, row, col, { "" })

      -- Remember we were in insert mode, then leave it for the picker.
      local was_insert = vim.fn.mode() == "i"
      if was_insert then
        vim.cmd("stopinsert")
      end

      require("sase.xprompt").pick({
        on_cancel = function()
          -- Restore a single # so the user can continue typing manually.
          vim.schedule(function()
            local cur = vim.api.nvim_win_get_cursor(0)
            local r = cur[1] - 1
            local c = cur[2]
            vim.api.nvim_buf_set_text(0, r, c, r, c, { "#" })
            vim.api.nvim_win_set_cursor(0, { r + 1, c + 1 })
            if was_insert then
              vim.cmd("startinsert")
              -- Move cursor forward past the inserted text.
              local new_cur = vim.api.nvim_win_get_cursor(0)
              vim.api.nvim_win_set_cursor(0, { new_cur[1], new_cur[2] + 1 })
            end
          end)
        end,
      })
    end)
  end,
})

-- Pre-warm the cache on VimEnter so the first ## is instant.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("SaseXPromptCache", { clear = true }),
  once = true,
  callback = function()
    -- Only pre-warm if sase is on PATH.
    if vim.fn.executable("sase") == 1 then
      require("sase.xprompt").refresh()
    end
  end,
})
