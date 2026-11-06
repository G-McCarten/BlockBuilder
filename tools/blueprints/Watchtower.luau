--[[
	Watchtower: the third site, in graybox. About 33,000 blocks.

	A square stone tower twenty-nine cells across in a walled yard, its
	walls three cells thick, with a door under a timber canopy and lanterns
	beside it. The yard's wall has merlons and a turret with a lantern at
	each corner, and a gatehouse in front: two hollow towers with lanterns on
	top, joined over the gate by an arch with a walk on it. A step of stone
	runs round the tower's foot. A guardhouse stands against the yard's back
	wall and a storehouse against its east wall: stone walls, a timber roof,
	a chimney and a lantern by the door.

	A timber stair winds round the outside from the step to the top, more
	than a whole turn. Its treads jut from the walls, so it rises with them
	and players can climb it while they build. Each tread is two cells long
	and climbs one cell, each corner has a landing with a lantern on a post,
	and slits light the stair all the way up. Doors open from the stair onto
	timber floors inside, one where it passes the middle of each face, and
	each floor has an arched window in every face the stair leaves clear.

	At the top the stair comes up through a timber gallery that runs round the
	tower on corbels, with a rail and a lantern at each corner. In the middle
	stands the lantern room: stone corner piers and walls of lanterns, glowing
	from every side. Over it, a timber roof with stone hips flares out at the
	eaves and then climbs steeply to a lantern at its point. The roof waits
	for the lantern room's corners.

	Front is low z.

	BLOCKS sets the site's size: the tower's width and height and the yard
	scale by one factor, and the stamp picks the factor that lands nearest
	it. The stair climbs until it reaches the gallery, part way along a face
	if need be. Treads, doors, windows, the houses' height and the gatehouse
	keep their size.

	Stamp it with: lune run tools/stamp_blueprint Watchtower
]]

-- The site's size in blocks.
local BLOCKS = 33000

