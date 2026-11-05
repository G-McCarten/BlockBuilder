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

Test.case("every hint has words on every device", function()
	for _, hint in Hints.ORDER do
		for _, device in { "mouse", "touch", "gamepad" } do
			local words = Hints.words(HintConfig, hint.id, device :: any)
			Test.check(type(words) == "string" and #words > 10, `{hint.id} has words on {device}`)
		end
	end
end)

Test.case("a hint that names a button names the device's own", function()
	Test.check(string.find(Hints.words(HintConfig, "lay", "mouse"), "Click") ~= nil, "a mouse clicks")
	Test.check(string.find(Hints.words(HintConfig, "lay", "touch"), "Tap") ~= nil, "a finger taps")
	Test.check(string.find(Hints.words(HintConfig, "crew", "gamepad"), "X") ~= nil, "a gamepad presses X")
	for _, device in { "touch", "gamepad" } do
		for _, id in { "lay", "buy", "crew" } do
			local words = Hints.words(HintConfig, id, device :: any)
			Test.check(
				not string.find(words, "Click") and not string.find(words, "Press Q"),
				`{id} on {device}: {words}`
			)
		end
	end
	Test.equal(Hints.words(HintConfig, "boss", "touch"), HintConfig.boss, "words for every device")
end)

return nil
