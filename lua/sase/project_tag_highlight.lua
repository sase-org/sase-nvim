-- Accent-colored highlighting for SASE project tags (`+sase`).
--
-- The xprompt LSP emits each project tag as two `saseProjectTag` semantic
-- tokens (the `+` sigil plus the name) with `accentN` modifiers resolved from
-- the Python-owned 18-color palette. The palette itself arrives in the
-- server's initialize result at
-- `experimental.sase.projectTagPalette`, so the highlight groups below carry
-- the same hex values as the TUI chip. The `+` sigil renders in its accent
-- without the name's bold (`SaseProjectTagSigilN`), matching the chip's
-- `dim <accent>` sigil. Unknown tags get the theme warning color with an
-- underline; disabled/provider-less tags and accent-less resolved tags
-- (such as `+home`) stay neutrally dim.

local M = {}

local CLIENT_NAME = "sase-xprompt-lsp"
local GROUP = "SaseProjectTagHighlight"
local TOKEN_TYPE = "saseProjectTag"

local ACCENT_COUNT = 18
local UNKNOWN_GROUP = "SaseProjectTagUnknown"
local DISABLED_GROUP = "SaseProjectTagDisabled"

-- Fallback copy of the Python-owned `PROJECT_ACCENTS` palette
-- (src/sase/project_accents.py). The live server publishes the same values
-- in its initialize result; this copy only covers older servers that lack
-- the `projectTagPalette` capability.
local FALLBACK_PALETTE = {
	"#C5547D",
	"#CA545A",
	"#C75A31",
	"#B46817",
	"#A17204",
	"#8B7B02",
	"#6F8312",
	"#3F8B2C",
	"#1B8B5D",
	"#108A79",
	"#1E878C",
	"#1485A1",
	"#0982BE",
	"#4379D3",
	"#6E70D4",
	"#8E67CA",
	"#A65EB7",
	"#B9589C",
}

local config = {
	enabled = true,
}

local applied_palette = nil

local function accent_group(index)
	return "SaseProjectTagAccent" .. tostring(index)
end

local function sigil_group(index)
	return "SaseProjectTagSigil" .. tostring(index)
end

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

local function client_by_id(client_id)
	if not (client_id and vim.lsp and vim.lsp.get_client_by_id) then
		return nil
	end
	return vim.lsp.get_client_by_id(client_id)
end

local function is_hex_color(value)
	return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

local function valid_palette(palette)
	if type(palette) ~= "table" then
		return false
	end
	for index = 1, ACCENT_COUNT do
		if not is_hex_color(palette[index]) then
			return false
		end
	end
	return true
end

local function current_palette()
	if valid_palette(applied_palette) then
		return applied_palette
	end
	return FALLBACK_PALETTE
end

local function warning_fg()
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "DiagnosticWarn" })
	if ok and type(hl) == "table" and type(hl.fg) == "number" then
		return hl.fg
	end
	return nil
end

local function hl_fg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	if ok and type(hl) == "table" and type(hl.fg) == "number" then
		return hl.fg
	end
	return nil
end

local function hex_number(hex)
	return tonumber(hex:sub(2), 16)
end

-- What this module last set for each palette-owned group, as `{ fg = number,
-- bold = true|nil }`.
local last_set = {}

local function record_set(name, new_hex, bold)
	last_set[name] = { fg = hex_number(new_hex), bold = bold == true and true or nil }
end

-- Sigil groups render the `+` in the tag's accent without the name's bold,
-- matching the TUI chip (`dim <accent>` sigil, `bold <accent>` name).
-- Neovim highlights have no `dim` attribute, so the non-bold fg carries it.
local function safe_get_hl(name)
	if vim.api.nvim_get_hl == nil then
		return {}
	end
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	if ok and type(hl) == "table" then
		return hl
	end
	return {}
end

local function define_accent_groups(palette, default)
	for index = 0, ACCENT_COUNT - 1 do
		local accent_name = accent_group(index)
		local sigil_name = sigil_group(index)
		local before_accent = safe_get_hl(accent_name)
		local before_sigil = safe_get_hl(sigil_name)
		local accent_hl = { fg = palette[index + 1], bold = true }
		local sigil_hl = { fg = palette[index + 1] }
		if default then
			accent_hl.default = true
			sigil_hl.default = true
		end
		vim.api.nvim_set_hl(0, accent_name, accent_hl)
		vim.api.nvim_set_hl(0, sigil_name, sigil_hl)
		-- With `default = true` an existing user/colorscheme group wins
		-- and the set is a no-op: only record groups we actually own.
		-- A group is ours when it was unset before, or when it now
		-- carries exactly the palette color we just applied.
		if type(before_accent) ~= "table" or next(before_accent) == nil then
			record_set(accent_name, palette[index + 1], true)
		else
			local after = safe_get_hl(accent_name)
			if after.fg == hex_number(palette[index + 1]) and after.bold == true then
				record_set(accent_name, palette[index + 1], true)
			end
		end
		if type(before_sigil) ~= "table" or next(before_sigil) == nil then
			record_set(sigil_name, palette[index + 1], nil)
		else
			local after = safe_get_hl(sigil_name)
			if after.fg == hex_number(palette[index + 1]) and after.bold ~= true then
				record_set(sigil_name, palette[index + 1], nil)
			end
		end
	end
end

