-- Headless smoke test for VCS repository completion inside registered workflow
-- refs such as `#gh:owner/`. The xprompt LSP gets candidate rows from the
-- editor helper bridge, then Neovim applies the returned text edit in the live
-- buffer.

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

local function assert_slash_trigger(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  local completion = client and client.server_capabilities and client.server_capabilities.completionProvider
  local triggers = completion and completion.triggerCharacters or {}
  for _, ch in ipairs(triggers) do
    if ch == "/" then
      return
    end
  end
  fail("`/` is not advertised as a completion trigger character: " .. vim.inspect(triggers))
end

local function completion_items(line, character)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, character })
  vim.cmd("redraw")

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(0) },
    position = { line = 0, character = character },
  }
  local responses = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 30000)
  if not responses then
    fail("completion request timed out for line " .. line)
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

local function apply_item(line, item)
  if not item.textEdit then
    fail("missing textEdit for " .. item.label)
  end
  local edits = { { range = item.textEdit.range, newText = item.textEdit.newText } }
  for _, edit in ipairs(item.additionalTextEdits or {}) do
    table.insert(edits, edit)
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.lsp.util.apply_text_edits(edits, bufnr, "utf-16")
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function assert_request(path)
  local lines = vim.fn.readfile(path)
  local request = vim.json.decode(table.concat(lines, "\n"))
  if request.schema_version ~= 1 or request.workflow ~= "gh" or request.namespace ~= "bbugyi200" then
    fail("unexpected helper request: " .. vim.inspect(request))
  end
end

local function assert_completion(line, item_label, expected, expected_new_text)
  local items = completion_items(line, #line)
  local item = find_item(items, item_label)
  if not item then
    fail("missing `" .. item_label .. "` completion item for line '" .. line .. "': " .. vim.inspect(items))
  end
  if expected_new_text and item.textEdit.newText ~= expected_new_text then
    fail("newText mismatch for '" .. line .. "': " .. vim.inspect(item.textEdit.newText))
  end
  local applied = apply_item(line, item)
  if applied ~= expected then
    fail(
      ("expansion mismatch for '%s'\n  expected: %s\n  actual:   %s"):format(
        line,
        vim.inspect(expected),
        vim.inspect(applied)
      )
    )
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")

local catalog_path = root .. "/vcs_project_catalog.json"
vim.fn.writefile({
  vim.json.encode({
    schema_version = 2,
    workflow_names = { "gh" },
    entries = {},
  }),
}, catalog_path)
vim.env.SASE_XPROMPT_VCS_PROJECT_CATALOG = catalog_path

local request_path = root .. "/vcs_repo_request.json"
local helper_path = root .. "/helper"
local response = vim.json.encode({
  schema_version = 1,
  status = "ok",
  error_kind = vim.NIL,
  message = "",
  provider_display = "GitHub",
  stale = false,
  entries = {
    {
      name = "tooling",
      ref = "bbugyi200/tooling",
      description = "Tooling repo",
      visibility = "public",
      is_fork = false,
      is_archived = false,
      pushed_at = "2026-07-07T18:30:00Z",
    },
    {
      name = "sase",
      ref = "bbugyi200/sase",
      description = "Structured Agentic Software Engineering",
      visibility = "private",
      is_fork = false,
      is_archived = false,
      pushed_at = "2026-07-07T18:00:00Z",
    },
  },
})
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" != "editor" ] || [ "$2" != "helper-bridge" ] || [ "$3" != "vcs-repo-catalog" ]; then',
  "  exit 7",
  "fi",
  "cat > " .. vim.fn.shellescape(request_path),
  "cat <<'JSON'",
  response,
  "JSON",
}, helper_path)
vim.fn.setfperm(helper_path, "rwx------")
vim.env.SASE_MOBILE_HELPER_BRIDGE_COMMAND = helper_path

local prompt_path = root .. "/sase_prompt_vcs_repo_smoke.md"
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
assert_slash_trigger(client_id)

assert_completion("#gh:bbugyi200/sa", "sase", "#gh:bbugyi200/sase ", "bbugyi200/sase ")
assert_request(request_path)

assert_completion("#gh(bbugyi200/sa", "sase", "#gh(bbugyi200/sase)", "bbugyi200/sase)")

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_vcs_repo_smoke: OK")
