-- Highlight groups owned by sase-nvim.

local M = {}

local GROUP = "SaseHighlights"
local XPROMPT_SEPARATOR_GROUP = "@lsp.type.xpromptSeparator"

local function default_config()
  return {
    xprompt_separator = { fg = "#D75FFF", bold = true, ctermfg = 171 },
  }
end

local config = default_config()

function M.apply()
  if type(config.xprompt_separator) ~= "table" then
    return
  end
  vim.api.nvim_set_hl(0, XPROMPT_SEPARATOR_GROUP, config.xprompt_separator)
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", default_config(), opts)
  M.apply()

  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = M.apply,
  })
end

function M._config()
  return config
end

return M
