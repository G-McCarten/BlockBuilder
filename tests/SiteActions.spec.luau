local Blueprint = require("../src/shared/Blueprint")
local BossEffects = require("../src/shared/BossEffects")
local BuildSite = require("../src/shared/BuildSite")
local SiteActions = require("../src/shared/SiteActions")
local SiteIndex = require("../src/shared/SiteIndex")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Cause = BuildSite.Cause
local State = BuildSite.State
local Shield = BuildSite.Shield

local function centreDist2(bp: Blueprint.Blueprint, s: number, px: number, py: number, pz: number): number
	return (bp.x[s] + 0.5 - px) ^ 2 + (bp.y[s] + 0.5 - py) ^ 2 + (bp.z[s] + 0.5 - pz) ^ 2
end

local function never()
	return 1
end
local function always()
	return 0
end

-- Two copies of the same part-built lodge, so one can run an action and the
-- other work out by hand what it should have done.
local function twins(seed: number, placements: number)
	local bp = Sites.lodge()
	return bp, SiteIndex.build(bp, 8), Sites.partlyBuilt(bp, seed, placements), Sites.partlyBuilt(bp, seed, placements)
end

local function pickReady(bp: Blueprint.Blueprint, site: BuildSite.Site, rng): number
	for _ = 1, 10000 do
		local s = rng:int(1, bp.count)
		if BuildSite.state(site, s) == State.READY then
			return s
		end
	end
	error("no READY slot found")
end

Test.group("SiteActions")

Test.case("a click places the aimed slot and the workable slots nearest it", function()
	local rng = Rng.new(3)
	local fullBatches = 0
	for trial = 1, 40 do
		local bp, index, site, twin = twins(trial, 1500)
		local aimed = pickReady(bp, site, rng)
		local stats = { batch = rng:int(1, 40), chainChance = 0, chainRadius = 0, setRate = 1 }
		local placed = {}
		local count = SiteActions.hand(site, index, aimed, stats, 7, never, placed)

		-- By hand: place the aimed slot, then take the eligible slots nearest
		-- its centre, anywhere on the site, wherever the player stands.
		BuildSite.place(twin, aimed, Cause.HAND, 7)
		local ax, ay, az = bp.x[aimed] + 0.5, bp.y[aimed] + 0.5, bp.z[aimed] + 0.5
		local eligible = {}
		for s = 1, bp.count do
			if BuildSite.canPlace(twin, s, Cause.BATCH) then
				table.insert(eligible, { s, centreDist2(bp, s, ax, ay, az) })
			end
		end
		table.sort(eligible, function(a, b)
			return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1])
		end)
		local want = math.min(stats.batch - 1, #eligible)
		if want == stats.batch - 1 then
			fullBatches += 1
		end
		Test.equal(count, 1 + want, "blocks placed")
		Test.equal(placed[1], aimed, "the aimed slot first")
		for i = 1, want do
			Test.equal(placed[1 + i], eligible[i][1], `batch pick {i}`)
			Test.equal(site.cause[placed[1 + i]], Cause.BATCH, "batch cause")
		end
		Test.equal(site.cause[aimed], Cause.HAND, "hand cause")
		Sites.checkRules(site)
	end
	Test.equal(fullBatches, 40, "a part-built lodge has work for every batch")
end)

