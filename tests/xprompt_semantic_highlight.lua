-- Headless tests for lua/sase/xprompt_semantic_highlight.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/xprompt_semantic_highlight.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local xprompt = require("sase.xprompt_semantic_highlight")

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

xprompt.setup({})

same(get_hl("SaseXpromptArgKey").link, "Identifier", "SaseXpromptArgKey default link")
same(get_hl("SaseXpromptArgOperator").link, "Comment", "SaseXpromptArgOperator default link")

vim.api.nvim_set_hl(0, "SaseXpromptArgKey", { bold = true })
xprompt.define_highlights()
local overridden_hl = get_hl("SaseXpromptArgKey")
same(overridden_hl.bold, true, "user-defined SaseXpromptArgKey survives default refresh")
same(overridden_hl.link, nil, "default refresh does not overwrite user SaseXpromptArgKey")

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

xprompt.setup({ enabled = true })

local key_token = { type = "parameter", line = 0, start_col = 5, end_col = 10 }
same(xprompt._token_group(key_token), "SaseXpromptArgKey", "parameter maps to key group")
xprompt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = key_token },
})
same(#highlighted, 1, "sase parameter token is highlighted")
same(highlighted[1].group, "SaseXpromptArgKey", "parameter group is applied")

reset_calls()
xprompt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "operator" } },
})
same(#highlighted, 1, "sase operator token is highlighted")
same(highlighted[1].group, "SaseXpromptArgOperator", "operator group is applied")

reset_calls()
xprompt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "string" } },
})
same(#highlighted, 0, "standard string token stays colorscheme-owned")

reset_calls()
xprompt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 8, token = { type = "parameter" } },
})
same(#highlighted, 0, "foreign LSP client is ignored")

reset_calls()
xprompt.setup({ enabled = false })
xprompt._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = { type = "parameter" } },
})
same(#highlighted, 0, "disabled xprompt highlighting is ignored")

-- --- top-level setup wiring ----------------------------------------------

require("sase").setup({
	lsp = { enabled = false },
	glossary_highlight = { enabled = false },
	xprompt_highlight = { enabled = false },
	alt_highlight = { enabled = false },
	alt_editing = { enabled = false },
	xprompt_spacer = { enabled = false },
})
same(xprompt._config().enabled, false, "top-level setup forwards xprompt_highlight opts")

vim.lsp.semantic_tokens.highlight_token = original_highlight_token
vim.lsp.get_client_by_id = original_get_client_by_id

if failures > 0 then
	error(string.format("%d xprompt_semantic_highlight test(s) failed", failures), 0)
end

print("xprompt_semantic_highlight: all tests passed")
