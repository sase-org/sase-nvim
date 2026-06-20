-- Headless tests for lua/sase/alt_edit.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/alt_edit.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local alt = require("sase.alt_edit")

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

-- --- Pure planners --------------------------------------------------------- #

-- plan_auto_pair: insert `{}` only directly after a directive-valid `%`.
same(alt.plan_auto_pair("%", 1), { start = 1, stop = 1, text = "{}", cursor = 2 }, "auto-pair at start")
same(alt.plan_auto_pair("run %", 5), { start = 5, stop = 5, text = "{}", cursor = 6 }, "auto-pair after space")
same(alt.plan_auto_pair("(%", 2), { start = 2, stop = 2, text = "{}", cursor = 3 }, "auto-pair after paren")
same(alt.plan_auto_pair("a%", 2), nil, "auto-pair rejects non-directive percent")
same(alt.plan_auto_pair("ab", 2), nil, "auto-pair requires a percent before")
-- The inserted `}` must not run into following non-whitespace text.
same(alt.plan_auto_pair("%foo", 1), nil, "auto-pair rejected when text follows")
same(alt.plan_auto_pair("% foo", 1), { start = 1, stop = 1, text = "{}", cursor = 2 }, "auto-pair ok before whitespace")

-- plan_paired_delete_left/right: only an empty directive `%{}` pair.
same(alt.plan_paired_delete_left("%{}", 2), { start = 1, stop = 3, text = "", cursor = 1 }, "paired backspace empty")
same(alt.plan_paired_delete_left("%{x}", 2), nil, "paired backspace rejects non-empty")
same(alt.plan_paired_delete_left("a{}", 2), nil, "paired backspace rejects non-directive")
same(alt.plan_paired_delete_right("%{}", 1), { start = 1, stop = 3, text = "", cursor = 1 }, "paired delete empty")
same(alt.plan_paired_delete_right("%{x}", 1), nil, "paired delete rejects non-empty")
same(alt.plan_paired_delete_right("a{}", 1), nil, "paired delete rejects non-directive")

-- plan_separator: padded `|`, with comma-spacing normalization of the branch.
same(alt.plan_separator("%{foo}", 5), { start = 2, stop = 5, text = "foo | ", cursor = 8 }, "separator simple branch")
same(
  alt.plan_separator("%{foo ,bar, and baz}", 19),
  { start = 2, stop = 19, text = "foo, bar, and baz | ", cursor = 22 },
  "separator acceptance example"
)
do
  -- Typing `|` after the second branch keeps the first separator intact.
  local plan = alt.plan_separator("%{a | b}", 7)
  if plan == nil then
    fail("separator second branch: expected a plan")
  else
    local applied = ("%{a | b}"):sub(1, plan.start) .. plan.text .. ("%{a | b}"):sub(plan.stop + 1)
    same(applied, "%{a | b | }", "separator second branch preserves prior separator")
  end
end
same(alt.plan_separator("plain", 3), nil, "separator outside span returns nil")
same(alt.plan_separator("a%{foo}", 5), nil, "separator ignores non-directive opener")

-- --- supports_buffer: attach eligibility ----------------------------------- #

alt.setup({})

local function make_buffer(ft, name)
  local buf = vim.api.nvim_create_buf(true, false)
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
  alt.supports_buffer(make_buffer("markdown", "/work/xprompts/" .. vim.fn.fnamemodify(tmp, ":t") .. ".md")),
  true,
  "markdown under xprompts/ eligible"
)

-- --- End-to-end editing in real buffers ------------------------------------ #

-- Drive a single, self-contained typing session and let any scheduled
-- (InsertCharPre) edit settle before asserting.
local function type_in(buf, keys)
  vim.api.nvim_set_current_buf(buf)
  alt.attach(buf)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
  vim.wait(80)
end

local function set_line(buf, line, row, col)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { row, col })
end

alt.setup({})

-- `%{` auto-pairs to `%{}` with the cursor between the braces.
do
  local buf = make_buffer("sase", tmp .. "_e1.sase")
  set_line(buf, "", 1, 0)
  type_in(buf, "i%{")
  same(vim.api.nvim_get_current_line(), "%{}", "e2e auto-pair text")
  same(vim.api.nvim_win_get_cursor(0), { 1, 2 }, "e2e auto-pair cursor between braces")
