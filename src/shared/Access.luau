--!strict
--[[
	Access: where players can stand on a site as it is built.

	A stand cell is a cell no standing block (PLACED or UNDOING) fills, with
	headroom free above it, resting on the ground (y == 0, anywhere) or on a
	standing block. Slots not yet placed are open air.

	  freeSurface   the nearest stand cell to a player's root, for moving a
	                character a block landed on, and for dropping a player off
	                a hoist pad next to the work
	  workingLayer  the lowest layer with a READY or SETTING slot: the height
	                hoist pads lift players to

	All in cell space (SiteConfig). A character standing in cell (x, y, z) has
	its root at (x + 0.5, y + 1, z + 0.5).
]]

local Access = {}

-- The fields of a Blueprint and a BuildSite this reads.
export type BlueprintLike = {
	count: number,
	y: { number },
	cellSlot: { [number]: number },
}

export type SiteLike = {
	progress: { number },
	rate: { number },
	unmet: { number },
}

local SPAN = 256

local function standing(bp: BlueprintLike, site: SiteLike, x: number, y: number, z: number): boolean
	if x < 0 or y < 0 or z < 0 or x >= SPAN or y >= SPAN or z >= SPAN then
		return false
	end
	local s = bp.cellSlot[x + SPAN * (y + SPAN * z)]
	if s == nil then
		return false
	end
	local r = site.rate[s]
	return r < 0 or (r == 0 and site.progress[s] >= 1)
end

-- Whether a character can stand in cell (x, y, z) right now.
function Access.canStand(bp: BlueprintLike, site: SiteLike, x: number, y: number, z: number, headroom: number): boolean
	if y < 0 then
		return false
	end
	for h = 0, headroom - 1 do
		if standing(bp, site, x, y + h, z) then
			return false
		end
	end
	return y == 0 or standing(bp, site, x, y - 1, z)
end

-- Offsets from a root to candidate stand cells, nearest first, by radius.
local offsetCache: { [number]: { number } } = {}

local function offsetsFor(radius: number): { number }
	local cached = offsetCache[radius]
	if cached then
		return cached
	end
	local list = {}
	local r = math.ceil(radius) + 1
	for dy = -r, r do
		for dz = -r, r do
			for dx = -r, r do
				-- From the root to the root of a character standing at the offset cell.
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 <= radius * radius then
					table.insert(list, { dx, dy, dz, d2 })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a[4] ~= b[4] then
			return a[4] < b[4]
		elseif a[2] ~= b[2] then
			return a[2] > b[2]
		elseif a[3] ~= b[3] then
			return a[3] < b[3]
		end
		return a[1] < b[1]
	end)
	local flat = table.create(#list * 3, 0)
	for i, o in list do
		flat[i * 3 - 2], flat[i * 3 - 1], flat[i * 3] = o[1], o[2], o[3]
	end
	offsetCache[radius] = flat
	return flat
end

-- The stand cell nearest the root at (px, py, pz) within radius cells, or nil.
-- Ties prefer the higher cell, so a character pushed by a block steps up onto it.
function Access.freeSurface(
	bp: BlueprintLike,
	site: SiteLike,
	px: number,
	py: number,
	pz: number,
	radius: number,
	headroom: number
): (number?, number?, number?)
	local fx, fy, fz = math.floor(px), math.floor(py - 0.5), math.floor(pz)
	local offsets = offsetsFor(radius)
	for i = 1, #offsets, 3 do
		local x, y, z = fx + offsets[i], fy + offsets[i + 1], fz + offsets[i + 2]
		if Access.canStand(bp, site, x, y, z, headroom) then
			return x, y, z
		end
	end
	return nil, nil, nil
end

-- The lowest layer holding a READY or SETTING slot, or nil when none is.
function Access.workingLayer(bp: BlueprintLike, site: SiteLike): number?
	local best: number? = nil
	local progress, rate, unmet, y = site.progress, site.rate, site.unmet, bp.y
	for s = 1, bp.count do
		if unmet[s] == 0 and rate[s] >= 0 and progress[s] < 1 then
			local layer = y[s]
			if best == nil or layer < best then
				best = layer
			end
		end
	end
	return best
end

return Access
