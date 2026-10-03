-- Macro picker triggered by #@ in insert mode.
-- Also provides the :SaseMacros command for manual invocation.

if vim.g.loaded_sase_macro then
  return
end
vim.g.loaded_sase_macro = true

-- :SaseMacros — open the picker from any mode.
vim.api.nvim_create_user_command("SaseMacros", function()
  require("sase.macro").pick()
end, { desc = "Open sase macro picker" })

-- :SaseMacrosRefresh — refresh the cached macro list.
vim.api.nvim_create_user_command("SaseMacrosRefresh", function()
  require("sase.macro").refresh()
  vim.notify("macro cache refreshed", vim.log.levels.INFO)
end, { desc = "Refresh sase macro cache" })

-- legacy xprompt spelling; remove with legacy_xprompt_syntax
local deprecated_command_warned = {}
local function deprecated_command(old_name, new_name)
  if deprecated_command_warned[old_name] then
    return
  end
  deprecated_command_warned[old_name] = true
  vim.notify(
    string.format("sase-nvim: `:%s` is deprecated; use `:%s`", old_name, new_name),
    vim.log.levels.WARN
  )
end

-- legacy xprompt spelling; remove with legacy_xprompt_syntax
vim.api.nvim_create_user_command("SaseXPrompts", function()
  deprecated_command("SaseXPrompts", "SaseMacros")
  require("sase.macro").pick()
end, { desc = "Deprecated alias of :SaseMacros" })

-- legacy xprompt spelling; remove with legacy_xprompt_syntax
vim.api.nvim_create_user_command("SaseXPromptsRefresh", function()
  deprecated_command("SaseXPromptsRefresh", "SaseMacrosRefresh")
  require("sase.macro").refresh()
end, { desc = "Deprecated alias of :SaseMacrosRefresh" })

-- Insert-mode #@ trigger.
-- When the user types @ and the character before cursor is #,
-- remove the # and open the picker. On cancel, restore a single #.
vim.api.nvim_create_autocmd("InsertCharPre", {
  group = vim.api.nvim_create_augroup("SaseMacroTrigger", { clear = true }),
  callback = function()
    if vim.v.char ~= "@" then
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

    -- Swallow the @ (don't insert it).
    vim.v.char = ""

    vim.schedule(function()
      -- Remove the first # that's already in the buffer.
      local pos = vim.api.nvim_win_get_cursor(0)
      local row = pos[1] - 1 -- 0-indexed row
      vim.api.nvim_buf_set_text(0, row, col - 1, row, col, { "" })

      -- Save the position where the # was so on_cancel can restore it
      -- (stopinsert shifts the cursor back, so we can't rely on cursor pos later).
      local restore_row = row
      local restore_col = col - 1

      -- Remember we were in insert mode, then leave it for the picker.
      local was_insert = vim.fn.mode() == "i"
      local origin_win = vim.api.nvim_get_current_win()
      if was_insert then
        vim.cmd("stopinsert")
      end

      require("sase.macro").pick({
        was_insert = was_insert,
        origin_win = origin_win,
        insert_pos = { row = row, col = col - 1 },
        on_cancel = function()
          -- Restore a single # at its original position.
          vim.schedule(function()
            vim.api.nvim_buf_set_text(0, restore_row, restore_col, restore_row, restore_col, { "#" })
            vim.api.nvim_win_set_cursor(0, { restore_row + 1, restore_col })
            if was_insert then
              vim.cmd("startinsert")
              -- Move cursor forward past the inserted #.
              local new_cur = vim.api.nvim_win_get_cursor(0)
              vim.api.nvim_win_set_cursor(0, { new_cur[1], new_cur[2] + 1 })
            end
          end)
        end,
      })
    end)
  end,
})

-- Pre-warm the cache on VimEnter so the first #@ is instant.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("SaseMacroCache", { clear = true }),
  once = true,
  callback = function()
    -- Only pre-warm if sase is on PATH.
    if vim.fn.executable("sase") == 1 then
      require("sase.macro").refresh()
    end
  end,
})
