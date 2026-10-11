-- Small semantic-token affordances for SASE macro argument structure.
--
-- The macro LSP deliberately emits standard semantic token types, so most
-- colorscheme styling remains owned by Neovim and the user's theme. Plain
-- Neovim makes parameter and operator tokens visually collapse, though, so this
-- module overlays two SASE-specific default groups on those token types only.

local M = {}

local CLIENT_NAME = "sase-macro-lsp"
local GROUP = "SaseMacroSemanticHighlight"

local DEFAULT_LINKS = {
	SaseMacroArgKey = "Identifier",
	SaseMacroArgOperator = "Comment",
}

-- legacy xprompt spelling; retired alias, always accepted
local LEGACY_GROUPS = {
	SaseMacroArgKey = "SaseXpromptArgKey",
	SaseMacroArgOperator = "SaseXpromptArgOperator",
}

local TOKEN_GROUPS = {
	parameter = "SaseMacroArgKey",
	operator = "SaseMacroArgOperator",
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

local function get_hl(name)
	if vim.api.nvim_get_hl then
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = true })
		if ok and type(hl) == "table" then
			return hl
		end
		return {}
	end
	local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)
	if ok and type(hl) == "table" then
		return hl
	end
	return {}
end

--- A highlight definition counts as a user override when it is non-empty and
--- is not one of the links this module owns (the canonical default link or
--- the legacy-to-canonical link). The `default` attribute flag is ignored.
local function is_user_override(name, owned_links)
	local hl = get_hl(name)
	if next(hl) == nil then
		return false
	end
	if hl.link ~= nil then
		local extra = false
		for key, _ in pairs(hl) do
			if key ~= "link" and key ~= "default" then
				extra = true
				break
			end
		end
		if not extra then
			for _, owned in ipairs(owned_links) do
				if hl.link == owned then
					return false
				end
			end
		end
	end
	return true
end

function M.define_highlights()
	for group, link in pairs(DEFAULT_LINKS) do
		-- legacy xprompt spelling; retired alias, always accepted
		local legacy = LEGACY_GROUPS[group]
		local legacy_hl = get_hl(legacy)
		vim.api.nvim_set_hl(0, group, { link = link, default = true })
		-- A user override of the legacy name takes effect on the canonical
		-- group, unless the canonical group carries its own override (which
		-- wins). The legacy link below keeps direct legacy references working.
		if
			next(legacy_hl) ~= nil
			and legacy_hl.link ~= group
			and not is_user_override(group, { link })
		then
			vim.api.nvim_set_hl(0, group, legacy_hl)
		end
		vim.api.nvim_set_hl(0, legacy, { link = group, default = true })
	end
end

--- The group a token highlight should use: the canonical group, except when
--- only the legacy name carries a user override (e.g. set after setup), in
--- which case the legacy group is applied so the override takes effect.
local function effective_group(group)
	-- legacy xprompt spelling; retired alias, always accepted
	local legacy = LEGACY_GROUPS[group]
	if legacy == nil then
		return group
	end
	if is_user_override(legacy, { group }) and not is_user_override(group, { DEFAULT_LINKS[group] }) then
		return legacy
	end
	return group
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
	highlight_token(data.token, ev.buf, data.client_id, effective_group(group))
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

M._effective_group = effective_group
M._is_user_override = is_user_override

return M
