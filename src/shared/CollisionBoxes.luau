--!strict
--[[
	CollisionBoxes: merges a chunk's standing blocks into few boxes.

	Clients give each near chunk invisible collision boxes covering the blocks
	that are there (PLACED or UNDOING). Greedy merging grows each box along x,
	then z, then y while every cell it would cover is solid and not yet
	covered, so a solid chunk is one box and a straight wall a few.

	build() writes six numbers per box into out, x0, y0, z0 inclusive and
	x1, y1, z1 exclusive, in cells, and returns how many boxes it wrote.
]]

local CollisionBoxes = {}

-- The fields of a SiteIndex, its Blueprint and a BuildSite this reads.
export type IndexLike = {
	blueprint: { x: { number }, y: { number }, z: { number } },
	chunkCells: number,
	nx: number,
	nz: number,
	slotStart: { number },
	slotList: { number },
}

export type SiteLike = {
	progress: { number },
	rate: { number },
}

local solidScratch: { boolean } = {}
local usedScratch: { boolean } = {}

function CollisionBoxes.build(index: IndexLike, site: SiteLike, chunk: number, out: { number }): number
	local n = index.chunkCells
	local bp = index.blueprint
	local i = chunk - 1
	local bx = (i % index.nx) * n
	local bz = ((i // index.nx) % index.nz) * n
	local by = (i // (index.nx * index.nz)) * n

	local cells = n * n * n
	local solid, used = solidScratch, usedScratch
	for c = 1, cells do
		solid[c] = false
		used[c] = false
	end

	local progress, rate = site.progress, site.rate
	local any = false
	for k = index.slotStart[chunk], index.slotStart[chunk + 1] - 1 do
		local s = index.slotList[k]
		local r = rate[s]
		if r < 0 or (r == 0 and progress[s] >= 1) then
			solid[1 + (bp.x[s] - bx) + n * ((bp.z[s] - bz) + n * (bp.y[s] - by))] = true
			any = true
		end
	end
	if not any then
		return 0
	end

	local function free(lx: number, ly: number, lz: number): boolean
		local c = 1 + lx + n * (lz + n * ly)
		return solid[c] and not used[c]
	end

	local boxes = 0
	for ly = 0, n - 1 do
		for lz = 0, n - 1 do
			for lx = 0, n - 1 do
				if free(lx, ly, lz) then
					local w = 1
					while lx + w < n and free(lx + w, ly, lz) do
						w += 1
					end
					local d = 1
					while lz + d < n do
						local row = true
						for ax = lx, lx + w - 1 do
							if not free(ax, ly, lz + d) then
								row = false
								break
							end
						end
						if not row then
							break
						end
						d += 1
					end
					local h = 1
					while ly + h < n do
						local slab = true
						for az = lz, lz + d - 1 do
							for ax = lx, lx + w - 1 do
								if not free(ax, ly + h, az) then
									slab = false
									break
								end
							end
							if not slab then
								break
							end
						end
						if not slab then
							break
						end
						h += 1
					end
					for ay = ly, ly + h - 1 do
						for az = lz, lz + d - 1 do
							for ax = lx, lx + w - 1 do
								used[1 + ax + n * (az + n * ay)] = true
							end
						end
					end
					local o = boxes * 6
					out[o + 1] = bx + lx
					out[o + 2] = by + ly
					out[o + 3] = bz + lz
					out[o + 4] = bx + lx + w
					out[o + 5] = by + ly + h
					out[o + 6] = bz + lz + d
					boxes += 1
				end
			end
		end
	end
	return boxes
end

return CollisionBoxes
