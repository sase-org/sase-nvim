-- Headless tests for the `+project` tag picker fallback in
-- lua/sase/complete/project_tag.lua and its `sase.complete` wiring.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/project_tag_picker.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

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

local project_tag = require("sase.complete.project_tag")

-- --- tag extraction ------------------------------------------------------

same(project_tag._tags_from_entries(nil), {}, "nil entries yield no tags")
same(project_tag._tags_from_entries({}), {}, "empty entries yield no tags")
same(
	project_tag._tags_from_entries({
		{ tag = "+sase", display_name = "sase" },
		{ tag = "+bob-cli", display_name = "bob-cli" },
		{ tag = "+home", display_name = "home" },
	}),
	{ "+sase", "+bob-cli", "+home" },
	"tag fields are collected in order"
)
same(
	project_tag._tags_from_entries({
		{ display_name = "no-tag" },
		{ tag = 42 },
		{ tag = "not a tag" },
		{ tag = "+ok" },
	}),
	{ "+ok" },
	"entries without a well-formed tag are skipped"
)

-- --- query filtering -----------------------------------------------------

local tags = { "+sase", "+bob-cli", "+actstat", "+home" }

same(project_tag._filter_tags(tags, ""), tags, "empty query lists every project")
same(project_tag._filter_tags(tags, nil), tags, "nil query lists every project")
same(project_tag._filter_tags(tags, "sa"), { "+sase" }, "prefix query filters by name")
same(project_tag._filter_tags(tags, "SA"), { "+sase" }, "query filtering is case-insensitive")
same(project_tag._filter_tags(tags, "bob"), { "+bob-cli" }, "partial name filters")
same(project_tag._filter_tags(tags, "o"), { "+bob-cli", "+home" }, "substring matches keep catalog order")
same(project_tag._filter_tags(tags, "s"), { "+sase", "+actstat" }, "prefix matches sort before substring matches")
same(project_tag._filter_tags(tags, "zzz"), {}, "unmatched query yields nothing")

-- --- <C-t> dispatcher wiring ----------------------------------------------

local picked = nil

package.loaded["sase.complete._token"] = {
	token_under_cursor = function()
		return { text = "+sa", row = 0, col_start = 20, col_end = 23 }
	end,
	classify = function(token)
		return token:sub(1, 1) == "+" and "project_tag" or nil
	end,
}
package.loaded["sase.complete.project_tag"] = {
	pick = function(opts)
		picked = opts
	end,
}

package.loaded["sase.complete"] = nil
local complete = require("sase.complete")

complete.setup({ completion_backend = "picker" })
complete.trigger()
same(picked ~= nil, true, "picker backend routes +query to the project-tag picker")
same(
	picked and picked.token,
	{ text = "+sa", row = 0, col_start = 20, col_end = 23 },
	"project-tag picker receives the token context"
)

if failures > 0 then
	error(string.format("%d project_tag_picker test(s) failed", failures), 0)
end

print("project_tag_picker: all tests passed")
