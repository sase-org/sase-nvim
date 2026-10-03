package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local token = require("sase.complete._token")
local macro = require("sase.macro")

local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function contains(text, needle, label)
	if not text:find(needle, 1, true) then
		error(string.format("%s: expected %s to contain %s", label, vim.inspect(text), vim.inspect(needle)))
	end
end

local function assert_no_newlines(lines, label)
	for index, line in ipairs(lines) do
		if line:find("\n", 1, true) or line:find("\r", 1, true) then
			error(string.format("%s: line %d contains a newline: %s", label, index, vim.inspect(line)))
		end
	end
end

eq(token.is_slash_skill_like("/"), true, "bare slash is slash-skill-like")
eq(token.is_slash_skill_like("/sase_plan"), true, "identifier slash skill is slash-skill-like")
eq(token.is_slash_skill_like("/tmp/foo"), false, "absolute path is not slash-skill-like")
eq(token.is_slash_skill_like("/sase-plan"), false, "punctuated slash token is not slash-skill-like")
eq(token.classify("/"), "macro", "bare slash classifies as macro")
eq(token.classify("/sase_plan"), "macro", "slash skill classifies as macro")
eq(token.classify("/tmp/foo"), "file", "absolute path remains file")

local items = {
	{
		name = "sase_plan",
		type = "macro",
		kind = "macro",
		insertion = "#sase_plan",
		is_skill = true,
		inputs = {},
		preview = "Plan",
	},
	{
		name = "sample",
		type = "macro",
		kind = "macro",
		insertion = "#sample",
		is_skill = false,
		inputs = {},
		preview = "Sample",
	},
	{
		name = "sync",
		type = "workflow",
		kind = "standalone_workflow",
		insertion = "#!sync",
		is_skill = false,
		inputs = {},
		preview = "Sync",
	},
}

-- legacy xprompt spelling; remove with legacy_xprompt_syntax
local legacy_item = {
	name = "legacy",
	type = "xprompt",
	kind = "xprompt",
	insertion = "#legacy",
	is_skill = false,
	inputs = {},
	preview = "Legacy",
}
eq(macro._item_kind_label(legacy_item), "Macro", "legacy kind still labels as Macro")
eq(macro._item_insertion(legacy_item), "#legacy", "legacy insertion keeps catalog insertion")
eq(
	macro._filter_items_for_token({ legacy_item }, { text = "#leg" })[1].name,
	"legacy",
	"legacy items still filter by name"
)

