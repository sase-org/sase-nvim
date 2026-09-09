-- Headless smoke coverage for star model shortcut completion served by the
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

local function assert_star_trigger(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  local completion = client and client.server_capabilities and client.server_capabilities.completionProvider
  local triggers = completion and completion.triggerCharacters or {}
  for _, ch in ipairs(triggers) do
    if ch == "*" then
      return
    end
  end
  fail("`*` is not advertised as a completion trigger character: " .. vim.inspect(triggers))
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

local function find_item(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
  return nil
end

local function labels(items)
  return vim.tbl_map(function(item)
    return item.label
  end, items)
end

local function assert_has_item(items, label)
  local item = find_item(items, label)
  if not item then
    fail("missing completion item " .. label .. ": " .. vim.inspect(labels(items)))
  end
  return item
end

local function assert_text_edit(item, filter_text, new_text)
  if not item.textEdit or not item.textEdit.range then
    fail("missing textEdit: " .. vim.inspect(item))
  end
  if item.filterText ~= filter_text then
    fail("filterText mismatch: " .. vim.inspect(item))
  end
  if item.textEdit.newText ~= new_text then
    fail(("textEdit newText mismatch: expected %s, got %s"):format(vim.inspect(new_text), vim.inspect(item.textEdit.newText)))
  end
end

local function apply_item_for_line(line, label)
  local item = assert_has_item(completion_items(line), label)
  if not item.textEdit then
    fail("missing textEdit for " .. label .. ": " .. vim.inspect(item))
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

local catalog_path = root .. "/model_catalog.json"
vim.fn.writefile({
  '{"schema_version":1,"entries":['
    .. '{"value":"@large","display":"@large","description":"Large alias","kind":"user_alias","aliases":["large"],"alias_kind":"user","target_provider":"claude","target_model":"opus","target_effort":"high","provenance":"configured"},'
    .. '{"value":"@launch","display":"@launch","description":"Launch alias","kind":"implicit_alias","aliases":["launch"],"alias_kind":"role","target_provider":"codex","target_model":"gpt-5","provenance":"implicit"},'
    .. '{"value":"large-model","display":"large-model","description":"Concrete model","kind":"model","provider":"codex","aliases":["large"]},'
    .. '{"value":"claude-fable-5","display":"claude-fable-5","description":"Claude (fable)","kind":"model","provider":"claude","aliases":["fable"]},'
    .. '{"value":"claude/","display":"claude/","description":"Claude","kind":"provider","provider":"claude"},'
    .. '{"value":"codex/","display":"codex/","description":"Codex","kind":"provider","provider":"codex"}'
    .. "]}",
}, catalog_path)
vim.env.SASE_XPROMPT_MODEL_CATALOG = catalog_path

local prompt_path = root .. "/sase_prompt_model_shortcut_smoke.md"
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
assert_star_trigger(client_id)

local alias_items = completion_items("*la")
local alias = assert_has_item(alias_items, "@large")
assert_text_edit(alias, "*la", "%m:@large ")
if find_item(alias_items, "large-model") then
  fail("*alias completion included concrete model rows: " .. vim.inspect(alias_items))
end

local model_items = completion_items("**fa")
local model = assert_has_item(model_items, "claude-fable-5")
assert_text_edit(model, "**fa", "%m:claude-fable-5 ")
if find_item(model_items, "@large") then
  fail("**model completion included alias rows: " .. vim.inspect(model_items))
end
local model_detail = model.labelDetails and model.labelDetails.detail or ""
if not model_detail:find("%m:claude-fable-5", 1, true) then
  fail("model labelDetails did not advertise expansion: " .. vim.inspect(model.labelDetails))
end

local scoped_items = completion_items("**codex/la")
local scoped = assert_has_item(scoped_items, "codex/large-model")
assert_text_edit(scoped, "**codex/la", "%m:codex/large-model ")

local applied_alias = apply_item_for_line("Use *la", "@large")
if applied_alias ~= "Use %m:@large " then
  fail("*alias text edit did not apply to live buffer: " .. vim.inspect(applied_alias))
end

local applied_model = apply_item_for_line("Use **la", "large-model")
if applied_model ~= "Use %m:large-model " then
  fail("**model text edit did not apply to live buffer: " .. vim.inspect(applied_model))
end

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_model_shortcut_smoke: OK")
