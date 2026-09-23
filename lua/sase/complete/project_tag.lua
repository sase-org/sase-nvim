-- Project-tag ("+project") picker fallback.
--
-- Used when the xprompt LSP cannot serve `+query` completion: no server is
-- attached, or native completion is disabled (e.g. nvim-cmp owns LSP
-- completion, so `sase.lsp.complete()` returns false). Offers projects from
-- `sase project list --json` (its `tag` field) and inserts the chosen `+name`
-- in place of the token under the cursor.

local M = {}

local _picker = require("sase.complete._picker")

--- Extract tag strings from decoded `sase project list --json` output.
--- Entries without a well-formed `tag` field are skipped.
--- @param entries table|nil
--- @return string[]
function M._tags_from_entries(entries)
	if type(entries) ~= "table" then
		return {}
	end
	local tags = {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.tag) == "string" and entry.tag:match("^%+%S+$") then
			tags[#tags + 1] = entry.tag
		end
	end
	return tags
end

--- Filter *tags* by the partial query typed after `+`. Prefix matches come
--- first (in catalog order), then substring matches.
--- @param tags string[]
--- @param partial string|nil  text after the leading `+`, e.g. "sa" for `+sa`
--- @return string[]
function M._filter_tags(tags, partial)
	partial = (type(partial) == "string" and partial or ""):lower()
	if partial == "" then
		local all = {}
		for _, tag in ipairs(tags or {}) do
			all[#all + 1] = tag
		end
		return all
	end
	local prefix = {}
	local substring = {}
	for _, tag in ipairs(tags or {}) do
		local name = tag:sub(2):lower()
		if name:sub(1, #partial) == partial then
			prefix[#prefix + 1] = tag
		elseif name:find(partial, 1, true) ~= nil then
			substring[#substring + 1] = tag
		end
	end
	for _, tag in ipairs(substring) do
		prefix[#prefix + 1] = tag
	end
	return prefix
end

--- Fetch project tags asynchronously via `sase project list --json`.
--- @param callback fun(tags: string[])
local function fetch_tags(callback)
	vim.fn.jobstart({ "sase", "project", "list", "--json" }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end
			local raw = vim.fn.trim(table.concat(data, "\n"))
			if raw == "" then
				return
			end
			local ok, entries = pcall(vim.json.decode, raw)
			if ok then
				local tags = M._tags_from_entries(entries)
				vim.schedule(function()
					callback(tags)
				end)
			end
		end,
	})
end

--- Open the project-tag picker.
--- @param opts? { origin_win?: integer, was_insert?: boolean, token?: { text: string, row: integer, col_start: integer, col_end: integer }, on_cancel?: fun() }
function M.pick(opts)
	opts = opts or {}
	opts.origin_win = opts.origin_win or vim.api.nvim_get_current_win()
	local token = opts.token
	if not token then
		if opts.on_cancel then
			opts.on_cancel()
		end
		return
	end

	local partial = token.text:sub(1, 1) == "+" and token.text:sub(2) or token.text

	local function show(tags)
		local filtered = M._filter_tags(tags, partial)
		if #filtered == 0 then
			vim.notify("No projects matching '" .. token.text .. "'", vim.log.levels.WARN)
			if opts.on_cancel then
				opts.on_cancel()
			end
			return
		end

		vim.ui.select(filtered, {
			prompt = "Projects> ",
			format_item = function(tag)
				return tag
			end,
		}, function(choice)
			if not choice then
				if opts.on_cancel then
					opts.on_cancel()
				end
				return
			end
			local end_pos = _picker.replace_range(token.row, token.col_start, token.col_end, choice)
			_picker.restore_insert_mode(opts.origin_win, end_pos)
		end)
	end

	fetch_tags(show)
end

-- Expose for tests.
M._fetch_tags = fetch_tags

return M
