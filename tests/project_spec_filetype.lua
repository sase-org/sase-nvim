local function same(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function not_same(actual, forbidden, label)
  if actual == forbidden then
    error(string.format("%s: did not expect %s", label, vim.inspect(forbidden)))
  end
end

dofile("ftdetect/sase_project_spec.lua")

same(
  vim.filetype.match({ filename = "/tmp/work/.sase/projects/sase/sase.sase" }),
  "sase_project_spec",
  "canonical project spec filetype"
)
not_same(
  vim.filetype.match({ filename = "/tmp/work/.sase/projects/sase/sase.gp" }),
  "sase_project_spec",
  "legacy gp file is not auto-associated"
)

vim.cmd("syntax clear")
vim.bo.filetype = "sase_project_spec"
vim.cmd("source syntax/sase_project_spec.vim")
same(vim.b.current_syntax, "sase_project_spec", "canonical syntax marker")
same(vim.fn.hlexists("saseProjectSpecFieldLabel"), 1, "canonical syntax groups are defined")
