--[[
	IceBridge: the second site, in graybox. About 26,000 blocks.

	An ice bridge of five pointed arches between two stone gates. The arches
	widen toward the middle and all crown just under the deck, so the narrow
	end arches stand on tall stone piers and the wide middle one springs from
	the ground. Each arch is an ice vault under the whole deck, with its ring
	two cells thick on the faces, and stone filling the faces between the
	rings and the deck, so the ice arcs show against it.

	Every pier runs up both faces of the bridge as a pointed stone cutwater,
	which carries a lamp post at the deck. The deck is ice, two cells thick
	and, at this size, seventeen wide and twenty-one layers up, with a rope
	rail on stone posts along each edge and a lantern on every other post. Over the middle of the bridge stands a lantern arch: four
	stone piers at the deck's edges, pointed arches between them over the
	road and the rails, and a stepped ice roof with a lantern on top.

	Each gate is a pair of hollow stone towers with ice caps and lanterns on
	top, joined over the road by a pointed arch with a walk on it. A door from
	the road opens onto a floor in each tower. Beyond each gate the road ends
	in a stone landing, and a stone stair runs down from it toward the front,
	beside the gate's front tower, so the stairs add nothing to the bridge's
	length.

	The rails, lamp posts and the lantern arch wait for their span's deck to
	close at its middle, so they go on after the deck.

	The bridge runs along x; front is low z.

	BLOCKS sets the site's size: the deck's height and width, the gates and
	the lantern arch scale by one factor, and the stamp picks the factor that
	lands nearest it. The spans keep their widths, so the bridge stays
	ninety-nine cells long and keeps its walks. The middle arch needs the
	deck sixteen layers up, so the bridge is never under about 12,700 blocks.

	Stamp it with: lune run tools/stamp_blueprint IceBridge
]]

-- The site's size in blocks.
local BLOCKS = 26000

