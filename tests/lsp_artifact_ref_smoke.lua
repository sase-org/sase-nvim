-- Headless smoke coverage for fuzzy artifact-reference completion served by the
-- xprompt LSP.
--
-- The server ranks `@kind:query` rows with its own fuzzy matcher, so the rows it
-- returns have to survive the *client's* filter to be usable at all. Neovim's
-- native completion prefix-matches `filterText` against the typed prefix
-- (`vim/lsp/completion.lua`), which would discard every fuzzy row if the item
-- filtered on the inserted reference. That is a client-observable contract the
-- Rust-side LSP tests cannot check, so this test drives the real conversion
-- Neovim performs and asserts the fuzzy row is still there afterwards.

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

local function assert_at_reference_trigger(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  local completion = client and client.server_capabilities and client.server_capabilities.completionProvider
  local triggers = completion and completion.triggerCharacters or {}
  for _, ch in ipairs(triggers) do
    if ch == "@" then
      return
    end
  end
  fail("`@` is not advertised as a completion trigger character: " .. vim.inspect(triggers))
end

--- Request completion for a single-line buffer with the cursor at end of line.
--- Returns the raw `CompletionList` so `isIncomplete` stays observable.
local function completion_list(line)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, #line })
  vim.cmd("redraw")

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(0) },
    position = { line = 0, character = #line },
  }
  local responses = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 30000)
  if not responses then
    fail("completion request timed out for " .. vim.inspect(line))
  end

  for _, response in pairs(responses) do
    if response.error then
      fail("completion request failed: " .. vim.inspect(response.error))
    end
    if response.result then
      return response.result
    end
  end

  return nil
end

local function items_of(result)
  if not result then
    return {}
  end
  local is_list = vim.islist or vim.tbl_islist
  if is_list(result) then
    return result
  end
  return result.items or {}
end

