-- Native floating-window xprompt picker with filtering and preview.
-- No external dependencies required — works without Telescope.

local M = {}
local api = vim.api

local ns = api.nvim_create_namespace("sase_xprompt_picker")

--- Active picker state (nil when closed).
--- @class _PickerState
--- @field items table
--- @field filtered table
--- @field cursor number
--- @field filter_text string
--- @field bufs table<string,number>
--- @field wins table<string,number>
--- @field aus number[]
--- @field on_done fun(name:string|nil)
--- @field closed boolean
--- @field item_first_line table<number,number>
--- @field prev_win number
local S = nil

-- Highlights (idempotent; `default = true` lets user colorschemes win).
local function ensure_hl()
  local function hl(name, opts)
    opts.default = true
    api.nvim_set_hl(0, name, opts)
  end
  hl("SaseXpBorder", { link = "FloatBorder" })
  hl("SaseXpTitle", { link = "FloatTitle" })
  hl("SaseXpHash", { fg = "#87D7FF", bold = true })
  hl("SaseXpGear", { fg = "#FFD700", bold = true })
  hl("SaseXpArgReq", { fg = "#D7AF87" })
  hl("SaseXpArgOpt", { fg = "#D7AF87", italic = true })
  hl("SaseXpDefault", { fg = "#888888", italic = true })
  hl("SaseXpCursor", { link = "CursorLine" })
  hl("SaseXpHint", { link = "Comment" })
  hl("SaseXpHintKey", { fg = "#87D7FF", bold = true })
  hl("SaseXpNoMatch", { link = "Comment" })
end

-- Layout ----------------------------------------------------------------

local function compute_layout()
  local ew = vim.o.columns
  local eh = vim.o.lines - vim.o.cmdheight

  local w = math.min(math.floor(ew * 0.85), 140)
  local h = math.min(math.floor(eh * 0.8), 36)
  w = math.max(w, 60)
  h = math.max(h, 14)

  local sr = math.floor((eh - h) / 2)
  local sc = math.floor((ew - w) / 2)

  -- Filter: 1 content row + 2 border rows = 3 visual rows.
  -- Body: remaining height, split into list (left 40%) and preview (right 60%).
  local body_h = h - 3
  local list_w = math.floor(w * 0.4)
  local prev_w = w - list_w

  return {
    filter = { width = w - 2, height = 1, row = sr, col = sc },
    list = { width = list_w - 2, height = body_h - 2, row = sr + 3, col = sc },
    preview = { width = prev_w - 2, height = body_h - 2, row = sr + 3, col = sc + list_w },
  }
end

-- Window / buffer helpers -----------------------------------------------

local function scratch_buf(name)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "wipe"
  vim.bo[b].buftype = "nofile"
  api.nvim_buf_set_name(b, "sase://" .. name)
  return b
end

local function float_win(buf, layout, title, extra)
  extra = extra or {}
  local cfg = {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = layout.height,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  }
  if title then
    cfg.title = " " .. title .. " "
    cfg.title_pos = "center"
  end
  -- footer (Neovim >= 0.10)
  if extra.footer then
    local ok = pcall(function()
      cfg.footer = extra.footer
      cfg.footer_pos = "center"
    end)
    if not ok then
      extra.footer = nil
    end
  end
  local win = api.nvim_open_win(buf, false, cfg)
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:SaseXpBorder,FloatTitle:SaseXpTitle"
  return win
end

-- Close & cleanup -------------------------------------------------------

local function close()
  if not S or S.closed then
    return
  end
  S.closed = true

  for _, id in ipairs(S.aus or {}) do
    pcall(api.nvim_del_autocmd, id)
  end
  for _, w in pairs(S.wins or {}) do
    if api.nvim_win_is_valid(w) then
      pcall(api.nvim_win_close, w, true)
    end
  end

  -- Restore the previously focused window.
  if S.prev_win and api.nvim_win_is_valid(S.prev_win) then
    pcall(api.nvim_set_current_win, S.prev_win)
  end
  S = nil
end

-- Rendering -------------------------------------------------------------

