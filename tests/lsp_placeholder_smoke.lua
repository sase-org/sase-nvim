-- Headless smoke coverage for document-local placeholder completion served by
-- the xprompt LSP. The plugin remains a thin LSP client: Neovim learns the `<`
-- trigger from server capabilities and applies the returned text edits.

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
  local output = vim.fn.system({ command, "editor", "helper-bridge", "--help" })
  return vim.v.shell_error == 0 and output:find("snippet%-catalog") ~= nil
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

local function assert_placeholder_trigger(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  local completion = client and client.server_capabilities and client.server_capabilities.completionProvider
  local triggers = completion and completion.triggerCharacters or {}
  for _, ch in ipairs(triggers) do
    if ch == "<" then
      return
    end
  end
  fail("`<` is not advertised as a completion trigger character: " .. vim.inspect(triggers))
end

local function completion_items(lines, line, character)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { line + 1, character })
  vim.cmd("redraw")

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(0) },
    position = { line = line, character = character },
  }
  local responses = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 30000)
  if not responses then
    fail("completion request timed out at " .. line .. ":" .. character)
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

local function labels(items)
  return vim.tbl_map(function(item)
    return item.label
  end, items)
end

local function find_item(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
  return nil
end

local function assert_text_edit(item, start_line, start_character, end_line, end_character, new_text)
  if not item or not item.textEdit or not item.textEdit.range then
    fail("missing textEdit: " .. vim.inspect(item))
  end
  local edit = item.textEdit
  local expected_range = {
    start = { line = start_line, character = start_character },
    ["end"] = { line = end_line, character = end_character },
  }
  if not vim.deep_equal(edit.range, expected_range) then
    fail("textEdit range mismatch: " .. vim.inspect(edit.range))
  end
  if edit.newText ~= new_text then
    fail(("textEdit newText mismatch: expected %s, got %s"):format(vim.inspect(new_text), vim.inspect(edit.newText)))
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")
vim.fn.mkdir(root .. "/sase", "p")
vim.fn.writefile({
  "ace:",
  "  snippets:",
  "    cbi: '`<$1>`$0'",
}, root .. "/sase/sase.yml")

local prompt_path = root .. "/sase_prompt_placeholder_smoke.md"
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
assert_placeholder_trigger(client_id)

local reused = {
  "`<the plan>` and <the prompt> already exist.",
  "Reuse <>.",
}
local reused_items = completion_items(reused, 1, 7)
if not vim.deep_equal(labels(reused_items), { "the plan", "the prompt" }) then
  fail("placeholder candidates are not in document order: " .. vim.inspect(reused_items))
end
for _, item in ipairs(reused_items) do
  if item.kind ~= vim.lsp.protocol.CompletionItemKind.Variable then
    fail("placeholder kind is not Variable: " .. vim.inspect(item))
  end
  if item.filterText ~= "" then
    fail("placeholder filterText mismatch: " .. vim.inspect(item))
  end
  assert_text_edit(item, 1, 7, 1, 8, item.label .. ">")
end

local missing_close_items = completion_items({ reused[1], "Reuse <the" }, 1, 10)
local missing_close_plan = find_item(missing_close_items, "the plan")
assert_text_edit(missing_close_plan, 1, 7, 1, 10, "the plan>")

local filtered_items = completion_items({ reused[1], "Reuse <the pr>." }, 1, 13)
if not vim.deep_equal(labels(filtered_items), { "the prompt" }) then
  fail("placeholder prefix filtering mismatch: " .. vim.inspect(filtered_items))
end
if filtered_items[1].filterText ~= "the pr" then
  fail("filtered placeholder filterText mismatch: " .. vim.inspect(filtered_items[1]))
end
assert_text_edit(filtered_items[1], 1, 7, 1, 14, "the prompt>")

local only_current = "No other placeholder: <on>"
local empty_items = completion_items({ only_current }, 0, #only_current - 1)
if #empty_items ~= 0 then
  fail("the placeholder under the cursor was not excluded: " .. vim.inspect(empty_items))
end

local snippet_items = completion_items({ "cb" }, 0, 2)
local cbi = find_item(snippet_items, "cbi")
if not cbi then
  fail("missing `cbi` snippet item: " .. vim.inspect(snippet_items))
end
if cbi.kind ~= vim.lsp.protocol.CompletionItemKind.Snippet then
  fail("`cbi` kind is not Snippet: " .. vim.inspect(cbi))
end
if not cbi.textEdit or cbi.textEdit.newText ~= "`<$1>`$0" then
  fail("`cbi` snippet text mismatch: " .. vim.inspect(cbi))
end
if not cbi.command or cbi.command.command ~= "editor.action.triggerSuggest" then
  fail("`cbi` does not retrigger placeholder suggestions: " .. vim.inspect(cbi))
end

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_placeholder_smoke: OK")
