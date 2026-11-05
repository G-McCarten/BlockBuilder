--!strict
--[[
	SiteIndex: a blueprint's slots grouped by chunk, for spatial queries.

	The site is cut into cubes chunkCells cells on a side. Chunk ids run
	1..chunkCount, x fastest, then z, then y. Each chunk's slots are listed in
	offset-and-list arrays:

	  slots of chunk c  slotList[slotStart[c] .. slotStart[c + 1] - 1]
	  chunkOf[s]        the chunk holding slot s

	Queries, all in cell space (SiteConfig), each keeping only slots for which
	accept(slot) is true:

	  nearest  the closest slots to a point, in order. Batch placement,
	           auto-aim and pets use it.
	  within   every slot whose centre is within a radius of a point
	  inBox    every slot whose centre is inside a box, for bands and sections
]]

local SiteIndex = {}

-- The fields of a Blueprint this reads.
export type BlueprintLike = {
	count: number,
	x: { number },
	y: { number },
	z: { number },
	sizeX: number,
	sizeY: number,
	sizeZ: number,
}

export type Index = {
	blueprint: BlueprintLike,
	chunkCells: number,
	nx: number,
	ny: number,
	nz: number,
	chunkCount: number,
	chunkOf: { number },
	slotStart: { number },
	slotList: { number },
	-- Scratch for nearest().
	bestDist: { number },
}

function SiteIndex.build(bp: BlueprintLike, chunkCells: number): Index
	local nx = math.max(1, math.ceil(bp.sizeX / chunkCells))
	local ny = math.max(1, math.ceil(bp.sizeY / chunkCells))
	local nz = math.max(1, math.ceil(bp.sizeZ / chunkCells))
	local chunkCount = nx * ny * nz
	local count = bp.count

	local chunkOf = table.create(count, 0)
	local sizes = table.create(chunkCount, 0)
	for s = 1, count do
		local c = 1 + bp.x[s] // chunkCells + nx * (bp.z[s] // chunkCells + nz * (bp.y[s] // chunkCells))
		chunkOf[s] = c
		sizes[c] += 1
	end

	local slotStart = table.create(chunkCount + 1, 0)
	local at = 1
	for c = 1, chunkCount do
		slotStart[c] = at
		at += sizes[c]
	end
	slotStart[chunkCount + 1] = at
	local cursor = table.clone(slotStart)
	local slotList = table.create(count, 0)
	for s = 1, count do
		local c = chunkOf[s]
		slotList[cursor[c]] = s
		cursor[c] += 1
	end

	return {
		blueprint = bp,
		chunkCells = chunkCells,
		nx = nx,
		ny = ny,
		nz = nz,
		chunkCount = chunkCount,
		chunkOf = chunkOf,
		slotStart = slotStart,
		slotList = slotList,
		bestDist = {},
	}
end

