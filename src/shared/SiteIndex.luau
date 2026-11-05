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

	  nearest  the closest slots to a point, in order. A click's batch,
	           auto-aim, bots and pets use it.
	  within   every slot whose centre is within a radius of a point
	  inBox    every slot whose centre is inside a box, for the boss's
	           shields and sections

	And slices(axis), for the ABILITY's bands across the site: each plane of
	cells across that axis cut into layers, made the first time a band asks.
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

-- The slots of each plane across an axis, by layer: plane p (the cells with
-- x == p for axis 1, z == p for axis 3) on layer y holds
-- list[start[b] .. start[b + 1] - 1] with b = p * layers + y + 1, in slot order.
export type Slices = {
	planes: number,
	layers: number,
	start: { number },
	list: { number },
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
	-- Each listed slot's centre, by its place in slotList, so a query reads a
	-- chunk's in a row rather than hopping about the blueprint's arrays.
	centreX: { number },
	centreY: { number },
	centreZ: { number },
	-- Scratch for nearest().
	bestDist: { number },
	-- slices(1) and slices(3), once made.
	slicesX: Slices?,
	slicesZ: Slices?,
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
	local centreX, centreY, centreZ = table.create(count, 0), table.create(count, 0), table.create(count, 0)
	for s = 1, count do
		local c = chunkOf[s]
		local i = cursor[c]
		slotList[i] = s
		centreX[i], centreY[i], centreZ[i] = bp.x[s] + 0.5, bp.y[s] + 0.5, bp.z[s] + 0.5
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
		centreX = centreX,
		centreY = centreY,
		centreZ = centreZ,
		bestDist = {},
	}
end

-- The site's planes across axis (1 for x, any other for z), each by layer.
-- Made once per index, on first use.
function SiteIndex.slices(index: Index, axis: number): Slices
	local cached = if axis == 1 then index.slicesX else index.slicesZ
	if cached then
		return cached
	end
	local bp = index.blueprint
	local across = if axis == 1 then bp.x else bp.z
	local y = bp.y
	local planes = math.max(1, if axis == 1 then bp.sizeX else bp.sizeZ)
	local layers = math.max(1, bp.sizeY)
	local buckets = planes * layers
	local count = bp.count

	local sizes = table.create(buckets, 0)
	for s = 1, count do
		local b = across[s] * layers + y[s] + 1
		sizes[b] += 1
	end
	local start = table.create(buckets + 1, 0)
	local at = 1
	for b = 1, buckets do
		start[b] = at
		at += sizes[b]
	end
	start[buckets + 1] = at
	-- Filled in slot order, so each plane's layer lists its slots in order.
	local cursor = table.clone(start)
	local list = table.create(count, 0)
	for s = 1, count do
		local b = across[s] * layers + y[s] + 1
		list[cursor[b]] = s
		cursor[b] += 1
	end

	local slices: Slices = { planes = planes, layers = layers, start = start, list = list }
	if axis == 1 then
		index.slicesX = slices
	else
		index.slicesZ = slices
	end
	return slices
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

-- How far a slot centre in the chunk at (cx, cy, cz) can come to (px, py, pz),
-- squared: never more than the squared distance nearest() and within()
-- compute for any of its slots, even after rounding, because each step
-- below rounds the same way theirs does and rounding keeps order.
local function chunkGap2(n: number, cx: number, cy: number, cz: number, px: number, py: number, pz: number): number
	-- Centres in a chunk run from half a cell in to half a cell short of its far side.
	local lo = cx * n + 0.5
	local gx = if px < lo then lo - px elseif px > lo + (n - 1) then px - (lo + (n - 1)) else 0
	lo = cy * n + 0.5
	local gy = if py < lo then lo - py elseif py > lo + (n - 1) then py - (lo + (n - 1)) else 0
	lo = cz * n + 0.5
	local gz = if pz < lo then lo - pz elseif pz > lo + (n - 1) then pz - (lo + (n - 1)) else 0
	return gx * gx + gy * gy + gz * gz
end

-- Offers chunk (cx, cy, cz)'s slots to the list of the found best, unless
-- none of them could make it. Returns how many are found now.
local function nearestInChunk(
	index: Index,
	cx: number,
	cy: number,
	cz: number,
	px: number,
	py: number,
	pz: number,
	r2: number,
	accept: (slot: number) -> boolean,
	maxCount: number,
	out: { number },
	found: number
): number
	local bestDist = index.bestDist
	local gap2 = chunkGap2(index.chunkCells, cx, cy, cz, px, py, pz)
	if gap2 > r2 or (found >= maxCount and gap2 > bestDist[found]) then
		return found
	end
	local slotList = index.slotList
	local centreX, centreY, centreZ = index.centreX, index.centreY, index.centreZ
	local c = 1 + cx + index.nx * (cz + index.nz * cy)
	for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
		local dx, dy, dz = centreX[i] - px, centreY[i] - py, centreZ[i] - pz
		local d2 = dx * dx + dy * dy + dz * dz
		if d2 <= r2 then
			local s = slotList[i]
			local worst = bestDist[found]
			if (found < maxCount or d2 < worst or (d2 == worst and s < out[found])) and accept(s) then
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
	return found
