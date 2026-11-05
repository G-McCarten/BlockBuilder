local HintConfig = require("../src/shared/HintConfig")
local Hints = require("../src/shared/Hints")
local Test = require("./lib/Test")

local function context(overrides: { [string]: any }?)
	local c = {
		placed = 5,
		purse = 0,
		cheapest = 100,
		bought = 0,
		workingLayer = 0,
		bossRisen = false,
		markers = 0,
		bound = false,
		peace = false,
		crewUnlocked = false,
	}
	for k, v in overrides or {} do
		c[k] = v
	end
	return c
end

Test.group("Hints")

Test.case("the first hint is how to lay a block, then each comes once in its moment", function()
	local shown = {}
	Test.equal(Hints.pick(context({ placed = 0 }), shown), "lay", "first, how to lay")
	shown.lay = true
	Test.equal(Hints.pick(context(), shown), nil, "nothing to say yet")
	Test.equal(Hints.pick(context({ purse = 120 }), shown), "buy", "a skill is affordable")
	shown.buy = true
	Test.equal(Hints.pick(context({ purse = 500 }), shown), nil, "said once")
	Test.equal(Hints.pick(context({ bossRisen = true, bound = true }), shown), "bound", "the most urgent first")
end)

Test.case("every hint has words", function()
	for _, hint in Hints.ORDER do
		Test.check(type(HintConfig[hint.id]) == "string" and #HintConfig[hint.id] > 10, `{hint.id} has words`)
	end
end)

return nil
