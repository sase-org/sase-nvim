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

--- Apply a single schema→globs mapping to yamlls.
--- Updates both the stored config (for future starts) and any running clients.
local function apply_schema(schema, globs)
  vim.schedule(function()
    local new_settings = { yaml = { schemas = { [schema] = globs } } }

    -- Update config for future client starts.
    vim.lsp.config("yamlls", { settings = new_settings })

    -- Notify any already-running yamlls clients.
    -- yamlls uses a pull model: it ignores the notification payload and
    -- sends workspace/configuration back to fetch updated settings.
    for _, client in ipairs(vim.lsp.get_clients({ name = "yamlls" })) do
      client.settings = vim.tbl_deep_extend("force", client.settings or {}, new_settings)
      client:notify("workspace/didChangeConfiguration", { settings = client.settings })
    end
  end)
end

-- sase config files  (sase.yml, sase_*.yml)
resolve_schema("config-schema", function(schema)
  apply_schema(schema, {
    "**/sase.yml",
    "**/sase_*.yml",
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
