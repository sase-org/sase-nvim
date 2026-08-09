-- Headless tests for lua/sase/glossary_highlight.lua.
-- Run: nvim --headless -u NONE -c "set rtp+=." -l tests/glossary_highlight.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local glossary = require("sase.glossary_highlight")

local failures = 0

local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL: " .. message .. "\n")
end

local function same(actual, expected, label)
  if vim.inspect(actual) ~= vim.inspect(expected) then
    fail(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function get_hl(name)
  if vim.api.nvim_get_hl then
    return vim.api.nvim_get_hl(0, { name = name, link = false })
  end
  return vim.api.nvim_get_hl_by_name(name, true)
end

-- --- default highlight group ---------------------------------------------

glossary.setup({})

local default_hl = get_hl("SaseGlossaryTerm")
same(default_hl.underline, true, "SaseGlossaryTerm is underlined")
same(default_hl.bold, nil, "SaseGlossaryTerm does not force bold")
same(default_hl.italic, nil, "SaseGlossaryTerm does not force italic")
same(default_hl.foreground or default_hl.fg, nil, "SaseGlossaryTerm does not force a color")

vim.api.nvim_set_hl(0, "SaseGlossaryTerm", { bold = true })
glossary.define_highlights()
local overridden_hl = get_hl("SaseGlossaryTerm")
same(overridden_hl.bold, true, "user-defined SaseGlossaryTerm survives default refresh")
same(overridden_hl.underline, nil, "default refresh does not overwrite user SaseGlossaryTerm")

-- --- LspTokenUpdate callback filtering -----------------------------------

vim.lsp.semantic_tokens = vim.lsp.semantic_tokens or {}

local original_highlight_token = vim.lsp.semantic_tokens.highlight_token
local original_get_client_by_id = vim.lsp.get_client_by_id
local highlighted = {}
local clients = {
  [7] = { name = "sase-xprompt-lsp" },
  [8] = { name = "foreign-lsp" },
}

vim.lsp.semantic_tokens.highlight_token = function(token, bufnr, client_id, group)
  highlighted[#highlighted + 1] = {
    token = token,
    bufnr = bufnr,
    client_id = client_id,
    group = group,
  }
end

vim.lsp.get_client_by_id = function(client_id)
  return clients[client_id]
end

local function reset_calls()
  highlighted = {}
end

glossary.setup({ enabled = true })

local glossary_token = { type = "type", line = 0, start_col = 4, end_col = 15 }
glossary._on_lsp_token_update({
  buf = 12,
  data = { client_id = 7, token = glossary_token },
})
same(#highlighted, 1, "glossary type token from sase LSP is highlighted")
same(highlighted[1].token, glossary_token, "highlighted token is forwarded")
same(highlighted[1].bufnr, 12, "buffer is forwarded")
same(highlighted[1].client_id, 7, "client id is forwarded")
same(highlighted[1].group, "SaseGlossaryTerm", "SaseGlossaryTerm group is applied")

reset_calls()
glossary._on_lsp_token_update({
  buf = 12,
  data = { client_id = 8, token = { type = "type" } },
})
same(#highlighted, 0, "foreign LSP client is ignored")

reset_calls()
glossary._on_lsp_token_update({
  buf = 12,
  data = { client_id = 7, token = { type = "namespace" } },
})
same(#highlighted, 0, "foreign token type is ignored")

reset_calls()
glossary.setup({ enabled = false })
glossary._on_lsp_token_update({
  buf = 12,
  data = { client_id = 7, token = { type = "type" } },
})
same(#highlighted, 0, "disabled glossary highlighting is ignored")

-- --- top-level setup wiring ----------------------------------------------

require("sase").setup({
  lsp = { enabled = false },
  glossary_highlight = { enabled = false },
  alt_highlight = { enabled = false },
  alt_editing = { enabled = false },
  xprompt_spacer = { enabled = false },
})
same(glossary._config().enabled, false, "top-level setup forwards glossary_highlight opts")

vim.lsp.semantic_tokens.highlight_token = original_highlight_token
vim.lsp.get_client_by_id = original_get_client_by_id

if failures > 0 then
  error(string.format("%d glossary_highlight test(s) failed", failures), 0)
end

print("glossary_highlight: all tests passed")
