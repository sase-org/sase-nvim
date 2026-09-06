package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local function same(actual, expected, label)
  if vim.inspect(actual) ~= vim.inspect(expected) then
    error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

local lsp_calls = 0
local picker_calls = 0

package.loaded["sase.complete._token"] = {
  token_under_cursor = function()
    return { text = "#plan" }
  end,
  classify = function()
    return "xprompt"
  end,
}
package.loaded["sase.lsp"] = {
  complete = function()
    lsp_calls = lsp_calls + 1
    return false
  end,
}
package.loaded["sase.complete.xprompt"] = {
  pick = function(opts)
    picker_calls = picker_calls + 1
    same(opts.token, { text = "#plan" }, "picker receives token context")
  end,
}

local complete = require("sase.complete")

complete.setup({ completion_backend = "auto" })
complete.trigger()
same(lsp_calls, 1, "auto tries lsp first")
same(picker_calls, 1, "auto falls back to picker")

lsp_calls = 0
picker_calls = 0
complete.setup({ completion_backend = "picker" })
complete.trigger()
same(lsp_calls, 0, "picker backend skips lsp")
same(picker_calls, 1, "picker backend opens picker")

complete.setup({ completion_backend = "leg" .. "acy" })
same(complete._config().completion_backend, "picker", "old backend value aliases to picker")
