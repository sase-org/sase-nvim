-- Editing behavior for the `%{A | B}` alt brace shorthand.
--
-- This mirrors the ACE prompt-input editing helpers in
-- `src/sase/ace/tui/widgets/_alt_syntax_editing.py` so Neovim and the TUI
-- behave identically while typing an alt directive:
--
--   * typing `{` immediately after a directive-valid `%` inserts two padding
--     spaces after the natively-typed `{`, leaving any closing `}` to the
--     user's normal auto-pair plugin and keeping the cursor after the first
--     space.
--
--   * typing `|` inside a live `%{...}` span normalizes the current branch's
--     comma spacing and appends a padded ` | ` separator, keeping the cursor
--     after the trailing space and before the closing `}`.
--
-- All planners are pure, line-based, depth- and backtick-aware string scans, so
-- they are cheap and unit-testable. The `{`/`|` behavior is driven from
-- `InsertCharPre`. Everything attaches only to the same prompt-oriented buffers
-- that `sase.lsp` supports, honoring `allow_all_markdown`.

local M = {}

local DEFAULT_FILETYPES = { "markdown", "gitcommit", "sase", "sase_prompt" }
local GROUP = "SaseAltEdit"

-- Characters that may legally precede a `%{` alt opener, matching the
-- sase-core directive-position rule and the ACE `_DIRECTIVE_OPENING_CONTEXTS`
-- set.
local VALID_PREFIX = {
  [":"] = true,
  ["("] = true,
  ["["] = true,
  ["{"] = true,
  ['"'] = true,
  ["'"] = true,
}

local PAIR_SAFE_CLOSE = {
  [")"] = true,
  ["]"] = true,
  ["}"] = true,
  [">"] = true,
}

-- Trailing punctuation can never begin a token, so padding inserted directly
-- before it is unambiguous -- this is how a fan-out question is normally
-- authored (`Which is better %{ A | B }?`).
local PAIR_SAFE_PUNCTUATION = {
  ["."] = true,
  [","] = true,
  [";"] = true,
  [":"] = true,
  ["!"] = true,
  ["?"] = true,
}

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
-- column reported by `nvim_win_get_cursor` and the ACE helpers' `offset`. A
-- character at 0-indexed position `i` is `line:sub(i + 1, i + 1)`.

-- Return true when the `%` at 0-indexed `percent_index` may open a `%{`.
local function is_directive_valid_brace_opening(line, percent_index)
  if percent_index < 0 or percent_index >= #line then
    return false
  end
  if line:sub(percent_index + 1, percent_index + 1) ~= "%" then
    return false
  end
  if percent_index == 0 then
    return true
  end
  local previous = line:sub(percent_index, percent_index)
  return previous:match("%s") ~= nil or VALID_PREFIX[previous] == true
end

local function next_char_allows_brace_padding(line, offset)
  if offset >= #line then
    return true
  end
  local following = line:sub(offset + 1, offset + 1)
  return following:match("%s") ~= nil
    or PAIR_SAFE_CLOSE[following] == true
    or PAIR_SAFE_PUNCTUATION[following] == true
end

-- Return the 0-indexed position of the `}` matching the `{` at 0-indexed
-- `open_index`, tracking brace nesting and skipping backtick spans. Mirrors the
-- ACE `_find_matching_brace`/sase-core `find_matching_delimiter`.
local function find_matching_brace(line, open_index)
  local depth = 0
  local in_backtick = false
  for i = open_index, #line - 1 do
    local char = line:sub(i + 1, i + 1)
    if in_backtick then
      if char == "`" then
        in_backtick = false
      end
    elseif char == "`" then
      in_backtick = true
    elseif char == "{" then
      depth = depth + 1
    elseif char == "}" then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    end
  end
  return nil
end

-- Return `(content_start, content_end)` of the `%{...}` enclosing `offset`, or
-- nil when `offset` is not inside any directive-valid span. `content_start` is
-- just after the `{`; `content_end` is the matching `}` (or `#line` when the
-- span is still unclosed). Mirrors the ACE `_find_enclosing_alt_span`.
local function find_enclosing_alt_span(line, offset)
  local search_from = 0
  while true do
    local found = line:find("%{", search_from + 1, true)
    if not found then
      return nil
    end
    local index = found - 1
    if is_directive_valid_brace_opening(line, index) then
      local content_start = index + 2
      local close = find_matching_brace(line, index + 1)
      local content_end = close == nil and #line or close
      if content_start <= offset and offset <= content_end then
        return content_start, content_end
      end
    end
    search_from = index + 2
  end
end

