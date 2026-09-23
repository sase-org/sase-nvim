-- Headless smoke test for project-tag semantic highlighting served by the
-- xprompt LSP and consumed by `sase.project_tag_highlight`. Confirms the
-- server emits `saseProjectTag` tokens with `accentN`/`unknown`/`disabled`
-- modifiers, publishes its accent palette in the initialize result, and that
-- the plugin builds its accent highlight groups from that published palette
-- (via the client's `on_init` hook — Neovim strips `experimental` from
-- `server_capabilities`, so it cannot be read back later).
--
-- The catalog uses a distinctive palette (not the real 18-color one) so the
-- highlight-group assertion proves the groups came from the server and not
-- from the Lua fallback copy.

local repo_dir = vim.fn.getcwd()
package.path = repo_dir .. "/lua/?.lua;" .. repo_dir .. "/lua/?/init.lua;" .. package.path

local function fail(message)
	error(message, 0)
end

local function resolve_cmd()
	if vim.env.SASE_XPROMPT_LSP_CMD and vim.env.SASE_XPROMPT_LSP_CMD ~= "" then
		return vim.fn.split(vim.env.SASE_XPROMPT_LSP_CMD)
	end

	local core_manifest = vim.fn.fnamemodify(repo_dir .. "/../sase-core/Cargo.toml", ":p")
	if vim.fn.filereadable(core_manifest) == 1 and vim.fn.executable("cargo") == 1 then
		return { "cargo", "run", "--quiet", "--manifest-path", core_manifest, "-p", "sase_xprompt_lsp", "--" }
	end

	if vim.fn.executable("sase") == 1 and vim.fn.system({ "sase", "lsp", "--version" }) and vim.v.shell_error == 0 then
		return { "sase", "lsp" }
	end

	if vim.fn.executable("sase-xprompt-lsp") == 1 then
		return { "sase-xprompt-lsp" }
	end

	fail("no xprompt LSP command available")
end

local function get_clients(bufnr)
	local filter = { name = "sase-xprompt-lsp", bufnr = bufnr }
	if vim.lsp.get_clients then
		return vim.lsp.get_clients(filter)
	end
	return vim.lsp.get_active_clients(filter)
end

local function wait_for_client(client_id)
	local started = vim.wait(60000, function()
		local client = vim.lsp.get_client_by_id(client_id)
		return client
			and #get_clients(0) > 0
			and client.server_capabilities
			and client.server_capabilities.semanticTokensProvider ~= nil
	end, 100)
	if not started then
		fail("xprompt LSP client did not attach with semantic-tokens support")
	end
end

local function index_of(list, value)
	for index, entry in ipairs(list or {}) do
		local text = type(entry) == "table" and entry or entry
		if text == value then
			return index - 1
		end
	end
	return nil
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")

-- Distinctive palette: proves the highlight groups track the server payload.
local palette = {}
for index = 1, 18 do
	palette[index] = string.format("#%02x%02x%02x", index * 10, index * 5, 0x80 + index)
end

local catalog_path = root .. "/vcs_project_catalog.json"
vim.fn.writefile({
	vim.json.encode({
		schema_version = 5,
		workflow_names = { "gh", "git" },
		accent_palette = palette,
		entries = {
			{
				name = "sase",
				vcs_prefix = "gh",
				display_tag = "#gh:sase",
				provider_display = "GitHub",
				description = "SASE repo",
				aliases = {},
				kind = "project",
				entry_kind = "project",
				project = "sase",
				status = "",
				key = "gh_sase-org__sase",
				tag = "+sase",
				accent_index = 3,
			},
		},
		project_tags = {
			{ key = "gh_sase-org__sase", name = "sase", aliases = {}, workflow_type = "gh" },
			-- Resolves but has no VCS provider: renders as disabled.
			{ key = "plain-dir", name = "plain" },
		},
	}),
}, catalog_path)
vim.env.SASE_XPROMPT_VCS_PROJECT_CATALOG = catalog_path

local prompt_path = root .. "/sase_prompt_project_tag_highlight_smoke.md"
vim.fn.writefile({ "+sase ships +plain and +nope" }, prompt_path)

vim.cmd("cd " .. vim.fn.fnameescape(root))

