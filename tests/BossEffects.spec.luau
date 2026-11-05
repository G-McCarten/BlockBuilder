local Blueprint = require("../src/shared/Blueprint")
local BossEffects = require("../src/shared/BossEffects")
local BuildSite = require("../src/shared/BuildSite")
local SiteIndex = require("../src/shared/SiteIndex")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Shield = BuildSite.Shield
local State = BuildSite.State

local function dist2(bp: Blueprint.Blueprint, s: number, x: number, y: number, z: number): number
	return (bp.x[s] + 0.5 - x) ^ 2 + (bp.y[s] + 0.5 - y) ^ 2 + (bp.z[s] + 0.5 - z) ^ 2
end

Test.group("BossEffects")

Test.case("undoNearest undoes the exposed blocks nearest the boss, and only those", function()
	local rng = Rng.new(4)
	local bp = Sites.lodge()
	local index = SiteIndex.build(bp, 8)
	for trial = 1, 30 do
		local site = Sites.partlyBuilt(bp, trial, 3000)
		local x, y, z = rng:range(0, bp.sizeX), rng:range(0, 12), rng:range(0, bp.sizeZ)
		local radius, count = rng:range(2, 10), rng:int(1, 6)
		local exposed = {}
		for s = 1, bp.count do
			if BuildSite.canUndo(site, s) and dist2(bp, s, x, y, z) <= radius * radius then
				table.insert(exposed, { s, dist2(bp, s, x, y, z) })
			end
		end
		table.sort(exposed, function(a, b)
			return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1])
		end)
		local before = Sites.snapshot(site)
		local out = {}
		local n = BossEffects.undoNearest(site, index, x, y, z, radius, count, 2, out)
		Test.equal(n, math.min(count, #exposed), "how many")
		local undone = {}
		for i = 1, n do
			Test.equal(out[i], exposed[i][1], `nearest #{i}`)
			Test.equal(BuildSite.state(site, out[i]), State.UNDOING, "undoing")
			undone[out[i]] = true
		end
		for s = 1, bp.count do
			if not undone[s] and BuildSite.isPlaced(site, s) ~= (before.rate[s] == 0 and before.progress[s] >= 1) then
				error(`slot {s} changed without being undone`)
			end
		end
		Sites.checkRules(site)
	end
end)

Test.case("a burst undoes every block exposed in its radius", function()
	local bp = Sites.lodge()
	local index = SiteIndex.build(bp, 8)
	local site = Sites.partlyBuilt(bp, 7, 4000)
	local x, y, z = 16, 4, 14
	local wanted = {}
	for s = 1, bp.count do
		if BuildSite.canUndo(site, s) and dist2(bp, s, x, y, z) <= 36 then
			wanted[s] = true
		end
	end
	local out = {}
	local n = BossEffects.burst(site, index, x, y, z, 6, math.huge, out)
	local got = 0
	for i = 1, n do
		Test.check(wanted[out[i]], `slot {out[i]} wasn't exposed in range`)
		got += 1
	end
	for s in wanted do
		Test.check(not BuildSite.isPlaced(site, s), `exposed slot {s} still stands`)
	end
	Test.check(got > 0, "the burst hit something")
	Sites.checkRules(site)
end)

Test.case("a collapse brings a section down from the top", function()
	local bp = Sites.hut()
	local index = SiteIndex.build(bp, 8)
	local site = Sites.finished(bp)
	local roof = 0
	for s = 1, bp.count do
		if bp.y[s] >= 5 then
			roof += 1
		end
	end
	local out = {}
	local n = BossEffects.collapse(site, index, 0, 5, 0, bp.sizeX, bp.sizeY, bp.sizeZ, math.huge, 1, out)
	Test.equal(n, roof, "every roof block came down")
	for s = 1, bp.count do
		Test.equal(BuildSite.isPlaced(site, s), bp.y[s] < 5, `slot {s} at layer {bp.y[s]}`)
	end
	Sites.checkRules(site)

	local budgeted = Sites.finished(bp)
	Test.equal(BossEffects.collapse(budgeted, index, 0, 5, 0, bp.sizeX, bp.sizeY, bp.sizeZ, 30, 1, {}), 30, "budget")
	Sites.checkRules(budgeted)
end)

Test.case("a collapse leaves blocks that something outside it still rests on", function()
	local bp = Sites.hut()
	local index = SiteIndex.build(bp, 8)
	local site = Sites.finished(bp)
	-- The walls' layers over the room's footprint, x and z 2..10: the roof above still rests on them.
	local n = BossEffects.collapse(site, index, 2, 1, 2, 11, 5, 11, math.huge, 1, {})
	Test.equal(n, 0, "nothing in the walls is exposed while the roof stands")
end)

Test.case("shields cover their circle or band, and lifting one keeps the other", function()
	local bp = Sites.lodge()
	local index = SiteIndex.build(bp, 8)
	local site = BuildSite.new(bp)
	local circle = BossEffects.shieldCircle(site, index, 16, 14, 4, Shield.BLOCKED, true)
	local band = BossEffects.shieldBand(site, index, 1, 14, 18, Shield.HAND_ONLY, true)
	local inCircle, inBand = 0, 0
	for s = 1, bp.count do
		local dx, dz = bp.x[s] + 0.5 - 16, bp.z[s] + 0.5 - 14
		local c = dx * dx + dz * dz <= 16
		local b = bp.x[s] + 0.5 >= 14 and bp.x[s] + 0.5 < 18
		inCircle += if c then 1 else 0
		inBand += if b then 1 else 0
		Test.equal(site.shield[s], (if b then Shield.HAND_ONLY else 0) + (if c then Shield.BLOCKED else 0), `slot {s}`)
	end
	Test.equal(circle, inCircle, "circle count")
	Test.equal(band, inBand, "band count")
	BossEffects.shieldCircle(site, index, 16, 14, 4, Shield.BLOCKED, false)
	for s = 1, bp.count do
		local b = bp.x[s] + 0.5 >= 14 and bp.x[s] + 0.5 < 18
		Test.equal(site.shield[s], if b then Shield.HAND_ONLY else 0, `slot {s} after the circle lifts`)
	end
end)

Test.case("the boss relents once enough is built", function()
	local bp = Sites.hut()
	local site = Sites.finished(bp)
	Test.check(BossEffects.relents(site, 0.97), "finished")
	Test.check(not BossEffects.relents(BuildSite.new(bp), 0.97), "not started")
end)

return nil
