package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local function fail(message)
	error(message, 0)
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

	local core_manifest = vim.fn.fnamemodify(vim.fn.getcwd() .. "/../sase-core/Cargo.toml", ":p")
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

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")
vim.fn.mkdir(root .. "/sase/macros", "p")

local project = vim.fn.fnamemodify(root, ":t")
local source_path = root .. "/sase/macros/local.md"
local prompt_path = root .. "/sase_prompt_definition_smoke.md"
vim.fn.writefile({ "Local macro definition body" }, source_path)
vim.fn.writefile({ "#" .. project .. "/local" }, prompt_path)

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

local started = vim.wait(30000, function()
	local client = vim.lsp.get_client_by_id(client_id)
	return client
		and #get_clients(0) > 0
		and client.server_capabilities
		and client.server_capabilities.definitionProvider == true
end, 100)
if not started then
	fail("macro LSP client did not attach")
end

vim.api.nvim_win_set_cursor(0, { 1, 2 })
vim.lsp.buf.definition()

local landed = vim.wait(30000, function()
	local current = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
	if current ~= vim.fn.fnamemodify(source_path, ":p") then
		return false
	end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	return table.concat(lines, "\n"):find("Local macro definition body", 1, true) ~= nil
end, 100)

if not landed then
	fail(
		string.format(
			"definition did not open populated source buffer; current=%s expected=%s",
			vim.api.nvim_buf_get_name(0),
			source_path
		)
	)
end

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
	client:stop(true)
else
	vim.lsp.stop_client(client_id, true)
end
