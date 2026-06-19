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

local function available(value)
  return function()
    return value
  end
end

same(
  lsp._resolve_cmd({ cmd = { "custom-lsp", "--stdio" } }, {}, executable({}), available(false)),
  { "custom-lsp", "--stdio" },
  "explicit table cmd"
)
same(
  lsp._resolve_cmd({ cmd = "custom-lsp --stdio" }, {}, executable({}), available(false)),
  { "custom-lsp", "--stdio" },
  "explicit string cmd"
)
same(
  lsp._resolve_cmd({}, { SASE_XPROMPT_LSP_CMD = "cargo run -p sase_xprompt_lsp --" }, executable({}), available(false)),
  { "cargo", "run", "-p", "sase_xprompt_lsp", "--" },
  "env cmd"
)
same(lsp._resolve_cmd({}, {}, executable({ sase = true }), available(true)), { "sase", "lsp" }, "sase wrapper cmd")
same(
  lsp._resolve_cmd({}, {}, executable({ sase = true, ["sase-xprompt-lsp"] = true }), available(false)),
  { "sase-xprompt-lsp" },
  "old sase falls through to standalone binary"
)
same(
  lsp._resolve_cmd({}, {}, executable({ sase = true }), available(false)),
  nil,
  "old sase without standalone binary is missing cmd"
)
same(
  lsp._resolve_cmd({}, {}, executable({ ["sase-xprompt-lsp"] = true }), available(false)),
  { "sase-xprompt-lsp" },
  "standalone binary cmd"
)
same(lsp._resolve_cmd({}, {}, executable({}), available(false)), nil, "missing cmd")

same(lsp._native_completion_enabled(false, false), false, "native completion disabled")
same(lsp._native_completion_enabled(true, true), true, "native completion forced")
same(lsp._native_completion_enabled("auto", false), true, "native completion auto without cmp")
same(lsp._native_completion_enabled("auto", true), false, "native completion auto skips cmp")
same(
  lsp._has_cmp_completion(function()
    return nil
  end, {}),
  false,
  "cmp absent"
)
same(
  lsp._has_cmp_completion(function()
    return {}
  end, {}),
  true,
  "cmp_nvim_lsp module detectable"
)
same(
  lsp._has_cmp_completion(function()
    return nil
  end, { cmp = true }),
  true,
  "loaded cmp detectable"
)
same(
  lsp._has_cmp_completion(function()
    return nil
  end, { cmp_nvim_lsp = true }),
  true,
  "loaded cmp_nvim_lsp detectable"
)

local cmp_capabilities = lsp._make_capabilities(function(name)
  if name ~= "cmp_nvim_lsp" then
    error("unexpected module lookup: " .. name)
  end
  return {
    default_capabilities = function(capabilities)
      capabilities.textDocument.completion.completionItem.resolveSupport = { properties = { "detail" } }
      return capabilities
    end,
  }
end)
same(
  cmp_capabilities.textDocument.completion.completionItem.resolveSupport,
  { properties = { "detail" } },
  "cmp capability shape is used when available"
)
same(
  cmp_capabilities.textDocument.completion.completionItem.snippetSupport,
  true,
  "cmp capabilities preserve snippet support"
)

require("sase").setup({
  complete = { keymap = false },
  lsp = { cmd = { "fake-lsp" }, filetypes = { "markdown" } },
})

same(require("sase.complete")._config().completion_backend, "auto", "complete backend defaults to auto")
same(lsp._config().enabled, true, "lsp enabled")
same(lsp._config().cmd, { "fake-lsp" }, "lsp cmd merged")
same(lsp._config().filetypes, { "markdown" }, "lsp filetypes merged")
same(lsp._config().allow_all_markdown, false, "all-markdown attachment is off by default")
same(lsp._config().native_completion, "auto", "native completion defaults to auto")

