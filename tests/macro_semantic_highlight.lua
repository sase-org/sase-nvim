-- Headless tests for lua/sase/macro_semantic_highlight.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/macro_semantic_highlight.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local macro = require("sase.macro_semantic_highlight")

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

local function get_hl(name)
	if vim.api.nvim_get_hl then
		return vim.api.nvim_get_hl(0, { name = name, link = true })
	end
	return vim.api.nvim_get_hl_by_name(name, true)
end

-- --- default highlight groups -------------------------------------------

macro.setup({})

same(get_hl("SaseMacroArgKey").link, "Identifier", "SaseMacroArgKey default link")
same(get_hl("SaseMacroArgOperator").link, "Comment", "SaseMacroArgOperator default link")

-- legacy xprompt spelling; retired alias, always accepted
same(get_hl("SaseXpromptArgKey").link, "SaseMacroArgKey", "legacy key group links to the canonical group")
same(
	get_hl("SaseXpromptArgOperator").link,
	"SaseMacroArgOperator",
	"legacy operator group links to the canonical group"
)

vim.api.nvim_set_hl(0, "SaseMacroArgKey", { bold = true })
macro.define_highlights()
local overridden_hl = get_hl("SaseMacroArgKey")
same(overridden_hl.bold, true, "user-defined SaseMacroArgKey survives default refresh")
same(overridden_hl.link, nil, "default refresh does not overwrite user SaseMacroArgKey")

-- --- legacy group overrides -----------------------------------------------
-- legacy xprompt spelling; retired alias, always accepted

local function clear_hl(name)
	vim.cmd("highlight clear " .. name)
end

clear_hl("SaseMacroArgKey")
clear_hl("SaseXpromptArgKey")
vim.api.nvim_set_hl(0, "SaseXpromptArgKey", { bold = true })
macro.define_highlights()
local mirrored_hl = get_hl("SaseMacroArgKey")
same(mirrored_hl.bold, true, "user override of the legacy group takes effect on the canonical group")

clear_hl("SaseMacroArgKey")
clear_hl("SaseXpromptArgKey")
vim.api.nvim_set_hl(0, "SaseXpromptArgKey", { italic = true })
vim.api.nvim_set_hl(0, "SaseMacroArgKey", { bold = true })
macro.define_highlights()
local winning_hl = get_hl("SaseMacroArgKey")
same(winning_hl.bold, true, "canonical override wins over the legacy override")
same(winning_hl.italic, nil, "legacy override does not leak when the canonical group is customized")

clear_hl("SaseMacroArgKey")
clear_hl("SaseXpromptArgKey")
vim.api.nvim_set_hl(0, "SaseXpromptArgKey", { bold = true })
same(
	macro._effective_group("SaseMacroArgKey"),
	"SaseXpromptArgKey",
	"legacy-only override reroutes token highlights set after setup"
)
vim.api.nvim_set_hl(0, "SaseMacroArgKey", { bold = true })
same(
	macro._effective_group("SaseMacroArgKey"),
	"SaseMacroArgKey",
	"canonical override wins the token highlight routing"
)
clear_hl("SaseMacroArgKey")
clear_hl("SaseXpromptArgKey")
macro.define_highlights()
same(macro._effective_group("SaseMacroArgKey"), "SaseMacroArgKey", "effective group is canonical by default")

-- --- LspTokenUpdate callback filtering -----------------------------------

vim.lsp.semantic_tokens = vim.lsp.semantic_tokens or {}

local original_highlight_token = vim.lsp.semantic_tokens.highlight_token
local original_get_client_by_id = vim.lsp.get_client_by_id
local highlighted = {}
local clients = {
	[7] = { name = "sase-macro-lsp" },
	[8] = { name = "foreign-lsp" },
}

vim.lsp.semantic_tokens.highlight_token = function(token, bufnr, client_id, group)
	highlighted[#highlighted + 1] = {
		token = token,
		bufnr = bufnr,
		client_id = client_id,
		group = group,
	}
