-- Pure token extraction + classification helpers for <C-t> completion.
-- Mirrors the rules in src/sase/ace/tui/widgets/file_completion.py and
-- xprompt_completion.py in the main sase repo so the Neovim dispatcher
-- and the TUI agree on what kind of completion a given token should get.

local M = {}

--- Characters that terminate a token, matching
--- _TOKEN_DELIMITERS in src/sase/ace/tui/widgets/file_completion.py.
local _DELIMS = {
  ["'"] = true, ['"'] = true, ["`"] = true, ["?"] = true, ["!"] = true,
  [";"] = true, [","] = true, ["("] = true, [")"] = true, ["["] = true,
  ["]"] = true, ["{"] = true, ["}"] = true, ["<"] = true, [">"] = true,
  ["|"] = true, ["&"] = true, ["="] = true, ["+"] = true, ["*"] = true,
  ["^"] = true, ["%"] = true, ["$"] = true, [":"] = true, ["\\"] = true,
}

local function is_delim(ch)
  if ch == "" then
    return true
  end
  if ch:match("%s") then
    return true
  end
  return _DELIMS[ch] == true
end

local function is_token_delim_at(line, pos)
  local ch = line:sub(pos, pos)
  if ch == "!" and pos > 1 and line:sub(pos - 1, pos - 1) == "#" then
    return false
  end
  return is_delim(ch)
end

--- @class SaseTokenInfo
--- @field text       string   Token text (no leading/trailing delimiter).
--- @field row        integer  0-indexed buffer row of the token.
--- @field col_start  integer  0-indexed byte column of the token start.
--- @field col_end    integer  0-indexed byte column one-past-the-end of the token.

--- Extract the token surrounding the cursor in the current window.
--- @return SaseTokenInfo|nil
function M.token_under_cursor()
  local cur = vim.api.nvim_win_get_cursor(0)
  local row = cur[1] - 1
  local col = cur[2]
  local line = vim.api.nvim_get_current_line()
  if col > #line then
    col = #line
  end

  -- Scan left: line is 0-indexed in the Python reference, so the char at
  -- "index s-1" in Python is line:sub(s, s) here (1-indexed).
  local s = col
  while s > 0 and not is_token_delim_at(line, s) do
    s = s - 1
  end
  local e = col
  while e < #line and not is_token_delim_at(line, e + 1) do
    e = e + 1
  end

  if s >= 2 and line:sub(s - 1, s) == "#!" and is_delim(line:sub(s - 2, s - 2)) then
    s = s - 2
  end

  if s == e and col >= 2 and line:sub(col - 1, col) == "#!" then
    local marker_start = col - 2
    if marker_start == 0 or is_delim(line:sub(marker_start, marker_start)) then
      return {
        text = "#!",
        row = row,
        col_start = marker_start,
        col_end = col,
      }
    end
  end

  if s == e then
    return nil
  end
  return {
    text = line:sub(s + 1, e),
    row = row,
    col_start = s,
    col_end = e,
  }
end

--- True when *token* looks like an xprompt reference (`#foo`, `#!foo`, `#foo.bar`).
--- Mirrors xprompt_completion.is_xprompt_like_token.
--- @param token string|nil
--- @return boolean
function M.is_xprompt_like(token)
  if not token or token == "" then
    return false
  end
  if token:sub(1, 1) ~= "#" then
    return false
  end
  return token:match("%s") == nil
end

--- True when *token* looks like a filesystem path fragment.
--- Mirrors file_completion.is_path_like_token.
--- @param token string|nil
--- @return boolean
function M.is_path_like(token)
  if not token or token == "" then
    return false
  end
  local bare = token
  if bare:sub(1, 1) == "@" then
    bare = bare:sub(2)
  end
  if bare == "" then
    return false
  end
  if bare:sub(1, 2) == "~/" then return true end
  if bare:sub(1, 1) == "/" then return true end
  if bare:sub(1, 2) == "./" then return true end
  if bare:sub(1, 3) == "../" then return true end
  if bare:sub(1, 6) == ".sase/" then return true end
  return bare:find("/", 1, true) ~= nil
end

--- Classify a token into a completion mode.
--- An empty / nil token means "cursor isn't on any token" which the TUI
--- maps to file-history completion, so we do the same here.
--- @param token string|nil
--- @return "xprompt"|"file"|"file_history"|nil
function M.classify(token)
  if not token or token == "" then
    return "file_history"
  end
  if M.is_xprompt_like(token) then
    return "xprompt"
  end
  if M.is_path_like(token) then
    return "file"
  end
  return nil
end

return M
