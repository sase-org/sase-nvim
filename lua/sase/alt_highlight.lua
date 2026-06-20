-- Syntax highlighting for the `%{A | B}` alt brace shorthand.
--
-- This module mirrors the sase-core launch grammar closely enough to colour
-- the parts of an alt directive that matter while editing a prompt:
--
--   * `%{` openers and `}` closers   -> SaseAltDelimiter
--   * top-level `|` branch separators -> SaseAltSeparator
--   * `name=` named-branch prefixes   -> SaseAltBranchName
--   * unmatched `%{` openers          -> SaseAltError
--
-- Scanning is line-based, depth- and backtick-aware, and bounded so prompt
-- editing stays responsive. It attaches to the same prompt-oriented buffers
-- that `sase.lsp` supports (markdown prompt files, gitcommit, sase, and
-- sase_prompt), honouring `allow_all_markdown`.

local M = {}

local DEFAULT_FILETYPES = { "markdown", "gitcommit", "sase", "sase_prompt" }
local GROUP = "SaseAltHighlight"
local NS = vim.api.nvim_create_namespace("sase_alt_highlight")

-- Stable highlight groups with default links so user overrides win.
local DEFAULT_LINKS = {
  SaseAltDelimiter = "Delimiter",
  SaseAltSeparator = "Operator",
  SaseAltBranchName = "Identifier",
  SaseAltError = "Error",
}

local config = {
  enabled = true,
  filetypes = DEFAULT_FILETYPES,
  allow_all_markdown = false,
  debounce_ms = 75,
  max_lines = 5000,
  max_bytes = 200000,
}

-- Characters that may legally precede a `%{` alt opener, matching the
-- sase-core `(^|[\s\(\[\{"'])` directive-position rule.
local VALID_PREFIX = {
  ["("] = true,
  ["["] = true,
  ["{"] = true,
  ['"'] = true,
  ["'"] = true,
}

local attached = {}
local timers = {}

local function copy_list(values)
  local copy = {}
  for idx, value in ipairs(values or {}) do
    copy[idx] = value
  end
  return copy
end

local function uv()
  return vim.uv or vim.loop
end

-- Return the 1-indexed inclusive range of non-whitespace content within
-- [lo, hi], or nil when the slice is empty/all whitespace.
local function trim_range(line, lo, hi)
  while lo <= hi and line:sub(lo, lo):match("%s") do
    lo = lo + 1
  end
  while hi >= lo and line:sub(hi, hi):match("%s") do
    hi = hi - 1
  end
  if lo > hi then
    return nil
  end
  return lo, hi
end

-- `open_pos` is the 1-indexed position of `{`. Returns the 1-indexed position
-- of the matching `}` (counting only brace nesting, skipping backtick spans),
-- mirroring sase-core `find_matching_delimiter`.
local function find_matching_brace(line, open_pos)
  local depth = 0
  local in_backticks = false
  for i = open_pos, #line do
    local ch = line:sub(i, i)
    if ch == "`" then
      in_backticks = not in_backticks
    elseif not in_backticks then
      if ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then
          return i
        end
      end
    end
  end
  return nil
end

-- Highlight the named-branch prefix (`name=`) of a single branch slice, if any.
-- The name is the trimmed text before the first top-level `=`, matching
-- sase-core `split_named_directive_arg`.
local function scan_branch_name(line, from_pos, to_pos, spans)
  if from_pos > to_pos then
    return
  end
  local depth = 0
  local in_backticks = false
  for i = from_pos, to_pos do
    local ch = line:sub(i, i)
    if ch == "`" then
      in_backticks = not in_backticks
    elseif not in_backticks then
      if ch == "(" or ch == "[" or ch == "{" then
        depth = depth + 1
      elseif ch == ")" or ch == "]" or ch == "}" then
        if depth > 0 then
          depth = depth - 1
        end
      elseif ch == "=" and depth == 0 then
        local name_lo, name_hi = trim_range(line, from_pos, i - 1)
        if name_lo then
          spans[#spans + 1] = {
            start_col = name_lo - 1,
            end_col = name_hi,
            group = "SaseAltBranchName",
          }
        end
        return
      end
    end
  end
end

