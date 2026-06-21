-- Optional-only xprompt spacer `:` cleanup.
--
-- A native LSP completion of an *optional-only* xprompt (one whose inputs are
-- all optional) inserts `#name ` with a deliberate trailing spacer -- mirroring
-- the ACE prompt input and the sase-core completion skeleton. This module lets
-- the next typed `:` replace that spacer in place so the common `#name:`
-- colon-argument flow needs no manual <backspace>.
--
-- The check is intentionally conservative and catalog-backed: it only fires
-- when the cursor sits immediately after `#name ` / `#!name ` and `name` is a
-- cached xprompt known to be optional-only. A cold or unknown catalog does
-- nothing rather than guessing, and ordinary spaces after no-input, unknown, or
-- slash-skill references are left untouched. The picker path inserts a bare
-- `#name` (no spacer), so it is not handled here.
--
-- The `:` behavior is driven from `InsertCharPre` and attaches only to the same
-- prompt-oriented buffers that `sase.lsp` supports, honoring `allow_all_markdown`.

local M = {}

local DEFAULT_FILETYPES = { "markdown", "gitcommit", "sase", "sase_prompt" }
local GROUP = "SaseXPromptSpacer"

local config = {
  enabled = true,
  filetypes = DEFAULT_FILETYPES,
  allow_all_markdown = false,
}

local attached = {}

local function copy_list(values)
  local copy = {}
  for idx, value in ipairs(values or {}) do
    copy[idx] = value
  end
  return copy
end

-- Offsets below are 0-indexed byte offsets into `line`, matching the cursor
-- column reported by `nvim_win_get_cursor`. A char at 0-indexed `i` is
-- `line:sub(i + 1, i + 1)`.

--- Return the `#name` / `#!name` reference ending immediately before the byte at
--- 0-indexed `space_index`, with its 0-indexed start, or nil. The reference must
--- be bounded on its left by start-of-line or a non-word character (matching the
--- xprompt trigger contexts) so a mid-word `#` fragment is ignored.
--- @param line string
--- @param space_index integer  0-indexed position of the candidate spacer
--- @return string|nil reference, integer|nil ref_start
local function reference_before(line, space_index)
  local prefix = line:sub(1, space_index) -- chars strictly before the spacer
  local ref = prefix:match("#!?[%a_][%w_/]*$")
  if not ref then
    return nil
  end
  local ref_start = space_index - #ref -- 0-indexed start of the reference
  if ref_start > 0 then
    local before = line:sub(ref_start, ref_start) -- char before ref (1-indexed)
    if before:match("[%w_/]") then
      return nil
    end
  end
  return ref, ref_start
end

--- Plan the spacer deletion for an optional-only `:` rewrite at 0-indexed
--- `offset` (the column where `:` is about to be typed). Returns nil unless the
--- char just before the cursor is a single space immediately following a
--- `#name` / `#!name` reference accepted by `is_optional_only`. Otherwise it
--- returns the 0-indexed byte range of the spacer to delete.
---
--- The typed `:` is left to insert normally (so it lands right after the
--- spacer); deleting the spacer afterward yields `#name:` and Neovim shifts the
--- cursor left onto the position just after the colon -- no manual cursor
--- placement, so the rewrite reads as one ordinary keystroke.
--- @param line string
--- @param offset integer  0-indexed cursor column
--- @param is_optional_only fun(reference: string): boolean
--- @return { start: integer, stop: integer }|nil
function M.plan_colon(line, offset, is_optional_only)
  if offset < 1 then
    return nil
  end
  local space_index = offset - 1 -- 0-indexed candidate spacer position
  if line:sub(space_index + 1, space_index + 1) ~= " " then
    return nil
  end
  local ref = reference_before(line, space_index)
  if not ref or not is_optional_only(ref) then
    return nil
  end
  return { start = space_index, stop = offset }
end

function M.supports_buffer(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local ft = vim.bo[bufnr].filetype
  local path = vim.api.nvim_buf_get_name(bufnr)
  return require("sase.lsp")._supports_filetype_path(ft, path, config)
end

-- Delete the planned spacer range on row `row` (0-indexed). The typed `:` was
-- left to insert normally, so the spacer still sits at the planned offsets when
-- this runs on the next tick; deleting it leaves `#name:`. The colon now sits
-- at `plan.start`, so the cursor is placed just after it -- via `startinsert!`
-- at end-of-line, where normal-mode cursor clamping would otherwise forbid the
-- final column (mirrors `xprompt.lua`'s `restore_insert_mode`).
local function apply_plan(bufnr, row, plan)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_text(bufnr, row, plan.start, row, plan.stop, { "" })
  if vim.api.nvim_get_current_buf() ~= bufnr then
    return
  end
  local target = plan.start + 1 -- 0-indexed column just after the colon
  if target >= #vim.api.nvim_get_current_line() then
    vim.cmd("startinsert!")
  else
    vim.api.nvim_win_set_cursor(0, { row + 1, target })
  end
end

-- `InsertCharPre` handler for the optional-only spacer `:` rewrite. The `:` is
-- left to insert normally; when a plan applies the redundant spacer is deleted
-- on the next tick (the buffer cannot be mutated from within `InsertCharPre`).
local function on_insert_char(bufnr)
  if vim.v.char ~= ":" then
    return
  end

  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local offset = cursor[2]
  local plan = M.plan_colon(line, offset, require("sase.xprompt").reference_is_optional_only)
  if not plan then
    return
  end

  vim.schedule(function()
    apply_plan(bufnr, row, plan)
  end)
end

local function detach(bufnr)
  if not attached[bufnr] then
    return
  end
  attached[bufnr] = nil
  pcall(vim.api.nvim_del_augroup_by_name, GROUP .. "Buf" .. bufnr)
end

function M.attach(bufnr)
  bufnr = bufnr or 0
  if not config.enabled or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not M.supports_buffer(bufnr) then
    detach(bufnr)
    return
  end
  if attached[bufnr] then
    return
  end
  attached[bufnr] = true

  local group = vim.api.nvim_create_augroup(GROUP .. "Buf" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    buffer = bufnr,
    callback = function()
      on_insert_char(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      detach(bufnr)
    end,
  })
end

function M.setup(opts)
  opts = opts or {}
  local lsp_config = require("sase.lsp")._config()
  local filetypes = lsp_config.filetypes
  if type(filetypes) ~= "table" or #filetypes == 0 then
    filetypes = DEFAULT_FILETYPES
  end

  config = vim.tbl_deep_extend("force", {
    enabled = true,
    filetypes = copy_list(filetypes),
    allow_all_markdown = lsp_config.allow_all_markdown == true,
  }, opts)

  for bufnr in pairs(attached) do
    detach(bufnr)
  end

  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  if not config.enabled then
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = config.filetypes,
    callback = function(args)
      M.attach(args.buf)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.attach(bufnr)
    end
  end
end

function M._config()
  return config
end

return M