-- Return the 0-indexed position of the last top-level `|` in [content_start,
-- offset), ignoring pipes nested in brackets or backticks. Mirrors the ACE
-- `_last_top_level_pipe`.
local function last_top_level_pipe(line, content_start, offset)
  local last = nil
  local paren, bracket, brace = 0, 0, 0
  local in_backtick = false
  for i = content_start, offset - 1 do
    local char = line:sub(i + 1, i + 1)
    if in_backtick then
      if char == "`" then
        in_backtick = false
      end
    elseif char == "`" then
      in_backtick = true
    elseif char == "(" then
      paren = paren + 1
    elseif char == ")" then
      paren = math.max(0, paren - 1)
    elseif char == "[" then
      bracket = bracket + 1
    elseif char == "]" then
      bracket = math.max(0, bracket - 1)
    elseif char == "{" then
      brace = brace + 1
    elseif char == "}" then
      brace = math.max(0, brace - 1)
    elseif char == "|" and paren == 0 and bracket == 0 and brace == 0 then
      last = i
    end
  end
  return last
end

-- Return the 0-indexed start of the branch the cursor is editing, after the
-- last top-level `|` (or `content_start`), skipping leading whitespace so the
-- space following a prior separator stays untouched. Mirrors the ACE
-- `_current_branch_start`.
local function current_branch_start(line, content_start, offset)
  local pipe = last_top_level_pipe(line, content_start, offset)
  local start = pipe == nil and content_start or pipe + 1
  while start < offset and line:sub(start + 1, start + 1):match("%s") do
    start = start + 1
  end
  return start
end

-- Normalize comma spacing within a single branch: each `,` keeps one trailing
-- space and no leading space, surrounding whitespace stripped, so
-- `foo ,bar, and baz` becomes `foo, bar, and baz`. Mirrors the ACE
-- `_normalize_branch_text`.
local function normalize_branch_text(branch)
  local parts = vim.split(branch, ",", { plain = true })
  for i, part in ipairs(parts) do
    parts[i] = vim.trim(part)
  end
  return table.concat(parts, ", ")
end

--- Plan a normalized `|` separator insertion inside a live `%{...}` span.
--- Returns nil when `offset` is not inside an active span. Otherwise the
--- current branch's comma spacing is normalized and a padded ` | ` is appended,
--- leaving the cursor after the trailing space and before the closing `}`.
--- @return { start: integer, stop: integer, text: string, cursor: integer }|nil
function M.plan_separator(line, offset)
  local content_start = find_enclosing_alt_span(line, offset)
  if content_start == nil then
    return nil
  end
  local branch_start = current_branch_start(line, content_start, offset)
  local before = line:sub(branch_start + 1, offset)
  local replacement = normalize_branch_text(before) .. " | "
  return {
    start = branch_start,
    stop = offset,
    text = replacement,
    cursor = branch_start + #replacement,
  }
end

--- Plan two-space padding after a natively-inserted `%{` opener.
--- `line` and `offset` are post-native-insert: `line` already contains the
--- typed `{`, and `offset` is the cursor column immediately after it. The plan
--- inserts only spaces, never a closing `}`.
--- @return { start: integer, stop: integer, text: string, cursor: integer }|nil
function M.plan_brace_padding(line, offset)
  local open_index = offset - 1
  if open_index < 1 or line:sub(open_index + 1, open_index + 1) ~= "{" then
    return nil
  end
  if not is_directive_valid_brace_opening(line, open_index - 1) then
    return nil
  end
  if not next_char_allows_brace_padding(line, offset) then
    return nil
  end
  return {
    start = offset,
    stop = offset,
    text = "  ",
    cursor = offset + 1,
  }
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

-- Apply a planned edit to `bufnr` on row `row` (0-indexed), then place the
-- cursor. Separator plans are relative to the unchanged line because
-- `InsertCharPre` swallows `|`; brace-padding plans are relative to the
-- post-native-insert line because `{` is left alone.
local function apply_plan(bufnr, row, plan)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_text(bufnr, row, plan.start, row, plan.stop, { plan.text })
  if vim.api.nvim_get_current_buf() == bufnr then
    vim.api.nvim_win_set_cursor(0, { row + 1, plan.cursor })
  end
end

-- `InsertCharPre` handler for alt editing. `|` plans swallow the typed
-- character and replace the branch. `{` plans leave the typed character to
-- insert normally, then add the two padding spaces on the next tick.
local function on_insert_char(bufnr)
  local char = vim.v.char
  if char ~= "|" and char ~= "{" then
    return
  end

  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local offset = cursor[2]
  local plan
  if char == "|" then
    plan = M.plan_separator(line, offset)
  else
    local post_line = line:sub(1, offset) .. "{" .. line:sub(offset + 1)
    plan = M.plan_brace_padding(post_line, offset + 1)
  end
  if not plan then
    return
  end

  if char == "|" then
    vim.v.char = ""
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
