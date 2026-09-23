-- Headless tests for lua/sase/project_tag_highlight.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/project_tag_highlight.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local highlight = require("sase.project_tag_highlight")

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

local function hex_to_number(hex)
	return tonumber(hex:sub(2), 16)
end

-- --- default highlight groups -------------------------------------------

highlight.setup({})

for index = 0, highlight._ACCENT_COUNT - 1 do
	local hl = get_hl("SaseProjectTagAccent" .. tostring(index))
	same(hl.bold, true, "SaseProjectTagAccent" .. tostring(index) .. " is bold")
	same(hl.fg, hex_to_number(highlight._FALLBACK_PALETTE[index + 1]), "SaseProjectTagAccent" .. tostring(index) .. " uses fallback palette")
	local sigil_hl = get_hl("SaseProjectTagSigil" .. tostring(index))
	same(sigil_hl.bold, nil, "SaseProjectTagSigil" .. tostring(index) .. " is dim (not bold)")
	same(sigil_hl.fg, hex_to_number(highlight._FALLBACK_PALETTE[index + 1]), "SaseProjectTagSigil" .. tostring(index) .. " uses fallback palette")
end

local unknown_hl = get_hl("SaseProjectTagUnknown")
if unknown_hl.link == nil then
	same(unknown_hl.underline, true, "SaseProjectTagUnknown is underlined")
else
	same(unknown_hl.link, "DiagnosticWarn", "SaseProjectTagUnknown falls back to warning link")
end
same(get_hl("SaseProjectTagDisabled").link, "Comment", "SaseProjectTagDisabled default link")

vim.api.nvim_set_hl(0, "SaseProjectTagAccent0", { bold = true, fg = 0x123456 })
highlight.define_highlights()
same(get_hl("SaseProjectTagAccent0").fg, 0x123456, "user-defined accent group survives default refresh")

-- --- palette application -------------------------------------------------

local palette = {}
for index = 1, highlight._ACCENT_COUNT do
	palette[index] = string.format("#%06x", index * 0x0A0A0A)
end

same(highlight.apply_palette({ "#fff" }), false, "short palette is rejected")
same(highlight.apply_palette("not-a-table"), false, "non-table palette is rejected")
same(highlight.apply_palette(palette), true, "full palette is accepted")
same(highlight._palette(), palette, "applied palette is current")

vim.api.nvim_set_hl(0, "SaseProjectTagAccent5", {})
highlight.define_highlights()
same(get_hl("SaseProjectTagAccent5").fg, hex_to_number(palette[6]), "applied palette colors the accent groups")
same(get_hl("SaseProjectTagAccent0").fg, 0x123456, "non-force apply keeps user customization")
same(get_hl("SaseProjectTagSigil5").fg, hex_to_number(palette[6]), "applied palette colors the sigil groups")

-- A server palette refresh preserves user overrides but tracks the rest.
vim.api.nvim_set_hl(0, "SaseProjectTagAccent0", { bold = true, fg = 0x123456 })
vim.api.nvim_set_hl(0, "SaseProjectTagSigil0", { fg = 0x123456 })
local refreshed = {}
for index = 1, highlight._ACCENT_COUNT do
	refreshed[index] = string.format("#%06x", 0xF00000 + index)
end
highlight.apply_palette(refreshed)
same(get_hl("SaseProjectTagAccent0").fg, 0x123456, "palette refresh keeps the user accent override")
same(get_hl("SaseProjectTagSigil0").fg, 0x123456, "palette refresh keeps the user sigil override")
same(get_hl("SaseProjectTagAccent5").fg, hex_to_number(refreshed[6]), "palette refresh tracks untracked accent groups")
same(get_hl("SaseProjectTagSigil5").fg, hex_to_number(refreshed[6]), "palette refresh tracks untracked sigil groups")

-- The legacy `force` flag no longer clobbers overrides either.
highlight.apply_palette(palette, { force = true })
same(get_hl("SaseProjectTagAccent0").fg, 0x123456, "force apply keeps user customization")

-- --- initialize-result extraction ---------------------------------------

