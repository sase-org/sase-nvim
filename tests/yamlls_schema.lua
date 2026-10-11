local function contains(values, target)
	for _, value in ipairs(values) do
		if value == target then
			return true
		end
	end
	return false
end

local original_jobstart = vim.fn.jobstart
local original_lsp_config = vim.lsp.config
local original_get_clients = vim.lsp.get_clients
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_schedule = vim.schedule
local original_create_autocmd = vim.api.nvim_create_autocmd
local original_create_augroup = vim.api.nvim_create_augroup

local schema_paths = {
	["config-schema"] = "/tmp/sase.schema.json",
	["macros-schema"] = "/tmp/workflow.schema.json",
	-- legacy xprompt spelling; retired alias, always accepted
	["xprompts-schema"] = "/tmp/legacy-workflow.schema.json",
}
local config_calls = {}
local lsp_attach_callback = nil
local requested_schemas = {}

vim.fn.jobstart = function(cmd, opts)
	table.insert(requested_schemas, cmd[3])
	local schema = schema_paths[cmd[3]]
	if not schema then
		error("unexpected schema request: " .. vim.inspect(cmd))
	end
	opts.on_stdout(nil, { schema })
	return 1
end

vim.lsp.config = function(name, config)
	if name ~= "yamlls" then
		error("unexpected lsp config: " .. tostring(name))
	end
	table.insert(config_calls, config)
end

vim.lsp.get_clients = function(opts)
	if opts and opts.name ~= "yamlls" then
		error("unexpected client lookup: " .. vim.inspect(opts))
	end
	return {}
end

vim.lsp.get_client_by_id = function(client_id)
	if client_id ~= 42 then
		error("unexpected client id: " .. tostring(client_id))
	end
	return {
		name = "yamlls",
		settings = { yaml = { schemas = {} } },
		config = { settings = { yaml = { schemas = {} } } },
		notify = function(self, method, payload)
			self.notified = { method = method, payload = payload }
		end,
	}
end

vim.schedule = function(callback)
	callback()
end

vim.api.nvim_create_augroup = function(name, opts)
	if name ~= "SaseYamlLsSchemas" or not opts.clear then
		error("unexpected augroup: " .. vim.inspect({ name = name, opts = opts }))
	end
	return 17
end

vim.api.nvim_create_autocmd = function(event, opts)
	if event ~= "LspAttach" or opts.group ~= 17 or type(opts.callback) ~= "function" then
		error("unexpected autocmd: " .. vim.inspect({ event = event, opts = opts }))
	end
	lsp_attach_callback = opts.callback
	return 18
end

dofile("plugin/sase_yamlls.lua")

vim.fn.jobstart = original_jobstart
vim.lsp.config = original_lsp_config
vim.lsp.get_clients = original_get_clients
vim.lsp.get_client_by_id = original_get_client_by_id
vim.schedule = original_schedule
vim.api.nvim_create_autocmd = original_create_autocmd
vim.api.nvim_create_augroup = original_create_augroup

local config_globs = nil
local workflow_globs = nil
for _, call in ipairs(config_calls) do
	local schemas = call.settings and call.settings.yaml and call.settings.yaml.schemas or {}
	if schemas["/tmp/sase.schema.json"] then
		config_globs = schemas["/tmp/sase.schema.json"]
	end
	if schemas["/tmp/workflow.schema.json"] then
		workflow_globs = schemas["/tmp/workflow.schema.json"]
	end
end

if not config_globs then
	error("config schema was not applied")
end

if not contains(config_globs, "**/src/sase/default_config.yml") then
	error("default_config.yml is missing from config schema globs: " .. vim.inspect(config_globs))
end
if not contains(config_globs, "**/sase/sase.yml") then
	error("canonical project config is missing from config schema globs: " .. vim.inspect(config_globs))
end
if contains(config_globs, "**/sase.yml") then
	error("legacy project config is still present in config schema globs: " .. vim.inspect(config_globs))
end
if not workflow_globs then
	error("macro workflow schema was not applied")
end
for _, glob in ipairs({
	"**/sase/macros/**/*.yml",
	"**/sase/macros/**/*.yaml",
	-- legacy xprompt spelling; retired alias, always accepted
	"**/sase/xprompts/**/*.yml",
	"**/sase/xprompts/**/*.yaml",
}) do
	if not contains(workflow_globs, glob) then
		error("macro workflow glob is missing: " .. glob .. " in " .. vim.inspect(workflow_globs))
	end
