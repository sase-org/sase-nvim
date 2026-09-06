-- Detect canonical project spec files under .sase/projects/ as the
-- sase_project_spec filetype.
vim.filetype.add({
  pattern = {
    [".*/%.sase/projects/[^/]+/[^/]+%.sase"] = "sase_project_spec",
  },
})