end

vim.lsp.get_client_by_id = function(client_id)
	return clients[client_id]
end

local function reset_calls()
	highlighted = {}
end

macro.setup({ enabled = true })

local key_token = { type = "parameter", line = 0, start_col = 5, end_col = 10 }
same(macro._token_group(key_token), "SaseMacroArgKey", "parameter maps to key group")
macro._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = key_token },
})
same(#highlighted, 1, "sase parameter token is highlighted")
same(highlighted[1].group, "SaseMacroArgKey", "parameter group is applied")

reset_calls()
macro._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "operator" } },
})
same(#highlighted, 1, "sase operator token is highlighted")
same(highlighted[1].group, "SaseMacroArgOperator", "operator group is applied")

-- legacy xprompt spelling; retired alias, always accepted
reset_calls()
vim.api.nvim_set_hl(0, "SaseXpromptArgKey", { bold = true })
macro._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = key_token },
})
same(#highlighted, 1, "legacy-overridden parameter token is highlighted")
same(highlighted[1].group, "SaseXpromptArgKey", "post-setup legacy override reroutes the applied group")
clear_hl("SaseXpromptArgKey")
macro.define_highlights()

reset_calls()
macro._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "string" } },
})
same(#highlighted, 0, "standard string token stays colorscheme-owned")

reset_calls()
macro._on_lsp_token_update({
	buf = 12,
	data = { client_id = 8, token = { type = "parameter" } },
})
same(#highlighted, 0, "foreign LSP client is ignored")

reset_calls()
macro.setup({ enabled = false })
macro._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "parameter" } },
})
same(#highlighted, 0, "disabled macro highlighting is ignored")

-- --- top-level setup wiring ----------------------------------------------

require("sase").setup({
	lsp = { enabled = false },
	glossary_highlight = { enabled = false },
	macro_highlight = { enabled = false },
	alt_highlight = { enabled = false },
	alt_editing = { enabled = false },
	macro_spacer = { enabled = false },
})
same(macro._config().enabled, false, "top-level setup forwards macro_highlight opts")

-- --- legacy setup keys ------------------------------------------------------
-- legacy xprompt spelling; retired alias, always accepted

local original_notify = vim.notify
local deprecation_warnings = {}
vim.notify = function(message, level)
	if level == vim.log.levels.WARN and type(message) == "string" and message:find("deprecated", 1, true) then
		deprecation_warnings[#deprecation_warnings + 1] = message
	end
end

require("sase").setup({
	lsp = { enabled = false },
	glossary_highlight = { enabled = false },
	xprompt_highlight = { enabled = false },
	alt_highlight = { enabled = false },
	alt_editing = { enabled = false },
	xprompt_spacer = { enabled = false },
})
same(macro._config().enabled, false, "top-level setup forwards the legacy highlight key")
local spacer = require("sase.macro_spacer")
same(spacer._config().enabled, false, "top-level setup forwards the legacy spacer key")
same(#deprecation_warnings, 2, "each legacy setup key warns once")
same(
	deprecation_warnings[1]:find("macro_highlight", 1, true) ~= nil,
	true,
	"legacy highlight warning names the replacement"
)

require("sase").setup({
	lsp = { enabled = false },
	xprompt_highlight = { enabled = false },
})
same(#deprecation_warnings, 2, "legacy setup key warning is one-time")

local both_ok = pcall(require("sase").setup, {
	lsp = { enabled = false },
	macro_highlight = { enabled = true },
	xprompt_highlight = { enabled = false },
})
same(both_ok, false, "supplying both the new and legacy highlight key is an error")

vim.notify = original_notify

vim.lsp.semantic_tokens.highlight_token = original_highlight_token
vim.lsp.get_client_by_id = original_get_client_by_id

if failures > 0 then
	error(string.format("%d macro_semantic_highlight test(s) failed", failures), 0)
end

print("macro_semantic_highlight: all tests passed")
