--!strict
--[[
	BossEffects: what the boss and its helpers do to a site.

	Difficulty gives players things to go and do. None of these makes a block
	tougher or a wait longer: they undo exposed blocks, hold slots back until
	players act, and give up before the end.

	  undoNearest   undoes the exposed blocks nearest a point: the boss at work
	                where it stands, and its minions
	  burst         undoes every exposed block within a radius: a marker whose
	                fuse ran out
	  collapse      undoes a section from the top down. A block whose
	                dependents are all coming down is exposed in turn, so the
	                section empties as far as its blocks aren't held up by
	                blocks outside it. Blocks above the lowest ones undone drop
	                back to LOCKED at once, as BuildSite's rules say.
	  shieldCircle  raises or lowers a shield flag on every slot in an upright
	                cylinder: the peace circle, with Shield.BLOCKED
	  shieldBand    the same over a band across the site: stubborn slots, with
	                Shield.HAND_ONLY
	  relents       whether the site is built far enough for the boss to give
	                up, so a site can always be finished

	An exposed block is one BuildSite.canUndo allows: placed, with nothing
	placed resting on it. All in cell space (SiteConfig).
]]

local BuildSite = require("./BuildSite")
local SiteIndex = require("./SiteIndex")

local BossEffects = {}

type Site = BuildSite.Site
type Index = SiteIndex.Index

local Cause = BuildSite.Cause

local found: { number } = {}

local function undoAll(site: Site, n: number, speed: number, out: { number }): number
	local count = 0
	for i = 1, n do
		local s = found[i]
		if BuildSite.undo(site, s, speed, Cause.BOSS, 0) then
			count += 1
			out[count] = s
		end
	end
	return count
end

-- Undoes up to count exposed blocks nearest (x, y, z) within radius, at speed
-- progress per second. Returns how many it started, written to out.
function BossEffects.undoNearest(
	site: Site,
	index: Index,
	x: number,
	y: number,
	z: number,
	radius: number,
	count: number,
	speed: number,
	out: { number }
): number
	local n = SiteIndex.nearest(index, x, y, z, radius, function(s)
		return BuildSite.canUndo(site, s)
	end, count, found)
	return undoAll(site, n, speed, out)
end

-- Undoes every block exposed within radius of (x, y, z). Returns how many,
-- written to out.
function BossEffects.burst(
	site: Site,
	index: Index,
	x: number,
	y: number,
	z: number,
	radius: number,
	speed: number,
	out: { number }
): number
	local n = SiteIndex.within(index, x, y, z, radius, function(s)
		return BuildSite.canUndo(site, s)
	end, found)
	return undoAll(site, n, speed, out)
end

-- Undoes up to maxBlocks placed blocks whose centres lie in the box from
-- (x0, y0, z0) inclusive to (x1, y1, z1) exclusive, highest first. Returns
-- how many, written to out.
function BossEffects.collapse(
	site: Site,
	index: Index,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	maxBlocks: number,
	speed: number,
	out: { number }
): number
	local n = SiteIndex.inBox(index, x0, y0, z0, x1, y1, z1, function(s)
		return BuildSite.isPlaced(site, s)
	end, found)
	for i = n + 1, #found do
		found[i] = nil
	end
	local y = index.blueprint.y
	table.sort(found, function(a, b)
		local ya, yb = y[a], y[b]
		return ya > yb or (ya == yb and a < b)
	end)
	-- Each pass undoes what has become exposed. Highest first means one pass
	-- usually clears a column; more passes catch blocks held by a neighbour.
	local count = 0
	local progressed = true
	while progressed and count < maxBlocks do
		progressed = false
		for i = 1, n do
			if count >= maxBlocks then
				break
			end
			local s = found[i]
			if BuildSite.undo(site, s, speed, Cause.BOSS, 0) then
				count += 1
				out[count] = s
				progressed = true
			end
		end
	end
	return count
end

-- Raises (on) or lowers a shield flag on every slot whose centre lies within
-- radius of (cx, cz) seen from above, at every height. Returns how many slots.
function BossEffects.shieldCircle(
	site: Site,
	index: Index,
	cx: number,
	cz: number,
	radius: number,
	flag: number,
	on: boolean
): number
	local bp = index.blueprint
	local r2 = radius * radius
	local far = radius + 1e-6
	local n = SiteIndex.inBox(index, cx - radius, 0, cz - radius, cx + far, bp.sizeY, cz + far, function(s)
		local dx, dz = bp.x[s] + 0.5 - cx, bp.z[s] + 0.5 - cz
		return dx * dx + dz * dz <= r2
	end, found)
	for i = 1, n do
		BuildSite.flagShield(site, found[i], flag, on)
	end
	return n
end

-- Raises (on) or lowers a shield flag on every slot in a band across the
-- site: lo <= x < hi for axis 1, lo <= z < hi for axis 3, at every height.
-- Returns how many slots.
function BossEffects.shieldBand(
	site: Site,
	index: Index,
	axis: number,
	lo: number,
	hi: number,
	flag: number,
	on: boolean
): number
	local bp = index.blueprint
	local x0, x1, z0, z1 = 0, bp.sizeX, 0, bp.sizeZ
	if axis == 1 then
		x0, x1 = lo, hi
	else
		z0, z1 = lo, hi
	end
	local n = SiteIndex.inBox(index, x0, 0, z0, x1, bp.sizeY, z1, function()
		return true
	end, found)
	for i = 1, n do
		BuildSite.flagShield(site, found[i], flag, on)
	end
	return n
end

-- Whether the share of blocks placed has reached threshold, past which the
-- boss gives up.
function BossEffects.relents(site: Site, threshold: number): boolean
	return BuildSite.percent(site) >= threshold
end

return BossEffects
