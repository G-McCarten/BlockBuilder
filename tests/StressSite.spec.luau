--[[
	The stress test's generated sites: the size asked for, a blueprint the
	validator accepts, the same blocks every time, and the shape of real
	builds.
]]

local Blueprint = require("../src/shared/Blueprint")
local BlueprintValidator = require("../src/shared/BlueprintValidator")
local BuildSite = require("../src/shared/BuildSite")
local KindLooks = require("../src/shared/KindLooks")
local SiteConfig = require("../src/shared/SiteConfig")
local StressSite = require("../src/shared/StressSite")
local Test = require("./lib/Test")

local function validate(bp)
	return BlueprintValidator.validate(bp, {
		graspCells = SiteConfig.BASE_GRASP_CELLS,
		headroomCells = SiteConfig.HEADROOM_CELLS,
	})
end

Test.group("StressSite")

Test.case("counts land within 2% of the target, from 1,000 to 65,535", function()
	for _, target in { 1000, 1234, 5000, 9999, 20000, 47000, 65535 } do
		local n = #StressSite.source(target).blocks
		Test.check(math.abs(n - target) <= target * 0.02, `{target} asked, {n} made`)
		Test.equal(n, target, "the street is paved to make up the count exactly")
	end
	Test.equal(#StressSite.source(10).blocks, StressSite.MIN_BLOCKS, "too few is raised to the least")
	Test.equal(#StressSite.source(1e6).blocks, StressSite.MAX_BLOCKS, "too many is cut to what a u16 can name")
end)

Test.case("every size passes the validator with the base grasp and headroom", function()
	for _, target in { 1000, 5000, 20000, 65535 } do
		local bp = Blueprint.build(StressSite.source(target))
		local report = validate(bp)
		Test.check(report.ok, `{target}: {table.concat(report.errors, "\n")}`)
		Test.check(report.stats.extraSupports > 0, `{target}: some extra ordering`)
		Test.check(report.stats.overhangs > 0, `{target}: floors resting on their walls`)
		-- The prototype's baseplate reaches 105 cells past the site's origin along x, 99 along z.
		Test.check(bp.sizeX <= 105 and bp.sizeZ <= 99, `{target}: {bp.sizeX} by {bp.sizeZ} fits the baseplate`)
	end
end)

Test.case("the same count makes the same blocks", function()
	local a, b = StressSite.source(12345), StressSite.source(12345)
	Test.equal(#a.blocks, #b.blocks, "as many blocks")
	for i, block in a.blocks do
		local other = b.blocks[i]
		local same = block.x == other.x and block.y == other.y and block.z == other.z and block.kind == other.kind
		Test.check(same, `block {i} differs`)
		Test.equal(#(block.after or {}), #(other.after or {}), `block {i}'s ordering`)
		for k, s in block.after or {} do
			Test.equal(s, (other.after :: { number })[k], `block {i}'s ordering`)
		end
	end
	Test.equal(Blueprint.encode(Blueprint.build(a)), Blueprint.encode(Blueprint.build(b)), "packed alike")
end)

Test.case("it's a district of hollow buildings with floors, roofs and several kinds", function()
	local bp = Blueprint.build(StressSite.source(20000))
	local used, perLayer = {}, {}
	for s = 1, bp.count do
		local kind = bp.palette[bp.kind[s]]
		used[kind] = (used[kind] or 0) + 1
		perLayer[bp.y[s]] = (perLayer[bp.y[s]] or 0) + 1
	end
	for kind in used do
		Test.check(KindLooks[kind] ~= nil, `{kind} has a look`)
	end
	for _, kind in { "stone", "timber", "glass", "slate", "thatch", "lantern" } do
		Test.check((used[kind] or 0) > 0, `some {kind}`)
	end
	-- A lamp post at each lot's corner, each lot a building.
	Test.check(used.lantern >= 10, `{used.lantern} lots`)
	-- Floors fill each storey's first layer; between them only walls stand.
	Test.check(perLayer[2] < perLayer[0] * 0.4, `hollow: {perLayer[2]} blocks mid-storey, {perLayer[0]} on the floor`)
	Test.check(perLayer[4] > perLayer[2] * 2, "an upper floor")
	Test.check(bp.count < bp.sizeX * bp.sizeY * bp.sizeZ * 0.25, "mostly air, as a street of buildings is")
	Test.check(bp.sizeY > 30, `{bp.sizeY} layers tall`)
end)

Test.case("layOrder lays everything below the top layer, each block after its supports", function()
	local bp = Blueprint.build(StressSite.source(5000))
	local top = bp.sizeY - 1
	local below = 0
	for s = 1, bp.count do
		if bp.y[s] < top then
			below += 1
		end
	end
	local order = StressSite.layOrder(bp)
	Test.equal(#order, below, "every slot below the top layer")
	local site = BuildSite.new(bp)
	for _, s in order do
		Test.check(bp.y[s] < top, `slot {s} is below the top layer`)
		Test.check(BuildSite.place(site, s, BuildSite.Cause.NONE, 0), `slot {s} lays when its turn comes`)
	end
	Test.equal(site.placedCount, below, "all of it stands")
	local ready = 0
	for s = 1, bp.count do
		if BuildSite.state(site, s) == BuildSite.State.READY then
			ready += 1
		end
	end
	Test.check(ready > 0 and ready == bp.count - below, `the top layer's {bp.count - below} are left to lay`)
end)

Test.case("plan reads a StressTest value, and ids name a size", function()
	local function plan(value: any): string
		local sizes, ladder = StressSite.plan(value)
		return if sizes then `{table.concat(sizes, ",")} {ladder}` else "nil"
	end
	Test.equal(plan(5000), "5000 false", "a number plays one site")
	Test.equal(plan("12000"), "12000 false", "so does a string holding one")
	Test.equal(plan(50), "1000 false", "raised to the least")
	Test.equal(plan(1e6), "65535 false", "cut to the most")
	Test.equal(plan("Ladder"), `{table.concat(StressSite.LADDER, ",")} true`, "the ladder")
	Test.equal(plan(" ladder "), `{table.concat(StressSite.LADDER, ",")} true`, "in any case")
	Test.equal(plan("1000, 2000"), "1000,2000 true", "a ladder of one's own")
	for _, value in { "nonsense", "", "Ladder please", true, 0 / 0 } do
		Test.equal(plan(value), "nil", `{tostring(value)} asks for nothing`)
	end
	Test.equal(plan(nil), "nil", "nor does no value")

	Test.equal(StressSite.parse(StressSite.id(5000)), 5000, "an id names its size")
	Test.equal(StressSite.id(64000.2), "Stress:64000", "a whole size")
	Test.equal(StressSite.parse("GreatHall"), nil, "a stamped site isn't one")
	Test.equal(StressSite.parse("Stress:12"), nil, "nor is a size out of range")
	Test.equal(StressSite.name(65535), "Stress test 65,535", "named for the sign")

	Test.equal(StressSite.stepSeconds(nil), StressSite.STEP_SECONDS, "a step holds 20 s unless told")
	Test.equal(StressSite.stepSeconds(3), 3, "or as long as it's told")
	Test.equal(StressSite.stepSeconds(-1), StressSite.STEP_SECONDS, "but never no time")
	local ladder = StressSite.LADDER
	Test.equal(#ladder, 8, "eight steps")
	Test.equal(ladder[1], 5000, "from 5,000")
	Test.equal(ladder[#ladder], 65535, "to the most")
	for i = 2, #ladder do
		Test.check(ladder[i] > ladder[i - 1], "rising")
	end
end)

return nil