Test.case("a big batch takes the nearest workable slots wherever they lie, past the player's grasp", function()
	-- Two rows of ground blocks, 60 cells apart, as work lies late in a big
	-- build: in patches, such as the tops of towers, far from one another.
	local blocks = {}
	for x = 0, 4 do
		table.insert(blocks, { x = x, y = 0, z = 0, kind = "a" })
		table.insert(blocks, { x = 60 + x, y = 0, z = 0, kind = "a" })
	end
	local bp = Blueprint.build({ name = "Apart", palette = { "a" }, blocks = blocks })
	local index = SiteIndex.build(bp, 8)
	local site = BuildSite.new(bp)
	local function at(x: number): number
		return Blueprint.slotAt(bp, x, 0, 0) :: number
	end
	local stats = { batch = 8, chainChance = 0, chainRadius = 0, setRate = 1 }
	local placed = {}
	Test.equal(SiteActions.hand(site, index, at(0), stats, 1, never, placed), 8, "a full batch")
	-- The aimed row first, nearest first, then the nearest of the far row.
	for i, x in { 0, 1, 2, 3, 4, 60, 61, 62 } do
		Test.equal(placed[i], at(x), `block {i} at x {x}`)
	end
	Test.check(not BuildSite.isPlaced(site, at(63)), "no more than the batch")
	Sites.checkRules(site)
end)

Test.case("a click on a slot that can't be placed does nothing", function()
	local bp, index, site = twins(1, 500)
	local locked
	for s = 1, bp.count do
		if BuildSite.state(site, s) == State.LOCKED then
			locked = s
			break
		end
	end
	local before = site.placedCount
	local stats = { batch = 5, chainChance = 1, chainRadius = 3, setRate = 1 }
	Test.equal(SiteActions.hand(site, index, locked, stats, 1, always, {}), 0, "nothing placed")
	Test.equal(site.placedCount, before, "site unchanged")
end)

Test.case("batch skips stubborn slots, which only the aimed click can take", function()
	local bp = Sites.hut()
	local index = SiteIndex.build(bp, 8)
	local site = BuildSite.new(bp)
	local aimed = Blueprint.slotAt(bp, 5, 0, 5) :: number
	BossEffects.shieldBand(site, index, 1, 0, bp.sizeX, Shield.HAND_ONLY, true)
	local placed = {}
	local stats = { batch = 10, chainChance = 0, chainRadius = 0, setRate = 1 }
	local count = SiteActions.hand(site, index, aimed, stats, 1, never, placed)
	Test.equal(count, 1, "only the aimed block")
	Test.check(BuildSite.isPlaced(site, aimed), "a player's own click takes a stubborn slot")
end)

Test.case("a chain starts every READY slot within its radius setting", function()
	local bp, index, site = twins(5, 2000)
	local rng = Rng.new(8)
	local aimed = pickReady(bp, site, rng)
	local stats = { batch = 1, chainChance = 1, chainRadius = 3, setRate = 0.5 }
	local placed = {}
	local before = Sites.snapshot(site)
	local count, started = SiteActions.hand(site, index, aimed, stats, 1, always, placed)
	Test.equal(count, 1, "one block")
	local ax, ay, az = bp.x[aimed] + 0.5, bp.y[aimed] + 0.5, bp.z[aimed] + 0.5
	local setting = 0
	for s = 1, bp.count do
		local inside = centreDist2(bp, s, ax, ay, az) <= 9
		if inside then
			Test.check(BuildSite.state(site, s) ~= State.READY, `slot {s} in the chain's reach is still READY`)
		end
		if site.rate[s] > 0 and before.rate[s] == 0 then
			Test.equal(site.cause[s], Cause.CHAIN, "the chain's cause")
			Test.check(inside, `slot {s} set outside the chain's reach`)
			Test.equal(site.rate[s], 0.5, "the chain's rate")
			setting += 1
		end
	end
	Test.equal(setting, started, "every slot started is counted")
	Test.check(started > 0, "the chain found work")
	Sites.checkRules(site)
end)