end

-- Typing `|` inside `%{foo}` yields `%{foo | }` with the cursor before `}`.
do
  local buf = make_buffer("sase", tmp .. "_e2.sase")
  set_line(buf, "%{foo}", 1, 5)
  type_in(buf, "i|")
  same(vim.api.nvim_get_current_line(), "%{foo | }", "e2e separator text")
  same(vim.api.nvim_win_get_cursor(0), { 1, 8 }, "e2e separator cursor before brace")
end

-- The explicit acceptance case from the design doc.
do
  local buf = make_buffer("sase", tmp .. "_e3.sase")
  set_line(buf, "%{foo ,bar, and baz}", 1, 19)
  type_in(buf, "i|")
  same(vim.api.nvim_get_current_line(), "%{foo, bar, and baz | }", "e2e acceptance text")
  same(vim.api.nvim_win_get_cursor(0), { 1, 22 }, "e2e acceptance cursor")
end

-- Backspacing the `{` of an empty `%{}` removes the paired `}`.
do
  local buf = make_buffer("sase", tmp .. "_e4.sase")
  set_line(buf, "%{}", 1, 2)
  type_in(buf, "i<BS>")
  same(vim.api.nvim_get_current_line(), "%", "e2e paired backspace text")
end

-- Delete-right on the `{` of an empty `%{}` removes the paired `}`.
do
  local buf = make_buffer("sase", tmp .. "_e5.sase")
  set_line(buf, "%{}", 1, 1)
  type_in(buf, "i<Del>")
  same(vim.api.nvim_get_current_line(), "%", "e2e paired delete text")
end

-- A non-empty `%{x}` is not paired-deleted; backspace removes only `{`.
do
  local buf = make_buffer("sase", tmp .. "_e6.sase")
  set_line(buf, "%{x}", 1, 2)
  type_in(buf, "i<BS>")
  same(vim.api.nvim_get_current_line(), "%x}", "e2e non-empty backspace removes only brace")
end

-- `|` outside any `%{...}` span inserts a literal pipe (`A` appends at the
-- end of line, side-stepping normal-mode cursor clamping in the harness).
do
  local buf = make_buffer("sase", tmp .. "_e7.sase")
  set_line(buf, "foo", 1, 0)
  type_in(buf, "A|")
  same(vim.api.nvim_get_current_line(), "foo|", "e2e pipe outside span is literal")
end

-- The `#@` picker trigger char is left untouched by alt_edit (it only acts on
-- `{`/`|`); the trigger itself lives in plugin/sase_xprompt.lua.
do
  local buf = make_buffer("sase", tmp .. "_e8.sase")
  set_line(buf, "", 1, 0)
  type_in(buf, "i#@")
  same(vim.api.nvim_get_current_line(), "#@", "e2e alt_edit leaves #@ untouched")
end

-- No edits happen outside supported buffers: plain markdown is inert.
do
  local buf = make_buffer("markdown", tmp .. "_e9_notes.md")
  set_line(buf, "", 1, 0)
  type_in(buf, "i%{")
  same(vim.api.nvim_get_current_line(), "%{", "e2e ineligible buffer: no auto-pair")
end
do
  local buf = make_buffer("markdown", tmp .. "_e10_notes.md")
  set_line(buf, "%{foo}", 1, 5)
  type_in(buf, "i|")
  same(vim.api.nvim_get_current_line(), "%{foo|}", "e2e ineligible buffer: literal pipe")
end

-- With allow_all_markdown, ordinary markdown becomes eligible and pairs.
alt.setup({ allow_all_markdown = true })
do
  local buf = make_buffer("markdown", tmp .. "_e11_notes.md")
  set_line(buf, "", 1, 0)
  type_in(buf, "i%{")
  same(vim.api.nvim_get_current_line(), "%{}", "e2e allow_all_markdown enables pairing")
end

if failures > 0 then
  error(string.format("%d alt_edit test(s) failed", failures), 0)
end

print("alt_edit: all tests passed")
