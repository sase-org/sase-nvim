-- Detect .gp files under .sase/projects/ as sase_gp filetype
vim.filetype.add({
  pattern = {
    [".*/%.sase/projects/.*%.gp"] = "sase_gp",
  },
})