require("sase").setup({
	complete = { keymap = false },
	lsp = { cmd = resolve_cmd(), filetypes = { "markdown" } },
})

vim.cmd("edit " .. vim.fn.fnameescape(prompt_path))
vim.bo.filetype = "markdown"

local client_id = require("sase.lsp").start(0)
if not client_id then
	fail("xprompt LSP did not start")
end
wait_for_client(client_id)

-- The plugin must have built its accent groups from the server palette.
local expected_fg = tonumber(palette[4]:sub(2), 16)
local accent3 = vim.api.nvim_get_hl(0, { name = "SaseProjectTagAccent3", link = true })
if accent3.fg ~= expected_fg then
	fail(
		("SaseProjectTagAccent3 fg mismatch: expected %s, got %s"):format(
			vim.inspect(expected_fg),
			vim.inspect(accent3)
		)
	)
end

-- The legend must carry the project-tag token type and modifiers.
local client = vim.lsp.get_client_by_id(client_id)
local legend = client.server_capabilities.semanticTokensProvider.legend
local tag_type = index_of(legend.tokenTypes, "saseProjectTag")
if tag_type == nil then
	fail("semantic-tokens legend has no saseProjectTag type: " .. vim.inspect(legend.tokenTypes))
end
local sigil_bit = index_of(legend.tokenModifiers, "sigil")
local unknown_bit = index_of(legend.tokenModifiers, "unknown")
local disabled_bit = index_of(legend.tokenModifiers, "disabled")
local accent3_bit = index_of(legend.tokenModifiers, "accent3")
if sigil_bit == nil or unknown_bit == nil or disabled_bit == nil or accent3_bit == nil then
	fail("semantic-tokens legend lacks tag modifiers: " .. vim.inspect(legend.tokenModifiers))
end

local function bitset(...)
	local bits = 0
	for _, bit in ipairs({ ... }) do
		bits = bits + 2 ^ bit
	end
	return bits
end

-- Every expected (line, start, length, type, modifiers) token must be
-- present in the full-document semantic tokens.
local expected = {
	{ 0, 0, 1, tag_type, bitset(sigil_bit, accent3_bit) }, -- `+` of +sase
	{ 0, 1, 4, tag_type, bitset(accent3_bit) }, -- `sase`
	{ 0, 12, 1, tag_type, bitset(sigil_bit, disabled_bit) }, -- `+` of +plain
	{ 0, 13, 5, tag_type, bitset(disabled_bit) }, -- `plain`
	{ 0, 23, 1, tag_type, bitset(sigil_bit, unknown_bit) }, -- `+` of +nope
	{ 0, 24, 4, tag_type, bitset(unknown_bit) }, -- `nope`
}

local params = { textDocument = { uri = vim.uri_from_bufnr(0) } }
local responses = vim.lsp.buf_request_sync(0, "textDocument/semanticTokens/full", params, 30000)
if not responses then
	fail("semanticTokens request timed out")
end

local data = nil
for _, response in pairs(responses) do
	if response.error then
		fail("semanticTokens request failed: " .. vim.inspect(response.error))
	end
	if response.result and response.result.data then
		data = response.result.data
	end
end
if data == nil then
	fail("semanticTokens response carried no data")
end

-- The payload is a flat array of 5-integer groups: delta line, delta start,
-- length, token type, and token modifiers bitset.
local absolute = {}
local line = 0
local start = 0
for offset = 1, #data, 5 do
	local delta_line = data[offset]
	local delta_start = data[offset + 1]
	line = line + delta_line
	if delta_line == 0 then
		start = start + delta_start
	else
		start = delta_start
	end
	absolute[#absolute + 1] = { line, start, data[offset + 2], data[offset + 3], data[offset + 4] }
end

local function contains(want)
	for _, got in ipairs(absolute) do
		if vim.inspect(got) == vim.inspect(want) then
			return true
		end
	end
	return false
end

for _, want in ipairs(expected) do
	if not contains(want) then
		fail(("missing semantic token %s in %s"):format(vim.inspect(want), vim.inspect(absolute)))
	end
end

if client and client.stop then
	client:stop(true)
else
	vim.lsp.stop_client(client_id, true)
end

print("lsp_project_tag_highlight_smoke: OK")
