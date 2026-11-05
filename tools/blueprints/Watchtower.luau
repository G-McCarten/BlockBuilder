--[[
	Watchtower: the third site, in graybox. About 9,000 blocks.

	A square stone tower seventeen cells across on a stepped plinth, its walls
	three cells thick, with a door under a timber canopy and lanterns beside
	it. A timber stair winds once round the outside, from the plinth to the
	top. Its treads jut from the walls, so it rises with them and players can
	climb it while they build. Each tread is two cells long and climbs one
	cell, each corner has a landing with a lantern on a post, and slits light
	the stair all the way up. Doors open from the stair onto four timber
	floors inside, and each floor has an arched window in every face the
	stair leaves clear.

	At the top the stair comes up through a timber gallery that runs round the
	tower on corbels, with a rail and a lantern at each corner. In the middle
	stands the lantern room: stone corner piers and walls of lanterns, glowing
	from every side. Over it, a timber roof with stone hips flares out at the
	eaves and then climbs steeply to a lantern at its point. The roof waits
	for the lantern room's corners.

	Front is low z.

	Stamp it with: lune run tools/stamp_blueprint Watchtower
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

local C = 14 -- the tower's middle on x and z
local R = 8 -- the shaft's half width: it spans C - R .. C + R
local THICK = 3
local LOW, HIGH = C - R, C + R
local BASE = 2 -- the first layer above the plinth

-- How far a cell is from the middle, in square rings: 0 at the middle, R on
-- the shaft's outer face.
local function ring(x: number, z: number): number
	return math.max(math.abs(x - C), math.abs(z - C))
end

-- Plinth: two stepped layers of stone.
for y = 0, 1 do
	local reach = R + 4 - y
	for z = C - reach, C + reach do
		for x = C - reach, C + reach do
			add(x, y, z, "stone")
		end
	end
end

-- The stair's path: slices two cells wide (the cell against the wall and
-- the one outside it) round the shaft, up the left face, along the back,
-- down the right face and back along the front, with a square landing at
-- each corner. Each slice knows the wall cells it leans on, so doors and
-- slits can be cut beside it.
local slices = {}
local function slice(cells: { { number } }, wall: { { number } }, along: number?)
	-- inner: the wall cells beside it lead through to the room inside.
	local inner = along ~= nil and along >= LOW + THICK and along <= HIGH - THICK
	table.insert(slices, { cells = cells, wall = wall, inner = inner })
end
local function corner(cx: number, cz: number, dx: number, dz: number)
	slice({
		{ cx, cz },
		{ cx + dx, cz },
		{ cx, cz + dz },
		{ cx + dx, cz + dz },
	}, {})
end
for z = LOW, HIGH do
	slice({ { LOW - 1, z }, { LOW - 2, z } }, { { LOW, z }, { LOW + 1, z }, { LOW + 2, z } }, z)
end
corner(LOW - 1, HIGH + 1, -1, 1)
for x = LOW, HIGH do
	slice({ { x, HIGH + 1 }, { x, HIGH + 2 } }, { { x, HIGH }, { x, HIGH - 1 }, { x, HIGH - 2 } }, x)
end
corner(HIGH + 1, HIGH + 1, 1, 1)
for z = HIGH, LOW, -1 do
	slice({ { HIGH + 1, z }, { HIGH + 2, z } }, { { HIGH, z }, { HIGH - 1, z }, { HIGH - 2, z } }, z)
end
corner(HIGH + 1, LOW - 1, 1, -1)
for x = HIGH, LOW, -1 do
	slice({ { x, LOW - 1 }, { x, LOW - 2 } }, { { x, LOW }, { x, LOW + 1 }, { x, LOW + 2 } }, x)
end
corner(LOW - 1, LOW - 1, -1, -1)

-- Heights: a cell up every two slices, and each landing level with the
-- slice before it.
local run = 0
for _, s in slices do
	if #s.wall > 0 then
		s.layer = BASE + run // 2
		run += 1
	else
		s.layer = BASE + (run - 1) // 2
	end
end
local GALLERY = slices[#slices].layer + 1 -- the gallery floor's layer
-- Timber floors inside, by layer: one where the stair is half way along
-- each face, so a door can open onto it.
local FLOORS = { 6, 14, 22, 30 }

-- Openings in the shaft, as wall cells to leave out.
local open: { [number]: boolean } = {}
local function cut(cx: number, cy: number, cz: number)
	open[key(cx, cy, cz)] = true
end
-- The front door, three wide and four tall.
for y = BASE, BASE + 3 do
	for x = C - 1, C + 1 do
		for z = LOW, LOW + THICK - 1 do
			cut(x, y, z)
		end
	end
end
-- From the stair: a door onto each floor where a tread is level with it,
-- and a slit at head height every sixth slice.
local doorDone: { [number]: boolean } = {}
for i, s in slices do
	if s.inner then
		for _, f in FLOORS do
			if s.layer == f and not doorDone[f] then
				doorDone[f] = true
				for _, w in s.wall do
					cut(w[1], f + 1, w[2])
					cut(w[1], f + 2, w[2])
				end
			end
		end
		if i % 6 == 3 and s.layer + 3 < GALLERY then
			for _, w in s.wall do
				cut(w[1], s.layer + 2, w[2])
				cut(w[1], s.layer + 3, w[2])
			end
		end
	end
end

-- An arched window in the middle of each face on every floor, three wide
-- with a one-cell head, unless a tread in front of it would lose the wall it
-- leans on.
local treadAt: { [number]: boolean } = {}
for _, s in slices do
	for _, c in s.cells do
		treadAt[key(c[1], s.layer, c[2])] = true
	end
end
for _, n in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
	for _, f in FLOORS do
		local cells = {}
		local clear = true
		for t = -1, 1 do
			for depth = R - THICK + 1, R + 1 do
				local cx = if n[1] ~= 0 then C + n[1] * depth else C + t
				local cz = if n[2] ~= 0 then C + n[2] * depth else C + t
				for y = f + 2, if t == 0 then f + 4 else f + 3 do
					if depth == R + 1 then
						if treadAt[key(cx, y, cz)] then
							clear = false
						end
					else
						table.insert(cells, { cx, y, cz })
					end
				end
			end
		end
		if clear then
			for _, c in cells do
				cut(c[1], c[2], c[3])
			end
		end
	end
end

-- The shaft, up to the gallery's layer.
for y = BASE, GALLERY do
	for z = LOW, HIGH do
		for x = LOW, HIGH do
			if ring(x, z) > R - THICK and not open[key(x, y, z)] then
				add(x, y, z, "stone")
			end
		end
	end
end

-- Timber floors inside, and one at the top under the lantern room.
for _, f in { FLOORS[1], FLOORS[2], FLOORS[3], FLOORS[4], GALLERY } do
	for z = LOW + THICK, HIGH - THICK do
		for x = LOW + THICK, HIGH - THICK do
			add(x, f, z, "timber")
		end
	end
end

-- The stair, after the shaft so each tread leans on the wall beside it.
for _, s in slices do
	for _, c in s.cells do
		add(c[1], s.layer, c[2], "timber")
	end
end

-- A post with a lantern on each landing's outer corner, below the gallery.
for _, s in slices do
	if #s.wall == 0 and s.layer + 3 < GALLERY then
		local far = s.cells[4]
		add(far[1], s.layer + 1, far[2], "timber")
		add(far[1], s.layer + 2, far[2], "timber")
		add(far[1], s.layer + 3, far[2], "lantern")
	end
end

-- The door's canopy, on two brackets, with a lantern each side.
for _, x in { C - 2, C + 2 } do
	add(x, BASE + 3, LOW - 1, "timber")
end
for x = C - 2, C + 2 do
	add(x, BASE + 4, LOW - 1, "timber")
	add(x, BASE + 4, LOW - 2, "timber")
end
for _, x in { C - 3, C + 3 } do
	add(x, BASE + 2, LOW - 1, "lantern")
end

-- Corbels under the gallery: a step out every third cell along each face,
-- leaving the stair clear and its headroom free.
local stairTop: { [number]: number } = {}
for _, s in slices do
	for _, c in s.cells do
		stairTop[key(c[1], 0, c[2])] = s.layer
	end
end
local function clearOfStair(cx: number, cz: number): boolean
	local t = stairTop[key(cx, 0, cz)]
	return t == nil or t < GALLERY - 4
end
for _, n in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
	local nx, nz = n[1], n[2]
	for t = -R + 2, R - 2, 3 do
		local ax = if nx ~= 0 then C + nx * (R + 1) else C + t
		local az = if nz ~= 0 then C + nz * (R + 1) else C + t
		local bx, bz = ax + nx, az + nz
		-- The wall cell it leans on, which a slit may have left out.
		local wx, wz = ax - nx, az - nz
		local walled = not open[key(wx, GALLERY - 2, wz)] and not open[key(wx, GALLERY - 1, wz)]
		if walled and clearOfStair(ax, az) and clearOfStair(bx, bz) then
			add(ax, GALLERY - 2, az, "timber")
			add(ax, GALLERY - 1, az, "timber")
			add(bx, GALLERY - 1, bz, "timber")
		end
	end
end

-- The gallery: a timber floor three cells wide round the shaft's top,
-- open where the stair comes up through it.
local GR = R + 3 -- the gallery's outer ring
local well: { [number]: boolean } = {}
for _, s in slices do
	if s.layer >= GALLERY - 2 then
		for _, c in s.cells do
			well[key(c[1], 0, c[2])] = true
		end
	end
end
for z = C - GR, C + GR do
	for x = C - GR, C + GR do
		if ring(x, z) > R and not well[key(x, 0, z)] then
			add(x, GALLERY, z, "timber")
		end
	end
end
-- Its rail: posts on every other cell of the outer edge, a rail along their
-- tops, and a lantern on each corner.
for z = C - GR, C + GR do
	for x = C - GR, C + GR do
		if ring(x, z) == GR then
			if (x + z) % 2 == 0 then
				add(x, GALLERY + 1, z, "timber")
			end
			add(x, GALLERY + 2, z, "timber")
		end
	end
end
for _, dx in { -1, 1 } do
	for _, dz in { -1, 1 } do
		add(C + dx * GR, GALLERY + 3, C + dz * GR, "lantern")
	end
end

-- The lantern room: a ring on the shaft's inner wall, five layers tall, with
-- stone corner piers, a stone sill and lintel, and lantern walls between, and
-- a door facing the stair.
local LR = R - THICK + 1 -- the lantern room's ring
local corners = {}
for y = GALLERY + 1, GALLERY + 5 do
	for z = C - LR, C + LR do
		for x = C - LR, C + LR do
			if ring(x, z) == LR then
				local pier = math.abs(x - C) >= LR - 1 and math.abs(z - C) >= LR - 1
				local door = z == C - LR and (x == C - 2 or x == C - 3) and y <= GALLERY + 3
				if not door then
					local band = y == GALLERY + 1 or y == GALLERY + 5
					local slot = add(x, y, z, if pier or band then "stone" else "lantern")
					if y == GALLERY + 5 and math.abs(x - C) == LR and math.abs(z - C) == LR then
						table.insert(corners, slot)
					end
				end
			end
		end
	end
end

-- The roof: courses two cells thick that flare out past the lantern room,
-- then climb steeply, each resting on the one below, with stone hips so its
-- edges show against the timber. The first course's cells over the lantern
-- room wait for its corners.
local ROOF = { 8, 7, 6, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0 }
for k, outer in ROOF do
	local y = GALLERY + 5 + k
	local inner = if k == 1 then LR else math.max(0, outer - 1)
	for z = C - outer, C + outer do
		for x = C - outer, C + outer do
			local r = ring(x, z)
			if r >= inner and r <= outer then
				local hip = math.abs(x - C) == r and math.abs(z - C) == r and r > 0
				add(x, y, z, if hip then "stone" else "timber", if k == 1 and r == LR then corners else nil)
			end
		end
	end
end
add(C, GALLERY + 5 + #ROOF + 1, C, "lantern")

return {
	name = "Watchtower",
	palette = { "lantern", "stone", "timber" },
	blocks = blocks,
}