-- The chunk's cells: x0, y0, z0 inclusive to x1, y1, z1 exclusive.
function SiteIndex.bounds(index: Index, c: number): (number, number, number, number, number, number)
	local i = c - 1
	local cx = i % index.nx
	local cz = (i // index.nx) % index.nz
	local cy = i // (index.nx * index.nz)
	local n = index.chunkCells
	return cx * n, cy * n, cz * n, (cx + 1) * n, (cy + 1) * n, (cz + 1) * n
end

-- Writes into out, nearest first, up to maxCount slots whose centre lies
-- within radius of (px, py, pz) and for which accept(slot) is true. Returns how
-- many it wrote. Equal distances keep the lower slot first.
function SiteIndex.nearest(
	index: Index,
	px: number,
	py: number,
	pz: number,
	radius: number,
	accept: (slot: number) -> boolean,
	maxCount: number,
	out: { number }
): number
	if maxCount < 1 or not (radius >= 0) then
		return 0
	end
	local bp = index.blueprint
	local x, y, z = bp.x, bp.y, bp.z
	local n = index.chunkCells
	local nx, nz = index.nx, index.nz
	local slotStart, slotList = index.slotStart, index.slotList
	local bestDist = index.bestDist
	local r2 = radius * radius
	local found = 0

	local cx0 = math.max(0, (px - radius) // n)
	local cx1 = math.min(nx - 1, (px + radius) // n)
	local cy0 = math.max(0, (py - radius) // n)
	local cy1 = math.min(index.ny - 1, (py + radius) // n)
	local cz0 = math.max(0, (pz - radius) // n)
	local cz1 = math.min(nz - 1, (pz + radius) // n)

	for cy = cy0, cy1 do
		for cz = cz0, cz1 do
			for cx = cx0, cx1 do
				local c = 1 + cx + nx * (cz + nz * cy)
				for i = slotStart[c], slotStart[c + 1] - 1 do
					local s = slotList[i]
					local dx, dy, dz = x[s] + 0.5 - px, y[s] + 0.5 - py, z[s] + 0.5 - pz
					local d2 = dx * dx + dy * dy + dz * dz
					local worst = bestDist[found]
					local better = found < maxCount or d2 < worst or (d2 == worst and s < out[found])
					if d2 <= r2 and better and accept(s) then
						-- Insert in order, dropping the farthest when full.
						local j = if found < maxCount then found + 1 else found
						while j > 1 and (bestDist[j - 1] > d2 or (bestDist[j - 1] == d2 and out[j - 1] > s)) do
							bestDist[j] = bestDist[j - 1]
							out[j] = out[j - 1]
							j -= 1
						end
						bestDist[j] = d2
						out[j] = s
						if found < maxCount then
							found += 1
						end
					end
				end
			end
		end
	end
	return found
end

-- Writes into out, in no particular order, every slot whose centre lies inside
-- the box from (x0, y0, z0) inclusive to (x1, y1, z1) exclusive and for which
-- accept(slot) is true. Returns how many it wrote.
function SiteIndex.inBox(
	index: Index,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	accept: (slot: number) -> boolean,
	out: { number }
): number
	local bp = index.blueprint
	local x, y, z = bp.x, bp.y, bp.z
	local n = index.chunkCells
	local nx, nz = index.nx, index.nz
	local slotStart, slotList = index.slotStart, index.slotList
	local found = 0
	-- Slot centres sit half a cell in, so a slot is inside when its cell is in [ceil(a - 0.5), ceil(b - 0.5)).
	local cx0 = math.max(0, math.ceil(x0 - 0.5) // n)
	local cx1 = math.min(nx - 1, (math.ceil(x1 - 0.5) - 1) // n)
	local cy0 = math.max(0, math.ceil(y0 - 0.5) // n)
	local cy1 = math.min(index.ny - 1, (math.ceil(y1 - 0.5) - 1) // n)
	local cz0 = math.max(0, math.ceil(z0 - 0.5) // n)
	local cz1 = math.min(nz - 1, (math.ceil(z1 - 0.5) - 1) // n)
	for cy = cy0, cy1 do
		for cz = cz0, cz1 do
			for cx = cx0, cx1 do
				local c = 1 + cx + nx * (cz + nz * cy)
				for i = slotStart[c], slotStart[c + 1] - 1 do
					local s = slotList[i]
					local sx, sy, sz = x[s] + 0.5, y[s] + 0.5, z[s] + 0.5
					if sx >= x0 and sx < x1 and sy >= y0 and sy < y1 and sz >= z0 and sz < z1 and accept(s) then
						found += 1
						out[found] = s
					end
				end
			end
		end
	end
	return found
end

-- Writes into out, in no particular order, every slot whose centre lies within
-- radius of (px, py, pz) and for which accept(slot) is true. Returns how many.
function SiteIndex.within(
	index: Index,
	px: number,
	py: number,
	pz: number,
	radius: number,
	accept: (slot: number) -> boolean,
	out: { number }
): number
	if not (radius >= 0) then
		return 0
	end
	local bp = index.blueprint
	local x, y, z = bp.x, bp.y, bp.z
	local r2 = radius * radius
	-- The box's far faces are exclusive, so widen it a hair to keep centres exactly radius away.
	local far = radius + 1e-6
	return SiteIndex.inBox(index, px - radius, py - radius, pz - radius, px + far, py + far, pz + far, function(s)
		local dx, dy, dz = x[s] + 0.5 - px, y[s] + 0.5 - py, z[s] + 0.5 - pz
		return dx * dx + dy * dy + dz * dz <= r2 and accept(s)
	end, out)
end

return SiteIndex
