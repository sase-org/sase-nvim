-- Add a definable-term underline to glossary semantic tokens from the SASE
-- macro LSP while leaving the colorscheme-owned token color alone.

local M = {}

local CLIENT_NAME = "sase-macro-lsp"
local GROUP = "SaseGlossaryHighlight"
local HIGHLIGHT_GROUP = "SaseGlossaryTerm"
local GLOSSARY_TOKEN_TYPE = "type"

local config = {
	enabled = true,
}

local function semantic_highlight_token()
	local semantic_tokens = vim.lsp and vim.lsp.semantic_tokens
	local highlight_token = semantic_tokens and semantic_tokens.highlight_token
	if type(highlight_token) == "function" then
		return highlight_token
	end
	return nil
end

local function has_lsp_token_update()
	return vim.fn.exists("##LspTokenUpdate") == 1
end

local function client_name(client_id)
	if not (client_id and vim.lsp and vim.lsp.get_client_by_id) then
		return nil
	end
	local client = vim.lsp.get_client_by_id(client_id)
	return client and client.name or nil
end

local function token_has_no_modifiers(token)
	local modifiers = token and token.modifiers
	if modifiers == nil then
		return true
	end
	return type(modifiers) == "table" and next(modifiers) == nil
end

local function is_glossary_token(token)
	-- The SASE macro LSP keeps glossary phrases as unmodified standard
	-- `type` tokens. Argument highlighting added later uses other standard
	-- token types, so modifier-bearing or non-type tokens must not pick up the
	-- glossary underline.
	return token and token.type == GLOSSARY_TOKEN_TYPE and token_has_no_modifiers(token)
end

function M.define_highlights()
	vim.api.nvim_set_hl(0, HIGHLIGHT_GROUP, { underline = true, default = true })
end

function M._supports_lsp_token_update()
	return semantic_highlight_token() ~= nil and has_lsp_token_update()
end

function M._on_lsp_token_update(ev)
	if not config.enabled then
		return
	end

	local data = ev and ev.data or {}
	local token = data.token
	if not is_glossary_token(token) then
		return
	end
	if client_name(data.client_id) ~= CLIENT_NAME then
		return
	end

	local highlight_token = semantic_highlight_token()
	if not highlight_token then
		return
	end
	highlight_token(token, ev.buf, data.client_id, HIGHLIGHT_GROUP)
end

function M.setup(opts)
	opts = opts or {}
	config = vim.tbl_deep_extend("force", {
		enabled = true,
	}, opts)

	M.define_highlights()

	local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
	if not config.enabled then
		return
	end

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			M.define_highlights()
		end,
	})

	if not M._supports_lsp_token_update() then
		return
	end

	vim.api.nvim_create_autocmd("LspTokenUpdate", {
		group = group,
		callback = M._on_lsp_token_update,
	})
end

function M._config()
	return config
end

function M._is_glossary_token(token)
	return is_glossary_token(token)
end

return M
