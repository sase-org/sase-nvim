-- Core xprompt picker module.
-- Fetches xprompt data via `sase xprompt list` and provides picker functions.

local M = {}

--- @class SaseXPromptInput
--- @field name string
--- @field type string
--- @field required boolean
--- @field default string|nil

--- @class SaseXPromptItem
--- @field name string
--- @field type "xprompt"|"workflow"
--- @field source string|nil
--- @field inputs SaseXPromptInput[]
--- @field preview string

--- Cached items from last fetch.
--- @type SaseXPromptItem[]|nil
local _cache = nil

--- Fetch all xprompts asynchronously via `sase xprompt list`.
--- @param callback fun(items: SaseXPromptItem[])
local function fetch_xprompts(callback)
  vim.fn.jobstart({ "sase", "xprompt", "list" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local raw = vim.fn.trim(table.concat(data, "\n"))
      if raw == "" then
        return
      end
      local ok, items = pcall(vim.json.decode, raw)
      if ok and items then
        _cache = items
        vim.schedule(function()
          callback(items)
        end)
      end
    end,
  })
end

--- Format display text for an xprompt item (matches the TUI style).
--- @param item SaseXPromptItem
--- @return string
local function format_display(item)
  local icon = item.type == "workflow" and "⚙ " or "  "
  local parts = { icon .. "#" .. item.name }
  -- Append user-facing input signatures.
  for _, inp in ipairs(item.inputs or {}) do
    if inp.required then
      parts[#parts + 1] = "  " .. inp.name
    else
      local suffix = (inp.default and inp.default ~= "") and ("=" .. inp.default) or "?"
      parts[#parts + 1] = "  " .. inp.name .. suffix
    end
  end
  return table.concat(parts, "\n")
end

--- Format a one-line display string for an xprompt item.
--- @param item SaseXPromptItem
--- @return string
local function format_entry(item)
  local icon = item.type == "workflow" and "⚙ #" or "  #"
  local suffix = ""
  local user_inputs = {}
  for _, inp in ipairs(item.inputs or {}) do
    user_inputs[#user_inputs + 1] = inp.required and inp.name or (inp.name .. "?")
  end
  if #user_inputs > 0 then
    suffix = "(" .. table.concat(user_inputs, ", ") .. ")"
  end
  return icon .. item.name .. suffix
end

--- Insert `#name` at the current cursor position (works in insert and normal mode).
--- @param name string
local function insert_at_cursor(name)
  local text = "#" .. name
  local mode = vim.fn.mode()
  if mode == "i" or mode == "ic" then
    -- Insert mode: put text before cursor.
    vim.api.nvim_put({ text }, "c", false, true)
  else
    -- Normal mode: put text after cursor.
    vim.api.nvim_put({ text }, "c", true, true)
  end
end

--- Open the xprompt picker. Prefers Telescope if available, otherwise
--- falls back to vim.ui.select.
--- @param opts? { on_cancel?: fun() }
function M.pick(opts)
  opts = opts or {}
  local function show(items)
    if #items == 0 then
      vim.notify("No xprompts found", vim.log.levels.WARN)
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    -- Try Telescope first.
    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope then
      local ok, ext = pcall(function()
        return require("telescope").extensions.sase.xprompts
      end)
      if ok and ext then
        ext({ items = items, on_cancel = opts.on_cancel })
        return
      end
    end

    -- Fallback: vim.ui.select.
    vim.ui.select(items, {
      prompt = "Select XPrompt> ",
      format_item = function(item)
        return format_entry(item)
      end,
    }, function(choice)
      if choice then
        insert_at_cursor(choice.name)
      elseif opts.on_cancel then
        opts.on_cancel()
      end
    end)
  end

  if _cache then
    show(_cache)
  else
    fetch_xprompts(show)
  end
end

--- Refresh the xprompt cache.
function M.refresh()
  fetch_xprompts(function(_) end)
end

--- Clear the cached xprompt list so the next pick re-fetches.
function M.clear_cache()
  _cache = nil
end

-- Expose helpers for the Telescope extension.
M._format_display = format_display
M._format_entry = format_entry
M._insert_at_cursor = insert_at_cursor
M._fetch_xprompts = fetch_xprompts

return M
