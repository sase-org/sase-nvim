-- Headless tests for lua/sase/xprompt_spacer.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/xprompt_spacer.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local spacer = require("sase.xprompt_spacer")
local xprompt = require("sase.xprompt")

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

local function always(value)
  return function()
    return value
  end
end

-- --- Pure planner: plan_colon -------------------------------------------- #

same(
  spacer.plan_colon("#optional ", 10, always(true)),
  { start = 9, stop = 10 },
  "plan targets optional-only spacer"
)
same(
  spacer.plan_colon("#!opt ", 6, always(true)),
  { start = 5, stop = 6 },
  "plan handles #! standalone reference"
)
same(
  spacer.plan_colon("foo #optional ", 14, always(true)),
  { start = 13, stop = 14 },
  "plan handles a reference mid-line"
)
same(spacer.plan_colon("#optional ", 10, always(false)), nil, "plan nil when not optional-only")
same(spacer.plan_colon("#optional", 9, always(true)), nil, "plan nil without a trailing spacer")
same(spacer.plan_colon("#optional x", 11, always(true)), nil, "plan nil when cursor not after the spacer")
same(spacer.plan_colon("before#optional ", 16, always(true)), nil, "plan nil for a mid-word '#' fragment")
same(spacer.plan_colon("# ", 2, always(true)), nil, "plan nil for a bare '#'")
same(spacer.plan_colon("/skill ", 7, always(true)), nil, "plan nil for a slash-skill reference")

-- --- Catalog predicate: reference_is_optional_only ------------------------ #

xprompt._set_cache({
  { name = "optional", insertion = "#optional", type = "xprompt", inputs = { { name = "topic", type = "word", required = false } }, preview = "" },
  { name = "plain", insertion = "#plain", type = "xprompt", inputs = {}, preview = "" },
  { name = "mixed", insertion = "#mixed", type = "xprompt", inputs = { { name = "a", type = "word", required = false }, { name = "b", type = "path", required = true } }, preview = "" },
  { name = "bang", insertion = "#!bang", kind = "standalone_workflow", type = "workflow", inputs = { { name = "x", type = "word", required = false } }, preview = "" },
})

same(xprompt.reference_is_optional_only("#optional"), true, "predicate: optional-only is true")
same(xprompt.reference_is_optional_only("#plain"), false, "predicate: no-input is false")
same(xprompt.reference_is_optional_only("#mixed"), false, "predicate: any required input is false")
same(xprompt.reference_is_optional_only("#!bang"), true, "predicate: standalone optional-only is true")
same(xprompt.reference_is_optional_only("#unknown"), false, "predicate: unknown reference is false")

xprompt._set_cache(nil)
same(xprompt.reference_is_optional_only("#optional"), false, "predicate: cold catalog is false")

-- --- supports_buffer: attach eligibility --------------------------------- #

spacer.setup({})

local function make_buffer(ft, name)
  local buf = vim.api.nvim_create_buf(true, false)
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].filetype = ft
  return buf
end

local tmp = vim.fn.tempname()

same(spacer.supports_buffer(make_buffer("sase", tmp .. "_a.sase")), true, "sase filetype eligible")
same(spacer.supports_buffer(make_buffer("sase_prompt", tmp .. "_b")), true, "sase_prompt filetype eligible")
same(spacer.supports_buffer(make_buffer("gitcommit", tmp .. "_COMMIT_EDITMSG")), true, "gitcommit eligible")
same(spacer.supports_buffer(make_buffer("lua", tmp .. "_c.lua")), false, "unrelated filetype not eligible")
same(spacer.supports_buffer(make_buffer("markdown", tmp .. "_notes.md")), false, "plain markdown not eligible")

-- --- End-to-end editing in real buffers ---------------------------------- #

local function type_in(buf, keys)
  vim.api.nvim_set_current_buf(buf)
  spacer.attach(buf)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
  vim.wait(80)
end

local function set_line(buf, line, row, col)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { row, col })
end

spacer.setup({})
xprompt._set_cache({
  { name = "optional", insertion = "#optional", type = "xprompt", inputs = { { name = "topic", type = "word", required = false } }, preview = "" },
  { name = "plain", insertion = "#plain", type = "xprompt", inputs = {}, preview = "" },
})

-- Optional-only `#name ` + `:` replaces the spacer in place.
do
  local buf = make_buffer("sase", tmp .. "_e1.sase")
  set_line(buf, "#optional ", 1, 0)
  type_in(buf, "A:")
  same(vim.api.nvim_get_current_line(), "#optional:", "e2e optional-only colon rewrite")
  same(vim.api.nvim_win_get_cursor(0), { 1, 10 }, "e2e cursor sits after the colon")
end

-- A no-input xprompt keeps its trailing space; the colon just inserts.
do
  local buf = make_buffer("sase", tmp .. "_e2.sase")
  set_line(buf, "#plain ", 1, 0)
  type_in(buf, "A:")
  same(vim.api.nvim_get_current_line(), "#plain :", "e2e no-input spacer is untouched")
end

-- An unknown reference is left alone.
do
  local buf = make_buffer("sase", tmp .. "_e3.sase")
  set_line(buf, "#unknown ", 1, 0)
  type_in(buf, "A:")
  same(vim.api.nvim_get_current_line(), "#unknown :", "e2e unknown reference is untouched")
end

-- A non-colon character does not trigger the rewrite.
do
  local buf = make_buffer("sase", tmp .. "_e4.sase")
  set_line(buf, "#optional ", 1, 0)
  type_in(buf, "Ax")
  same(vim.api.nvim_get_current_line(), "#optional x", "e2e non-colon key is inert")
end

-- An ineligible buffer never attaches, so nothing is rewritten.
do
  local buf = make_buffer("markdown", tmp .. "_e5_notes.md")
  set_line(buf, "#optional ", 1, 0)
  type_in(buf, "A:")
  same(vim.api.nvim_get_current_line(), "#optional :", "e2e ineligible buffer is inert")
end

-- A cold catalog does nothing rather than guessing.
do
  xprompt._set_cache(nil)
  local buf = make_buffer("sase", tmp .. "_e6.sase")
  set_line(buf, "#optional ", 1, 0)
  type_in(buf, "A:")
  same(vim.api.nvim_get_current_line(), "#optional :", "e2e cold catalog is inert")
end

if failures > 0 then
  error(string.format("%d xprompt_spacer test(s) failed", failures), 0)
end

print("xprompt_spacer: all tests passed")
