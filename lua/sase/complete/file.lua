-- File-system ("file") completion mode.
--
-- Fetches candidates from `sase file list --path <cwd> --token <token>`
-- and hands off to a Telescope picker (with vim.ui.select fallback).
-- Selecting a file replaces the path-like token under the cursor with
-- the candidate's full insertion. Selecting a directory replaces the
-- token and re-opens the picker rooted at the new path (drill-down),
-- mirroring the TUI's `<ctrl+t>` file-completion behaviour.

local M = {}

local _picker = require("sase.complete._picker")

--- @class SaseFileCandidate
--- @field display    string
--- @field insertion  string
--- @field is_dir     boolean
--- @field name       string

--- Fetch candidates asynchronously via `sase file list`.
--- @param token    string                              Partial token under cursor.
--- @param cwd      string                              Directory to anchor relative tokens.
--- @param callback fun(candidates: SaseFileCandidate[])
local function fetch_candidates(token, cwd, callback)
  vim.fn.jobstart({ "sase", "file", "list", "-p", cwd, "-t", token }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local raw = vim.fn.trim(table.concat(data, "\n"))
      if raw == "" then
        return
      end
      local ok, candidates = pcall(vim.json.decode, raw)
      if ok and type(candidates) == "table" then
        vim.schedule(function()
          callback(candidates)
        end)
      end
    end,
  })
end

--- Open the file-completion picker.
--- @param opts? { origin_win?: integer, was_insert?: boolean, token?: { text: string, row: integer, col_start: integer, col_end: integer }, cwd?: string, on_cancel?: fun() }
function M.pick(opts)
  opts = opts or {}
  opts.origin_win = opts.origin_win or vim.api.nvim_get_current_win()
  opts.cwd = opts.cwd or vim.fn.getcwd()
  local token = opts.token
  if not token then
    if opts.on_cancel then
      opts.on_cancel()
    end
    return
  end

  local function show(candidates)
    if #candidates == 0 then
      vim.notify("No file completions for '" .. token.text .. "'", vim.log.levels.WARN)
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope then
      local ok, ext = pcall(function()
        return require("telescope").extensions.sase.file
      end)
      if ok and ext then
        ext({
          candidates = candidates,
          token = token,
          cwd = opts.cwd,
          origin_win = opts.origin_win,
          was_insert = opts.was_insert,
          on_cancel = opts.on_cancel,
        })
        return
      end
    end

    -- Fallback: vim.ui.select. Drill-down still works one step at a time.
    vim.ui.select(candidates, {
      prompt = "Files> ",
      format_item = function(c)
        return (c.is_dir and "📁 " or "📄 ") .. c.display
      end,
    }, function(choice)
      if not choice then
        if opts.on_cancel then
          opts.on_cancel()
        end
        return
      end
      local end_pos = _picker.replace_range(
        token.row, token.col_start, token.col_end, choice.insertion
      )
      if choice.is_dir then
        local new_token = {
          text = choice.insertion,
          row = token.row,
          col_start = token.col_start,
          col_end = token.col_start + #choice.insertion,
        }
        M.pick({
          origin_win = opts.origin_win,
          was_insert = opts.was_insert,
          token = new_token,
          cwd = opts.cwd,
          on_cancel = opts.on_cancel,
        })
      else
        _picker.restore_insert_mode(opts.origin_win, end_pos)
      end
    end)
  end

  fetch_candidates(token.text, opts.cwd, show)
end

-- Expose for the Telescope extension.
M._fetch_candidates = fetch_candidates

return M
