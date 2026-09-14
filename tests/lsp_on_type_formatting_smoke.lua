-- Headless smoke coverage for native on-type formatting served by the
-- xprompt LSP through the plugin's real Neovim client.

local repo_dir = vim.fn.getcwd()
package.path = repo_dir .. "/lua/?.lua;" .. repo_dir .. "/lua/?/init.lua;" .. package.path

local function fail(message)
  error(message, 0)
end

local function resolve_cmd()
  if vim.env.SASE_XPROMPT_LSP_CMD and vim.env.SASE_XPROMPT_LSP_CMD ~= "" then
    return vim.fn.split(vim.env.SASE_XPROMPT_LSP_CMD)
  end
  fail("SASE_XPROMPT_LSP_CMD must point at the rebuilt xprompt LSP")
end

local function get_clients(bufnr)
  local filter = { name = "sase-xprompt-lsp", bufnr = bufnr }
  if vim.lsp.get_clients then
    return vim.lsp.get_clients(filter)
  end
  return vim.lsp.get_active_clients(filter)
end

local function wait_for_client(client_id)
  local started = vim.wait(30000, function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client
      and #get_clients(0) > 0
      and client.server_capabilities
      and client.server_capabilities.documentOnTypeFormattingProvider ~= nil
  end, 100)
  if not started then
    fail("xprompt LSP client did not attach with on-type formatting support")
  end
end

local function current_line()
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
  vim.wait(80)
end

local function wait_for_line(expected)
  local ok = vim.wait(30000, function()
    return current_line() == expected
  end, 50)
  if not ok then
    fail("expected line " .. vim.inspect(expected) .. ", got " .. vim.inspect(current_line()))
  end
end

local function set_line(line)
  vim.cmd("stopinsert")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, math.max(0, #line - 1) })
  vim.cmd("redraw")
end

local function type_open_paren(expected)
  feed("a(")
  wait_for_line(expected)
  local cursor_before_escape = vim.api.nvim_win_get_cursor(0)
  feed("<Esc>")
  vim.wait(1000, function()
    return vim.api.nvim_get_mode().mode ~= "i"
  end, 20)
  return cursor_before_escape
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.sase", "p")

local prompt_path = root .. "/sase_prompt_on_type_formatting_smoke.md"
vim.fn.writefile({ "" }, prompt_path)

vim.cmd("cd " .. vim.fn.fnameescape(root))

require("sase").setup({
  complete = { keymap = false },
  lsp = { cmd = resolve_cmd(), filetypes = { "markdown" }, native_completion = false },
})

vim.cmd("edit " .. vim.fn.fnameescape(prompt_path))
vim.bo.filetype = "markdown"

local client_id = require("sase.lsp").start(0)
if not client_id then
  fail("xprompt LSP did not start")
end
wait_for_client(client_id)

set_line("%q:")
type_open_paren("%q(")

set_line("🙂 %q:")
vim.keymap.set("i", "(", "()<Left>", { buffer = true, noremap = true })
local cursor = type_open_paren("🙂 %q()")
if cursor[2] ~= #"🙂 %q" then
  fail("paired insertion cursor was not between parens: " .. vim.inspect(cursor))
end

vim.keymap.del("i", "(", { buffer = true })
set_line("%q(")
type_open_paren("%q((")

set_line("%unknown:")
type_open_paren("%unknown:(")

local scratch = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(scratch)
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "%q:" })
vim.bo[scratch].filetype = "markdown"
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("i(")
vim.wait(200, function()
  return false
end, 20)
if vim.api.nvim_buf_get_lines(scratch, 0, 1, false)[1] ~= "(%q:" then
  fail("unattached scratch buffer was edited by on-type formatting")
end

local client = vim.lsp.get_client_by_id(client_id)
if client and client.stop then
  client:stop(true)
else
  vim.lsp.stop_client(client_id, true)
end

print("lsp_on_type_formatting_smoke: OK")
