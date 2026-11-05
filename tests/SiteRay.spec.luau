local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local SiteRay = require("../src/shared/SiteRay")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local State = BuildSite.State
local Cause = BuildSite.Cause

-- The reference: every cell the ray crosses, found by intersecting the ray
-- with each slot's box, walked in order of entry.
local function reference(
	bp: Blueprint.Blueprint,
	site: BuildSite.Site,
	o: { number },
	d: { number },
	maxT: number,
	p: { number },
	grasp: number
): (number?, number)
	local len = math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
	local u = { d[1] / len, d[2] / len, d[3] / len }
	local hits = {}
	for s = 1, bp.count do
		local lo, hi = 0, maxT
		local cell = { bp.x[s], bp.y[s], bp.z[s] }
		for a = 1, 3 do
			if u[a] == 0 then
				if o[a] < cell[a] or o[a] >= cell[a] + 1 then
					lo, hi = 1, 0
				end
			else
				local t0, t1 = (cell[a] - o[a]) / u[a], (cell[a] + 1 - o[a]) / u[a]
				if t0 > t1 then
					t0, t1 = t1, t0
				end
				lo, hi = math.max(lo, t0), math.min(hi, t1)
			end
		end
		if lo < hi then
			table.insert(hits, { s, lo })
		end
	end
	table.sort(hits, function(a, b)
		return a[2] < b[2]
	end)
	for _, hit in hits do
		local s = hit[1]
		local state = BuildSite.state(site, s)
		if state == State.PLACED or state == State.UNDOING then
			return nil, hit[2]
		elseif state == State.READY or state == State.SETTING then
			local ex, ey, ez = bp.x[s] + 0.5 - p[1], bp.y[s] + 0.5 - p[2], bp.z[s] + 0.5 - p[3]
			if ex * ex + ey * ey + ez * ez <= grasp * grasp then
				return s, hit[2]
			end
		end
	end
	return nil, maxT
end

local function cast(bp, site, o, d, maxT, p, grasp)
	return SiteRay.cast(bp, site, o[1], o[2], o[3], d[1], d[2], d[3], maxT, p[1], p[2], p[3], grasp)
end

Test.group("SiteRay")

Test.case("takes a READY slot in reach, and stops at a placed block", function()
	local bp = Sites.hut()
	local site = BuildSite.new(bp)
	local floor = Blueprint.slotAt(bp, 5, 0, 5) :: number
	-- Looking straight down at the floor from above.
	local slot, t = cast(bp, site, { 5.5, 9.5, 5.5 }, { 0, -1, 0 }, 50, { 5.5, 3, 5.5 }, 5)
	Test.equal(slot, floor, "the floor slot below")
	Test.check(math.abs(t - 8.5) < 1e-9, `hit its top face, t {t}`)

	BuildSite.place(site, floor, Cause.HAND, 1)
	slot, t = cast(bp, site, { 5.5, 9.5, 5.5 }, { 0, -1, 0 }, 50, { 5.5, 3, 5.5 }, 5)
	Test.equal(slot, nil, "a placed block stops the ray")
	Test.check(math.abs(t - 8.5) < 1e-9, `at its top face, t {t}`)
end)

Test.case("passes through LOCKED ghosts and slots beyond grasp", function()
	local bp = Sites.hut()
	local site = BuildSite.new(bp)
	-- Along the front wall's row at y = 1, from outside the hut at low x.
	local origin, dir = { -3, 1.5, 2.5 }, { 1, 0, 0 }
	local slot = cast(bp, site, origin, dir, 50, { 6.5, 2, 2.5 }, 5)
	Test.equal(slot, nil, "the whole wall row is LOCKED until the floor is down")

	for x = 2, 10 do
		BuildSite.place(site, Blueprint.slotAt(bp, x, 0, 2) :: number, Cause.HAND, 1)
	end
	Test.equal(
		BuildSite.state(site, Blueprint.slotAt(bp, 2, 1, 2) :: number),
		State.READY,
		"wall over the floor is READY"
	)
	slot = cast(bp, site, origin, dir, 50, { 9.5, 2, 2.5 }, 3)
	Test.equal(slot, Blueprint.slotAt(bp, 7, 1, 2), "first READY within 3 cells of a player at x 9.5")
end)

Test.case("misses the site and handles a zero direction", function()
	local bp = Sites.hut()
	local site = BuildSite.new(bp)
	Test.equal(cast(bp, site, { -5, 50, -5 }, { 0, 1, 0 }, 100, { 0, 0, 0 }, 5), nil, "pointing away")
	Test.equal(cast(bp, site, { 5, 5, 5 }, { 0, 0, 0 }, 100, { 5, 5, 5 }, 5), nil, "no direction")
	Test.equal(cast(bp, site, { 5.5, 9.5, 5.5 }, { 0, -1, 0 }, 2, { 5.5, 3, 5.5 }, 5), nil, "too short to reach")
end)

Test.case("matches a ray-box reference on random rays through part-built sites", function()
	local rng = Rng.new(77)
	local checked, taken, stopped = 0, 0, 0
	for _, bp in { Sites.lodge(), Sites.hut() } do
		for seed = 1, 3 do
			local site = Sites.partlyBuilt(bp, seed, bp.count // 3)
			for _ = 1, 400 do
				local o = { rng:range(-8, bp.sizeX + 8), rng:range(-2, bp.sizeY + 8), rng:range(-8, bp.sizeZ + 8) }
				-- Half the rays aim near a random READY slot, the rest anywhere in the site.
				local target = { rng:range(0, bp.sizeX), rng:range(0, bp.sizeY), rng:range(0, bp.sizeZ) }
				local aim = rng:int(1, bp.count)
				if rng:next() < 0.5 and BuildSite.state(site, aim) == State.READY then
					target = { bp.x[aim] + rng:next(), bp.y[aim] + rng:next(), bp.z[aim] + rng:next() }
				end
				local d = { target[1] - o[1], target[2] - o[2], target[3] - o[3] }
				local maxT = rng:range(5, 80)
				local p = { target[1] + rng:range(-3, 3), target[2] + rng:range(-3, 3), target[3] + rng:range(-3, 3) }
				local grasp = rng:range(2, 9)
				local slot, t = cast(bp, site, o, d, maxT, p, grasp)
				local wantSlot, wantT = reference(bp, site, o, d, maxT, p, grasp)
				Test.equal(slot, wantSlot, "slot")
				Test.check(math.abs(t - wantT) < 1e-6, `distance {t}, want {wantT}`)
				checked += 1
				if slot then
					taken += 1
				elseif t < maxT then
					stopped += 1
				end
			end
		end
	end
	print(`        {checked} rays: {taken} took a slot, {stopped} stopped at a block`)
	Test.check(taken > 100 and stopped > 100, "both outcomes are exercised")
end)

return nil