local function find_item(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
  return nil
end

--- Run the exact conversion `vim.lsp.completion` performs on a response, so the
--- assertion covers Neovim's own filtering rather than just the wire payload.
local function client_words(client_id, line, result)
  local line_to_cursor = line:sub(1, #line)
  local word_boundary = vim.fn.match(line_to_cursor, "\\k*$")
  local matches = vim.lsp.completion._convert_results(
    line,
    0,
    #line,
    client_id,
    word_boundary,
    nil,
    result,
    "utf-16"
  )
  return vim.tbl_map(function(match)
    return match.word
  end, matches)
end

local root = vim.fn.tempname()
local shard = root .. "/sase/designs/202607"
local bundle = shard .. "/sase_sites_hub_and_pages"
vim.fn.mkdir(root .. "/.sase", "p")
vim.fn.mkdir(bundle, "p")
vim.fn.writefile({
  "---",
  "title: SASE Sites Hub and Pages",
  "---",
  "",
}, bundle .. "/sase_sites_hub_and_pages.md")

-- The launcher normally materializes this catalog; the raw server reads it from
-- SASE_XPROMPT_ARTIFACT_REF_CATALOG, which keeps the test independent of a
-- configured SASE project.
local catalog_path = root .. "/artifact_ref_catalog.json"
local function document_project(name)
  local project_root = root .. "/" .. name
  return {
    name = name,
    key = "key_" .. name,
    aliases = { name .. "-alias" },
    context = {
      schema_version = 1,
      document_roots = {
        { kind = "designs", root = project_root .. "/designs" },
      },
      chats_root = project_root .. "/chats",
      artifact_index_path = project_root .. "/artifact-index.jsonl",
      repositories = {},
      projects = {},
      agent_roots = {
        { project = name, root = project_root },
      },
    },
  }
end

-- Agent payloads are global names, so `@agent:sase-b3` is a mid-name fragment
-- rather than a prefix. Publish a page under a longer sibling so a prefix-only
-- server would return nothing here.
local agent_name = "bbugyi200.athena.sase-b3.5"
for _, published in ipairs({ agent_name, "bbugyi200.athena.unrelated-lane" }) do
  vim.fn.mkdir(root .. "/sase/agents/" .. published, "p")
  vim.fn.writefile({ "# " .. published, "" }, root .. "/sase/agents/" .. published .. "/README.md")
end
vim.fn.writefile({
  vim.json.encode({
    schema_version = 1,
    default_project = "sase",
    projects = { document_project("sase") },
  }),
}, catalog_path)
vim.env.SASE_XPROMPT_ARTIFACT_REF_CATALOG = catalog_path

local prompt_path = root .. "/sase_prompt_artifact_ref_smoke.md"
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
assert_at_reference_trigger(client_id)

-- A fuzzy payload query reaches a document nested in a bundle directory, which
-- no prefix match could find.
local payload_line = "@designs:site"
local payload_result = completion_list(payload_line)
if not payload_result or payload_result.isIncomplete ~= true then
  fail("artifact-reference response is not an incomplete list: " .. vim.inspect(payload_result))
end

local payload = "202607/sase_sites_hub_and_pages/sase_sites_hub_and_pages.md"
local reference = "@designs:" .. payload
local payload_items = items_of(payload_result)
local bundled = find_item(payload_items, reference)
if not bundled then
  fail("fuzzy query did not surface the bundled document: " .. vim.inspect(payload_items))
end
if bundled.filterText ~= payload_line then
  fail("payload filterText is not the typed reference: " .. vim.inspect(bundled))
end
if not bundled.textEdit or bundled.textEdit.newText ~= reference then
  fail("payload textEdit does not insert the full reference: " .. vim.inspect(bundled))
end
if not bundled.documentation or not bundled.documentation.value:find("**site**", 1, true) then
  fail("payload documentation does not preview the matched run: " .. vim.inspect(bundled.documentation))
end
if not vim.tbl_contains(client_words(client_id, payload_line, payload_result), reference) then
  fail("Neovim's completion filter dropped the server-ranked fuzzy payload row")
end

-- Agent payloads are ranked by the same matcher, which is the half the Rust
-- tests cannot prove: a mid-name fragment has to survive the client filter too,
-- and the row has to carry the agent's short name as its title.
local agent_line = "@agent:sase-b3"
local agent_result = completion_list(agent_line)
local agent_reference = "@agent:" .. agent_name
local agent_items = items_of(agent_result)
local published = find_item(agent_items, agent_reference)
if not published then
  fail("fuzzy query did not surface the published agent page: " .. vim.inspect(agent_items))
end
if published.filterText ~= agent_line then
  fail("agent filterText is not the typed reference: " .. vim.inspect(published))
end
if not published.textEdit or published.textEdit.newText ~= agent_reference then
  fail("agent textEdit does not insert the full reference: " .. vim.inspect(published))
end
if not published.labelDetails or published.labelDetails.detail ~= " · 5" then
  fail("agent row does not carry its short name as a title: " .. vim.inspect(published.labelDetails))
end
if not vim.tbl_contains(client_words(client_id, agent_line, agent_result), agent_reference) then
  fail("Neovim's completion filter dropped the server-ranked fuzzy agent row")
end

-- The kind stage is fuzzy too, and filters on the bare typed word.
local kind_line = "@dsgn"
local kind_result = completion_list(kind_line)
local kind_items = items_of(kind_result)
local kind = find_item(kind_items, "@designs:")
if not kind then
  fail("fuzzy query did not surface the `designs` artifact kind: " .. vim.inspect(kind_items))
end
if kind.filterText ~= kind_line then
  fail("kind filterText is not the typed word: " .. vim.inspect(kind))
end
if not vim.tbl_contains(client_words(client_id, kind_line, kind_result), "@designs:") then
  fail("Neovim's completion filter dropped the server-ranked fuzzy kind row")
end

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_artifact_ref_smoke: OK")