Test.case("a sweep places everything it can in its band, at every height, and nothing outside", function()
	local bp, index, site = twins(2, 0)
	local before = Sites.snapshot(site)
	local placed = {}
	local count = SiteActions.sweep(site, index, 1, 10, 14, 3, math.huge, placed)
	Test.check(count > 100, `placed a band of the lodge, got {count}`)
	local tallest = 0
	for s = 1, bp.count do
		local cx = bp.x[s] + 0.5
		local inBand = cx >= 10 and cx < 14
		if inBand then
			Test.check(not BuildSite.canPlace(site, s, Cause.ABILITY), `slot {s} in the band is still placeable`)
			if BuildSite.isPlaced(site, s) then
				tallest = math.max(tallest, bp.y[s])
			end
		else
			Test.equal(site.progress[s], before.progress[s], `slot {s} outside the band changed`)
		end
	end
	Test.check(tallest >= 20, `the band climbed the lodge to layer {tallest}`)
	Sites.checkRules(site)

	local _, _, budgeted = twins(2, 0)
	Test.equal(SiteActions.sweep(budgeted, index, 3, 0, bp.sizeZ, 3, 25, {}), 25, "stops at its budget")
end)

Test.case("the power tool places what was workable in its arc and starts the band beyond it", function()
	local bp, index, site = twins(4, 2500)
	local px, py, pz = 16.5, 3, 2.5
	local fx, fz = 0, 1
	local stats = { radius = 5, halfAngle = math.rad(50), band = 3, setRate = 0.25 }
	local cosHalf = math.cos(stats.halfAngle)
	local function region(s: number): string
		local d2 = centreDist2(bp, s, px, py, pz)
		local dx, dz = bp.x[s] + 0.5 - px, bp.z[s] + 0.5 - pz
		local flat = math.sqrt(dx * dx + dz * dz)
		local ahead = flat < 1e-9 or (dx * fx + dz * fz) / flat >= cosHalf
		if ahead and d2 <= stats.radius ^ 2 then
			return "arc"
		elseif ahead and d2 <= (stats.radius + stats.band) ^ 2 then
			return "band"
		end
		return "out"
	end
	local workable = {}
	for s = 1, bp.count do
		workable[s] = BuildSite.canPlace(site, s, Cause.TOOL)
	end
	local before = Sites.snapshot(site)
	local placed = {}
	local count, started = SiteActions.arc(site, index, px, py, pz, fx, fz, stats, 2, placed)
	Test.check(count > 0, "placed something")
	for i = 1, count do
		local s = placed[i]
		Test.check(workable[s] and region(s) == "arc", `slot {s} placed but wasn't workable in the arc`)
	end
	local bandStarted = 0
	for s = 1, bp.count do
		local where = region(s)
		if where == "arc" and workable[s] then
			Test.check(BuildSite.isPlaced(site, s), `workable slot {s} in the arc wasn't placed`)
		elseif where == "band" then
			if site.rate[s] > 0 and before.rate[s] == 0 then
				bandStarted += 1
			end
		elseif where == "out" then
			Test.equal(site.progress[s], before.progress[s], `slot {s} outside the arc changed progress`)
			Test.equal(site.rate[s], before.rate[s], `slot {s} outside the arc changed rate`)
		end
	end
	Test.equal(bandStarted, started, "the band's starts")
	Sites.checkRules(site)
end)

Test.case("a pet goes for the nearest slot it can place, and works around it", function()
	local rng = Rng.new(21)
	for trial = 1, 20 do
		local bp, index, site = twins(trial, 1000)
		local x, y, z = rng:range(0, bp.sizeX), rng:range(0, 10), rng:range(0, bp.sizeZ)
		local leash = rng:range(2, 12)
		local target = SiteActions.forageTarget(site, index, x, y, z, leash)
		local best, bestD = nil, math.huge
		for s = 1, bp.count do
			local d = centreDist2(bp, s, x, y, z)
			if d <= leash * leash and BuildSite.canPlace(site, s, Cause.PET) and d < bestD then
				best, bestD = s, d
			end
		end
		Test.equal(target, best, "nearest within leash")
		if target then
			local placed = {}
			local workable = {}
			for s = 1, bp.count do
				workable[s] = BuildSite.canPlace(site, s, Cause.PET)
			end
			local count, started = SiteActions.forage(site, index, target, 2, 4, 0.5, 9, placed)
			Test.check(count >= 1 and placed[1] == target, "the target first")
			local tx, ty, tz = bp.x[target] + 0.5, bp.y[target] + 0.5, bp.z[target] + 0.5
			for s = 1, bp.count do
				local inReach = centreDist2(bp, s, tx, ty, tz) <= 4
				if inReach and workable[s] then
					Test.check(BuildSite.isPlaced(site, s), `workable slot {s} in the pet's reach wasn't placed`)
				end
			end
			for i = 1, count do
				Test.check(workable[placed[i]], `slot {placed[i]} wasn't workable before the pet came`)
			end
			Test.check(started >= 0, "ring")
			Sites.checkRules(site)
		end
	end
end)

