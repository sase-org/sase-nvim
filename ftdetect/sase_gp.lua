-- Detect project spec files under .sase/projects/ as sase_gp filetype.
-- Canonical extension is .sase; legacy .gp is recognized for backward
-- compatibility while existing user data is migrated.
vim.filetype.add({
  pattern = {
    [".*/%.sase/projects/.*%.sase"] = "sase_gp",
    [".*/%.sase/projects/.*%.gp"] = "sase_gp",
  },
})
