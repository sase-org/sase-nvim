-- Neovim LSP client glue for the sase xprompt language server.

local M = {}

local DEFAULT_FILETYPES = { "markdown", "gitcommit", "sase", "sase_prompt" }
local CLIENT_NAME = "sase-xprompt-lsp"
local GROUP = "SaseXPromptLsp"

local config = {
  enabled = true,
  cmd = nil,
  filetypes = DEFAULT_FILETYPES,
  allow_all_markdown = false,
  autotrigger = true,
  native_completion = "auto",
}

local cached_sase_lsp_available = nil

local function copy_list(values)
  local copy = {}
  for idx, value in ipairs(values or {}) do
    copy[idx] = value
  end
  return copy
end

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_cmd(cmd)
  if type(cmd) == "table" then
    return #cmd > 0 and copy_list(cmd) or nil
  end
  if type(cmd) == "string" then
    local cleaned = trim(cmd)
    if cleaned ~= "" then
      return vim.fn.split(cleaned)
    end
  end
  return nil
end

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function command_success(cmd)
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

local function sase_lsp_available()
  if cached_sase_lsp_available ~= nil then
    return cached_sase_lsp_available
  end
  cached_sase_lsp_available = command_success({ "sase", "lsp", "--version" })
  return cached_sase_lsp_available
end

function M._resolve_cmd(opts, env, executable_fn, sase_lsp_available_fn)
  opts = opts or config
  env = env or vim.env
  executable_fn = executable_fn or executable
  sase_lsp_available_fn = sase_lsp_available_fn or sase_lsp_available

  local explicit = normalize_cmd(opts.cmd)
  if explicit then
    return explicit
  end

  local override = normalize_cmd(env.SASE_XPROMPT_LSP_CMD)
  if override then
    return override
  end

  if executable_fn("sase") and sase_lsp_available_fn() then
    return { "sase", "lsp" }
  end

  if executable_fn("sase-xprompt-lsp") then
    return { "sase-xprompt-lsp" }
  end

  return nil
end

local function first_existing_ancestor(start_dir, markers)
  local uv = vim.uv or vim.loop
  local dir = start_dir
  while dir and dir ~= "" do
    for _, marker in ipairs(markers) do
      if uv.fs_stat(dir .. "/" .. marker) then
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  return nil
end

function M.root_dir(bufnr)
  bufnr = bufnr or 0
  if vim.fs and vim.fs.root then
    local ok, root = pcall(vim.fs.root, bufnr, { ".sase", ".git" })
    if ok and root then
      return root
    end
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local loop = vim.uv or vim.loop
  local start_dir = name ~= "" and vim.fn.fnamemodify(name, ":p:h") or loop.cwd()
  return first_existing_ancestor(start_dir, { ".sase", ".git" }) or start_dir or loop.cwd()
end

local function filetype_set(filetypes)
  local set = {}
  for _, ft in ipairs(filetypes or {}) do
    set[ft] = true
  end
  return set
end

local function basename(path)
  local normalized = (path or ""):gsub("\\", "/")
  return normalized:match("([^/]+)$") or normalized
end

local function has_path_component(path, expected)
  for component in (path or ""):gsub("\\", "/"):gmatch("[^/]+") do
    if component == expected then
      return true
    end
  end
  return false
end

local function has_prompt_temp_name(path)
  local name = basename(path)
  return name:match("^sase_ace_prompt_.+%.md$") ~= nil or name:match("^sase_prompt_.+%.md$") ~= nil
end

