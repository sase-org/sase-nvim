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

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")
local prompt_path = root .. "/sase_prompt_semantic_smoke.md"
vim.fn.writefile({
  "---",
  "title: Demo",
  "---",
  "one",
  "---",
  "```",
  "---",
  "```",
  "  ---  ",
  "three",
}, prompt_path)

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

local started = vim.wait(30000, function()
  local client = vim.lsp.get_client_by_id(client_id)
  return client
    and #get_clients(0) > 0
    and client.server_capabilities
    and client.server_capabilities.semanticTokensProvider ~= nil
end, 100)
if not started then
  fail("xprompt LSP client did not attach with semantic token support")
end

local responses = vim.lsp.buf_request_sync(0, "textDocument/semanticTokens/full", {
  textDocument = { uri = vim.uri_from_bufnr(0) },
}, 30000)
if not responses then
  fail("semantic token request timed out")
end

local expected = { 4, 0, 3, 0, 0, 4, 2, 3, 0, 0 }
for _, response in pairs(responses) do
  if response.error then
    fail("semantic token request failed: " .. vim.inspect(response.error))
  end
  if response.result then
    if vim.inspect(response.result.data) ~= vim.inspect(expected) then
      fail("semantic token data mismatch: " .. vim.inspect(response.result.data))
    end
    local client = vim.lsp.get_client_by_id(client_id)
    if client and client.stop then
      client:stop(true)
    else
      vim.lsp.stop_client(client_id, true)
    end
    return
  end
end

fail("semantic token request returned no result")
