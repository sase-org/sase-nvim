package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local token = require("sase.complete._token")
local xprompt = require("sase.xprompt")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
  end
end

eq(token.is_slash_skill_like("/"), true, "bare slash is slash-skill-like")
eq(token.is_slash_skill_like("/sase_plan"), true, "identifier slash skill is slash-skill-like")
eq(token.is_slash_skill_like("/tmp/foo"), false, "absolute path is not slash-skill-like")
eq(token.is_slash_skill_like("/sase-plan"), false, "punctuated slash token is not slash-skill-like")
eq(token.classify("/"), "xprompt", "bare slash classifies as xprompt")
eq(token.classify("/sase_plan"), "xprompt", "slash skill classifies as xprompt")
eq(token.classify("/tmp/foo"), "file", "absolute path remains file")

local items = {
  {
    name = "sase_plan",
    type = "xprompt",
    kind = "xprompt",
    insertion = "#sase_plan",
    is_skill = true,
    inputs = {},
    preview = "Plan",
  },
  {
    name = "sample",
    type = "xprompt",
    kind = "xprompt",
    insertion = "#sample",
    is_skill = false,
    inputs = {},
    preview = "Sample",
  },
  {
    name = "sync",
    type = "workflow",
    kind = "standalone_workflow",
    insertion = "#!sync",
    is_skill = false,
    inputs = {},
    preview = "Sync",
  },
}

local slash = xprompt._filter_items_for_token(items, { text = "/sas" })
eq(#slash, 1, "slash filtering returns only matching skills")
eq(slash[1].name, "sase_plan", "slash filtering matches by item name")
eq(xprompt._item_insertion(slash[1]), "/sase_plan", "slash insertion uses slash reference")
eq(xprompt._item_kind_label(slash[1]), "Skill", "slash item label is Skill")

local hash = xprompt._filter_items_for_token(items, { text = "#sa" })
eq(#hash, 2, "hash filtering preserves non-skill xprompts")
eq(xprompt._item_insertion(hash[1]), "#sase_plan", "hash insertion keeps catalog insertion")
eq(xprompt._item_insertion(hash[2]), "#sample", "hash insertion keeps regular xprompt insertion")

local standalone = xprompt._filter_items_for_token(items, { text = "#!" })
eq(#standalone, 1, "bang filtering returns standalone workflows")
eq(standalone[1].name, "sync", "bang filtering preserves standalone behavior")
eq(xprompt._item_insertion(standalone[1]), "#!sync", "bang insertion keeps catalog insertion")
