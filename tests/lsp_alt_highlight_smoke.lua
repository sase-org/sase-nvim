-- Headless smoke test for alternation semantic highlighting served by the
-- macro LSP and consumed by `sase.alt_highlight`. Confirms the server emits
-- `operator`/`parameter` tokens with `alternation`/`separator`/`unknown`
-- modifiers for a mid-word `foo%{bar | baz}qux`, a named branch, and an
-- unclosed opener. When the server does not advertise the `alternation`
-- modifier (older builds), the test skips cleanly instead of failing.

local repo_dir = vim.fn.getcwd()
package.path = repo_dir .. "/lua/?.lua;" .. repo_dir .. "/lua/?/init.lua;" .. package.path

local function fail(message)
	error(message, 0)
end

local function skip(message)
	print("lsp_alt_highlight_smoke: SKIP (" .. message .. ")")
	vim.cmd("quitall!")
end

local function macro_lsp_crate(core_manifest)
	local crates_dir = vim.fn.fnamemodify(core_manifest, ":h") .. "/crates"
	if vim.fn.filereadable(crates_dir .. "/sase_macro_lsp/Cargo.toml") == 1 then
		return "sase_macro_lsp"
	end
	-- legacy xprompt spelling; retired alias, always accepted
	return "sase_xprompt_lsp"
end

local function resolve_cmd()
	local macro_cmd = vim.env.SASE_MACRO_LSP_CMD
	if macro_cmd and macro_cmd ~= "" then
		return vim.fn.split(macro_cmd)
	end

	-- legacy xprompt spelling; retired alias, always accepted
	local legacy_cmd = vim.env.SASE_XPROMPT_LSP_CMD
	if legacy_cmd and legacy_cmd ~= "" then
		return vim.fn.split(legacy_cmd)
	end

	local core_manifest = vim.fn.fnamemodify(repo_dir .. "/../sase-core/Cargo.toml", ":p")
	if vim.fn.filereadable(core_manifest) == 1 and vim.fn.executable("cargo") == 1 then
		return { "cargo", "run", "--quiet", "--manifest-path", core_manifest, "-p", macro_lsp_crate(core_manifest), "--" }
	end

	if vim.fn.executable("sase") == 1 and vim.fn.system({ "sase", "lsp", "--version" }) and vim.v.shell_error == 0 then
		return { "sase", "lsp" }
	end

	if vim.fn.executable("sase-macro-lsp") == 1 then
		return { "sase-macro-lsp" }
	end

	-- legacy xprompt spelling; retired alias, always accepted
	if vim.fn.executable("sase-xprompt-lsp") == 1 then
		return { "sase-xprompt-lsp" }
	end

	fail("no macro LSP command available")
end

local function get_clients(bufnr)
	local filter = { name = "sase-macro-lsp", bufnr = bufnr }
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
		fail("macro LSP client did not attach with semantic-tokens support")
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

local prompt_path = root .. "/sase_prompt_alt_highlight_smoke.md"
vim.fn.writefile({
	"foo%{bar | baz}qux",
	"%{sec=x | y}",
	"foo%{bar",
}, prompt_path)

vim.cmd("cd " .. vim.fn.fnameescape(root))

require("sase").setup({
	complete = { keymap = false },
	lsp = { cmd = resolve_cmd(), filetypes = { "markdown" } },
})

vim.cmd("edit " .. vim.fn.fnameescape(prompt_path))
vim.bo.filetype = "markdown"

local client_id = require("sase.lsp").start(0)
if not client_id then
	fail("macro LSP did not start")
end
wait_for_client(client_id)

local function stop_client()
	local client = vim.lsp.get_client_by_id(client_id)
	if client and client.stop then
		client:stop(true)
	else
		vim.lsp.stop_client(client_id, true)
	end
end

-- The legend must carry the standard alternation token types and modifiers.
local client = vim.lsp.get_client_by_id(client_id)
local legend = client.server_capabilities.semanticTokensProvider.legend
local operator_type = index_of(legend.tokenTypes, "operator")
local parameter_type = index_of(legend.tokenTypes, "parameter")
local alternation_bit = index_of(legend.tokenModifiers, "alternation")
local separator_bit = index_of(legend.tokenModifiers, "separator")
local unknown_bit = index_of(legend.tokenModifiers, "unknown")
if
	operator_type == nil
	or parameter_type == nil
	or alternation_bit == nil
	or separator_bit == nil
	or unknown_bit == nil
then
	stop_client()
	skip("server does not advertise alternation semantic tokens")
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
	-- `foo%{bar | baz}qux`: mid-word opener, separator, and closer.
	{ 0, 3, 2, operator_type, bitset(alternation_bit) },
	{ 0, 9, 1, operator_type, bitset(alternation_bit, separator_bit) },
	{ 0, 14, 1, operator_type, bitset(alternation_bit) },
	-- `%{sec=x | y}`: named branch prefix.
	{ 1, 2, 3, parameter_type, bitset(alternation_bit) },
	{ 1, 8, 1, operator_type, bitset(alternation_bit, separator_bit) },
	-- `foo%{bar`: unclosed opener carries `unknown`.
	{ 2, 3, 2, operator_type, bitset(alternation_bit, unknown_bit) },
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

stop_client()

print("lsp_alt_highlight_smoke: OK")