same(lsp._is_supported_markdown_path("/tmp/project/xprompts/foo.md"), true, "xprompts markdown is supported")
same(lsp._is_supported_markdown_path("/tmp/project/.xprompts/foo.md"), true, ".xprompts markdown is supported")
same(
  lsp._is_supported_markdown_path("/tmp/project/src/sase/default_xprompts/research_swarm.md"),
  true,
  "default_xprompts markdown is supported"
)
same(lsp._is_supported_markdown_path("/tmp/sase_ace_prompt_abc.md"), true, "ace prompt temp markdown is supported")
same(lsp._is_supported_markdown_path("/tmp/sase_prompt_abc.md"), true, "cli prompt temp markdown is supported")
same(
  lsp._is_supported_markdown_path("/tmp/project/sdd/research/202605/memory_system_prior_art.md"),
  false,
  "ordinary research markdown is unsupported"
)
same(
  lsp._supports_filetype_path(
    "markdown",
    "/tmp/project/sdd/research/202605/memory_system_prior_art.md",
    { filetypes = { "markdown" } }
  ),
  false,
  "ordinary markdown is not supported by default"
)
same(
  lsp._supports_filetype_path(
    "markdown",
    "/tmp/project/sdd/research/202605/memory_system_prior_art.md",
    { filetypes = { "markdown" }, allow_all_markdown = true }
  ),
  true,
  "all-markdown opt-in preserves legacy support"
)
same(
  lsp._supports_filetype_path("sase_prompt", "", { filetypes = { "markdown", "sase_prompt" } }),
  true,
  "sase_prompt filetype support does not require a markdown path"
)

vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/xprompts/current.md")
vim.bo.filetype = "markdown"
local original_start = vim.lsp.start
local captured_config = nil
local captured_opts = nil
vim.lsp.start = function(start_config, start_opts)
  captured_config = start_config
  captured_opts = start_opts
  return 123
end

require("sase").setup({
  complete = { keymap = false },
  lsp = { cmd = { "fake-lsp" }, filetypes = { "markdown" }, native_completion = true },
})

vim.lsp.start = original_start

if type(vim.lsp.buf.definition) ~= "function" then
  error("standard vim.lsp.buf.definition is unavailable")
end
same(captured_config.name, "sase-xprompt-lsp", "lsp client name")
same(captured_config.cmd, { "fake-lsp" }, "lsp start cmd")
same(
  captured_config.capabilities.textDocument.definition,
  { dynamicRegistration = true, linkSupport = true },
  "definition client capabilities preserved"
)
same(
  captured_config.capabilities.textDocument.completion.completionItem.snippetSupport,
  true,
  "completion advertises snippet support"
)
same(captured_config.init_options, { allow_all_markdown = false }, "lsp init options default to narrowed markdown")
same(captured_config.handlers, nil, "definition uses standard lsp handlers")
same(captured_opts, { bufnr = 0, silent = true }, "lsp start opts")

local original_completion = vim.lsp.completion
local enable_calls = {}
vim.lsp.completion = {
  enable = function(...)
    table.insert(enable_calls, { ... })
  end,
}

captured_config.on_attach({
  id = 7,
  name = "sase-xprompt-lsp",
  supports_method = function()
    return true
  end,
}, 0)
same(#enable_calls, 1, "native completion enabled when requested")
same(enable_calls[1], { true, 7, 0, { autotrigger = true } }, "native completion enable args")

enable_calls = {}
vim.lsp.start = function(start_config, start_opts)
  captured_config = start_config
  captured_opts = start_opts
  return 123
end
require("sase").setup({
  complete = { keymap = false },
  lsp = { cmd = { "fake-lsp" }, filetypes = { "markdown" }, native_completion = false },
})
vim.lsp.start = original_start
captured_config.on_attach({
  id = 8,
  name = "sase-xprompt-lsp",
  supports_method = function()
    return true
  end,
}, 0)
same(#enable_calls, 0, "native completion skipped when disabled")
vim.lsp.completion = original_completion

require("sase").setup({
  complete = { keymap = false, completion_backend = "legacy" },
  lsp = { enabled = false },
})

same(require("sase.complete")._config().completion_backend, "legacy", "legacy backend remains configurable")
same(lsp._config().enabled, false, "lsp can be disabled")
