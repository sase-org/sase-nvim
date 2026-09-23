-- Headless tests for `+project` tag token recognition in
-- lua/sase/complete/_token.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/project_tag_token.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local token = require("sase.complete._token")

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

-- --- pure classification -------------------------------------------------

same(token.is_project_tag_like("+"), true, "bare plus is tag-like")
same(token.is_project_tag_like("+s"), true, "partial query is tag-like")
same(token.is_project_tag_like("+sase"), true, "full query is tag-like")
same(token.is_project_tag_like("+bob-cli"), true, "punctuated query is tag-like")
same(token.is_project_tag_like("+1"), false, "numeric query is not tag-like")
same(token.is_project_tag_like("+ item"), false, "query with space is not tag-like")
same(token.is_project_tag_like("C++"), false, "increment operator is not tag-like")
same(token.is_project_tag_like("a+b"), false, "infix plus is not tag-like")
same(token.is_project_tag_like("#sase"), false, "hash ref is not tag-like")
same(token.is_project_tag_like(nil), false, "nil is not tag-like")

same(token.classify("+"), "project_tag", "bare plus classifies as project_tag")
same(token.classify("+sase"), "project_tag", "tag query classifies as project_tag")
same(token.classify("#plan"), "xprompt", "hash ref still classifies as xprompt")
same(token.classify(nil), "file_history", "empty token still classifies as file_history")

-- --- cursor extraction ---------------------------------------------------
--
-- `token_under_cursor` reads the current window, so drive it through a
-- scratch buffer with explicit cursor positions.

local function token_at(line, col)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
	vim.api.nvim_win_set_cursor(0, { 1, col })
	return token.token_under_cursor()
end

same(token_at("+sase", 5), { text = "+sase", row = 0, col_start = 0, col_end = 5 }, "start-of-line query keeps its plus")
same(token_at("+", 1), { text = "+", row = 0, col_start = 0, col_end = 1 }, "bare start-of-line plus is the trigger")
same(
	token_at("Describe this repo. +sa", 23),
	{ text = "+sa", row = 0, col_start = 20, col_end = 23 },
	"query after whitespace keeps its plus"
)
same(
	token_at("%{+sase | +bob}", 13),
	{ text = "+bob", row = 0, col_start = 10, col_end = 14 },
	"query after a pipe keeps its plus"
)
same(token_at("a+b", 3), { text = "b", row = 0, col_start = 2, col_end = 3 }, "infix plus still splits the token")
same(token_at("C++", 3), nil, "increment operator extracts no token")
same(token_at("+1", 2), { text = "1", row = 0, col_start = 1, col_end = 2 }, "numeric query keeps its old token shape")

if failures > 0 then
	error(string.format("%d project_tag_token test(s) failed", failures), 0)
end

print("project_tag_token: all tests passed")
