--!strict
--[[
	SiteActions: how each kind of work lays blocks on a site.

	Every action works through BuildSite, so the site's rules hold whatever an
	action does. Actions take their numbers as arguments; the skill tree, pets
	and configs supply them.

	  hand          a player's click: the aimed slot, then the nearest READY or
	                SETTING slots within grasp up to the batch size. Each block
	                placed may start a chain.
	  chain         starts every READY slot within a radius of a block setting
	  sweep         the ABILITY's band: places workable slots across a band of
	                the site at every height
	  arc           the POWER_TOOL: places everything workable in an arc in
	                front of the player, and starts a band beyond it setting
	  forageTarget  where a pet goes: the nearest slot it can place within leash
	  forage        what a pet does there: places the target and everything
	                within reach, and starts a ring around it setting

	The arc and a pet's work take what is workable when they act, the ghost
	layer in front of them, never what their own placing readies. A click's
	batch is chosen just after the aimed block lands, so it can include the
	block that one readied. A band is different again, because it dwells: it
	places lowest first and keeps going while that readies more, up to the
	budget it is given, which its caller sets from a rate in blocks per second
	so the band is as strong at any tick rate.

	Actions write the slots they place into an output list, so the caller can
	tally them and play effects. Pay stays with BuildSite.onPlaced, which says
	which placements are first ones.

	All in cell space (SiteConfig). random is a function returning [0, 1).
]]

local BuildSite = require("./BuildSite")
local SiteIndex = require("./SiteIndex")

local SiteActions = {}

local Cause = BuildSite.Cause
local State = BuildSite.State

type Site = BuildSite.Site
type Index = SiteIndex.Index

export type HandStats = {
	-- Reach from the player's root, in cells.
	grasp: number,
	-- Blocks a click places, the aimed one included.
	batch: number,
	-- Chance each block placed starts a chain.
	chainChance: number,
	-- Cells around the block a chain reaches.
	chainRadius: number,
	-- Progress per second of blocks a chain starts: 1 / setTime.
	setRate: number,
}

export type ArcStats = {
	-- Cells from the player's root the arc places out to.
	radius: number,
	-- Half the arc's width seen from above, in radians.
	halfAngle: number,
	-- Depth in cells of the band beyond the arc that starts setting.
	band: number,
	setRate: number,
}

-- Scratch lists. Actions don't call one another while using the same one.
local found: { number } = {}
local ringFound: { number } = {}

local function centre(index: Index, s: number): (number, number, number)
	local bp = index.blueprint
	return bp.x[s] + 0.5, bp.y[s] + 0.5, bp.z[s] + 0.5
end

-- Sorts the first n slots of list by layer, then slot.
local function lowestFirst(index: Index, list: { number }, n: number)
	local y = index.blueprint.y
	for i = n + 1, #list do
		list[i] = nil
	end
	table.sort(list, function(a, b)
		local ya, yb = y[a], y[b]
		return ya < yb or (ya == yb and a < b)
	end)
end

-- Places the first n slots of list that cause may place, in order, appending
-- them to placed after count, and goes over the list again while that places
-- more, up to maxPlace in all. Returns the new count.
local function placeAll(
	site: Site,
	list: { number },
	n: number,
	cause: number,
	causer: number,
	placed: { number },
	count: number,
	maxPlace: number
): number
	local progressed = true
	while progressed and count < maxPlace do
		progressed = false
		for i = 1, n do
			if count >= maxPlace then
				break
			end
			local s = list[i]
			if BuildSite.place(site, s, cause, causer) then
				count += 1
				placed[count] = s
				progressed = true
			end
		end
	end
	return count
end

-- Places the first n slots of list that cause may place, once through, in
-- order, appending them to placed after count. Returns the new count.
local function placeOnce(
	site: Site,
	list: { number },
	n: number,
	cause: number,
	causer: number,
	placed: { number },
	count: number
): number
	for i = 1, n do
		local s = list[i]
		if BuildSite.place(site, s, cause, causer) then
			count += 1
			placed[count] = s
		end
	end
	return count
end

function SiteActions.chain(site: Site, index: Index, slot: number, radius: number, rate: number, causer: number): number
	local cx, cy, cz = centre(index, slot)
	local n = SiteIndex.within(index, cx, cy, cz, radius, function(s)
		return BuildSite.state(site, s) == State.READY and BuildSite.canPlace(site, s, Cause.CHAIN)
	end, ringFound)
	local started = 0
	for i = 1, n do
		if BuildSite.startSetting(site, ringFound[i], rate, Cause.CHAIN, causer) then
			started += 1
		end
	end
	return started
end

-- Returns how many blocks it placed, written to placed, and how many it started setting.
function SiteActions.hand(
	site: Site,
	index: Index,
	slot: number,
	px: number,
	py: number,
	pz: number,
	stats: HandStats,
	causer: number,
	random: () -> number,
	placed: { number }
): (number, number)
	if not BuildSite.place(site, slot, Cause.HAND, causer) then
		return 0, 0
	end
	placed[1] = slot
	local count = 1

	if stats.batch > 1 then
		local bp = index.blueprint
		local grasp2 = stats.grasp * stats.grasp
		local cx, cy, cz = centre(index, slot)
		-- Anything in the player's grasp is within twice the grasp of the aimed slot.
		local n = SiteIndex.nearest(index, cx, cy, cz, 2 * stats.grasp, function(s)
			if not BuildSite.canPlace(site, s, Cause.BATCH) then
				return false
			end
			local dx, dy, dz = bp.x[s] + 0.5 - px, bp.y[s] + 0.5 - py, bp.z[s] + 0.5 - pz
			return dx * dx + dy * dy + dz * dz <= grasp2
		end, stats.batch - 1, found)
		count = placeOnce(site, found, n, Cause.BATCH, causer, placed, count)
	end

	local started = 0
	if stats.chainChance > 0 then
		for i = 1, count do
			if random() < stats.chainChance then
				started += SiteActions.chain(site, index, placed[i], stats.chainRadius, stats.setRate, causer)
			end
		end
	end
	return count, started