local slash = macro._filter_items_for_token(items, { text = "/sas" })
eq(#slash, 1, "slash filtering returns only matching skills")
eq(slash[1].name, "sase_plan", "slash filtering matches by item name")
eq(macro._item_insertion(slash[1]), "/sase_plan", "slash insertion uses slash reference")
eq(macro._item_kind_label(slash[1]), "Skill", "slash item label is Skill")

local hash = macro._filter_items_for_token(items, { text = "#sa" })
eq(#hash, 2, "hash filtering preserves non-skill macros")
eq(macro._item_insertion(hash[1]), "#sase_plan", "hash insertion keeps catalog insertion")
eq(macro._item_insertion(hash[2]), "#sample", "hash insertion keeps regular macro insertion")

local standalone = macro._filter_items_for_token(items, { text = "#!" })
eq(#standalone, 1, "bang filtering returns standalone workflows")
eq(standalone[1].name, "sync", "bang filtering preserves standalone behavior")
eq(macro._item_insertion(standalone[1]), "#!sync", "bang insertion keeps catalog insertion")

eq(macro._format_entry(items[2]), "  #sample", "entry without descriptions stays compact")
eq(macro._format_display(items[2]), "  #sample", "display without descriptions stays compact")

local fixture_path = vim.fn.getcwd() .. "/tests/fixtures/macro_list_with_descriptions.json"
local described_items = vim.json.decode(table.concat(vim.fn.readfile(fixture_path), "\n"))
local described = described_items[1]

eq(
	macro._format_entry(described),
	"  #review(diff, focus?) - Review a diff and identify follow-up work.",
	"entry includes macro description"
)
eq(
	macro._format_display(described),
	"  #review\n"
		.. "  Review a diff and identify follow-up work.\n"
		.. "  diff - Diff file to review.\n"
		.. "  focus=bugs - Scope word for the review.",
	"display includes macro and input descriptions"
)

local by_description = macro._filter_items_for_token(described_items, { text = "#follow" })
eq(#by_description, 1, "hash filtering matches macro descriptions")
eq(by_description[1].name, "review", "description filtering returns described item")

local by_input_description = macro._filter_items_for_token(described_items, { text = "#scope" })
eq(#by_input_description, 1, "hash filtering matches input descriptions")
eq(by_input_description[1].name, "review", "input description filtering returns described item")

local preview = macro._format_preview(described)
contains(preview, "## Description", "preview has description section")
contains(preview, "Review a diff and identify follow-up work.", "preview includes macro description")
contains(preview, "## Inputs", "preview has inputs section")
contains(preview, "- diff: path - Diff file to review.", "preview includes required input description")
contains(
	preview,
	"- focus: word (default: bugs) - Scope word for the review.",
	"preview includes defaulted input description"
)
contains(preview, "## Preview", "preview keeps content preview section")
contains(preview, "Review {{ diff }} with {{ focus }}.", "preview keeps existing content preview")

local null_default = {
	name = "nullable",
	type = "macro",
	kind = "macro",
	insertion = "#nullable",
	is_skill = false,
	inputs = {
		{
			name = "topic",
			type = "word",
			required = false,
			default = vim.NIL,
			description = "Optional topic.",
		},
	},
	preview = "Nullable {{ topic }}.",
}

local null_preview_ok, null_preview = pcall(macro._format_preview, null_default)
eq(null_preview_ok, true, "preview tolerates optional vim.NIL defaults")
contains(
	null_preview,
	"- topic: word (optional) - Optional topic.",
	"preview renders optional vim.NIL defaults as optional"
)

local null_display_ok, null_display = pcall(macro._format_display, null_default)
eq(null_display_ok, true, "display tolerates optional vim.NIL defaults")
contains(null_display, "  topic? - Optional topic.", "display renders optional vim.NIL defaults with optional marker")

local null_preview_lines = macro._preview_lines(null_default)
assert_no_newlines(null_preview_lines, "null default preview")

local multiline = {
	name = "multiline",
	type = "macro",
	kind = "macro",
	insertion = "#multiline",
	is_skill = false,
	description = "Primary line\nSecondary line\r\nThird line\rFourth line",
	inputs = {
		{
			name = "topic",
			type = "word",
			required = true,
			default = nil,
			description = "Input first line\nInput second line\r\nInput third line\rInput fourth line",
		},
	},
	preview = "Preview first line\nPreview second line\r\nPreview third line\rPreview fourth line",
}

local multiline_preview_lines = macro._preview_lines(multiline)
assert_no_newlines(multiline_preview_lines, "multiline preview")
eq(
	table.concat(multiline_preview_lines, "\n"),
	"## Description\n"
		.. "Primary line\n"
		.. "Secondary line\n"
		.. "Third line\n"
		.. "Fourth line\n"
		.. "\n"
		.. "## Inputs\n"
		.. "- topic: word - Input first line\n"
		.. "  Input second line\n"
		.. "  Input third line\n"
		.. "  Input fourth line\n"
		.. "\n"
		.. "## Preview\n"
		.. "Preview first line\n"
		.. "Preview second line\n"
		.. "Preview third line\n"
		.. "Preview fourth line",
	"preview splits multiline descriptions and body into buffer-safe lines"
)

local multiline_entry = macro._format_entry(multiline)
assert_no_newlines({ multiline_entry }, "multiline fallback entry")
contains(multiline_entry, "Primary line Secondary line Third line Fourth line", "entry flattens multiline descriptions")
