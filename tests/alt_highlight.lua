-- Headless tests for lua/sase/alt_highlight.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/alt_highlight.lua
--
-- Highlighting is an LSP-token overlay: the xprompt LSP owns the alternation
-- grammar and this module maps tokens carrying the `alternation` modifier
-- onto the long-lived `SaseAlt*` groups via `LspTokenUpdate`.

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

local function get_hl(name)
	if vim.api.nvim_get_hl then
		return vim.api.nvim_get_hl(0, { name = name, link = true })
	end
	return vim.api.nvim_get_hl_by_name(name, true)
end

-- --- default highlight groups -------------------------------------------

alt.setup({})

same(get_hl("SaseAltDelimiter").link, "Delimiter", "SaseAltDelimiter default link")
same(get_hl("SaseAltSeparator").link, "Operator", "SaseAltSeparator default link")
same(get_hl("SaseAltBranchName").link, "Identifier", "SaseAltBranchName default link")
same(get_hl("SaseAltError").link, "Error", "SaseAltError default link")

vim.api.nvim_set_hl(0, "SaseAltDelimiter", { bold = true })
alt.define_highlights()
local overridden_hl = get_hl("SaseAltDelimiter")
same(overridden_hl.bold, true, "user-defined SaseAltDelimiter survives default refresh")
same(overridden_hl.link, nil, "default refresh does not overwrite user SaseAltDelimiter")

-- --- token -> group mapping ----------------------------------------------

-- List-shaped modifiers (older shape, also used here).
same(
	alt._token_group({ type = "operator", modifiers = { "alternation" } }),
	"SaseAltDelimiter",
	"operator + alternation maps to delimiter"
)
same(
	alt._token_group({ type = "operator", modifiers = { "alternation", "separator" } }),
	"SaseAltSeparator",
	"separator maps to separator group"
)
same(
	alt._token_group({ type = "parameter", modifiers = { "alternation" } }),
	"SaseAltBranchName",
	"parameter + alternation maps to branch name"
)
same(
	alt._token_group({ type = "operator", modifiers = { "alternation", "unknown" } }),
	"SaseAltError",
	"unclosed opener maps to error"
)
-- Set-shaped modifiers (Neovim 0.10+).
same(
	alt._token_group({ type = "operator", modifiers = { alternation = true } }),
	"SaseAltDelimiter",
	"set-shaped alternation maps to delimiter"
)
same(
	alt._token_group({ type = "operator", modifiers = { alternation = true, separator = true } }),
	"SaseAltSeparator",
	"set-shaped separator maps to separator group"
)
same(
	alt._token_group({ type = "parameter", modifiers = { alternation = true } }),
	"SaseAltBranchName",
	"set-shaped parameter maps to branch name"
)
same(
	alt._token_group({ type = "operator", modifiers = { alternation = true, unknown = true } }),
	"SaseAltError",
	"set-shaped unclosed opener maps to error"
)
-- Tokens without the alternation modifier stay colorscheme-owned.
same(alt._token_group({ type = "operator" }), nil, "bare operator is ignored")
same(alt._token_group({ type = "operator", modifiers = {} }), nil, "modifier-less operator is ignored")
same(alt._token_group({ type = "parameter" }), nil, "bare parameter is ignored")
same(alt._token_group({ type = "parameter", modifiers = { "documentation" } }), nil, "foreign parameter is ignored")
same(
	alt._token_group({ type = "string", modifiers = { "alternation" } }),
	nil,
	"unexpected alternation type is ignored"
)
same(alt._token_group(nil), nil, "nil token is ignored")

-- --- LspTokenUpdate callback filtering -----------------------------------

vim.lsp.semantic_tokens = vim.lsp.semantic_tokens or {}

local original_highlight_token = vim.lsp.semantic_tokens.highlight_token
local original_get_client_by_id = vim.lsp.get_client_by_id
local highlighted = {}
local clients = {
	[7] = { name = "sase-xprompt-lsp" },
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

alt.setup({ enabled = true })

local delimiter_token = { type = "operator", modifiers = { alternation = true } }
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = delimiter_token },
})
same(#highlighted, 1, "sase delimiter token is highlighted")
same(highlighted[1].group, "SaseAltDelimiter", "delimiter group is applied")

reset_calls()
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "operator", modifiers = { "alternation", "separator" } } },
})
same(#highlighted, 1, "sase separator token is highlighted")
same(highlighted[1].group, "SaseAltSeparator", "separator group is applied")

reset_calls()
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "parameter", modifiers = { "alternation" } } },
})
same(#highlighted, 1, "sase branch-name token is highlighted")
same(highlighted[1].group, "SaseAltBranchName", "branch-name group is applied")

reset_calls()
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "operator", modifiers = { "alternation", "unknown" } } },
})
same(#highlighted, 1, "sase error token is highlighted")
same(highlighted[1].group, "SaseAltError", "error group is applied")

reset_calls()
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "operator" } },
})
same(#highlighted, 0, "non-alternation operator stays colorscheme-owned")

reset_calls()
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 8, token = delimiter_token },
})
same(#highlighted, 0, "foreign LSP client is ignored")

reset_calls()
alt.setup({ enabled = false })
alt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = delimiter_token },
})
same(#highlighted, 0, "disabled alt highlighting is ignored")

-- --- legacy setup keys are accepted ---------------------------------------

alt.setup({ enabled = true, debounce_ms = 10, max_lines = 100, max_bytes = 1000 })
same(alt._config().enabled, true, "legacy scan bounds are accepted")
alt.setup({ enabled = true, filetypes = { "sase" }, allow_all_markdown = true })
same(alt._config().enabled, true, "legacy filetype keys are accepted")

-- --- top-level setup wiring ----------------------------------------------

require("sase").setup({
	lsp = { enabled = false },
	glossary_highlight = { enabled = false },
	xprompt_highlight = { enabled = false },
	alt_highlight = { enabled = false },
	alt_editing = { enabled = false },
	xprompt_spacer = { enabled = false },
})
same(alt._config().enabled, false, "top-level setup forwards alt_highlight opts")

vim.lsp.semantic_tokens.highlight_token = original_highlight_token
vim.lsp.get_client_by_id = original_get_client_by_id

if failures > 0 then
	error(string.format("%d alt_highlight test(s) failed", failures), 0)
end

print("alt_highlight: all tests passed")
