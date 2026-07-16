-- Headless tests for lua/sase/alt_highlight.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/alt_highlight.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local alt = require("sase.alt_highlight")

local failures = 0

local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL: " .. message .. "\n")
end

local function same(actual, expected, label)
  if vim.inspect(actual) ~= vim.inspect(expected) then
    fail(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

-- Find a span by group + columns within a scan_line result.
local function has_span(spans, start_col, end_col, group)
  for _, span in ipairs(spans) do
    if span.start_col == start_col and span.end_col == end_col and span.group == group then
      return true
    end
  end
  return false
end

local function count_group(spans, group)
  local n = 0
  for _, span in ipairs(spans) do
    if span.group == group then
      n = n + 1
    end
  end
  return n
end

local function assert_span(spans, start_col, end_col, group, label)
  if not has_span(spans, start_col, end_col, group) then
    fail(string.format("%s: missing %s span [%d,%d) in %s", label, group, start_col, end_col, vim.inspect(spans)))
  end
end

-- --- scan_line: span placement --------------------------------------------

do
  -- "%{a | b}" -> opener, closer, one separator; no branch names.
  local spans = alt.scan_line("%{a | b}")
  assert_span(spans, 0, 2, "SaseAltDelimiter", "basic opener")
  assert_span(spans, 7, 8, "SaseAltDelimiter", "basic closer")
  assert_span(spans, 4, 5, "SaseAltSeparator", "basic separator")
  same(count_group(spans, "SaseAltSeparator"), 1, "basic separator count")
  same(count_group(spans, "SaseAltBranchName"), 0, "basic has no branch names")
  same(count_group(spans, "SaseAltError"), 0, "basic has no errors")
end

do
  -- Named branches: "%{sec=[[security]] | perf=[[performance]]}".
  local line = "%{sec=[[security]] | perf=[[performance]]}"
  local spans = alt.scan_line(line)
  assert_span(spans, 2, 5, "SaseAltBranchName", "named branch sec")
  assert_span(spans, 21, 25, "SaseAltBranchName", "named branch perf")
  same(count_group(spans, "SaseAltSeparator"), 1, "named branch separator count")
  -- The `]]`/`[[` text-block brackets must not be mistaken for separators.
  same(count_group(spans, "SaseAltDelimiter"), 2, "named branch delimiter count")
end

do
  -- Commas inside a branch are literal text, not separators.
  local spans = alt.scan_line("%{foo, bar | baz}")
  same(count_group(spans, "SaseAltSeparator"), 1, "comma branch separator count")
  assert_span(spans, 11, 12, "SaseAltSeparator", "comma branch separator position")
  same(count_group(spans, "SaseAltBranchName"), 0, "comma branch has no names")
end

do
  -- Unmatched opener is an error, with no delimiter pair.
  local spans = alt.scan_line("%{foo")
  assert_span(spans, 0, 2, "SaseAltError", "unmatched opener error")
  same(count_group(spans, "SaseAltDelimiter"), 0, "unmatched opener has no delimiters")
end

do
  -- A `%{` that is not in a directive-valid position is ignored.
  local spans = alt.scan_line("a%{b}")
  same(#spans, 0, "invalid-prefix produces no spans")
end

do
  -- A `%{` opened right after `(` is valid.
  local spans = alt.scan_line("(%{x|y})")
  assert_span(spans, 1, 3, "SaseAltDelimiter", "paren-prefixed opener")
  assert_span(spans, 4, 5, "SaseAltSeparator", "paren-prefixed separator")
end

do
  -- Pipes inside backtick spans are not separators.
  local spans = alt.scan_line("%{`a|b` | c}")
  same(count_group(spans, "SaseAltSeparator"), 1, "backtick separator count")
  assert_span(spans, 8, 9, "SaseAltSeparator", "backtick separator position")
end

-- --- supports_buffer: attach eligibility ----------------------------------

alt.setup({})

local function make_buffer(ft, name)
  local buf = vim.api.nvim_create_buf(false, true)
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].filetype = ft
  return buf
end

local tmp = vim.fn.tempname()

same(alt.supports_buffer(make_buffer("sase", tmp .. "_a.sase")), true, "sase filetype eligible")
same(alt.supports_buffer(make_buffer("sase_prompt", tmp .. "_b")), true, "sase_prompt filetype eligible")
same(alt.supports_buffer(make_buffer("gitcommit", tmp .. "_COMMIT_EDITMSG")), true, "gitcommit eligible")
same(alt.supports_buffer(make_buffer("lua", tmp .. "_c.lua")), false, "unrelated filetype not eligible")
same(alt.supports_buffer(make_buffer("markdown", tmp .. "_notes.md")), false, "plain markdown not eligible")
same(
  alt.supports_buffer(make_buffer("markdown", "/work/sase/xprompts/" .. vim.fn.fnamemodify(tmp, ":t") .. ".md")),
  true,
  "markdown under canonical sase/xprompts/ eligible"
)
same(
  alt.supports_buffer(make_buffer("markdown", "/work/sase_prompt_" .. vim.fn.fnamemodify(tmp, ":t") .. ".md")),
  true,
  "markdown prompt-temp name eligible"
)

-- With allow_all_markdown, ordinary markdown becomes eligible.
alt.setup({ allow_all_markdown = true })
same(alt.supports_buffer(make_buffer("markdown", tmp .. "_notes2.md")), true, "allow_all_markdown enables plain markdown")

-- --- highlight_buffer: extmarks applied (and gated) -----------------------

alt.setup({})
local ns = vim.api.nvim_get_namespaces()["sase_alt_highlight"]
if not ns then
  fail("namespace sase_alt_highlight not registered")
else
  local eligible = make_buffer("sase", tmp .. "_hl.sase")
  vim.api.nvim_buf_set_lines(eligible, 0, -1, false, { "%{a | b}" })
  alt.highlight_buffer(eligible)
  local marks = vim.api.nvim_buf_get_extmarks(eligible, ns, 0, -1, {})
  same(#marks, 3, "eligible buffer gets 3 extmarks")

  local ineligible = make_buffer("markdown", tmp .. "_hl_notes.md")
  vim.api.nvim_buf_set_lines(ineligible, 0, -1, false, { "%{a | b}" })
  alt.highlight_buffer(ineligible)
  local none = vim.api.nvim_buf_get_extmarks(ineligible, ns, 0, -1, {})
  same(#none, 0, "ineligible buffer gets no extmarks")
end

if failures > 0 then
  error(string.format("%d alt_highlight test(s) failed", failures), 0)
end

print("alt_highlight: all tests passed")
