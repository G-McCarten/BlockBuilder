local WorldArc = require("../src/shared/WorldArc")
local WorldArcConfig = require("../src/shared/WorldArcConfig")
local Test = require("./lib/Test")

Test.group("WorldArc")

local keys = {
	{ at = 0, fog = 100, tint = { 0, 100, 200 } },
	{ at = 0.5, fog = 300, tint = { 100, 100, 0 } },
	{ at = 1, fog = 400, tint = { 200, 0, 0 } },
}

Test.case("blends between the keys either side of a share", function()
	local look = WorldArc.at(keys, 0.25)
	Test.equal(look.fog, 200, "half way to the second key")
	Test.equal(look.tint[1], 50, "red")
	Test.equal(look.tint[3], 100, "blue")
	Test.equal(WorldArc.at(keys, 0.75).fog, 350, "between the second and third")
	Test.equal(WorldArc.at(keys, 0.5).fog, 300, "on a key")
end)

Test.case("holds the first and last keys beyond the ends", function()
	Test.equal(WorldArc.at(keys, -1).fog, 100, "before the start")
	Test.equal(WorldArc.at(keys, 2).fog, 400, "after the end")
	Test.equal(WorldArc.at(keys, 1).tint[1], 200, "at the end")
end)

Test.case("Frostward's arc runs from blizzard to aurora", function()
	local start, done = WorldArc.at(WorldArcConfig, 0), WorldArc.at(WorldArcConfig, 1)
	Test.check(start.weather > 0 and done.weather == 0, "the snow stops")
	Test.check(start.skyGlow == 0 and done.skyGlow == 1, "the aurora opens")
	Test.check(done.clockTime > start.clockTime, "night falls")
	Test.check(done.fogEnd > start.fogEnd, "the fog lifts")
	for _, key in WorldArcConfig do
		for name in WorldArcConfig[1] do
			Test.check(key[name] ~= nil, `every key has {name}`)
		end
	end
end)

return nil