Test.case("random actions and boss effects never break the site's rules", function()
	local rng = Rng.new(99)
	local bp = Sites.lodge()
	local index = SiteIndex.build(bp, 8)
	local site = BuildSite.new(bp)
	local firstPays = table.create(bp.count, 0)
	site.onPlaced = function(s, first)
		if first then
			firstPays[s] += 1
			assert(firstPays[s] == 1, `slot {s} paid twice`)
		end
	end
	local random = function()
		return rng:next()
	end
	local out = {}
	local counts = { hand = 0, sweep = 0, arc = 0, forage = 0, undone = 0 }
	for op = 1, 3000 do
		local roll = rng:next()
		local px, py, pz = rng:range(0, bp.sizeX), rng:range(1, bp.sizeY), rng:range(0, bp.sizeZ)
		if roll < 0.35 then
			local n = SiteIndex.nearest(index, px, py, pz, 6, function(s)
				return BuildSite.canPlace(site, s, Cause.HAND)
			end, 1, out)
			if n > 0 then
				local stats = { batch = rng:int(1, 6), chainChance = 0.3, chainRadius = 2, setRate = 1 }
				counts.hand += SiteActions.hand(site, index, out[1], stats, 1, random, {})
			end
		elseif roll < 0.45 then
			local lo = rng:range(0, bp.sizeX)
			counts.sweep += SiteActions.sweep(site, index, 1, lo, lo + 2, 1, 40, {})
		elseif roll < 0.52 then
			local stats = { radius = 4, halfAngle = math.rad(45), band = 2, setRate = 0.5 }
			counts.arc += SiteActions.arc(site, index, px, py, pz, rng:range(-1, 1), rng:range(-1, 1), stats, 1, {})
		elseif roll < 0.62 then
			local target = SiteActions.forageTarget(site, index, px, py, pz, 8)
			if target then
				counts.forage += SiteActions.forage(site, index, target, 1.5, 3, 0.5, 1, {})
			end
		elseif roll < 0.75 then
			counts.undone += BossEffects.undoNearest(site, index, px, py, pz, 6, rng:int(1, 4), rng:range(0.5, 3), {})
		elseif roll < 0.8 then
			counts.undone += BossEffects.burst(site, index, px, py, pz, 3, rng:range(0.5, 3), {})
		elseif roll < 0.82 then
			counts.undone += BossEffects.collapse(site, index, px - 3, 0, pz - 3, px + 3, bp.sizeY, pz + 3, 60, 2, {})
		elseif roll < 0.86 then
			BossEffects.shieldCircle(site, index, px, pz, 4, Shield.BLOCKED, rng:next() < 0.5)
		elseif roll < 0.88 then
			BossEffects.shieldBand(site, index, 3, pz, pz + 2, Shield.HAND_ONLY, rng:next() < 0.5)
		else
			BuildSite.step(site, rng:range(0.05, 0.5))
		end
		if op % 50 == 0 then
			Sites.checkRules(site)
		end
	end
	Sites.checkRules(site)
	print(
		`        3000 ops: {counts.hand} by hand, {counts.sweep} by sweep, {counts.arc} by arc, `
			.. `{counts.forage} by pets, {counts.undone} undone, {site.placedCount} of {bp.count} standing`
	)
end)

return nil
