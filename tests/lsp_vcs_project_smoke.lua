-- Headless smoke test for the `+` VCS project completion served by the xprompt
-- LSP. Confirms Neovim auto-picks up the `+` trigger character from the server
-- capabilities and that the canonical expansion (including replacing an existing
-- leading VCS tag) applies correctly in a real buffer.
--
-- Neovim's native `vim.lsp.completion` applies the selected item's primary
-- `textEdit` (as the inserted word) plus its `additionalTextEdits` on
-- `CompleteDone`. This test exercises the same edits through
-- `vim.lsp.util.apply_text_edits`, so a green run means a confirmed `+`
-- completion rewrites the buffer exactly like the TUI.

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

local function assert_plus_trigger(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  local completion = client and client.server_capabilities and client.server_capabilities.completionProvider
  local triggers = completion and completion.triggerCharacters or {}
  for _, ch in ipairs(triggers) do
    if ch == "+" then
      return
    end
  end
  fail("`+` is not advertised as a completion trigger character: " .. vim.inspect(triggers))
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

--- Drive a `+` completion for a single-line prompt, then apply the accepted
--- item's edits to the live buffer exactly as native completion does on
--- `CompleteDone` (primary `textEdit` plus `additionalTextEdits`), and assert
--- the buffer matches the canonical expansion. Using the real attached buffer
--- keeps the test faithful to the document the server actually saw, including
--- Neovim's normal trailing line ending.
local function assert_expansion(line, item_label, expected, expected_filter_text, expected_detail)
  local character = #line
  local items = completion_items(line, character)
  local item = find_item(items, item_label)
  if not item then
    fail("missing `" .. item_label .. "` completion item for line '" .. line .. "': " .. vim.inspect(items))
  end
  if item.filterText ~= expected_filter_text then
    fail("filterText mismatch for '" .. line .. "': " .. vim.inspect(item.filterText))
  end
  local detail = item.detail or ""
  if not detail:find(expected_detail, 1, true) then
    fail("detail mismatch for '" .. line .. "': " .. vim.inspect(item.detail))
  end

  local edits = {}
  if item.textEdit then
    table.insert(edits, { range = item.textEdit.range, newText = item.textEdit.newText })
  end
  for _, edit in ipairs(item.additionalTextEdits or {}) do
    table.insert(edits, edit)
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.lsp.util.apply_text_edits(edits, bufnr, "utf-16")

  local applied = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
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

-- Hand-written catalog mirroring `vcs_project_catalog_payload()` so the test is
-- independent of any real project state. `workflow_names` includes `git` so the
-- replace-existing-tag case is exercised end to end.
local catalog_path = root .. "/vcs_project_catalog.json"
vim.fn.writefile({
  vim.json.encode({
    schema_version = 3,
    workflow_names = { "gh", "git", "hg" },
    entries = {
      {
        name = "sase",
        vcs_prefix = "gh",
        display_tag = "#gh:sase",
        provider_display = "GitHub",
        description = "SASE repo",
        aliases = {},
        kind = "project",
        project = "sase",
        status = "",
      },
      {
        name = "ship-completion",
        vcs_prefix = "gh",
        display_tag = "#gh:ship-completion",
        provider_display = "GitHub",
        description = "Completion Patch",
        aliases = {},
        kind = "patch",
        project = "sase",
        status = "Ready",
      },
      {
        name = "legacy-completion",
        vcs_prefix = "gh",
        display_tag = "#gh:legacy-completion",
        provider_display = "GitHub",
        description = "Legacy completion Patch",
        aliases = {},
        kind = "changespec",
        project = "sase",
        status = "Ready",
      },
    },
  }),
}, catalog_path)
vim.env.SASE_XPROMPT_VCS_PROJECT_CATALOG = catalog_path

local prompt_path = root .. "/sase_prompt_vcs_project_smoke.md"
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

assert_plus_trigger(client_id)

-- Realistic end-of-line `+` triggers from the plan's parity table (selected
-- project `sase`). The exhaustive golden table is unit-tested in the Python
-- (Phase 1) and Rust (Phase 3) suites; here we confirm the integration applies
-- the same expansion in a live Neovim buffer.
-- Start-of-line trigger on an otherwise-empty first line must not insert a
-- blank line above the expanded VCS tag.
assert_expansion("+s", "sase", "#gh:sase ", "+sase", "#gh:sase")
assert_expansion("+ship", "ship-completion", "#gh:ship-completion ", "+ship-completion", "#gh:ship-completion")
assert_expansion(
  "+legacy",
  "legacy-completion",
  "#gh:legacy-completion ",
  "+legacy-completion",
  "#gh:legacy-completion"
)
assert_expansion("Describe this repo. +", "sase", "#gh:sase Describe this repo.", "+sase", "#gh:sase")
-- Replace-existing: a leading VCS tag is swapped, never stacked.
assert_expansion("#git:foo Fix bug +", "sase", "#gh:sase Fix bug", "+sase", "#gh:sase")
-- Replace-existing with a HITL suffix on the old tag (the suffix is dropped).
assert_expansion("#gh!!:foo do X +", "sase", "#gh:sase do X", "+sase", "#gh:sase")

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_vcs_project_smoke: OK")
