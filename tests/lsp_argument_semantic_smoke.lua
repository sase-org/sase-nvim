-- Headless smoke coverage for xprompt argument semantic tokens served by the
-- xprompt LSP.

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

local function semantic_tokens_provider(client)
	local capabilities = client and client.server_capabilities
	return capabilities and (capabilities.semanticTokensProvider or capabilities.semantic_tokens_provider) or nil
end

local function wait_for_client(client_id)
	local started = vim.wait(30000, function()
		local client = vim.lsp.get_client_by_id(client_id)
		return client and #get_clients(0) > 0 and semantic_tokens_provider(client) ~= nil
	end, 100)
	if not started then
		fail("xprompt LSP client did not attach with semantic token support")
	end
end

local function semantic_tokens(text)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(text, "\n", { plain = true }))
	vim.cmd("redraw")

	local params = {
		textDocument = { uri = vim.uri_from_bufnr(0) },
	}
	local responses = vim.lsp.buf_request_sync(0, "textDocument/semanticTokens/full", params, 30000)
	if not responses then
		fail("semantic token request timed out")
	end

	for _, response in pairs(responses) do
		if response.error then
			fail("semantic token request failed: " .. vim.inspect(response.error))
		end
		if response.result and response.result.data then
			return response.result.data
		end
	end

	return {}
end

local function decode_tokens(data, legend)
	local tokens = {}
	local line = 0
	local start = 0
	for idx = 1, #data, 5 do
		local delta_line = data[idx]
		local delta_start = data[idx + 1]
		local length = data[idx + 2]
		local token_type = data[idx + 3]
		local modifiers = data[idx + 4]
		line = line + delta_line
		if delta_line == 0 then
			start = start + delta_start
		else
			start = delta_start
		end
		tokens[#tokens + 1] = {
			line = line,
			start = start,
			length = length,
			type = legend[token_type + 1],
			modifiers = modifiers,
		}
	end
	return tokens
end

local function assert_token_at(tokens, line, start, length, token_type)
	for _, token in ipairs(tokens) do
		if
			token.line == line
			and token.start == start
			and token.length == length
			and token.type == token_type
		then
			return
		end
	end
	fail(
		string.format(
			"missing %s token at %d:%d+%d in %s",
			token_type,
			line,
			start,
			length,
			vim.inspect(tokens)
		)
	)
end

local function assert_token(tokens, start, length, token_type)
	assert_token_at(tokens, 0, start, length, token_type)
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")

local prompt_path = root .. "/sase_prompt_argument_semantic_smoke.md"
vim.fn.writefile({ "" }, prompt_path)

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

local client = vim.lsp.get_client_by_id(client_id)
local provider = semantic_tokens_provider(client)
local legend = provider.legend and provider.legend.tokenTypes or {}

local line = "#git(owner=sase, count=2, draft=true)"
local tokens = decode_tokens(semantic_tokens(line), legend)

assert_token(tokens, 1, 3, "function")
assert_token(tokens, 4, 1, "operator")
assert_token(tokens, 5, 5, "parameter")
assert_token(tokens, 10, 1, "operator")
assert_token(tokens, 11, 4, "string")
assert_token(tokens, 17, 5, "parameter")
assert_token(tokens, 23, 1, "number")
assert_token(tokens, 26, 5, "parameter")
assert_token(tokens, 32, 4, "keyword")

local directive_tokens = decode_tokens(semantic_tokens("%q(capacity=2)"), legend)
assert_token(directive_tokens, 1, 1, "macro")
assert_token(directive_tokens, 3, 8, "parameter")
assert_token(directive_tokens, 12, 1, "number")

local multiline_tokens = decode_tokens(semantic_tokens("🙂 #git(text=[[alpha\r\nbeta 🙂\r\ngamma]])"), legend)
assert_token_at(multiline_tokens, 0, 4, 3, "function")
assert_token_at(multiline_tokens, 0, 13, 7, "string")
assert_token_at(multiline_tokens, 1, 0, 7, "string")
assert_token_at(multiline_tokens, 2, 0, 7, "string")

local fenced = "```markdown\n#git(owner=sase)\n```"
local fenced_tokens = decode_tokens(semantic_tokens(fenced), legend)
for _, token in ipairs(fenced_tokens) do
	if token.type == "parameter" or token.type == "operator" then
		fail("argument token leaked inside fenced block: " .. vim.inspect(fenced_tokens))
	end
end

if client and client.stop then
	client:stop(true)
else
	vim.lsp.stop_client(client_id, true)
end

print("lsp_argument_semantic_smoke: OK")
