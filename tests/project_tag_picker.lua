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

-- --- picker failures -------------------------------------------------------
--
-- The tests below drive the real `pick()` with stubbed Neovim async plumbing
-- (`jobstart`, `ui.select`, `schedule`): the in-place buffer replacement is
-- real, only the process and the menu are faked.

local saved_jobstart = vim.fn.jobstart
local saved_ui_select = vim.ui.select
local saved_schedule = vim.schedule
local saved_notify = vim.notify
local saved_restore_insert_mode = require("sase.complete._picker").restore_insert_mode

local notified = {}
local function stub_common()
	notified = {}
	vim.schedule = function(fn)
		fn()
	end
	vim.notify = function(message, level)
		notified[#notified + 1] = { message = message, level = level }
	end
	require("sase.complete._picker").restore_insert_mode = function() end
end

local function restore_common()
	vim.fn.jobstart = saved_jobstart
	vim.ui.select = saved_ui_select
	vim.schedule = saved_schedule
	vim.notify = saved_notify
	require("sase.complete._picker").restore_insert_mode = saved_restore_insert_mode
end

local function job_with_stdout(payload, code)
	vim.fn.jobstart = function(_, opts)
		if payload ~= nil then
			opts.on_stdout(1, { payload })
		end
		opts.on_exit(1, code or 0)
		return 1
	end
end

stub_common()
job_with_stdout(vim.json.encode({ { tag = "+sase" }, { tag = "+bob-cli" } }))
vim.ui.select = function(items, _, on_choice)
	on_choice(items[1])
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "use +sa" })
local pick_cancelled = false
project_tag.pick({
	token = { text = "+sa", row = 0, col_start = 4, col_end = 7 },
	on_cancel = function()
		pick_cancelled = true
	end,
})
same(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "use +sase ", "picker inserts the chosen tag with a trailing space")
same(pick_cancelled, false, "a successful pick does not cancel")
same(#notified, 0, "a successful pick notifies nothing")

-- Every fetch failure warns and cancels instead of failing silently.
local failure_cases = {
	{
		label = "failing `sase project list`",
		setup = function()
			vim.fn.jobstart = function()
				return -1
			end
		end,
	},
	{
		label = "invalid JSON",
		setup = function()
			job_with_stdout("not json{", 0)
		end,
	},
	{
		label = "empty output",
		setup = function()
			job_with_stdout("", 0)
		end,
	},
	{
		label = "non-zero exit",
		setup = function()
			job_with_stdout(nil, 1)
		end,
	},
}
for _, case in ipairs(failure_cases) do
	notified = {}
	case.setup()
	vim.ui.select = function()
		fail(case.label .. " must never open the menu")
	end
	local cancelled = false
	project_tag.pick({
		token = { text = "+sa", row = 0, col_start = 4, col_end = 7 },
		on_cancel = function()
			cancelled = true
		end,
	})
	same(cancelled, true, case.label .. " calls on_cancel")
	same(#notified, 1, case.label .. " warns once")
	same(notified[1].level, vim.log.levels.WARN, case.label .. " warns at WARN level")
end
restore_common()

-- --- auto-mode fallback ------------------------------------------------------
--
-- In `auto` mode with native completion disabled (e.g. nvim-cmp owns LSP
-- completion), `sase.lsp.complete()` returns false and a `+query` reaches
-- the project picker.

do
	local saved_token = package.loaded["sase.complete._token"]
	local saved_lsp = package.loaded["sase.lsp"]
	local saved_complete = package.loaded["sase.complete"]
	local real_pick = project_tag.pick

	stub_common()
	job_with_stdout(vim.json.encode({ { tag = "+sase" } }))
	vim.ui.select = function(_, _, on_choice)
		on_choice(nil)
	end

	package.loaded["sase.complete._token"] = {
		token_under_cursor = function()
			return { text = "+sa", row = 0, col_start = 20, col_end = 23 }
		end,
		classify = function(token_text)
			return token_text:sub(1, 1) == "+" and "project_tag" or nil
		end,
	}
	local lsp_calls = 0
	package.loaded["sase.lsp"] = {
		complete = function()
			lsp_calls = lsp_calls + 1
			return false
		end,
	}
	local reached = nil
	project_tag.pick = function(opts)
		reached = opts
	end
	package.loaded["sase.complete"] = nil
	local complete = require("sase.complete")
	complete.setup({ completion_backend = "auto" })
	complete.trigger()
	same(lsp_calls, 1, "auto mode asks the LSP first")
	same(reached ~= nil, true, "auto mode falls back to the project picker when LSP completion is unavailable")
	same(
		reached and reached.token,
		{ text = "+sa", row = 0, col_start = 20, col_end = 23 },
		"auto-mode fallback passes the +query token to the picker"
	)

	project_tag.pick = real_pick
	package.loaded["sase.complete._token"] = saved_token
	package.loaded["sase.lsp"] = saved_lsp
	package.loaded["sase.complete"] = saved_complete
	restore_common()
end

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