local function watchtower(scale: number)
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

	local R = math.max(6, len(13)) -- the shaft's half width: it spans C - R .. C + R
	local THICK = 3
	-- The gallery's height: it grows with the scale, and shrinks as the
	-- shaft widens a whole cell, so the count grows smoothly.
	local TOP = math.max(2 * R + 4, math.floor(60 * scale * 13 * scale / R + 0.5))
	local YARD = R + math.max(8, len(13)) -- the yard wall's ring
	local GATE_DEPTH = 3 -- how far the gatehouse stands out past the yard wall
	local C = YARD + GATE_DEPTH + 1 -- the tower's middle on x and z
	local LOW, HIGH = C - R, C + R
	local BASE = 2 -- the first layer above the plinth

	-- How far a cell is from the middle, in square rings: 0 at the middle, R on
	-- the shaft's outer face.
	local function ring(x: number, z: number): number
		return math.max(math.abs(x - C), math.abs(z - C))
	end

	-- The yard ------------------------------------------------------------

	-- A stone floor out to the wall, and a second layer of stone under the
	-- tower and its stair, which makes a step.
	for z = C - YARD, C + YARD do
		for x = C - YARD, C + YARD do
			add(x, 0, z, "stone")
			if ring(x, z) <= R + 3 then
				add(x, 1, z, "stone")
			end
		end
	end

	-- The gatehouse: two hollow towers either side of the gate, each with a
	-- door onto the passage, a floor half way up and one on top with merlons
	-- and a lantern, and over the passage an arch carrying a walk between them.
	local GT = 12 -- the gatehouse towers' top floor
	local GZ0, GZ1 = C - YARD - GATE_DEPTH, C - YARD + GATE_DEPTH
	box(C - 6, C + 6, 0, 0, GZ0, C - YARD - 1, "stone")
	for _, side in { -1, 1 } do
		local tx0, tx1 = math.min(C + side * 2, C + side * 6), math.max(C + side * 2, C + side * 6)
		local inner = C + side * 2
		for y = 1, GT do
			for z = GZ0, GZ1 do
				for x = tx0, tx1 do
					local wall = x == tx0 or x == tx1 or z == GZ0 or z == GZ1
					local door = x == inner and z == C - YARD and y <= 3
					local slit = (y == 8 or y == 9) and z == GZ0 and x == (tx0 + tx1) // 2
					if (wall and not door and not slit) or y == 6 or y == GT then
						add(x, y, z, "stone")
					end
				end
			end
		end
		for z = GZ0, GZ1 do
			for x = tx0, tx1 do
				if (x == tx0 or x == tx1 or z == GZ0 or z == GZ1) and (x + z) % 2 == 0 then
					add(x, GT + 1, z, "stone")
				end
			end
		end
		add((tx0 + tx1) // 2, GT + 1, (GZ0 + GZ1) // 2, "lantern")
	end
	for y = 5, GT do
		for z = GZ0, GZ1 do
			for x = C - 1, C + 1 do
				if y > 5 or x ~= C then
					add(x, y, z, "stone")
				end
			end
		end
	end
	for x = C - 1, C + 1 do
		add(x, GT + 1, GZ0, "stone")
		add(x, GT + 1, GZ1, "stone")
	end

	-- The yard wall, with merlons, and a turret at each corner: hollow, with
	-- a floor on top behind merlons and a lantern in the middle.
	local TURRET = 8
	for z = C - YARD, C + YARD do
		for x = C - YARD, C + YARD do
			local gate = z == C - YARD and math.abs(x - C) <= 6
			local turret = math.abs(x - C) >= YARD - 2 and math.abs(z - C) >= YARD - 2
			if ring(x, z) == YARD and not gate and not turret then
				for y = 1, 3 do
					add(x, y, z, "stone")
				end
				if (x + z) % 2 == 0 then
					add(x, 4, z, "stone")
				end
			end
		end
	end
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			local cx, cz = C + dx * YARD, C + dz * YARD
			box(cx - 2, cx + 2, 0, 0, cz - 2, cz + 2, "stone")
			for y = 1, TURRET do
				for z = cz - 2, cz + 2 do
					for x = cx - 2, cx + 2 do
						local edge = math.abs(x - cx) == 2 or math.abs(z - cz) == 2
						if edge or y == TURRET then
							add(x, y, z, "stone")
						end
					end
				end
			end
			for z = cz - 2, cz + 2 do
				for x = cx - 2, cx + 2 do
					if (math.abs(x - cx) == 2 or math.abs(z - cz) == 2) and (x + z) % 2 == 0 then
						add(x, TURRET + 1, z, "stone")
					end
				end
			end
			add(cx, TURRET + 1, cz, "lantern")
		end
	end

	-- Houses against the yard wall: stone walls with a door and windows
	-- facing the tower, a timber gable roof two cells thick over stone gable
	-- ends, a chimney at one end and a lantern by the door. A house spans
	-- a0..a1 along the wall and d0..d1 out from the middle, on the side of
	-- the middle that sign gives, along z or along x as axis says.
	local HTOP = 6
	local function house(a0: number, a1: number, d0: number, d1: number, axis: string, sign: number)
		local function cell(a: number, y: number, d: number, kind: string)
			if axis == "z" then
				add(a, y, C + sign * d, kind)
			else
				add(C + sign * d, y, a, kind)
			end
		end
		local middle = (a0 + a1) // 2
		for y = 1, HTOP do
			for d = d0, d1 do
				for a = a0, a1 do
					local edge = a == a0 or a == a1 or d == d0 or d == d1
					local door = d == d0 and (a == middle or a == middle + 1) and y <= 3
					local window = d == d0 and y >= 3 and y <= 4 and (a - a0) % 5 == 2 and math.abs(a - middle) > 2
					if edge and not door and not window then
						cell(a, y, d, "stone")
					end
				end
			end
		end
		local dm = (d0 + d1) // 2
		for y = 1, HTOP + 8 do
			for a = a1 + 1, a1 + 2 do
				for d = dm, dm + 1 do
					cell(a, y, d, "stone")
				end
			end
		end
		for k = 0, (d1 - d0 + 1) // 2 do
			local y = HTOP + 1 + k
			for a = a0 - 1, a1 + 1 do
				for _, d in { d0 - 1 + k, d0 + k, d1 - k, d1 + 1 - k } do
					cell(a, y, d, "timber")
				end
			end
			for d = d0 + k + 1, d1 - k - 1 do
				cell(a0, y, d, "stone")
				cell(a1, y, d, "stone")
			end
		end
		cell(middle + 2, 4, d0 - 1, "lantern")
	end
	-- A guardhouse against the back wall and a storehouse against the east
	-- wall, clear of the turrets.
	house(C - len(10), C + len(10), YARD - 8, YARD - 1, "z", 1)
	house(C - len(8), C + len(8), YARD - 8, YARD - 1, "x", 1)

	-- The stair's path ----------------------------------------------------

	-- Slices two cells wide (the cell against the wall and the one outside
	-- it) round the shaft: up the left face, along the back, down the right
	-- face and back along the front, with a square landing at each corner,
	-- until it reaches the gallery. Each slice knows the wall cells it leans on, so doors
	-- and slits can be cut beside it.
	local slices = {}
	local steps = 0 -- slices that lean on a wall, two to a layer of climb
	local STEPS = 2 * (TOP - 1 - BASE) + 1
	local function slice(cells: { { number } }, wall: { { number } }, along: number?)
		if steps >= STEPS then
			return
		end
		if #wall > 0 then
			steps += 1
		end
		-- inner: the wall cells beside it lead through to the room inside.
		local inner = along ~= nil and along >= LOW + THICK and along <= HIGH - THICK
		table.insert(slices, { cells = cells, wall = wall, inner = inner, along = along })
	end
	local function corner(cx: number, cz: number, dx: number, dz: number)
		slice({
			{ cx, cz },
			{ cx + dx, cz },
			{ cx, cz + dz },
			{ cx + dx, cz + dz },
		}, {})
	end
	local function face(n: number)
		local side = n % 4
		if side == 0 then
			for z = LOW, HIGH do
				slice({ { LOW - 1, z }, { LOW - 2, z } }, { { LOW, z }, { LOW + 1, z }, { LOW + 2, z } }, z)
			end
			corner(LOW - 1, HIGH + 1, -1, 1)
		elseif side == 1 then
			for x = LOW, HIGH do
				slice({ { x, HIGH + 1 }, { x, HIGH + 2 } }, { { x, HIGH }, { x, HIGH - 1 }, { x, HIGH - 2 } }, x)
			end
			corner(HIGH + 1, HIGH + 1, 1, 1)
		elseif side == 2 then
			for z = HIGH, LOW, -1 do
				slice({ { HIGH + 1, z }, { HIGH + 2, z } }, { { HIGH, z }, { HIGH - 1, z }, { HIGH - 2, z } }, z)
			end
			corner(HIGH + 1, LOW - 1, 1, -1)
		else
			for x = HIGH, LOW, -1 do
				slice({ { x, LOW - 1 }, { x, LOW - 2 } }, { { x, LOW }, { x, LOW + 1 }, { x, LOW + 2 } }, x)
			end
			corner(LOW - 1, LOW - 1, -1, -1)
		end
	end
	-- Faces until the stair has climbed to the gallery, part way along the
	-- last one.
	local faces = 0
	while steps < STEPS do
		face(faces)
		faces += 1
	end

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
	local FLOORS = {}
	for _, s in slices do
		if s.along == C and s.layer + 4 < GALLERY then
			table.insert(FLOORS, s.layer)
		end
	end

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
			-- Slits keep clear of the windows in the faces' middles.
			if i % 6 == 3 and s.layer + 3 < GALLERY and math.abs(s.along - C) >= 4 then
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

	-- The tower ------------------------------------------------------------

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
	local levels = table.clone(FLOORS)
	table.insert(levels, GALLERY)
	for _, f in levels do
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
			local k = key(c[1], 0, c[2])
			stairTop[k] = math.max(stairTop[k] or 0, s.layer)
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
	-- edges show against the timber. Each ring repeats more often the nearer
	-- the point it is. The first course's cells over the lantern room wait for
	-- its corners.
	local ROOF = {}
	for v = R, 0, -1 do
		local reps = if v == 0 then 2 elseif v > R * 0.65 then 1 elseif v > R * 0.55 then 2 else 3
		for _ = 1, reps do
			table.insert(ROOF, v)
		end
	end
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

	return blocks
end

-- The site at the scale whose count lands nearest target, but never over the
-- 65,535 blocks a slot index can name. The count grows with the scale, so a
-- bisection finds where it crosses the target.
local function fit(build: (number) -> { any }, target: number): { any }
	local lo, hi = 0.5, 1.5
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
	name = "Watchtower",
	palette = { "lantern", "stone", "timber" },
	blocks = fit(watchtower, BLOCKS),
}
