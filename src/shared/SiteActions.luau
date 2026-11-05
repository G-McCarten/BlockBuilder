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
-- A band's merge cursors over the planes it covers, one layer at a time.
local heads: { number } = {}
local ends: { number } = {}

-- Shield flags that turn away anything but a player's own click.
local REFUSES_ABILITY = bit32.bor(BuildSite.Shield.BLOCKED, BuildSite.Shield.HAND_ONLY)

local function centre(index: Index, s: number): (number, number, number)
	local bp = index.blueprint
	return bp.x[s] + 0.5, bp.y[s] + 0.5, bp.z[s] + 0.5
end

-- One layer of a band's pass: the layer's slots in planes p0..p1, merged
-- into slot order, each placed if it can be when its turn comes. Returns the
-- new count, and whether this layer placed any.
--
-- Workable below means the band could place the slot now, short of the
-- binding's cap, which BuildSite.place checks: READY or SETTING as
-- BuildSite.state reads them, with no shield flag against it. Written out in
-- each loop rather than called, as these loops read every slot in the band.
local function sweepLayer(
	site: Site,
	slices: SiteIndex.Slices,
	y: number,
	p0: number,
	p1: number,
	causer: number,
	maxPlace: number,
	placed: { number },
	count: number
): (number, boolean)
	local start, list, layers = slices.start, slices.list, slices.layers
	local rate, progress, unmet, shield = site.rate, site.progress, site.unmet, site.shield
	-- Only placing on this layer could make more of it workable, so a layer with
	-- nothing workable now has nothing for this pass.
	local any = false
	for p = p0, p1 do
		local b = p * layers + y + 1
		for i = start[b], start[b + 1] - 1 do
			local s = list[i]
			local r = rate[s]
			if
				(r > 0 or not (r < 0 or progress[s] >= 1 or unmet[s] > 0))
				and not bit32.btest(shield[s], REFUSES_ABILITY)
			then
				any = true
				break
			end
		end
		if any then
			break
		end
	end
	if not any then
		return count, false
	end

	local w = 0
	for p = p0, p1 do
		local b = p * layers + y + 1
		if start[b] < start[b + 1] then
			w += 1
			heads[w] = start[b]
			ends[w] = start[b + 1]
		end
	end
	local progressed = false
	while true do
		-- The lowest slot left at the head of any plane's list.
		local s, k = math.huge, 0
		for j = 1, w do
			local h = heads[j]
			if h < ends[j] and list[h] < s then
				s, k = list[h], j
			end
		end
		if k == 0 then
			return count, progressed
		end
		heads[k] += 1
		local r = rate[s]
		if
			(r > 0 or not (r < 0 or progress[s] >= 1 or unmet[s] > 0))
			and not bit32.btest(shield[s], REFUSES_ABILITY)
			and BuildSite.place(site, s, Cause.ABILITY, causer)
		then
			count += 1
			placed[count] = s
			progressed = true
			if count >= maxPlace or (site.bound and site.placedCount >= site.boundCap) then
				return count, true
			end
		end
	end
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
		local cx, cy, cz = centre(index, slot)
		-- Anything in the player's grasp is within twice the grasp of the aimed
		-- slot. The fence keeps only what is in their grasp.
		local n = SiteIndex.nearestFenced(index, cx, cy, cz, 2 * stats.grasp, px, py, pz, stats.grasp, function(s)
			return BuildSite.canPlace(site, s, Cause.BATCH)
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

-- axis 1 runs the band along x, 3 along z: it covers the slots whose centres
-- lie at lo <= coordinate < hi on that axis, the whole site on the others.
-- Places up to maxPlace blocks and returns how many, written to placed.
--
-- Each pass goes through the band's slots lowest layer first, then by slot,
-- placing each that can be placed when its turn comes, so a block readies
-- the ones above it for later in the same pass. Passes repeat while they
-- place any, up to maxPlace in all.
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
	if not (maxPlace > 0) or (site.bound and site.placedCount >= site.boundCap) then
		return 0
	end
	local bp = index.blueprint
	local n = index.chunkCells
	local size = if axis == 1 then bp.sizeX else bp.sizeZ
	local chunks = if axis == 1 then index.nx else index.nz
	-- The planes the band covers, among the chunks a box query over it reads.
	local c0 = math.max(0, math.ceil(lo - 0.5) // n)
	local c1 = math.min(chunks - 1, (math.ceil(hi - 0.5) - 1) // n)
	local p0, p1 = math.huge, -math.huge
	for p = c0 * n, math.min(size - 1, c1 * n + n - 1) do
		if p + 0.5 >= lo and p + 0.5 < hi then
			p0 = math.min(p0, p)
			p1 = p
		end
	end
	if p0 > p1 then
		return 0
	end

	local slices = SiteIndex.slices(index, axis)
	local count = 0
	local progressed = true
	while progressed and count < maxPlace do
		progressed = false
		for y = 0, slices.layers - 1 do
			local placedHere
			count, placedHere = sweepLayer(site, slices, y, p0, p1, causer, maxPlace, placed, count)
			if placedHere then
				progressed = true
				if count >= maxPlace or (site.bound and site.placedCount >= site.boundCap) then
					return count
				end
			end
		end
	end
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
