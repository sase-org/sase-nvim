package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local lsp = require("sase.lsp")

local function same(actual, expected, label)
  if vim.inspect(actual) ~= vim.inspect(expected) then
    error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function executable(names)
  return function(name)
    return names[name] == true
  end
end

same(lsp._resolve_cmd({ cmd = { "custom-lsp", "--stdio" } }, {}, executable({})), { "custom-lsp", "--stdio" }, "explicit table cmd")
same(lsp._resolve_cmd({ cmd = "custom-lsp --stdio" }, {}, executable({})), { "custom-lsp", "--stdio" }, "explicit string cmd")
same(
  lsp._resolve_cmd({}, { SASE_XPROMPT_LSP_CMD = "cargo run -p sase_xprompt_lsp --" }, executable({})),
  { "cargo", "run", "-p", "sase_xprompt_lsp", "--" },
  "env cmd"
)
same(lsp._resolve_cmd({}, {}, executable({ sase = true })), { "sase", "lsp" }, "sase wrapper cmd")
same(lsp._resolve_cmd({}, {}, executable({ ["sase-xprompt-lsp"] = true })), { "sase-xprompt-lsp" }, "standalone binary cmd")
same(lsp._resolve_cmd({}, {}, executable({})), nil, "missing cmd")

require("sase").setup({
  complete = { keymap = false, completion_backend = "auto" },
  lsp = { enabled = true, cmd = { "fake-lsp" }, filetypes = { "markdown" } },
})

same(require("sase.complete")._config().completion_backend, "auto", "complete backend merged")
same(lsp._config().enabled, true, "lsp enabled")
same(lsp._config().cmd, { "fake-lsp" }, "lsp cmd merged")
same(lsp._config().filetypes, { "markdown" }, "lsp filetypes merged")
