-- Alternation highlighting for the `%{A | B}` alt brace shorthand.
--
-- Highlighting comes from the SASE macro LSP, not from a Lua copy of the
-- alternation grammar. The server scans each prompt for alternations outside
-- literal zones and emits standard semantic tokens carrying the `alternation`
-- modifier; this module overlays the long-lived `SaseAlt*` groups on those
-- tokens via `LspTokenUpdate`, in the style of
-- `sase.macro_semantic_highlight`:
--
--   * `operator` without `separator` -> SaseAltDelimiter
--   * `separator`                    -> SaseAltSeparator
--   * `parameter`                    -> SaseAltBranchName
--   * `unknown`                      -> SaseAltError
--
-- The server owns the opener rule, so there is exactly one grammar: `%{`
-- opens anywhere outside literal zones (including mid-word, as in
-- `foo%{bar | baz}qux`), while the legacy `%(`/`%alt(` forms still need a
-- directive-valid position. The overlay applies only when Neovim exposes
-- `LspTokenUpdate`; older clients keep editing support but no alt colors.

local M = {}

local CLIENT_NAME = "sase-macro-lsp"
local GROUP = "SaseAltHighlight"

-- Stable highlight groups with default links so user overrides win.
local DEFAULT_LINKS = {
	SaseAltDelimiter = "Delimiter",
	SaseAltSeparator = "Operator",
	SaseAltBranchName = "Identifier",
	SaseAltError = "Error",
}

local config = {
	enabled = true,
	-- Accepted for backward compatibility and ignored: the server owns buffer
	-- eligibility and there is no Lua-side scan to bound anymore.
	filetypes = nil,
	allow_all_markdown = false,
	debounce_ms = 75,
	max_lines = 5000,
	max_bytes = 200000,
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

local function modifier_set(token)
	local set = {}
	local modifiers = token and token.modifiers
	if type(modifiers) ~= "table" then
		return set
	end
	-- Neovim 0.10+ passes semantic-token modifiers as a set
	-- (`{ alternation = true, separator = true }`); older shapes and these
	-- tests use a list (`{ "alternation", "separator" }`). Accept both.
	for key, value in pairs(modifiers) do
		if type(value) == "string" then
			set[value] = true
		elseif value == true and type(key) == "string" then
			set[key] = true
		end
	end
	return set
end

local function token_group(token)
	if not token then
		return nil
	end
	local modifiers = modifier_set(token)
	if not modifiers["alternation"] then
		return nil
	end
	if modifiers["unknown"] then
		return "SaseAltError"
	end
	if token.type == "parameter" then
		return "SaseAltBranchName"
	end
	if token.type == "operator" then
		if modifiers["separator"] then
			return "SaseAltSeparator"
		end
		return "SaseAltDelimiter"
	end
	return nil
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
		filetypes = nil,
		allow_all_markdown = false,
		debounce_ms = 75,
		max_lines = 5000,
		max_bytes = 200000,
	}, opts)

	M.define_highlights()

	local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
	if not config.enabled then
		return
	end

	-- Re-establish default links after a colorscheme swap clears them.
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
