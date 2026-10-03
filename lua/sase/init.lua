-- Top-level entry point for sase-nvim: `require("sase").setup{...}`.

local M = {}

local deprecated_key_warned = {}

local function resolve_setup_key(opts, new_name, old_name)
	local new_value = opts[new_name]
	-- legacy xprompt spelling; remove with legacy_xprompt_syntax
	local old_value = opts[old_name]
	if new_value ~= nil and old_value ~= nil then
		error(string.format("sase-nvim: supply only one of `%s` or `%s`", new_name, old_name), 0)
	end
	if old_value ~= nil then
		if not deprecated_key_warned[old_name] then
			deprecated_key_warned[old_name] = true
			vim.notify(
				string.format("sase-nvim: setup key `%s` is deprecated; use `%s`", old_name, new_name),
				vim.log.levels.WARN
			)
		end
		return old_value
	end
	return new_value
end

--- Configure sase-nvim.
---
--- Example:
--- ```lua
--- require("sase").setup({
---   complete = { keymap = true },  -- bind <C-t> in insert mode
--- })
--- ```
--- @param opts? { complete?: { keymap?: boolean|string, completion_backend?: "auto"|"lsp"|"picker" }, lsp?: { enabled?: boolean, cmd?: string|string[], native_completion?: "auto"|boolean, allow_all_markdown?: boolean }, glossary_highlight?: { enabled?: boolean }, macro_highlight?: { enabled?: boolean }, project_tag_highlight?: { enabled?: boolean }, alt_highlight?: { enabled?: boolean, allow_all_markdown?: boolean, filetypes?: string[] }, alt_editing?: { enabled?: boolean, allow_all_markdown?: boolean, filetypes?: string[] }, macro_spacer?: { enabled?: boolean, allow_all_markdown?: boolean, filetypes?: string[] } }
function M.setup(opts)
	opts = opts or {}
	require("sase.lsp").setup(opts.lsp or {})
	require("sase.glossary_highlight").setup(opts.glossary_highlight or {})
	require("sase.macro_semantic_highlight").setup(resolve_setup_key(opts, "macro_highlight", "xprompt_highlight") or {})
	require("sase.project_tag_highlight").setup(opts.project_tag_highlight or {})
	require("sase.alt_highlight").setup(opts.alt_highlight or {})
	require("sase.alt_edit").setup(opts.alt_editing or {})
	require("sase.macro_spacer").setup(resolve_setup_key(opts, "macro_spacer", "xprompt_spacer") or {})
	if opts.complete ~= nil then
		require("sase.complete").setup(opts.complete)
	end
end

return M