-- A refresh only touches a group that is unset or still identical to what
-- this module last set; anything else is a user or colorscheme override
-- (even one keeping the palette foreground with different attributes, such
-- as italic without bold) and is left alone.
local function full_hl(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	if ok and type(hl) == "table" then
		return hl
	end
	return {}
end

-- Styling keys this module never sets. Any of them present on the current
-- group means someone else customized it.
local EXTRA_STYLE_KEYS = {
	"bg",
	"link",
	"italic",
	"underline",
	"undercurl",
	"underdouble",
	"underdotted",
	"underdashed",
	"strikethrough",
	"reverse",
	"standout",
	"nocombine",
}

local function has_extra_style(hl)
	for _, key in ipairs(EXTRA_STYLE_KEYS) do
		if hl[key] ~= nil then
			return true
		end
	end
	return false
end

local function hl_matches(hl, fg_number, bold)
	if (hl.fg or nil) ~= (fg_number or nil) then
		return false
	end
	if (hl.bold == true) ~= (bold == true) then
		return false
	end
	return not has_extra_style(hl)
end

-- Define one palette-owned group, preserving user and colorscheme overrides:
-- a group that is unset or still identical to what this module last set
-- tracks the new palette, while anything else is left alone.
local function track_palette_group(name, new_hex, old_fg, bold)
	local current = full_hl(name)
	local should_set = false
	if next(current) == nil then
		should_set = true
	else
		local record = last_set[name]
		if record ~= nil then
			should_set = hl_matches(current, record.fg, record.bold)
		else
			-- No record yet (e.g. groups defined before this module
			-- started tracking): treat the group as ours only when it
			-- carries the previous palette color with no extra styling.
			should_set = hl_matches(current, old_fg, bold)
		end
	end
	if not should_set then
		return
	end
	local was_unset = next(current) == nil
	local hl = { fg = new_hex, bold = bold }
	if was_unset then
		hl.default = true
	end
	vim.api.nvim_set_hl(0, name, hl)
	record_set(name, new_hex, bold)
end

local function track_palette(palette, old)
	for index = 0, ACCENT_COUNT - 1 do
		local old_fg = hex_number(old[index + 1])
		track_palette_group(accent_group(index), palette[index + 1], old_fg, true)
		track_palette_group(sigil_group(index), palette[index + 1], old_fg, nil)
	end
end

function M.define_highlights()
	define_accent_groups(current_palette(), true)
	local fg = warning_fg()
	if fg ~= nil then
		vim.api.nvim_set_hl(0, UNKNOWN_GROUP, { fg = fg, underline = true, default = true })
	else
		vim.api.nvim_set_hl(0, UNKNOWN_GROUP, { link = "DiagnosticWarn", default = true })
	end
	vim.api.nvim_set_hl(0, DISABLED_GROUP, { link = "Comment", default = true })
end

--- Apply a server-published palette and track the accent and sigil groups to
--- it. Palettes that are not 18 hex colors are ignored. Groups the user (or
--- colorscheme) customized keep their colors; every other group refreshes
--- immediately and again on `ColorScheme` via `define_highlights`
--- (`default = true`).
--- @param palette string[]|nil
--- @param opts? { force?: boolean }  deprecated, ignored: overrides always win
function M.apply_palette(palette, opts)
	if not valid_palette(palette) then
		return false
	end
	local old = current_palette()
	applied_palette = palette
	track_palette(palette, old)
	return true
end

local function modifier_set(token)
	local set = {}
	local modifiers = token and token.modifiers
	if type(modifiers) ~= "table" then
		return set
	end
	-- Neovim 0.10+ passes semantic-token modifiers as a set
	-- (`{ sigil = true, accent3 = true }`); older shapes and these tests
	-- use a list (`{ "sigil", "accent3" }`). Accept both.
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
	if not token or token.type ~= TOKEN_TYPE then
		return nil
	end
	local modifiers = modifier_set(token)
	if modifiers["unknown"] then
		return UNKNOWN_GROUP
	end
	if modifiers["disabled"] then
		return DISABLED_GROUP
	end
	for index = 0, ACCENT_COUNT - 1 do
		if modifiers["accent" .. tostring(index)] then
			if modifiers["sigil"] then
				return sigil_group(index)
			end
			return accent_group(index)
		end
	end
	return DISABLED_GROUP
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
	local client = client_by_id(data.client_id)
	if not client or client.name ~= CLIENT_NAME then
		return
	end

	local highlight_token = semantic_highlight_token()
	if not highlight_token then
		return
	end
	highlight_token(data.token, ev.buf, data.client_id, group)
end

--- Extract a valid accent palette from a raw LSP initialize result.
--- Neovim strips `experimental` from `client.server_capabilities`, so the
--- palette must be captured in the client's `on_init` hook (see
--- `sase.lsp`), not read back from the attached client.
--- @param initialize_result table|nil
--- @return string[]|nil
function M.palette_from_initialize_result(initialize_result)
	if type(initialize_result) ~= "table" then
		return nil
	end
	local capabilities = initialize_result.capabilities
	if type(capabilities) ~= "table" then
		return nil
	end
	local experimental = capabilities.experimental
	if type(experimental) ~= "table" then
		return nil
	end
	local sase = experimental.sase
	if type(sase) ~= "table" then
		return nil
	end
	if valid_palette(sase.projectTagPalette) then
		return sase.projectTagPalette
	end
	return nil
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

function M._palette()
	return current_palette()
end

function M._accent_group(index)
	return accent_group(index)
end

function M._sigil_group(index)
	return sigil_group(index)
end

M._UNKNOWN_GROUP = UNKNOWN_GROUP
M._DISABLED_GROUP = DISABLED_GROUP
M._ACCENT_COUNT = ACCENT_COUNT
M._FALLBACK_PALETTE = FALLBACK_PALETTE

return M