local function render_list()
  if not S or S.closed then
    return
  end
  local buf = S.bufs.list
  if not api.nvim_buf_is_valid(buf) then
    return
  end

  local items = S.filtered
  local cursor = S.cursor
  local lines = {}
  local hls = {}
  S.item_first_line = {}

  for i, item in ipairs(items) do
    S.item_first_line[i] = #lines -- 0-indexed

    local sel = (i == cursor)
    local prefix = sel and " ▸ " or "   "
    local icon = ""
    local has_icon = false
    if item.type == "workflow" then
      icon = "⚙ "
      has_icon = true
    end

    local line = prefix .. icon .. "#" .. item.name
    local lnum = #lines
    lines[#lines + 1] = line

    -- Icon highlight
    local col = #prefix
    if has_icon then
      hls[#hls + 1] = { lnum, col, col + #icon, "SaseXpGear" }
      col = col + #icon
    end
    -- Hash highlight
    hls[#hls + 1] = { lnum, col, col + 1, "SaseXpHash" }
    -- Selection bar
    if sel then
      hls[#hls + 1] = { lnum, 0, -1, "SaseXpCursor" }
    end

    -- Input args (indented lines below the name)
    for _, inp in ipairs(item.inputs or {}) do
      lnum = #lines
      if inp.required then
        local arg_line = "       " .. inp.name
        lines[#lines + 1] = arg_line
        hls[#hls + 1] = { lnum, 7, 7 + #inp.name, "SaseXpArgReq" }
      else
        local def = ""
        if inp.default and inp.default ~= vim.NIL and tostring(inp.default) ~= "" then
          def = "=" .. tostring(inp.default)
        else
          def = "?"
        end
        local arg_line = "       " .. inp.name .. def
        lines[#lines + 1] = arg_line
        hls[#hls + 1] = { lnum, 7, 7 + #inp.name, "SaseXpArgOpt" }
        hls[#hls + 1] = { lnum, 7 + #inp.name, 7 + #inp.name + #def, "SaseXpDefault" }
      end
      if sel then
        hls[#hls + 1] = { lnum, 0, -1, "SaseXpCursor" }
      end
    end
  end

  if #lines == 0 then
    lines = { "  No matches" }
    hls = { { 0, 0, -1, "SaseXpNoMatch" } }
  end

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  -- Keep the cursor item visible in the list window.
  if S.item_first_line[cursor] and api.nvim_win_is_valid(S.wins.list) then
    local target = S.item_first_line[cursor] + 1 -- 1-indexed
    pcall(api.nvim_win_set_cursor, S.wins.list, { target, 0 })
  end
end

local function render_preview()
  if not S or S.closed then
    return
  end
  local buf = S.bufs.preview
  if not api.nvim_buf_is_valid(buf) then
    return
  end

  local item = S.filtered[S.cursor]
  local text = (item and item.preview) or ""
  local lines = vim.split(text, "\n")

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"

  -- Scroll preview to top.
  if api.nvim_win_is_valid(S.wins.preview) then
    pcall(api.nvim_win_set_cursor, S.wins.preview, { 1, 0 })
  end
end

-- Filtering -------------------------------------------------------------

local function do_filter()
  if not S then
    return
  end
  local text = S.filter_text:lower()
  if text == "" then
    S.filtered = vim.deepcopy(S.items)
  else
    S.filtered = {}
    for _, item in ipairs(S.items) do
      if item.name:lower():find(text, 1, true) then
        S.filtered[#S.filtered + 1] = item
      end
    end
  end
  S.cursor = math.min(S.cursor, math.max(#S.filtered, 1))
  if S.cursor < 1 then
    S.cursor = 1
  end
end

-- Navigation & scrolling ------------------------------------------------

local function navigate(delta)
  if not S or #S.filtered == 0 then
    return
  end
  S.cursor = S.cursor + delta
  if S.cursor < 1 then
    S.cursor = #S.filtered
  end
  if S.cursor > #S.filtered then
    S.cursor = 1
  end
  render_list()
  render_preview()
end

local function scroll_preview(dir)
  if not S or not api.nvim_win_is_valid(S.wins.preview) then
    return
  end
  local win = S.wins.preview
  local h = api.nvim_win_get_height(win)
  local delta = math.max(1, math.floor(h / 2))
  api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    view.topline = math.max(1, view.topline + delta * dir)
    vim.fn.winrestview(view)
  end)
end

-- Actions ---------------------------------------------------------------

local function do_select()
  if not S then
    return
  end
  local item = S.filtered[S.cursor]
  local cb = S.on_done
  close()
  if cb then
    vim.schedule(function()
      cb(item and item.name or nil)
    end)
  end
end

local function do_cancel()
  if not S then
    return
  end
  local cb = S.on_done
  close()
  if cb then
    vim.schedule(function()
      cb(nil)
    end)
  end
end

-- Keymaps ---------------------------------------------------------------

local function setup_keymaps(buf)
  local kopts = { buffer = buf, noremap = true, silent = true }

  local function imap(lhs, rhs)
    vim.keymap.set("i", lhs, rhs, kopts)
  end
  local function nmap(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, kopts)
  end

  -- Navigate list
  imap("<C-n>", function() navigate(1) end)
  imap("<C-p>", function() navigate(-1) end)
  imap("<Down>", function() navigate(1) end)
  imap("<Up>", function() navigate(-1) end)
  nmap("j", function() navigate(1) end)
  nmap("k", function() navigate(-1) end)
  nmap("<C-n>", function() navigate(1) end)
  nmap("<C-p>", function() navigate(-1) end)
  nmap("<Down>", function() navigate(1) end)
  nmap("<Up>", function() navigate(-1) end)

  -- Scroll preview
  imap("<C-d>", function() scroll_preview(1) end)
  imap("<C-u>", function() scroll_preview(-1) end)
  nmap("<C-d>", function() scroll_preview(1) end)
  nmap("<C-u>", function() scroll_preview(-1) end)

  -- Select / cancel
  imap("<CR>", do_select)
  nmap("<CR>", do_select)
  imap("<Esc>", do_cancel)
  nmap("<Esc>", do_cancel)
  nmap("q", do_cancel)
  imap("<C-c>", do_cancel)
  nmap("<C-c>", do_cancel)
end

-- Public API ------------------------------------------------------------

--- Open the xprompt picker.
--- @param items SaseXPromptItem[]
--- @param opts { on_done: fun(name: string|nil) }
function M.open(items, opts)
  if S then
    close()
  end
  ensure_hl()

  S = {
    items = items,
    filtered = vim.deepcopy(items),
    cursor = 1,
    filter_text = "",
    bufs = {},
    wins = {},
    aus = {},
    on_done = opts.on_done,
    closed = false,
    item_first_line = {},
    prev_win = api.nvim_get_current_win(),
  }

  local layout = compute_layout()

  -- Buffers
  S.bufs.filter = scratch_buf("xprompt_filter")
  S.bufs.list = scratch_buf("xprompt_list")
  S.bufs.preview = scratch_buf("xprompt_preview")

  -- Hint text for list footer (Neovim 0.10+ supports footer in float borders).
  local hint_parts = {
    { " ^n", "SaseXpHintKey" },
    { "/", "SaseXpHint" },
    { "^p", "SaseXpHintKey" },
    { " ↑/↓: navigate  ", "SaseXpHint" },
    { "^d", "SaseXpHintKey" },
    { "/", "SaseXpHint" },
    { "^u", "SaseXpHintKey" },
    { ": scroll preview  ", "SaseXpHint" },
    { "⏎", "SaseXpHintKey" },
    { ": select  ", "SaseXpHint" },
    { "Esc", "SaseXpHintKey" },
    { ": cancel ", "SaseXpHint" },
  }

  -- Windows
  S.wins.filter = float_win(S.bufs.filter, layout.filter, "Select XPrompt")
  S.wins.list = float_win(S.bufs.list, layout.list, "XPrompts", { footer = hint_parts })
  S.wins.preview = float_win(S.bufs.preview, layout.preview, "Preview")

  -- Keymaps on the filter buffer.
  setup_keymaps(S.bufs.filter)

  -- React to text changes in the filter buffer.
  S.aus[#S.aus + 1] = api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = S.bufs.filter,
    callback = function()
      if not S or S.closed then
        return
      end
      local lines = api.nvim_buf_get_lines(S.bufs.filter, 0, -1, false)
      S.filter_text = lines[1] or ""
      S.cursor = 1
      do_filter()
      render_list()
      render_preview()
    end,
  })

  -- Close picker if any of its windows are closed externally.
  S.aus[#S.aus + 1] = api.nvim_create_autocmd("WinClosed", {
    callback = function(ev)
      if not S or S.closed then
        return true -- delete this autocmd
      end
      local closed_win = tonumber(ev.match)
      for _, w in pairs(S.wins) do
        if w == closed_win then
          do_cancel()
          return true
        end
      end
    end,
  })

  -- Initial render.
  render_list()
  render_preview()

  -- Focus the filter window and enter insert mode.
  api.nvim_set_current_win(S.wins.filter)
  vim.cmd("startinsert")
end

function M.close()
  close()
end

return M
