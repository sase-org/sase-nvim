-- XPrompt browse picker module.
-- Normal inline completion is LSP-backed. The browse surfaces still fetch via
-- `sase xprompt list` until the server exposes a catalog/browse request.

local M = {}

--- @class SaseXPromptInput
--- @field name string
--- @field type string
--- @field required boolean
--- @field default string|number|boolean|nil
--- @field description string|nil

--- @class SaseXPromptItem
--- @field name string
--- @field type "xprompt"|"workflow"
--- @field kind? "xprompt"|"embeddable_workflow"|"standalone_workflow"
--- @field prefix? string
--- @field insertion? string
--- @field is_skill? boolean
--- @field description string|nil
--- @field source string|nil
--- @field inputs SaseXPromptInput[]
--- @field preview string
--- @field _slash_skill_completion? boolean

--- Cached items from last fetch.
--- @type SaseXPromptItem[]|nil
local _cache = nil

--- @param text string|nil
--- @return boolean
local function is_slash_skill_token_text(text)
  return type(text) == "string" and text:match("^/[A-Za-z0-9_]*$") ~= nil
end

--- @param value any
--- @return string|nil
local function non_empty_string(value)
  if type(value) ~= "string" or value:match("%S") == nil then
    return nil
  end
  return value
end

--- @param value any
--- @return string|nil
local function display_scalar_text(value)
  if value == nil or value == vim.NIL then
    return nil
  end
  if type(value) == "string" then
    if value == "" then
      return nil
    end
    return value
  end
  if type(value) == "number" or type(value) == "boolean" then
    return tostring(value)
  end
  return nil
end

--- @param text string
--- @return string[]
local function split_buffer_lines(text)
  local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  return vim.split(normalized, "\n", { plain = true })
end

