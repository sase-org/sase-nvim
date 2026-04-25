-- File-history ("recent files") completion mode.
--
-- Fetches the recency-ordered path list from `sase file-history list`,
-- caches it, and hands off to a Telescope picker (with vim.ui.select
-- fallback). Selecting an entry inserts the bare path at the cursor;
-- <C-d> in the Telescope picker removes the highlighted entry from
-- ~/.sase/file_reference_history.json via `sase file-history delete`.

local M = {}

local _picker = require("sase.complete._picker")

--- Cached paths from last fetch (most-recent-first).
--- @type string[]|nil
local _cache = nil

--- Fetch recent paths asynchronously via `sase file-history list`.
--- @param callback fun(paths: string[])
local function fetch_paths(callback)
  vim.fn.jobstart({ "sase", "file-history", "list" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local raw = vim.fn.trim(table.concat(data, "\n"))
      if raw == "" then
        return
      end
      local ok, paths = pcall(vim.json.decode, raw)
      if ok and type(paths) == "table" then
        _cache = paths
        vim.schedule(function()
          callback(paths)
        end)
      end
    end,
  })
end

--- Remove *path* from the file-reference history via `sase file-history delete`.
--- @param path string
--- @param callback? fun(ok: boolean)
local function delete_path(path, callback)
  vim.fn.jobstart({ "sase", "file-history", "delete", "-p", path }, {
    on_exit = function(_, code)
      if callback then
        vim.schedule(function()
          callback(code == 0)
        end)
      end
    end,
  })
end

--- Open the file-history picker. Prefers Telescope if available,
--- otherwise falls back to vim.ui.select (without delete support).
--- @param opts? { origin_win?: integer, was_insert?: boolean, on_cancel?: fun() }
function M.pick(opts)
  opts = opts or {}
  opts.origin_win = opts.origin_win or vim.api.nvim_get_current_win()

  local function show(paths)
    if #paths == 0 then
      vim.notify("No recent files in sase history", vim.log.levels.WARN)
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope then
      local ok, ext = pcall(function()
        return require("telescope").extensions.sase.file_history
      end)
      if ok and ext then
        ext({
          paths = paths,
          on_cancel = opts.on_cancel,
          was_insert = opts.was_insert,
          origin_win = opts.origin_win,
        })
        return
      end
    end

    -- Fallback: vim.ui.select (no delete support).
    vim.ui.select(paths, {
      prompt = "Recent files> ",
    }, function(choice)
      if choice then
        local end_pos = _picker.insert_text_at_cursor(choice, nil)
        -- Cache goes stale after an insert (recency changes).
        _cache = nil
        _picker.restore_insert_mode(opts.origin_win, end_pos)
      elseif opts.on_cancel then
        opts.on_cancel()
      end
    end)
  end

  if _cache then
    show(_cache)
  else
    fetch_paths(show)
  end
end

--- Force a re-fetch on the next pick.
function M.clear_cache()
  _cache = nil
end

--- Refresh the cache immediately (fire-and-forget).
function M.refresh()
  fetch_paths(function(_) end)
end

-- Expose helpers for the Telescope extension.
M._fetch_paths = fetch_paths
M._delete_path = delete_path

return M
