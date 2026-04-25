-- Shared picker plumbing for the <C-t> completion dispatcher.
-- Each per-mode module (xprompt / file / file_history) reuses these
-- helpers to insert the chosen item at the cursor and return to insert
-- mode the way the user expects.

local M = {}

--- Insert *text* at the cursor. When *insert_pos* is supplied we use
--- nvim_buf_set_text with an explicit (row, col) so Telescope's deferred
--- cursor restoration can't shift us off the intended insertion site.
--- @param text string           Text to insert verbatim.
--- @param insert_pos? { row: integer, col: integer }  0-indexed buffer position.
--- @return { row: integer, col: integer }|nil  0-indexed post-insert cursor target.
function M.insert_text_at_cursor(text, insert_pos)
  if insert_pos then
    local r, c = insert_pos.row, insert_pos.col
    vim.api.nvim_buf_set_text(0, r, c, r, c, { text })
    vim.api.nvim_win_set_cursor(0, { r + 1, c + #text - 1 })
    return { row = r, col = c + #text }
  end

  local mode = vim.fn.mode()
  if mode == "i" or mode == "ic" then
    vim.api.nvim_put({ text }, "c", false, true)
  else
    vim.api.nvim_put({ text }, "c", true, true)
  end
  return nil
end

--- Replace the text in the range [col_start, col_end) on *row* with *text*
--- and return the post-insert cursor target.
--- @param row        integer
--- @param col_start  integer
--- @param col_end    integer
--- @param text       string
--- @return { row: integer, col: integer }
function M.replace_range(row, col_start, col_end, text)
  vim.api.nvim_buf_set_text(0, row, col_start, row, col_end, { text })
  vim.api.nvim_win_set_cursor(0, { row + 1, col_start + #text - 1 })
  return { row = row, col = col_start + #text }
end

--- Return to insert mode with the cursor just past *end_pos*.
--- When *end_pos* is nil we fall back to the current cursor (used by
--- the vim.ui.select path where we don't know the insertion site up-front).
--- @param origin_win integer|nil
--- @param end_pos? { row: integer, col: integer }
function M.restore_insert_mode(origin_win, end_pos)
  vim.schedule(function()
    if origin_win and vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end
    local line_len = #vim.api.nvim_get_current_line()
    if end_pos then
      if end_pos.col >= line_len then
        vim.cmd("startinsert!")
      else
        vim.api.nvim_win_set_cursor(0, { end_pos.row + 1, end_pos.col })
        vim.cmd("startinsert")
      end
    else
      local pos = vim.api.nvim_win_get_cursor(0)
      if pos[2] + 1 >= line_len then
        vim.cmd("startinsert!")
      else
        vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 1 })
        vim.cmd("startinsert")
      end
    end
  end)
end

return M
