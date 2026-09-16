-- Small semantic-token affordances for SASE xprompt argument structure.
--
-- The xprompt LSP deliberately emits standard semantic token types, so most
-- colorscheme styling remains owned by Neovim and the user's theme. Plain
-- Neovim makes parameter and operator tokens visually collapse, though, so this
-- module overlays two SASE-specific default groups on those token types only.

local M = {}

local CLIENT_NAME = "sase-xprompt-lsp"
local GROUP = "SaseXpromptSemanticHighlight"

local DEFAULT_LINKS = {
	SaseXpromptArgKey = "Identifier",
	SaseXpromptArgOperator = "Comment",
}

local TOKEN_GROUPS = {
	parameter = "SaseXpromptArgKey",
	operator = "SaseXpromptArgOperator",
}

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

local function token_group(token)
	if not token then
		return nil
	end
	return TOKEN_GROUPS[token.type]
end

function M.define_highlights()
	for group, link in pairs(DEFAULT_LINKS) do
		vim.api.nvim_set_hl(0, group, { link = link, default = true })
	end
end

function M._supports_lsp_token_update()
	return semantic_highlight_token() ~= nil and has_lsp_token_update()
end

function M._on_lsp_token_update(ev)
	if not config.enabled then
		return
	end

	local data = ev and ev.data or {}
	local group = token_group(data.token)
	if not group then
		return
	end
	if client_name(data.client_id) ~= CLIENT_NAME then
		return
	end

	local highlight_token = semantic_highlight_token()
	if not highlight_token then
		return
	end
	highlight_token(data.token, ev.buf, data.client_id, group)
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

function M._token_group(token)
	return token_group(token)
end

return M
