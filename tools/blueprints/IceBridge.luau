--[[
	IceBridge: the second site, in graybox. About 7,500 blocks.

	An ice bridge of five arches between two stone gates. The arches widen
	toward the middle and all crown just under the deck, so the narrow end
	arches stand on tall stone piers and the wide middle one springs from the
	ground. Each arch is an ice vault under the whole deck, with its ring two
	cells thick on the faces, and stone filling the faces between the rings
	and the deck, so the ice arcs show against it.

	Every pier runs up both faces of the bridge as a pointed stone cutwater,
	which carries a lamp post at the deck. The deck is ice, two cells thick and
	nine wide, with a rope rail on stone posts along each edge and a lantern on
	every other post.

	Each gate is a pair of hollow stone towers with ice caps and lanterns on
	top, joined over the road by a pointed arch with a walk on it. A door from
	the road opens onto a floor in each tower. A stone stair climbs from the
	ground to each gate.

	The rails and lamp posts wait for their span's deck to close at its middle,
	so they go on after the deck.

	The bridge runs along x; front is low z.

	Stamp it with: lune run tools/stamp_blueprint IceBridge
]]

local blocks = {}
local taken: { [number]: number } = {}

local function key(x: number, y: number, z: number): number
	return x + 256 * (y + 256 * z)
end

-- Adds a block unless the cell is taken. Returns its index, or the index of
-- the block already there.
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

local Z0, Z1 = 4, 12 -- the deck's width
local MID = 8 -- the road's middle line
local DECK = 11 -- the deck's lower layer; players walk on top of layer 12
local ROAD = DECK + 2 -- the first layer above the road
local SPANS = { 11, 15, 19, 15, 11 } -- each arch's opening, west to east
local PIER = 3 -- each pier's length along x
local RING = 2 -- each arch ring's thickness
local STAIR = 13 -- steps from the ground to a gate
local GATE = 5 -- each gate's length along x

-- Where everything sits along x.
local westGate = STAIR
local bridgeStart = westGate + GATE
local arches = {}
local x = bridgeStart
for i, width in SPANS do
	local radius = width / 2
	-- Spring each arch so its ring's crown sits just under the deck.
	local spring = math.max(0, math.floor(DECK - 0.5 - radius - RING) + 1)
	table.insert(arches, { from = x, to = x + width - 1, centre = x + radius, radius = radius, spring = spring })
	x += width
	if i < #SPANS then
		x += PIER
	end
end
local bridgeEnd = x - 1
local eastGate = bridgeEnd + 1

-- What an arch makes of cell (x, y) in its span: open air, the vault (the
-- ring's inner cell, under the whole deck), the ring's outer cell (on the
-- faces only), or the face walls above the ring.
local RANK = { solid = 0, rib = 1, vault = 2, open = 3 }
local function archCell(a, cx: number, cy: number): string
	if cy < a.spring then
		return if cx >= a.from and cx <= a.to then "open" else "solid"
	end
	local dx, dy = cx + 0.5 - a.centre, cy + 0.5 - a.spring
	local d = math.sqrt(dx * dx + dy * dy)
	if d < a.radius then
		return "open"
	elseif d < a.radius + 1 then
		return "vault"
	elseif d < a.radius + RING then
		return "rib"
	end
	return "solid"
end

-- Gates: two hollow towers each side of a stone causeway, its top level
-- with the deck. Added before the bridge so the end arches spring from them.
local TOWER_TOP = 23
local towersByGate = {}
for _, g in { westGate, eastGate } do
	local gx0, gx1 = g, g + GATE - 1
	box(gx0, gx1, 0, DECK + 1, Z0 + 2, Z1 - 2, "stone")
	local towers = {}
	for _, tz in { Z0 - 3, Z1 - 1 } do
		local tz1 = tz + 4
		for y = 0, TOWER_TOP do
			for cz = tz, tz1 do
				for cx = gx0, gx1 do
					local wall = cx == gx0 or cx == gx1 or cz == tz or cz == tz1
					local outer = if tz < MID then cz == tz else cz == tz1
					local slit = (y == 16 or y == 17 or y == 20 or y == 21)
						and ((outer and cx == gx0 + 2) or ((cx == gx0 or cx == gx1) and cz == tz + 2))
					local door = (y == ROAD or y == ROAD + 1) and cx == gx0 + 2 and cz == (if tz < MID then tz1 else tz)
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
	for y = ROAD, ROAD + 8 do
		for cz = Z0 + 2, Z1 - 2 do
			local off = math.abs(cz - MID)
			local open = y <= ROAD + 4 or (y == ROAD + 5 and off <= 1) or (y == ROAD + 6 and off == 0)
			if not open then
				for cx = gx0, gx1 do
					add(cx, y, cz, "stone")
				end
			end
		end
	end
	for cz = Z0 + 2, Z1 - 2, 2 do
		add(gx0, ROAD + 9, cz, "stone")
		add(gx1, ROAD + 9, cz, "stone")
	end
end

-- Piers: solid stone across the deck's width, as tall as the higher of the
-- two arches springing from them.
local piers = {}
for i = 1, #arches - 1 do
	local p0 = arches[i].to + 1
	local top = math.max(arches[i].spring, arches[i + 1].spring) - 1
	box(p0, p0 + PIER - 1, 0, top, Z0, Z1, "stone")
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
		add(p0 + 1, y, Z0 - 2, "stone")
		add(p0 + 1, y, Z1 + 2, "stone")
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

-- Rope rails along both edges, on stone posts every fourth cell, with a
-- lantern on every other post. They wait for their span's keystone.
for cx = bridgeStart + 1, bridgeEnd - 1 do
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

-- Lamp posts on the cutwaters, one each side of every pier, waiting for
-- the deck like the rails.
for _, p0 in piers do
	local wait = { keystoneFor(p0 + 1) }
	for _, cz in { Z0 - 1, Z1 + 1 } do
		add(p0 + 1, ROAD, cz, "stone", wait)
		add(p0 + 1, ROAD + 1, cz, "stone")
		add(p0 + 1, ROAD + 2, cz, "stone")
		add(p0 + 1, ROAD + 3, cz, "lantern")
	end
end

-- Ice caps on the towers: an eave a cell wider than the tower, then
-- narrowing to a point with a lantern on it.
for _, g in { westGate, eastGate } do
	for _, t in towersByGate[g] do
		local cx, cz = g + 2, t.z0 + 2
		for k = 0, 3 do
			local half = 3 - k
			box(cx - half, cx + half, TOWER_TOP + 1 + k, TOWER_TOP + 1 + k, cz - half, cz + half, "ice")
		end
		add(cx, TOWER_TOP + 5, cz, "lantern")
	end
end

-- Stairs: solid stone, a step a cell, from the ground up to each gate.
for i = 0, STAIR - 1 do
	local height = i + 1
	box(i, i, 0, height - 1, Z0 + 2, Z1 - 2, "stone")
	local ex = eastGate + GATE + STAIR - 1 - i
	box(ex, ex, 0, height - 1, Z0 + 2, Z1 - 2, "stone")
end

return {
	name = "IceBridge",
	palette = { "ice", "lantern", "rope", "stone" },
	blocks = blocks,
}