end

-- axis 1 runs the band along x, 3 along z: it covers lo <= coordinate < hi on
-- that axis, the whole site on the others. Places up to maxPlace blocks and
-- returns how many, written to placed.
function SiteActions.sweep(
	site: Site,
	index: Index,
	axis: number,
	lo: number,
	hi: number,
	causer: number,
	maxPlace: number,
	placed: { number }
): number
	local bp = index.blueprint
	local x0, x1, z0, z1 = 0, bp.sizeX, 0, bp.sizeZ
	if axis == 1 then
		x0, x1 = lo, hi
	else
		z0, z1 = lo, hi
	end
	-- Unplaced slots, LOCKED ones included: placing below can ready them.
	local n = SiteIndex.inBox(index, x0, 0, z0, x1, bp.sizeY, z1, function(s)
		return not BuildSite.isPlaced(site, s)
	end, found)
	lowestFirst(index, found, n)

	local count = placeAll(site, found, n, Cause.ABILITY, causer, placed, 0, maxPlace)
	return count
end

-- Places everything workable whose centre lies within stats.radius of the
-- player's root and within stats.halfAngle of the facing (fx, fz) seen from
-- above, then starts READY slots from radius to radius + band in the same arc
-- setting. Returns how many it placed, written to placed, and how many it
-- started.
function SiteActions.arc(
	site: Site,
	index: Index,
	px: number,
	py: number,
	pz: number,
	fx: number,
	fz: number,
	stats: ArcStats,
	causer: number,
	placed: { number }
): (number, number)
	local flen = math.sqrt(fx * fx + fz * fz)
	if not (flen > 0) then
		return 0, 0
	end
	fx, fz = fx / flen, fz / flen
	local cosHalf = math.cos(stats.halfAngle)
	local bp = index.blueprint
	local function inArc(s: number, near: number, far: number): boolean
		local dx, dy, dz = bp.x[s] + 0.5 - px, bp.y[s] + 0.5 - py, bp.z[s] + 0.5 - pz
		local d2 = dx * dx + dy * dy + dz * dz
		if d2 < near * near or d2 > far * far then
			return false
		end
		local flat = math.sqrt(dx * dx + dz * dz)
		return flat < 1e-9 or (dx * fx + dz * fz) / flat >= cosHalf
	end

	local radius = stats.radius
	local n = SiteIndex.within(index, px, py, pz, radius, function(s)
		return BuildSite.canPlace(site, s, Cause.TOOL) and inArc(s, 0, radius)
	end, found)
	local count = placeOnce(site, found, n, Cause.TOOL, causer, placed, 0)

	local far = radius + stats.band
	local m = SiteIndex.within(index, px, py, pz, far, function(s)
		return BuildSite.state(site, s) == State.READY and inArc(s, radius, far)
	end, ringFound)
	local started = 0
	for i = 1, m do
		if BuildSite.startSetting(site, ringFound[i], stats.setRate, Cause.TOOL, causer) then
			started += 1
		end
	end
	return count, started
end

-- The nearest slot a pet at (x, y, z) could place within leash, or nil.
function SiteActions.forageTarget(site: Site, index: Index, x: number, y: number, z: number, leash: number): number?
	local n = SiteIndex.nearest(index, x, y, z, leash, function(s)
		return BuildSite.canPlace(site, s, Cause.PET)
	end, 1, found)
	return if n > 0 then found[1] else nil
end

-- A pet's work at target: places it and every workable slot within reach of
-- it, then starts READY slots within ring of it setting. Returns how many it
-- placed, written to placed, and how many it started.
function SiteActions.forage(
	site: Site,
	index: Index,
	target: number,
	reach: number,
	ring: number,
	setRate: number,
	causer: number,
	placed: { number }
): (number, number)
	if not BuildSite.canPlace(site, target, Cause.PET) then
		return 0, 0
	end
	-- What is workable around the target before the pet lays anything.
	local cx, cy, cz = centre(index, target)
	local n = SiteIndex.within(index, cx, cy, cz, reach, function(s)
		return s ~= target and BuildSite.canPlace(site, s, Cause.PET)
	end, found)
	BuildSite.place(site, target, Cause.PET, causer)
	placed[1] = target
	local count = placeOnce(site, found, n, Cause.PET, causer, placed, 1)

	local m = SiteIndex.within(index, cx, cy, cz, ring, function(s)
		return BuildSite.state(site, s) == State.READY
	end, ringFound)
	local started = 0
	for i = 1, m do
		if BuildSite.startSetting(site, ringFound[i], setRate, Cause.PET, causer) then
			started += 1
		end
	end
	return count, started
end

return SiteActions
