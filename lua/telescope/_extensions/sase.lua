-- Telescope extension for sase xprompt picker with preview.

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local entry_display = require("telescope.pickers.entry_display")

local xprompt = require("sase.xprompt")

--- Create a Telescope previewer that shows xprompt content.
local function make_previewer()
  return previewers.new_buffer_previewer({
    title = "XPrompt Preview",
    define_preview = function(self, entry)
      local item = entry.value
      local lines = vim.split(item.preview or "", "\n")
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      -- Use markdown highlighting for preview.
      vim.bo[self.state.bufnr].filetype = "markdown"
    end,
  })
end

--- Main picker function.
--- @param opts? { items?: table, on_cancel?: fun() }
local function xprompts_picker(opts)
  opts = opts or {}

  local function show(items)
    if #items == 0 then
      vim.notify("No xprompts found", vim.log.levels.WARN)
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = 2 }, -- icon
        { remaining = true }, -- name + inputs
      },
    })

    local function make_display(entry)
      local item = entry.value
      local icon = item.type == "workflow" and "⚙" or " "
      -- Build name with input hints.
      local name = "#" .. item.name
      local input_parts = {}
      for _, inp in ipairs(item.inputs or {}) do
        input_parts[#input_parts + 1] = inp.required and inp.name or (inp.name .. "?")
      end
      if #input_parts > 0 then
        name = name .. "(" .. table.concat(input_parts, ", ") .. ")"
      end
      return displayer({
        { icon, item.type == "workflow" and "Type" or "Comment" },
        { name, "Function" },
      })
    end

    pickers
      .new(opts, {
        prompt_title = "XPrompts",
        finder = finders.new_table({
          results = items,
          entry_maker = function(item)
            return {
              value = item,
              display = make_display,
              ordinal = item.name,
            }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = make_previewer(),
        attach_mappings = function(prompt_bufnr, _map)
          local selected = false
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            selected = true
            actions.close(prompt_bufnr)
            if selection then
              xprompt._insert_at_cursor(selection.value.name)
            elseif opts.on_cancel then
              opts.on_cancel()
            end
          end)
          -- Handle close/cancel to restore #@ trigger if needed.
          actions.close:enhance({
            post = function()
              if not selected and opts.on_cancel then
                opts.on_cancel()
              end
            end,
          })
          return true
        end,
      })
      :find()
  end

  if opts.items then
    show(opts.items)
  else
    xprompt._fetch_xprompts(show)
  end
end

return telescope.register_extension({
  exports = {
    xprompts = xprompts_picker,
  },
})
