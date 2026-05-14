-- Configure yaml-language-server schema associations for sase files.
-- All schema paths are resolved asynchronously via `sase path` so
-- startup is never blocked.

--- Resolve a schema path via `sase path <name>` and call `on_resolved(path)`.
local function resolve_schema(name, on_resolved)
  vim.fn.jobstart({ "sase", "path", name }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local schema = vim.fn.trim(table.concat(data, "\n"))
      if schema ~= "" then
        on_resolved(schema)
      end
    end,
  })
end

local resolved_schemas = {}

local function schema_settings()
  return { yaml = { schemas = vim.deepcopy(resolved_schemas) } }
end

local function update_client(client, settings)
  client.settings = vim.tbl_deep_extend("force", client.settings or {}, settings)
  client.config = client.config or {}
  client.config.settings = vim.tbl_deep_extend("force", client.config.settings or {}, settings)
  client:notify("workspace/didChangeConfiguration", { settings = client.settings })
end

--- Apply a single schema→globs mapping to yamlls.
--- Updates both the stored config (for future starts) and any running clients.
local function apply_schema(schema, globs)
  resolved_schemas[schema] = globs

  vim.schedule(function()
    local new_settings = schema_settings()

    -- Update config for future client starts.
    vim.lsp.config("yamlls", { settings = new_settings })

    -- Notify any already-running yamlls clients.
    -- yamlls uses a pull model: it ignores the notification payload and
    -- sends workspace/configuration back to fetch updated settings.
    for _, client in ipairs(vim.lsp.get_clients({ name = "yamlls" })) do
      update_client(client, new_settings)
    end
  end)
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("SaseYamlLsSchemas", { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client or client.name ~= "yamlls" or not next(resolved_schemas) then
      return
    end
    update_client(client, schema_settings())
  end,
})

-- sase config files  (sase.yml, sase_*.yml, src/sase/default_config.yml)
resolve_schema("config-schema", function(schema)
  apply_schema(schema, {
    "**/sase.yml",
    "**/sase_*.yml",
    "**/src/sase/default_config.yml",
  })
end)

-- xprompt workflow files  (xprompts/**/*.yml)
resolve_schema("xprompts-schema", function(schema)
  apply_schema(schema, {
    "*/xprompts/**/*.yml",
    "*/.xprompts/**/*.yml",
  })
end)

-- xprompt collection files  (xprompts.yml)
resolve_schema("xprompts-collection-schema", function(schema)
  apply_schema(schema, {
    "**/xprompts.yml",
    "**/xprompts.yaml",
  })
end)