end
for _, glob in ipairs({
	"**/.macros/**/*.yml",
	"**/.macros/**/*.yaml",
	"**/macros/**/*.yml",
	"**/macros/**/*.yaml",
	"**/macros.yml",
	"**/macros.yaml",
}) do
	if contains(workflow_globs, glob) then
		error("legacy macro workflow glob is still present: " .. glob .. " in " .. vim.inspect(workflow_globs))
	end
end

if not contains(requested_schemas, "macros-schema") then
	error("new macros-schema target was not requested first: " .. vim.inspect(requested_schemas))
end
if contains(requested_schemas, "xprompts-schema") then
	error("legacy schema target must not be requested while macros-schema resolves: " .. vim.inspect(requested_schemas))
end

if not lsp_attach_callback then
	error("yamlls LspAttach callback was not registered")
end

local attached_client = {
	name = "yamlls",
	settings = { yaml = { schemas = {} } },
	config = { settings = { yaml = { schemas = {} } } },
	notify = function(self, method, payload)
		self.notified = { method = method, payload = payload }
	end,
}

vim.lsp.get_client_by_id = function(client_id)
	if client_id ~= 42 then
		error("unexpected client id: " .. tostring(client_id))
	end
	return attached_client
end

lsp_attach_callback({ data = { client_id = 42 } })
vim.lsp.get_client_by_id = original_get_client_by_id

local attached_globs = attached_client.settings.yaml.schemas["/tmp/sase.schema.json"]
if not attached_globs or not contains(attached_globs, "**/src/sase/default_config.yml") then
	error("default_config.yml was not pushed to attached yamlls client: " .. vim.inspect(attached_client.settings))
end

if not attached_client.notified or attached_client.notified.method ~= "workspace/didChangeConfiguration" then
	error("attached yamlls client was not notified")
end

-- --- legacy fallback: macros-schema resolves empty, xprompts-schema answers -

local fallback_requests = {}
local fallback_calls = {}

vim.fn.jobstart = function(cmd, opts)
	table.insert(fallback_requests, cmd[3])
	if cmd[3] == "macros-schema" then
		opts.on_stdout(nil, { "   " })
	elseif cmd[3] == "config-schema" then
		opts.on_stdout(nil, { "/tmp/sase.schema.json" })
	elseif cmd[3] == "xprompts-schema" then
		-- legacy xprompt spelling; retired alias, always accepted
		opts.on_stdout(nil, { "/tmp/legacy-workflow.schema.json" })
	else
		error("unexpected schema request: " .. vim.inspect(cmd))
	end
	return 1
end

vim.lsp.config = function(name, config)
	if name ~= "yamlls" then
		error("unexpected lsp config: " .. tostring(name))
	end
	table.insert(fallback_calls, config)
end

vim.lsp.get_clients = function()
	return {}
end

vim.schedule = function(callback)
	callback()
end

vim.api.nvim_create_augroup = function()
	return 19
end

vim.api.nvim_create_autocmd = function()
	return 20
end

dofile("plugin/sase_yamlls.lua")

vim.fn.jobstart = original_jobstart
vim.lsp.config = original_lsp_config
vim.lsp.get_clients = original_get_clients
vim.schedule = original_schedule
vim.api.nvim_create_autocmd = original_create_autocmd
vim.api.nvim_create_augroup = original_create_augroup

if not contains(fallback_requests, "macros-schema") then
	error("fallback run never tried macros-schema: " .. vim.inspect(fallback_requests))
end
if not contains(fallback_requests, "xprompts-schema") then
	error("empty macros-schema did not fall back to xprompts-schema: " .. vim.inspect(fallback_requests))
end

local fallback_globs = nil
for _, call in ipairs(fallback_calls) do
	local schemas = call.settings and call.settings.yaml and call.settings.yaml.schemas or {}
	if schemas["/tmp/legacy-workflow.schema.json"] then
		fallback_globs = schemas["/tmp/legacy-workflow.schema.json"]
	end
end

if not fallback_globs then
	error("legacy workflow schema was not applied on fallback")
end
for _, glob in ipairs({
	"**/sase/macros/**/*.yml",
	"**/sase/xprompts/**/*.yml",
}) do
	if not contains(fallback_globs, glob) then
		error("fallback schema glob is missing: " .. glob .. " in " .. vim.inspect(fallback_globs))
	end
end

print("yamlls_schema: all tests passed")