end

-- Writes into out, nearest first, up to maxCount slots whose centre lies
-- within radius of (px, py, pz) and for which accept(slot) is true. Returns how
-- many it wrote. Equal distances keep the lower slot first.
--
-- The answer is the best maxCount by distance, then slot, so the order chunks
-- are read in can't change it. They are read in rings outward from the
-- point's chunk, so a search stops once no further ring can hold anything
-- better than what it has, and skips chunks that can't. accept is called only
-- for slots in range that would make the list, so it must have no side
-- effects.
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
	if maxCount < 1 or not (radius >= 0) or px ~= px or py ~= py or pz ~= pz then
		return 0
	end
	local n = index.chunkCells
	local r2 = radius * radius
	local cx0 = math.max(0, (px - radius) // n)
	local cx1 = math.min(index.nx - 1, (px + radius) // n)
	local cy0 = math.max(0, (py - radius) // n)
	local cy1 = math.min(index.ny - 1, (py + radius) // n)
	local cz0 = math.max(0, (pz - radius) // n)
	local cz1 = math.min(index.nz - 1, (pz + radius) // n)
	if cx0 > cx1 or cy0 > cy1 or cz0 > cz1 then
		return 0
	end

	-- The point's chunk, or the nearest one in range to it.
	local qx = math.clamp(px // n, cx0, cx1)
	local qy = math.clamp(py // n, cy0, cy1)
	local qz = math.clamp(pz // n, cz0, cz1)
	local rings = math.max(qx - cx0, cx1 - qx, qy - cy0, cy1 - qy, qz - cz0, cz1 - qz)
	local bestDist = index.bestDist
	local found = 0
	for k = 0, rings do
		if k > 0 then
			-- A chunk k rings out lies k chunks away along some axis, so its slot
			-- centres are at least (k - 1) chunks and half a cell from the point.
			local gap = (k - 1) * n + 0.5
			local gap2 = gap * gap
			if gap2 > r2 or (found >= maxCount and gap2 > bestDist[found]) then
				break
			end
		end
		local xlo, xhi = math.max(cx0, qx - k), math.min(cx1, qx + k)
		local zlo, zhi = math.max(cz0, qz - k), math.min(cz1, qz + k)
		for cy = math.max(cy0, qy - k), math.min(cy1, qy + k) do
			local yEdge = cy == qy - k or cy == qy + k
			for cz = zlo, zhi do
				if yEdge or cz == qz - k or cz == qz + k then
					-- On the ring's top, bottom or sides: the whole row.
					for cx = xlo, xhi do
						found = nearestInChunk(index, cx, cy, cz, px, py, pz, r2, accept, maxCount, out, found)
					end
				else
					-- Inside them: only the row's two ends are on the ring.
					if qx - k >= cx0 then
						found = nearestInChunk(index, qx - k, cy, cz, px, py, pz, r2, accept, maxCount, out, found)
					end
					if qx + k <= cx1 then
						found = nearestInChunk(index, qx + k, cy, cz, px, py, pz, r2, accept, maxCount, out, found)
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
-- The order is inBox's over the sphere's box, which callers' results follow.
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
	local n = index.chunkCells
	local nx, nz = index.nx, index.nz
	local slotStart, slotList = index.slotStart, index.slotList
	local centreX, centreY, centreZ = index.centreX, index.centreY, index.centreZ
	local r2 = radius * radius
	-- The box's far faces are exclusive, so widen it a hair to keep centres exactly radius away.
	local far = radius + 1e-6
	local x0, y0, z0 = px - radius, py - radius, pz - radius
	local x1, y1, z1 = px + far, py + far, pz + far
	local found = 0
	-- The same box, chunks and order as inBox, skipping chunks the sphere misses.
	local cx0 = math.max(0, math.ceil(x0 - 0.5) // n)
	local cx1 = math.min(nx - 1, (math.ceil(x1 - 0.5) - 1) // n)
	local cy0 = math.max(0, math.ceil(y0 - 0.5) // n)
	local cy1 = math.min(index.ny - 1, (math.ceil(y1 - 0.5) - 1) // n)
	local cz0 = math.max(0, math.ceil(z0 - 0.5) // n)
	local cz1 = math.min(nz - 1, (math.ceil(z1 - 0.5) - 1) // n)
	for cy = cy0, cy1 do
		for cz = cz0, cz1 do
			for cx = cx0, cx1 do
				if chunkGap2(n, cx, cy, cz, px, py, pz) <= r2 then
					local c = 1 + cx + nx * (cz + nz * cy)
					for i = slotStart[c], slotStart[c + 1] - 1 do
						local sx, sy, sz = centreX[i], centreY[i], centreZ[i]
						if sx >= x0 and sx < x1 and sy >= y0 and sy < y1 and sz >= z0 and sz < z1 then
							local dx, dy, dz = sx - px, sy - py, sz - pz
							if dx * dx + dy * dy + dz * dz <= r2 then
								local s = slotList[i]
								if accept(s) then
									found += 1
									out[found] = s
								end
							end
						end
					end
				end
			end
		end
	end
	return found
end

return SiteIndex
