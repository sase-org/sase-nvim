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

local function supports_snippet_catalog(command)
  vim.fn.system({ command, "editor", "helper-bridge", "--help" })
  if vim.v.shell_error ~= 0 then
    return false
  end
  return vim.fn.system({ command, "editor", "helper-bridge", "--help" }):find("snippet%-catalog") ~= nil
end

local function configure_helper_bridge()
  if vim.env.SASE_MOBILE_HELPER_BRIDGE_COMMAND and vim.env.SASE_MOBILE_HELPER_BRIDGE_COMMAND ~= "" then
    return
  end

  local candidates = vim.fn.glob(repo_dir .. "/../sase*/.venv/bin/sase", true, true)
  table.sort(candidates)
  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 and supports_snippet_catalog(candidate) then
      vim.env.SASE_MOBILE_HELPER_BRIDGE_COMMAND = candidate
      return
    end
  end

  if vim.fn.executable("sase") == 1 and supports_snippet_catalog("sase") then
    vim.env.SASE_MOBILE_HELPER_BRIDGE_COMMAND = "sase"
  end
end

local function get_clients(bufnr)
  local filter = { name = "sase-xprompt-lsp", bufnr = bufnr }
  if vim.lsp.get_clients then
    return vim.lsp.get_clients(filter)
  end
  return vim.lsp.get_active_clients(filter)
end

local function wait_for_client(client_id)
  local started = vim.wait(30000, function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client
      and #get_clients(0) > 0
      and client.server_capabilities
      and client.server_capabilities.completionProvider ~= nil
  end, 100)
  if not started then
    fail("xprompt LSP client did not attach with completion support")
  end
end

local function completion_items_for(prefix)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { prefix })
  vim.api.nvim_win_set_cursor(0, { 1, #prefix })
  vim.cmd("redraw")

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(0) },
    position = { line = 0, character = #prefix },
  }
  local responses = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 30000)
  if not responses then
    fail("completion request timed out for prefix " .. prefix)
  end

  for _, response in pairs(responses) do
    if response.error then
      fail("completion request failed: " .. vim.inspect(response.error))
    end
    local result = response.result
    if result then
      local is_list = vim.islist or vim.tbl_islist
      if is_list(result) then
        return result
      end
      if result.items then
        return result.items
      end
    end
  end

  return {}
end

local function find_item(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
  return nil
end

local function assert_snippet_item(item, label, expected_new_text, expected_detail)
  if not item then
    fail("missing snippet completion item " .. label)
  end
  if item.kind ~= vim.lsp.protocol.CompletionItemKind.Snippet then
    fail(label .. " kind is not Snippet: " .. vim.inspect(item))
  end
  if item.insertTextFormat ~= vim.lsp.protocol.InsertTextFormat.Snippet then
    fail(label .. " insertTextFormat is not Snippet: " .. vim.inspect(item))
  end
  if not item.textEdit or item.textEdit.newText ~= expected_new_text then
    fail(label .. " newText mismatch: " .. vim.inspect(item))
  end
  if item.detail ~= expected_detail then
    fail(label .. " detail mismatch: " .. vim.inspect(item.detail))
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")

vim.fn.writefile({
  "ace:",
  "  snippets:",
  "    user_smoke: 'User $1 done$0'",
  "xprompts:",
  "  xp_smoke:",
  "    snippet: true",
  "    description: XPrompt smoke snippet",
  "    content: 'XPrompt body'",
}, root .. "/sase.yml")

local prompt_path = root .. "/sase_prompt_snippet_smoke.md"
vim.fn.writefile({ "" }, prompt_path)

vim.cmd("cd " .. vim.fn.fnameescape(root))
configure_helper_bridge()

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

local user_item = find_item(completion_items_for("user_"), "user_smoke")
assert_snippet_item(user_item, "user_smoke", "User $1 done$0", "user_config")

local xprompt_item = find_item(completion_items_for("xp_"), "xp_smoke")
assert_snippet_item(xprompt_item, "xp_smoke", "XPrompt body$0", "xprompt")

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end
