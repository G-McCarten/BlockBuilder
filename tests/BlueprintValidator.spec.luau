local Blueprint = require("../src/shared/Blueprint")
local BlueprintValidator = require("../src/shared/BlueprintValidator")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local function validate(source: Blueprint.Source, options: BlueprintValidator.Options?)
	return BlueprintValidator.validate(Blueprint.build(source), options)
end

local function mentions(report: BlueprintValidator.Report, text: string): boolean
	for _, message in report.errors do
		if string.find(message, text, 1, true) then
			return true
		end
	end
	return false
end

local function block(x: number, y: number, z: number, after: { number }?)
	return { x = x, y = y, z = z, kind = 1, after = after }
end

local function source(blocks)
	return { name = "Case", palette = { "a" }, blocks = blocks }
end

Test.group("BlueprintValidator")

Test.case("accepts the TestHut, reach included", function()
	local report = BlueprintValidator.validate(Sites.hut())
	Test.check(report.ok, table.concat(report.errors, "\n"))
	Test.equal(report.stats.unreachable, 0, "unreachable slots")
	Test.equal(report.stats.overhangs, 90, "overhangs")
	Test.equal(report.stats.depth, 16, "depth")
end)

Test.case("accepts generated terrain", function()
	for seed = 1, 3 do
		local report = validate(Sites.terrain(seed, 24, 20), { checkReach = false })
		Test.check(report.ok, table.concat(report.errors, "\n"))
	end
end)

Test.case("rejects a cycle made by extra ordering", function()
	-- Two ground blocks and two blocks above them, each waiting for the other.
	local report = validate(source({ block(0, 0, 0), block(4, 0, 0), block(0, 1, 0, { 4 }), block(4, 1, 0, { 3 }) }))
	Test.check(not report.ok, "a cycle can never be finished")
	Test.check(mentions(report, "cycle: 2 slots can never be placed"), table.concat(report.errors, "\n"))
end)

Test.case("rejects a block that floats", function()
	local report = validate(source({ block(0, 0, 0), block(5, 2, 5) }))
	Test.check(mentions(report, "floats"), table.concat(report.errors, "\n"))
end)

Test.case("rejects two blocks in one cell", function()
	local report = validate(source({ block(0, 0, 0), block(0, 0, 0) }))
	Test.check(mentions(report, "overlaps slot 1"), table.concat(report.errors, "\n"))
end)

Test.case("rejects a block that supports itself", function()
	local report = validate(source({ block(0, 0, 0, { 1 }) }))
	Test.check(mentions(report, "supports itself"), table.concat(report.errors, "\n"))
end)

Test.case("rejects kinds outside the palette and bad facings", function()
	local report = validate({
		name = "Case",
		palette = { "a" },
		blocks = { { x = 0, y = 0, z = 0, kind = 2 }, { x = 1, y = 0, z = 0, kind = 1, facing = 4 } },
	})
	Test.check(mentions(report, "isn't in the palette"), table.concat(report.errors, "\n"))
	Test.check(mentions(report, "facing 4 isn't 0..3"), table.concat(report.errors, "\n"))
end)

Test.case("caps a site at 65,535 slots", function()
	local over = validate(Sites.floor(65536), { checkReach = false })
	Test.check(mentions(over, "more than the 65535"), table.concat(over.errors, "\n"))
	local full = validate(Sites.floor(65535))
	Test.check(full.ok, table.concat(full.errors, "\n"))
end)

Test.case("finds the top of a bare tower out of reach, and steps fix it", function()
	local bare = validate(Sites.tower(20, false), { graspCells = 5 })
	Test.check(not bare.ok, "a 20-cell column can't be reached from the ground")
	-- From the ground beside it, reach starts half a cell up and spans 5 cells, so layers 0..5 are in reach.
	Test.equal(bare.stats.unreachable, 14, "cells above the ground's reach")
	local stepped = validate(Sites.tower(20, true), { graspCells = 5 })
	Test.check(stepped.ok, table.concat(stepped.errors, "\n"))
end)

return nil