-- Scan the inner content of an alt span (1-indexed inclusive [from_pos, to_pos],
-- exclusive of the braces) for top-level `|` separators and per-branch names.
-- Depth tracks all bracket pairs and backtick spans, matching
-- sase-core `parse_directive_args_with_names`.
local function scan_inner(line, from_pos, to_pos, spans)
  if from_pos > to_pos then
    return
  end
  local depth = 0
  local in_backticks = false
  local branch_start = from_pos
  for i = from_pos, to_pos do
    local ch = line:sub(i, i)
    if ch == "`" then
      in_backticks = not in_backticks
    elseif not in_backticks then
      if ch == "(" or ch == "[" or ch == "{" then
        depth = depth + 1
      elseif ch == ")" or ch == "]" or ch == "}" then
        if depth > 0 then
          depth = depth - 1
        end
      elseif ch == "|" and depth == 0 then
        spans[#spans + 1] = {
          start_col = i - 1,
          end_col = i,
          group = "SaseAltSeparator",
        }
        scan_branch_name(line, branch_start, i - 1, spans)
        branch_start = i + 1
      end
    end
  end
  scan_branch_name(line, branch_start, to_pos, spans)
end

local function is_valid_prefix(line, pct_pos)
  -- pct_pos is the 1-indexed position of `%`.
  if pct_pos == 1 then
    return true
  end
  local prev = line:sub(pct_pos - 1, pct_pos - 1)
  return prev:match("%s") ~= nil or VALID_PREFIX[prev] == true
end

-- Compute highlight spans for a single line. Each span is
-- `{ start_col, end_col, group }` with 0-indexed, end-exclusive byte columns,
-- ready for `nvim_buf_set_extmark`.
function M.scan_line(line)
  local spans = {}
  local search = 1
  while true do
    local pct = line:find("%{", search, true)
    if not pct then
      break
    end
    if not is_valid_prefix(line, pct) then
      search = pct + 1
    else
      local brace = pct + 1
      local close = find_matching_brace(line, brace)
      if close then
        spans[#spans + 1] = {
          start_col = pct - 1,
          end_col = pct + 1,
          group = "SaseAltDelimiter",
        }
        spans[#spans + 1] = {
          start_col = close - 1,
          end_col = close,
          group = "SaseAltDelimiter",
        }
        scan_inner(line, brace + 1, close - 1, spans)
      else
        spans[#spans + 1] = {
          start_col = pct - 1,
          end_col = pct + 1,
          group = "SaseAltError",
        }
      end
      -- Continue just past this opener so nested `%{...}` are also scanned.
      search = pct + 2
    end
  end
  return spans
end

function M.define_highlights()
  for group, link in pairs(DEFAULT_LINKS) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
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

-- Re-apply highlights for the whole (bounded) buffer.
function M.highlight_buffer(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  if not config.enabled or not M.supports_buffer(bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local upper = math.min(line_count, config.max_lines)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, upper, false)
  local budget = config.max_bytes
  for idx, line in ipairs(lines) do
    budget = budget - (#line + 1)
    if budget < 0 then
      break
    end
    for _, span in ipairs(M.scan_line(line)) do
      vim.api.nvim_buf_set_extmark(bufnr, NS, idx - 1, span.start_col, {
        end_col = span.end_col,
        hl_group = span.group,
      })
    end
  end
end

local function clear_timer(bufnr)
  local timer = timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
    timers[bufnr] = nil
  end
end

-- Debounced rescan, coalescing rapid edits.
function M.schedule_highlight(bufnr)
  clear_timer(bufnr)
  local timer = uv().new_timer()
  timers[bufnr] = timer
  timer:start(
    config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if timers[bufnr] == timer then
        clear_timer(bufnr)
      end
      M.highlight_buffer(bufnr)
    end)
  )
end

local function detach(bufnr)
  attached[bufnr] = nil
  clear_timer(bufnr)
end

function M.attach(bufnr)
  bufnr = bufnr or 0
  if not config.enabled or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not M.supports_buffer(bufnr) then
    -- Drop any stale highlights if a buffer lost eligibility.
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    return
  end

  if not attached[bufnr] then
    attached[bufnr] = true
    local group =
      vim.api.nvim_create_augroup(GROUP .. "Buf" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        M.schedule_highlight(bufnr)
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
  M.highlight_buffer(bufnr)
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
    debounce_ms = 75,
    max_lines = 5000,
    max_bytes = 200000,
  }, opts)

  for bufnr in pairs(attached) do
    detach(bufnr)
  end

  M.define_highlights()

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
  -- Re-establish default links after a colorscheme swap clears them.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.define_highlights()
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
