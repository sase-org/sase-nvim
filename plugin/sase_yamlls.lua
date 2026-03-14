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
local function apply_schema(schema, globs)
  vim.schedule(function()
    vim.lsp.config("yamlls", {
      settings = {
        yaml = {
          schemas = { [schema] = globs },
        },
      },
    })
  end)
end

-- sase config files  (sase.yml, sase_*.yml, default_config.yml)
resolve_schema("config-schema", function(schema)
  apply_schema(schema, {
    "**/sase.yml",
    "**/sase_*.yml",
    "**/sase/default_config.yml",
    "**/sase_*/default_config.yml",
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