local function iceBridge(scale: number)
	local blocks = {}
	local taken: { [number]: number } = {}

	local function key(x: number, y: number, z: number): number
		return x + 256 * (y + 256 * z)
	end

	-- Adds a block unless the cell is taken. Returns its index, or the index
	-- of the block already there.
	local function add(x: number, y: number, z: number, kind: string, after: { number }?): number
		local k = key(x, y, z)
		local existing = taken[k]
		if existing then
			return existing
		end
		table.insert(blocks, { x = x, y = y, z = z, kind = kind, after = after })
		taken[k] = #blocks
		return #blocks
	end

	local function box(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, kind: string)
		for y = y0, y1 do
			for z = z0, z1 do
				for x = x0, x1 do
					add(x, y, z, kind)
				end
			end
		end
	end

	-- A length of n cells at this scale.
	local function len(n: number): number
		return math.max(1, math.floor(n * scale + 0.5))
	end

	local SPANS = { 9, 13, 15, 13, 9 } -- each arch's opening, west to east
	local PIER = 4 -- each pier's length along x
	local RING = 2 -- each arch ring's thickness
	local GATE = 7 -- each gate's length along x
	local LAND = 5 -- each landing's length along x, and its stair's width
	local DECK = math.max(16, len(16)) -- the deck's lower layer
	local ROAD = DECK + 2 -- the first layer above the road
	local WIDTH = math.max(9, len(13) // 2 * 2 + 1) -- the deck's width, odd so the road has a middle line
	local Z0 = DECK -- room in front for the stairs
	local Z1 = Z0 + WIDTH - 1
	local MID = (Z0 + Z1) // 2 -- the road's middle line
	local TOWER = 7 -- the gate towers' size on x and z
	local TOWER_TOP = DECK + math.max(12, len(16))

	-- Where everything sits along x.
	local westGate = LAND
	local bridgeStart = westGate + GATE
	local arches = {}
	local x = bridgeStart
	for i, width in SPANS do
		-- A pointed arch rises 0.87 of its width. Spring each so its ring's
		-- point sits just under the deck.
		local rise = width * math.sqrt(3) / 2
		local spring = math.max(0, math.floor(DECK - 0.5 - rise - RING) + 1)
		table.insert(arches, { from = x, to = x + width - 1, width = width, centre = x + width / 2, spring = spring })
		x += width
		if i < #SPANS then
			x += PIER
		end
	end
	local bridgeEnd = x - 1
	local eastGate = bridgeEnd + 1
	local eastLanding = eastGate + GATE

	-- What an arch makes of cell (x, y) in its span: open air, the vault (the
	-- ring's inner cell, under the whole deck), the ring's outer cell (on the
	-- faces only), or the face walls above the ring. A pointed arch's opening
	-- is where two circles as wide as it is meet, each centred on the
	-- springing of the other side.
	local RANK = { solid = 0, rib = 1, vault = 2, open = 3 }
	local function archCell(a, cx: number, cy: number): string
		if cy < a.spring then
			return if cx >= a.from and cx <= a.to then "open" else "solid"
		end
		local dy = cy + 0.5 - a.spring
		local dl, dr = cx + 0.5 - a.from, cx + 0.5 - (a.to + 1)
		local d = math.max(math.sqrt(dl * dl + dy * dy), math.sqrt(dr * dr + dy * dy))
		if d < a.width then
			return "open"
		elseif d < a.width + 1 then
			return "vault"
		elseif d < a.width + RING then
			return "rib"
		end
		return "solid"
	end

	-- Gates: two hollow towers each side of a stone causeway, its top level
	-- with the deck. Added before the bridge so the end arches spring from them.
	local towersByGate = {}
	for _, g in { westGate, eastGate } do
		local gx0, gx1 = g, g + GATE - 1
		box(gx0, gx1, 0, DECK + 1, Z0 + 2, Z1 - 2, "stone")
		local towers = {}
		for _, front in { true, false } do
			local tz = if front then Z0 + 1 - (TOWER - 1) else Z1 - 1
			local tz1 = tz + TOWER - 1
			local outer = if front then tz else tz1
			local inner = if front then tz1 else tz
			for y = 0, TOWER_TOP do
				for cz = tz, tz1 do
					for cx = gx0, gx1 do
						local wall = cx == gx0 or cx == gx1 or cz == tz or cz == tz1
						local high = (y - DECK) % 6
						local slit = y > ROAD + 2
							and (high == 2 or high == 3)
							and ((cz == outer and cx == gx0 + 3) or ((cx == gx0 or cx == gx1) and cz == tz + 3))
						local door = (y == ROAD or y == ROAD + 1) and cx >= gx0 + 2 and cx <= gx0 + 4 and cz == inner
						if wall and not slit and not door then
							add(cx, y, cz, "stone")
						end
					end
				end
			end
			-- A floor inside at the road's level, through the door.
			box(gx0 + 1, gx1 - 1, DECK + 1, DECK + 1, tz + 1, tz1 - 1, "stone")
			table.insert(towers, { z0 = tz, z1 = tz1 })
		end
		towersByGate[g] = towers

		-- A pointed arch over the road between the towers, with a walk on top
		-- and merlons along both edges.
		for y = ROAD, ROAD + 10 do
			for cz = Z0 + 2, Z1 - 2 do
				local off = math.abs(cz - MID)
				local half = (Z1 - Z0 - 4) // 2
				local open = y <= ROAD + 5 or (y == ROAD + 6 and off <= half - 1) or (y == ROAD + 7 and off <= 1)
				if not open then
					for cx = gx0, gx1 do
						add(cx, y, cz, "stone")
					end
				end
			end
		end
		for cz = Z0 + 2, Z1 - 2, 2 do
			add(gx0, ROAD + 11, cz, "stone")
			add(gx1, ROAD + 11, cz, "stone")
		end
	end

	-- Piers: solid stone across the deck's width, as tall as the higher of the
	-- two arches springing from them.
	local piers = {}
	for i = 1, #arches - 1 do
		local p0 = arches[i].to + 1
		local top = math.max(arches[i].spring, arches[i + 1].spring) - 1
		if top >= 0 then
			box(p0, p0 + PIER - 1, 0, top, Z0, Z1, "stone")
		end
		table.insert(piers, p0)
	end

	-- Cutwaters: pointed stone prows on both faces of every pier, from the
	-- ground to the deck's top.
	for _, p0 in piers do
		for y = 0, DECK + 1 do
			for cx = p0, p0 + PIER - 1 do
				add(cx, y, Z0 - 1, "stone")
				add(cx, y, Z1 + 1, "stone")
			end
			for cx = p0 + 1, p0 + PIER - 2 do
				add(cx, y, Z0 - 2, "stone")
				add(cx, y, Z1 + 2, "stone")
			end
		end
	end

	-- Arches: an ice vault under the whole deck, a ring two cells thick on
	-- each face, and stone walls on the faces between the rings and the deck.
	for cx = bridgeStart, bridgeEnd do
		for cy = 0, DECK - 1 do
			local best = "solid"
			for _, a in arches do
				if cx >= a.from - PIER - RING and cx <= a.to + PIER + RING then
					local c = archCell(a, cx, cy)
					if RANK[c] > RANK[best] then
						best = c
					end
				end
			end
			if best == "vault" then
				for cz = Z0, Z1 do
					add(cx, cy, cz, "ice")
				end
			elseif best ~= "open" then
				local kind = if best == "rib" then "ice" else "stone"
				add(cx, cy, Z0, kind)
				add(cx, cy, Z1, kind)
			end
		end
	end

	-- The deck, two cells thick, between the gates. Each span's keystone is the
	-- top cell at its middle, on the road's middle line.
	for y = DECK, DECK + 1 do
		for cz = Z0, Z1 do
			for cx = bridgeStart, bridgeEnd do
				add(cx, y, cz, "ice")
			end
		end
	end
	local function keystoneFor(cx: number): number
		local best, bestD = arches[1], math.huge
		for _, a in arches do
			local d = math.abs(cx + 0.5 - a.centre)
			if d < bestD then
				best, bestD = a, d
			end
		end
		return taken[key(math.floor(best.centre), DECK + 1, MID)]
	end

	-- The lantern arch over the middle span: a stone pier two cells square
	-- at each corner of the deck, pointed arches between them along both
	-- edges and across the road, a stone course over them, and a stepped ice
	-- roof with a lantern on top. It waits for its span's keystone.
	local middle = arches[(#arches + 1) // 2]
	local AX0 = math.floor(middle.centre) - 5
	local AX1 = AX0 + 10
	local ARCH_TOP = ROAD + math.max(8, len(9))
	local archWait = { keystoneFor(math.floor(middle.centre)) }
	for y = ROAD, ARCH_TOP do
		for cz = Z0, Z1 do
			for cx = AX0, AX1 do
				local pier = (cx <= AX0 + 1 or cx >= AX1 - 1) and (cz <= Z0 + 1 or cz >= Z1 - 1)
				local edge = cx <= AX0 + 1 or cx >= AX1 - 1 or cz <= Z0 + 1 or cz >= Z1 - 1
				-- Over each opening, the arch closes in over its last three layers.
				local fromTop = ARCH_TOP - y
				local alongX = cz <= Z0 + 1 or cz >= Z1 - 1
				local off = if alongX then math.abs(cx - (AX0 + AX1) / 2) else math.abs(cz - MID)
				local halfOpen = if alongX then (AX1 - AX0 - 4) / 2 else (Z1 - Z0 - 4) / 2
				local closed = fromTop <= 0
					or (fromTop == 1 and off > 1)
					or (fromTop == 2 and off > halfOpen - 1)
					or off > halfOpen
				if pier or (edge and closed) then
					add(cx, y, cz, "stone", if y == ROAD then archWait else nil)
				end
			end
		end
	end
	local half = 0
	while AX0 - 1 + half <= AX1 + 1 - half and Z0 - 1 + half <= Z1 + 1 - half do
		local y = ARCH_TOP + 1 + half
		for cz = Z0 - 1 + half, Z1 + 1 - half do
			for cx = AX0 - 1 + half, AX1 + 1 - half do
				local rim = cx <= AX0 + half or cx >= AX1 - half or cz <= Z0 + half or cz >= Z1 - half
				if rim then
					add(cx, y, cz, "ice")
				end
			end
		end
		half += 1
	end
	add(math.floor(middle.centre), ARCH_TOP + 1 + half, MID, "lantern")

	-- Rope rails along both edges, on stone posts every fourth cell, with a
	-- lantern on every other post. They wait for their span's keystone, and
	-- leave room for the lantern arch.
	for cx = bridgeStart + 1, bridgeEnd - 1 do
		if cx < AX0 or cx > AX1 then
			local wait = { keystoneFor(cx) }
			for _, cz in { Z0, Z1 } do
				local post = (cx - bridgeStart - 1) % 4 == 0
				if post then
					add(cx, ROAD, cz, "stone", wait)
					add(cx, ROAD + 1, cz, "stone")
					if (cx - bridgeStart - 1) % 8 == 0 then
						add(cx, ROAD + 2, cz, "lantern")
					end
				else
					add(cx, ROAD, cz, "rope", wait)
				end
			end
		end
	end

	-- Lamp posts on the cutwaters, one each side of every pier, waiting for
	-- the deck like the rails.
	for _, p0 in piers do
		local wait = { keystoneFor(p0 + 1) }
		for _, cz in { Z0 - 1, Z1 + 1 } do
			for cx = p0 + 1, p0 + PIER - 2 do
				add(cx, ROAD, cz, "stone", wait)
			end
			add(p0 + 1, ROAD + 1, cz, "stone")
			add(p0 + 1, ROAD + 2, cz, "stone")
			add(p0 + 1, ROAD + 3, cz, "stone")
			add(p0 + 1, ROAD + 4, cz, "lantern")
		end
	end

	-- Ice caps on the towers: an eave a cell wider than the tower, then
	-- narrowing to a point with a lantern on it.
	for _, g in { westGate, eastGate } do
		for _, t in towersByGate[g] do
			local cx, cz = g + (GATE - 1) // 2, t.z0 + (TOWER - 1) // 2
			local reach = (TOWER - 1) // 2 + 1
			for k = 0, reach do
				local r = reach - k
				box(cx - r, cx + r, TOWER_TOP + 1 + k, TOWER_TOP + 1 + k, cz - r, cz + r, "ice")
			end
			add(cx, TOWER_TOP + reach + 2, cz, "lantern")
		end
	end

	-- Landings and stairs: a stone landing level with the road beyond each
	-- gate, and from it a stair of solid stone, a step a cell, down toward the
	-- front beside the gate's front tower.
	for _, lx in { 0, eastLanding } do
		box(lx, lx + LAND - 1, 0, DECK + 1, Z0 + 2, Z1 - 2, "stone")
		for i = 0, DECK do
			local z = Z0 + 1 - i
			box(lx, lx + LAND - 1, 0, DECK - i, z, z, "stone")
		end
	end

	return blocks
end

-- The site at the scale whose count lands nearest target, but never over the
-- 65,535 blocks a slot index can name. The count grows with the scale, so a
-- bisection finds where it crosses the target.
local function fit(build: (number) -> { any }, target: number): { any }
	local lo, hi = 0.5, 3
	for _ = 1, 16 do
		local mid = (lo + hi) / 2
		if #build(mid) < target then
			lo = mid
		else
			hi = mid
		end
	end
	local below, above = build(lo), build(hi)
	return if #above > 65535 or target - #below <= #above - target then below else above
end

return {
	name = "IceBridge",
	palette = { "ice", "lantern", "rope", "stone" },
	blocks = fit(iceBridge, BLOCKS),
}
