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
local file_history = require("sase.complete.file_history")
local file_complete = require("sase.complete.file")
local complete_picker = require("sase.complete._picker")

--- Create a Telescope previewer that shows xprompt content.
local function make_previewer()
  return previewers.new_buffer_previewer({
    title = "XPrompt Preview",
    define_preview = function(self, entry)
      local item = entry.value
      local lines = xprompt._preview_lines(item)
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      -- Use markdown highlighting for preview.
      vim.bo[self.state.bufnr].filetype = "markdown"
    end,
  })
end

--- Main picker function.
--- @param opts? table
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
      local name = xprompt._item_insertion(item)
      local input_parts = {}
      for _, inp in ipairs(item.inputs or {}) do
        input_parts[#input_parts + 1] = inp.required and inp.name or (inp.name .. "?")
      end
      if #input_parts > 0 then
        name = name .. "(" .. table.concat(input_parts, ", ") .. ")"
      end
      local description = xprompt._single_line_text(item.description)
      if description then
        name = name .. " - " .. description
      end
      return displayer({
        { icon, xprompt._item_kind_label(item) },
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
              ordinal = xprompt._item_search_text(item),
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
              local end_pos = xprompt._insert_at_cursor(selection.value, opts.insert_pos, opts.replace_range)
              xprompt._restore_insert_mode(opts.origin_win, end_pos)
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

--- File-history ("recent files") picker.
--- @param opts? { paths?: string[], on_cancel?: fun(), was_insert?: boolean, origin_win?: integer }
local function file_history_picker(opts)
  opts = opts or {}

  local function show(paths)
    if #paths == 0 then
      vim.notify("No recent files in sase history", vim.log.levels.WARN)
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    pickers
      .new(opts, {
        prompt_title = "recent files",
        results_title = "[^L] accept  [^D] delete",
        finder = finders.new_table({
          results = paths,
          entry_maker = function(path)
            return {
              value = path,
              display = path,
              ordinal = path,
            }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
          local selected = false
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            selected = true
            actions.close(prompt_bufnr)
            if selection then
              local end_pos = complete_picker.insert_text_at_cursor(selection.value, nil)
              -- Cache is stale after an insert (recency changes).
              file_history.clear_cache()
              complete_picker.restore_insert_mode(opts.origin_win, end_pos)
            elseif opts.on_cancel then
              opts.on_cancel()
            end
          end)

          local function delete_selected()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            local victim = selection.value
            file_history._delete_path(victim, function(ok)
              if not ok then
                vim.notify("sase: failed to delete '" .. victim .. "'", vim.log.levels.ERROR)
                return
              end
              -- Remove from the in-memory list and refresh the picker in place.
              for i, p in ipairs(paths) do
                if p == victim then
                  table.remove(paths, i)
                  break
                end
              end
              file_history.clear_cache()
              local current_picker = action_state.get_current_picker(prompt_bufnr)
              if #paths == 0 then
                actions.close(prompt_bufnr)
                vim.notify("No recent files in sase history", vim.log.levels.WARN)
                return
              end
              current_picker:refresh(
                finders.new_table({
                  results = paths,
                  entry_maker = function(path)
                    return {
                      value = path,
                      display = path,
                      ordinal = path,
                    }
                  end,
                }),
                { reset_prompt = false }
              )
            end)
          end

          map("i", "<C-d>", delete_selected)
          map("n", "<C-d>", delete_selected)

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

  if opts.paths then
    show(opts.paths)
  else
    file_history._fetch_paths(show)
  end
end

--- File-system completion picker.
--- @param opts? table
local function file_picker(opts)
  opts = opts or {}
  local token = opts.token
  if not token then
    return
  end

  local function show(candidates)
    if #candidates == 0 then
      vim.notify("No file completions for '" .. token.text .. "'", vim.log.levels.WARN)
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    local title = (token.text ~= "" and token.text) or opts.cwd

    pickers
      .new(opts, {
        prompt_title = "files",
        results_title = title,
        finder = finders.new_table({
          results = candidates,
          entry_maker = function(c)
            local icon = c.is_dir and "📁" or "📄"
            return {
              value = c,
              display = icon .. "  " .. c.display,
              ordinal = c.name,
            }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _map)
          local selected = false
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            selected = true
            actions.close(prompt_bufnr)
            if not selection then
              if opts.on_cancel then
                opts.on_cancel()
              end
              return
            end
            local choice = selection.value
            local end_pos = complete_picker.replace_range(
              token.row, token.col_start, token.col_end, choice.insertion
            )
            if choice.is_dir then
              -- Drill down: re-open the picker rooted at the new directory.
              local new_token = {
                text = choice.insertion,
                row = token.row,
                col_start = token.col_start,
                col_end = token.col_start + #choice.insertion,
              }
              file_complete.pick({
                origin_win = opts.origin_win,
                was_insert = opts.was_insert,
                token = new_token,
                cwd = opts.cwd,
                on_cancel = opts.on_cancel,
              })
            else
              complete_picker.restore_insert_mode(opts.origin_win, end_pos)
            end
          end)
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

  if opts.candidates then
    show(opts.candidates)
  else
    file_complete._fetch_candidates(token.text, opts.cwd, show)
  end
end

return telescope.register_extension({
  exports = {
    xprompts = xprompts_picker,
    file_history = file_history_picker,
    file = file_picker,
  },
})