local function is_supported_markdown_path(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  return has_path_component(path, "xprompts")
    or has_path_component(path, ".xprompts")
    or has_prompt_temp_name(path)
end

local function supports_filetype_path(ft, path, opts)
  opts = opts or config
  if filetype_set(opts.filetypes)[ft] ~= true then
    return false
  end
  if ft ~= "markdown" then
    return true
  end
  return opts.allow_all_markdown == true or is_supported_markdown_path(path)
end

function M.supports_buffer(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  local path = vim.api.nvim_buf_get_name(bufnr)
  return supports_filetype_path(ft, path, config)
end

local function get_clients(bufnr)
  local filter = { name = CLIENT_NAME, bufnr = bufnr or 0 }
  if vim.lsp.get_clients then
    return vim.lsp.get_clients(filter)
  end
  return vim.lsp.get_active_clients(filter)
end

local function load_module(name)
  local ok, module = pcall(require, name)
  if ok then
    return module
  end
  return nil
end

function M._has_cmp_completion(require_fn, loaded_modules)
  loaded_modules = loaded_modules or package.loaded
  if loaded_modules["cmp"] or loaded_modules["cmp_nvim_lsp"] then
    return true
  end

  require_fn = require_fn or load_module
  return require_fn("cmp_nvim_lsp") ~= nil
end

function M._native_completion_enabled(native_completion, has_cmp)
  if native_completion == false then
    return false
  end
  if native_completion == true then
    return true
  end
  return not has_cmp
end

function M._make_capabilities(require_fn)
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local cmp_nvim_lsp = (require_fn or load_module)("cmp_nvim_lsp")
  if cmp_nvim_lsp and type(cmp_nvim_lsp.default_capabilities) == "function" then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
  end
  capabilities.textDocument.completion.completionItem.snippetSupport = true
  return capabilities
end

local function native_completion_enabled()
  return M._native_completion_enabled(config.native_completion, M._has_cmp_completion())
end

function M.is_attached(bufnr)
  return #get_clients(bufnr or 0) > 0
end

local function enable_completion(client, bufnr)
  if not native_completion_enabled() then
    return
  end
  if not (vim.lsp.completion and vim.lsp.completion.enable) then
    return
  end
  if client.name ~= CLIENT_NAME then
    return
  end
  local supports = client.supports_method
  if supports and not client:supports_method("textDocument/completion") then
    return
  end
  pcall(vim.lsp.completion.enable, true, client.id, bufnr, { autotrigger = config.autotrigger ~= false })
end

function M.start(bufnr)
  bufnr = bufnr or 0
  if not config.enabled or not M.supports_buffer(bufnr) then
    return nil
  end
  if M.is_attached(bufnr) then
    local clients = get_clients(bufnr)
    return clients[1] and clients[1].id or nil
  end

  local cmd = M._resolve_cmd(config)
  if not cmd then
    return nil
  end

  return vim.lsp.start({
    name = CLIENT_NAME,
    cmd = cmd,
    root_dir = M.root_dir(bufnr),
    capabilities = M._make_capabilities(),
    init_options = {
      allow_all_markdown = config.allow_all_markdown == true,
    },
    on_attach = enable_completion,
  }, { bufnr = bufnr, silent = true })
end

function M.can_start()
  return config.enabled and M._resolve_cmd(config) ~= nil
end

function M.complete()
  if not config.enabled then
    return false
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if not M.supports_buffer(bufnr) then
    return false
  end
  M.start(bufnr)
  if not M.is_attached(bufnr) then
    return false
  end
  if not native_completion_enabled() then
    return false
  end
  if vim.lsp.completion and vim.lsp.completion.get then
    vim.lsp.completion.get()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n", false)
  end
  return true
end

function M.setup(opts)
  opts = opts or {}
  cached_sase_lsp_available = nil
  config = vim.tbl_deep_extend("force", {
    enabled = true,
    cmd = nil,
    filetypes = DEFAULT_FILETYPES,
    allow_all_markdown = false,
    autotrigger = true,
    native_completion = "auto",
  }, opts)

  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  if not config.enabled then
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = config.filetypes,
    callback = function(args)
      M.start(args.buf)
    end,
  })

  if M.supports_buffer(0) then
    M.start(0)
  end
end

function M._config()
  return config
end

M._is_supported_markdown_path = is_supported_markdown_path
M._supports_filetype_path = supports_filetype_path

return M
