-- Headless smoke coverage for queue-directive completion served by the
-- xprompt LSP through the plugin's real Neovim client.

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

local function completion_items(line)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, #line })
  vim.cmd("redraw")

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(0) },
    position = { line = 0, character = #line },
  }
  local responses = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 30000)
  if not responses then
    fail("completion request timed out for line " .. vim.inspect(line))
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

local function find_label(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
  return nil
end

local function find_new_text(items, new_text)
  for _, item in ipairs(items) do
    if item.textEdit and item.textEdit.newText == new_text then
      return item
    end
  end
  return nil
end

local function insertions(items)
  local seen = {}
  for _, item in ipairs(items) do
    if item.textEdit then
      seen[item.textEdit.newText] = true
    end
  end
  return seen
end

local function assert_has_insertions(line, expected)
  local items = completion_items(line)
  local seen = insertions(items)
  for _, value in ipairs(expected) do
    if not seen[value] then
      fail("missing " .. vim.inspect(value) .. " completion for " .. vim.inspect(line) .. ": " .. vim.inspect(items))
    end
  end
  return items
end

local function apply_item(item)
  if not item or not item.textEdit then
    fail("missing textEdit: " .. vim.inspect(item))
  end
  local edits = { { range = item.textEdit.range, newText = item.textEdit.newText } }
  for _, edit in ipairs(item.additionalTextEdits or {}) do
    table.insert(edits, edit)
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.lsp.util.apply_text_edits(edits, bufnr, "utf-16")
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")

local prompt_path = root .. "/sase_prompt_queue_directive_smoke.md"
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

local directive_items = completion_items("%")
for _, label in ipairs({ "%queue", "%q:...", "%queue(runners=..., priority=...)" }) do
  if not find_label(directive_items, label) then
    fail("missing queue directive completion label " .. label .. ": " .. vim.inspect(directive_items))
  end
end

assert_has_insertions("%queue(", { "p=", "priority=", "runners=", "0", "1" })

local q_colon_items = assert_has_insertions("%q:", { "0", "1" })
local applied = apply_item(find_new_text(q_colon_items, "1"))
if applied ~= "%q:1" then
  fail("queue alias text edit did not apply to live buffer: " .. vim.inspect(applied))
end

local wait_items = completion_items("%wait(")
local wait_insertions = insertions(wait_items)
for _, forbidden in ipairs({ "p=", "priority=", "runners=" }) do
  if wait_insertions[forbidden] then
    fail("%wait( advertised queue field " .. forbidden .. ": " .. vim.inspect(wait_items))
  end
end

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_queue_directive_smoke: OK")
