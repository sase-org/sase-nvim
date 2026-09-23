-- Project-tag ("+project") picker fallback.
--
-- Used when the xprompt LSP cannot serve `+query` completion: no server is
-- attached, or native completion is disabled (e.g. nvim-cmp owns LSP
-- completion, so `sase.lsp.complete()` returns false). Offers projects from
-- `sase project list --json` (its `tag` field) and inserts the chosen `+name`
-- with a trailing space in place of the token under the cursor. Only the
-- `+query` token is replaced; other workspace targets are left alone.

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
--- Exactly one of *callback* / *on_error* runs, on the main loop.
--- @param callback fun(tags: string[])
--- @param on_error? fun(reason: string)
local function fetch_tags(callback, on_error)
	local settled = false
	local function fail(reason)
		if settled then
			return
		end
		settled = true
		if on_error then
			vim.schedule(function()
				on_error(reason)
			end)
		end
	end
	local function succeed(tags)
		if settled then
			return
		end
		settled = true
		vim.schedule(function()
			callback(tags)
		end)
	end
	local job_id = vim.fn.jobstart({ "sase", "project", "list", "--json" }, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if settled or not data then
				return
			end
			local raw = vim.fn.trim(table.concat(data, "\n"))
			if raw == "" then
				return
			end
			local ok, entries = pcall(vim.json.decode, raw)
			if ok then
				succeed(M._tags_from_entries(entries))
			else
				fail("could not parse `sase project list --json` output")
			end
		end,
		on_exit = function(_, code)
			if not settled and code ~= 0 then
				fail("`sase project list --json` exited with code " .. tostring(code))
			elseif not settled then
				fail("`sase project list --json` produced no output")
			end
		end,
	})
	if job_id <= 0 then
		fail("could not start `sase project list --json`")
	end
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

	local function cancel(reason)
		if reason ~= nil then
			vim.notify(reason, vim.log.levels.WARN)
		end
		if opts.on_cancel then
			opts.on_cancel()
		end
	end

	local function show(tags)
		local filtered = M._filter_tags(tags, partial)
		if #filtered == 0 then
			cancel("No projects matching '" .. token.text .. "'")
			return
		end

		vim.ui.select(filtered, {
			prompt = "Projects> ",
			format_item = function(tag)
				return tag
			end,
		}, function(choice)
			if not choice then
				cancel(nil)
				return
			end
			-- Trailing space, like the LSP completion expansion.
			-- Unlike LSP accept, the picker replaces only the `+query`
			-- token: every other workspace target in the prompt stays.
			local end_pos = _picker.replace_range(token.row, token.col_start, token.col_end, choice .. " ")
			_picker.restore_insert_mode(opts.origin_win, end_pos)
		end)
	end

	fetch_tags(show, cancel)
end

-- Expose for tests.
M._fetch_tags = fetch_tags

return M