same(highlight.palette_from_initialize_result(nil), nil, "nil result has no palette")
same(highlight.palette_from_initialize_result({}), nil, "result without capabilities has no palette")
same(
	highlight.palette_from_initialize_result({ capabilities = { experimental = { sase = { projectTagPalette = palette } } } }),
	palette,
	"palette is extracted from the raw initialize result"
)
same(
	highlight.palette_from_initialize_result({ capabilities = { experimental = { sase = { projectTagPalette = { "#fff" } } } } }),
	nil,
	"invalid server palette is rejected"
)
same(
	highlight.palette_from_initialize_result({ capabilities = {} }),
	nil,
	"result without experimental has no palette"
)

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

highlight.setup({ enabled = true })

local function token_of(modifiers)
	return { type = "saseProjectTag", modifiers = modifiers }
end

same(highlight._token_group(token_of({ "sigil", "accent3" })), "SaseProjectTagSigil3", "sigil accent token maps to its dim sigil group")
same(highlight._token_group(token_of({ "accent3" })), "SaseProjectTagAccent3", "name accent token maps to its accent group")
same(highlight._token_group(token_of({ "accent17" })), "SaseProjectTagAccent17", "name accent token maps to its accent group")
same(highlight._sigil_group(3), "SaseProjectTagSigil3", "sigil group helper names the dim group")
same(highlight._token_group(token_of({ "sigil", "unknown" })), "SaseProjectTagUnknown", "unknown sigil maps to unknown group")
same(highlight._token_group(token_of({ "unknown" })), "SaseProjectTagUnknown", "unknown name maps to unknown group")
same(highlight._token_group(token_of({ "sigil", "disabled" })), "SaseProjectTagDisabled", "disabled sigil maps to disabled group")
same(highlight._token_group(token_of({ "sigil" })), "SaseProjectTagDisabled", "accent-less sigil stays neutral")
same(highlight._token_group(token_of({})), "SaseProjectTagDisabled", "accent-less name stays neutral")
same(highlight._token_group(token_of({ "sigil", "accent18" })), "SaseProjectTagDisabled", "out-of-range accent stays neutral")
same(highlight._token_group({ type = "parameter", modifiers = {} }), nil, "non-tag types are ignored")
same(highlight._token_group(nil), nil, "missing token is ignored")

highlight._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = token_of({ "sigil", "accent3" }) },
})
same(#highlighted, 1, "sase project tag sigil token is highlighted")
same(highlighted[1].group, "SaseProjectTagSigil3", "dim sigil group is applied")

reset_calls()
highlight._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = token_of({ "accent3" }) },
})
same(#highlighted, 1, "sase project tag name token is highlighted")
same(highlighted[1].group, "SaseProjectTagAccent3", "accent group is applied")

reset_calls()
highlight._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = token_of({ "unknown" }) },
})
same(#highlighted, 1, "unknown tag token is highlighted")
same(highlighted[1].group, "SaseProjectTagUnknown", "unknown group is applied")

reset_calls()
highlight._on_lsp_token_update({
	buf = 12,
	data = { client_id = 8, token = token_of({ "accent3" }) },
})
same(#highlighted, 0, "foreign LSP client is ignored")

reset_calls()
highlight.setup({ enabled = false })
highlight._on_lsp_token_update({
	buf = 12,
	data = { client_id = 7, token = token_of({ "accent3" }) },
})
same(#highlighted, 0, "disabled highlighting is ignored")

-- --- top-level setup wiring ----------------------------------------------

require("sase").setup({
	lsp = { enabled = false },
	glossary_highlight = { enabled = false },
	xprompt_highlight = { enabled = false },
	project_tag_highlight = { enabled = false },
	alt_highlight = { enabled = false },
	alt_editing = { enabled = false },
	xprompt_spacer = { enabled = false },
})
same(highlight._config().enabled, false, "top-level setup forwards project_tag_highlight opts")

vim.lsp.semantic_tokens.highlight_token = original_highlight_token
vim.lsp.get_client_by_id = original_get_client_by_id

if failures > 0 then
	error(string.format("%d project_tag_highlight test(s) failed", failures), 0)
end

print("project_tag_highlight: all tests passed")