--- @param lines string[]
--- @param value any
--- @param opts? { first_prefix?: string, rest_prefix?: string }
--- @return boolean
local function append_text_lines(lines, value, opts)
  local text = non_empty_string(value)
  if not text then
    return false
  end

  opts = opts or {}
  local first_prefix = opts.first_prefix or ""
  local rest_prefix = opts.rest_prefix
  if rest_prefix == nil then
    rest_prefix = first_prefix
  end

  for index, line in ipairs(split_buffer_lines(text)) do
    local prefix = index == 1 and first_prefix or rest_prefix
    lines[#lines + 1] = prefix .. line
  end
  return true
end

--- @param value any
--- @return string|nil
local function single_line_text(value)
  local text = non_empty_string(value)
  if not text then
    return nil
  end

  local parts = {}
  for _, line in ipairs(split_buffer_lines(text)) do
    local part = line:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then
      parts[#parts + 1] = part
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " ")
end

--- @param item SaseXPromptItem
--- @return SaseXPromptItem
local function slash_skill_item(item)
  local copy = {}
  for key, value in pairs(item) do
    copy[key] = value
  end
  copy._slash_skill_completion = true
  return copy
end

--- Return the reference text to insert/display for an xprompt item.
--- Falls back to legacy fields for older `sase xprompt list` output.
--- @param item SaseXPromptItem
--- @return string
local function item_insertion(item)
  if item._slash_skill_completion then
    return "/" .. item.name
  end
  if type(item.insertion) == "string" and item.insertion ~= "" then
    return item.insertion
  end
  local prefix = item.prefix
  if not prefix or prefix == "" then
    prefix = item.kind == "standalone_workflow" and "#!" or "#"
  end
  return prefix .. item.name
end

--- Return whether *reference* names a cached xprompt whose inputs are all
--- optional (an "optional-only" xprompt). Optional-only xprompts complete to
--- `#name ` with a deliberate trailing spacer, so the optional-spacer handler
--- may replace that space with a colon. No-input references, references with any
--- required input, unknown references, and a cold catalog all return false so
--- the handler does nothing rather than guessing.
--- @param reference string  full reference text, e.g. "#name" or "#!name"
--- @return boolean
local function reference_is_optional_only(reference)
  if not _cache or type(reference) ~= "string" or reference == "" then
    return false
  end
  for _, item in ipairs(_cache) do
    if item_insertion(item) == reference then
      local inputs = item.inputs
      if type(inputs) ~= "table" or #inputs == 0 then
        return false
      end
      for _, inp in ipairs(inputs) do
        if inp.required then
          return false
        end
      end
      return true
    end
  end
  return false
end

--- @param item SaseXPromptItem
--- @return boolean
local function is_standalone(item)
  return item.kind == "standalone_workflow"
    or item.prefix == "#!"
    or (type(item.insertion) == "string" and item.insertion:sub(1, 2) == "#!")
end

--- @param item SaseXPromptItem
--- @return string
local function item_kind_label(item)
  if item._slash_skill_completion then
    return "Skill"
  end
  if item.kind == "standalone_workflow" then
    return "Standalone"
  end
  if item.kind == "embeddable_workflow" or item.type == "workflow" then
    return "Workflow"
  end
  return "XPrompt"
end

--- @param inp SaseXPromptInput
--- @return string
local function input_entry_label(inp)
  if inp.required then
    return inp.name
  end
  return inp.name .. "?"
end

--- @param inp SaseXPromptInput
--- @return string
local function input_display_label(inp)
  if inp.required then
    return inp.name
  end
  local default = display_scalar_text(inp.default)
  local suffix = default and ("=" .. default) or "?"
  return inp.name .. suffix
end

--- @param inp SaseXPromptInput
--- @return string
local function input_detail_label(inp)
  local label = inp.name
  if type(inp.type) == "string" and inp.type ~= "" then
    label = label .. ": " .. inp.type
  end
  if not inp.required then
    local default = display_scalar_text(inp.default)
    if default then
      label = label .. " (default: " .. default .. ")"
    else
      label = label .. " (optional)"
    end
  end
  return label
end

--- @param parts string[]
--- @param value any
local function append_search_part(parts, value)
  local text = single_line_text(value)
  if text then
    parts[#parts + 1] = text:lower()
  end
end

--- Search text used by local fallback filters and Telescope ordinal matching.
--- @param item SaseXPromptItem
--- @return string
local function item_search_text(item)
  local parts = {}
  append_search_part(parts, item.name)
  append_search_part(parts, item_insertion(item))
  append_search_part(parts, item.description)
  for _, inp in ipairs(item.inputs or {}) do
    append_search_part(parts, inp.name)
    append_search_part(parts, inp.description)
  end
  return table.concat(parts, " ")
end

--- @param item SaseXPromptItem
--- @param partial string
--- @return boolean
local function item_matches_partial(item, partial)
  if partial == "" then
    return true
  end
  local partial_lower = partial:lower()
  if item.name:lower():sub(1, #partial_lower) == partial_lower then
    return true
  end
  return item_search_text(item):find(partial_lower, 1, true) ~= nil
end

--- @param items SaseXPromptItem[]
--- @param token? { text: string }
--- @return SaseXPromptItem[]
local function filter_items_for_token(items, token)
  if not token or not token.text or token.text == "" then
    return items
  end

  if is_slash_skill_token_text(token.text) then
    local partial = token.text:sub(2)
    local filtered = {}
    for _, item in ipairs(items) do
      if item.is_skill == true and item_matches_partial(item, partial) then
        filtered[#filtered + 1] = slash_skill_item(item)
      end
    end
    return filtered
  end

  if token.text:sub(1, 1) ~= "#" then
    return {}
  end

  local standalone_only = token.text:sub(1, 2) == "#!"
  local partial = standalone_only and token.text:sub(3) or token.text:sub(2)
  local filtered = {}

  for _, item in ipairs(items) do
    if (not standalone_only or is_standalone(item)) and item_matches_partial(item, partial) then
      filtered[#filtered + 1] = item
    end
  end

  return filtered
end

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
  local parts = { icon .. item_insertion(item) }
  local description = single_line_text(item.description)
  if description then
    parts[#parts + 1] = "  " .. description
  end
  -- Append user-facing input signatures.
  for _, inp in ipairs(item.inputs or {}) do
    local line = "  " .. input_display_label(inp)
    local input_description = single_line_text(inp.description)
    if input_description then
      line = line .. " - " .. input_description
    end
    parts[#parts + 1] = line
  end
  return table.concat(parts, "\n")
end

--- Format a one-line display string for an xprompt item.
--- @param item SaseXPromptItem
--- @return string
local function format_entry(item)
  local icon = item.type == "workflow" and "⚙ " or "  "
  local suffix = ""
  local user_inputs = {}
  for _, inp in ipairs(item.inputs or {}) do
    user_inputs[#user_inputs + 1] = input_entry_label(inp)
  end
  if #user_inputs > 0 then
    suffix = "(" .. table.concat(user_inputs, ", ") .. ")"
  end
  local entry = icon .. item_insertion(item) .. suffix
  local description = single_line_text(item.description)
  if description then
    entry = entry .. " - " .. description
  end
  return entry
end

--- @param item SaseXPromptItem
--- @return string[]
local function preview_lines(item)
  local lines = {}
  local description = non_empty_string(item.description)
  if description then
    lines[#lines + 1] = "## Description"
    append_text_lines(lines, description)
  end

  local input_lines = {}
  for _, inp in ipairs(item.inputs or {}) do
    local input_description = non_empty_string(inp.description)
    if input_description then
      append_text_lines(input_lines, input_description, {
        first_prefix = "- " .. input_detail_label(inp) .. " - ",
        rest_prefix = "  ",
      })
    end
  end
  if #input_lines > 0 then
    if #lines > 0 then
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "## Inputs"
    for _, line in ipairs(input_lines) do
      lines[#lines + 1] = line
    end
  end

  local preview = non_empty_string(item.preview)
  if preview then
    if #lines > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "## Preview"
    end
    append_text_lines(lines, preview)
  end

  if #lines == 0 then
    return { "" }
  end
  return lines
end

--- @param item SaseXPromptItem
--- @return string
local function format_preview(item)
  return table.concat(preview_lines(item), "\n")
end

--- Normalize legacy bare names and new catalog insertion values.
--- @param value string|SaseXPromptItem
--- @return string
local function normalize_insertion(value)
  if type(value) == "table" then
    return item_insertion(value)
  end
  if value:sub(1, 1) == "#" then
    return value
  end
  if value:sub(1, 1) == "/" then
    return value
  end
  return "#" .. value
end

--- Insert an xprompt reference at the current cursor position (works in insert and normal mode).
--- When `replace_range` is provided, the existing `[col_start, col_end)` byte range
--- on `row` is replaced with the selected reference (used by <C-t> on a `#token` to swap the whole
--- token, mirroring the TUI's `_replace_token_text`).
--- When `insert_pos` is provided, uses position-exact insertion via nvim_buf_set_text
--- to avoid cursor drift from mode transitions and Telescope open/close.
--- @param value string|SaseXPromptItem
--- @param insert_pos? { row: integer, col: integer }  0-indexed (row, col)
--- @param replace_range? { row: integer, col_start: integer, col_end: integer }
local function insert_at_cursor(value, insert_pos, replace_range)
  local text = normalize_insertion(value)
  if replace_range then
    local r, s, e = replace_range.row, replace_range.col_start, replace_range.col_end
    vim.api.nvim_buf_set_text(0, r, s, r, e, { text })
    vim.api.nvim_win_set_cursor(0, { r + 1, s + #text - 1 })
    return { row = r, col = s + #text }
  end
  if insert_pos then
    local r, c = insert_pos.row, insert_pos.col
    vim.api.nvim_buf_set_text(0, r, c, r, c, { text })
    vim.api.nvim_win_set_cursor(0, { r + 1, c + #text - 1 })
    return { row = r, col = c + #text }
  else
    local mode = vim.fn.mode()
    if mode == "i" or mode == "ic" then
      -- Insert mode: put text before cursor.
      vim.api.nvim_put({ text }, "c", false, true)
    else
      -- Normal mode: put text after cursor.
      vim.api.nvim_put({ text }, "c", true, true)
    end
  end
end

--- Return to insert mode after the picker closes, with the cursor
--- positioned right after the text that was just inserted.
--- @param origin_win integer|nil
--- @param end_pos? { row: integer, col: integer }  0-indexed post-insertion cursor target
local function restore_insert_mode(origin_win, end_pos)
  vim.schedule(function()
    if origin_win and vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end
    local line_len = #vim.api.nvim_get_current_line()
    if end_pos then
      -- Use the known-good position from insert_at_cursor, immune to
      -- Telescope's deferred cursor restoration.
      if end_pos.col >= line_len then
        vim.cmd("startinsert!")
      else
        vim.api.nvim_win_set_cursor(0, { end_pos.row + 1, end_pos.col })
        vim.cmd("startinsert")
      end
    else
      -- Fallback for vim.ui.select / non-insert_pos path: read current cursor.
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

--- Open the xprompt picker. Prefers Telescope if available, otherwise
--- falls back to vim.ui.select.
--- @param opts? { on_cancel?: fun() }
function M.pick(opts)
  opts = opts or {}
  opts.origin_win = opts.origin_win or vim.api.nvim_get_current_win()
  local function show(items)
    items = filter_items_for_token(items, opts.token)
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
        ext({
          items = items,
          on_cancel = opts.on_cancel,
          was_insert = opts.was_insert,
          origin_win = opts.origin_win,
          insert_pos = opts.insert_pos,
          replace_range = opts.replace_range,
        })
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
        local end_pos = insert_at_cursor(choice, opts.insert_pos, opts.replace_range)
        restore_insert_mode(opts.origin_win, end_pos)
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

--- Test seam: replace the cached catalog directly. Production code populates
--- the cache via `fetch_xprompts`/`M.refresh`.
--- @param items SaseXPromptItem[]|nil
function M._set_cache(items)
  _cache = items
end

M.reference_is_optional_only = reference_is_optional_only

-- Expose helpers for the Telescope extension.
M._format_display = format_display
M._format_entry = format_entry
M._insert_at_cursor = insert_at_cursor
M._fetch_xprompts = fetch_xprompts
M._restore_insert_mode = restore_insert_mode
M._item_insertion = item_insertion
M._item_kind_label = item_kind_label
M._item_search_text = item_search_text
M._filter_items_for_token = filter_items_for_token
M._is_slash_skill_token_text = is_slash_skill_token_text
M._single_line_text = single_line_text
M._format_preview = format_preview
M._preview_lines = preview_lines

return M
