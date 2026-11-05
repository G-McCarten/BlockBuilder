--[[
	GreatHall: the fourth site, in graybox. About 12,300 blocks.

	A long stone hall on a plinth, its walls two cells thick and thirteen
	layers tall. Stepped stone buttresses divide the long walls into eight
	bays, each with a tall glass window under a pointed head, and pairs of
	buttresses brace the corners. A stone porch with a pointed arch and its
	own slate gable stands in front of the door.

	The roof is slate, two cells thick, stepping up a cell a layer from eaves
	that overhang the walls to a ridge, over stone gables. Timber dormers
	with glass windows sit on both slopes, each under a small slate gable,
	and a timber louvre with glass sides and a hipped slate cap stands on the
	ridge over the porch. The west end has a tall window, with a round one in
	the gable above it. A stone chimney stands against the east gable and
	rises past the ridge, with a hearth inside.

	Inside, two rows of timber columns carry tie beams across the hall, and
	each beam carries a truss: a short king post and a collar reaching across
	to the slopes. A timber gallery runs across the west end, with a stair up
	to it. The roof waits for the beams: every roof block that rests on a
	wall or gable waits for the nearest beam.

	The hall runs along x. Front is low z.

	Stamp it with: lune run tools/stamp_blueprint GreatHall
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

local X0, X1 = 5, 62 -- the walls' outer faces along x
local Z0, Z1 = 11, 33 -- and along z
local ZC = (Z0 + Z1) // 2 -- the ridge's line
local XC = (X0 + X1) / 2 -- the middle of the front, between two cells
local WALL_TOP = 13
local WINDOW_HEAD = WALL_TOP - 3 -- the windows' pointed heads, a cell wide
local BAY = 7 -- a buttress every seventh cell along the long walls
local RIDGE = WALL_TOP + 1 + (ZC - Z0 + 1) -- the ridge's layer

-- Cells left open (the door, the hearth, the dormers' insides) and cells
-- of wall that are glass (the windows).
local void: { [number]: boolean } = {}
local function clear(x: number, y: number, z: number)
	void[key(x, y, z)] = true
end
local function isVoid(x: number, y: number, z: number): boolean
	return void[key(x, y, z)] == true
end
local glazed: { [number]: boolean } = {}
local function glaze(x: number, y: number, z: number)
	glazed[key(x, y, z)] = true
end

-- Plinth: one layer under the hall, its buttresses and the porch.
box(X0 - 4, X1 + 4, 0, 0, Z0 - 4, Z1 + 4, "stone")
box(math.floor(XC) - 5, math.ceil(XC) + 5, 0, 0, Z0 - 7, Z0 - 5, "stone")

-- The long walls' windows: three wide, with a pointed head one cell above.
-- The porch covers the two bays either side of the middle.
local DOOR0, DOOR1 = math.floor(XC) - 1, math.ceil(XC) + 1
local PORCH0, PORCH1 = math.floor(XC) - 4, math.ceil(XC) + 4
for bay = 0, 7 do
	local wx = X0 + bay * BAY + 3
	for _, wz in { Z0, Z1 } do
		local hidden = wz == Z0 and wx >= PORCH0 and wx <= PORCH1
		if not hidden then
			for y = 3, WINDOW_HEAD do
				for x = wx, wx + 2 do
					if y < WINDOW_HEAD or x == wx + 1 then
						for d = 0, 1 do
							glaze(x, y, wz + (if wz == Z0 then d else -d))
						end
					end
				end
			end
		end
	end
end
-- The door, four wide under a pointed head.
for y = 1, 7 do
	for x = DOOR0, DOOR1 do
		if y < 7 or (x > DOOR0 and x < DOOR1) then
			clear(x, y, Z0)
			clear(x, y, Z0 + 1)
		end
	end
end
-- The west end's tall window, and the hearth in the east wall.
for y = 3, WINDOW_HEAD do
	for z = ZC - 1, ZC + 1 do
		if y < WINDOW_HEAD or z == ZC then
			glaze(X0, y, z)
			glaze(X0 + 1, y, z)
		end
	end
end
for y = 1, 3 do
	for z = ZC - 1, ZC + 1 do
		clear(X1 - 1, y, z)
	end
end

-- The east chimney first, so the roof's overhang stops at it: a stack
-- against the gable, past the ridge, with two pots.
local CHIMNEY_TOP = RIDGE + 2
box(X1 + 1, X1 + 3, 0, CHIMNEY_TOP, ZC - 2, ZC + 2, "stone")
add(X1 + 2, CHIMNEY_TOP + 1, ZC - 1, "stone")
add(X1 + 2, CHIMNEY_TOP + 1, ZC + 1, "stone")

-- Walls, two cells thick, with glass in the windows.
for y = 1, WALL_TOP do
	for z = Z0, Z1 do
		for x = X0, X1 do
			local wall = x <= X0 + 1 or x >= X1 - 1 or z <= Z0 + 1 or z >= Z1 - 1
			if wall and not isVoid(x, y, z) then
				add(x, y, z, if glazed[key(x, y, z)] then "glass" else "stone")
			end
		end
	end
end

-- Buttresses: two cells wide, three deep at the foot, stepping back to two
-- and then one before the wall's top. (ox, oz) points out of the wall.
local function buttress(x: number, z: number, ox: number, oz: number)
	for y = 1, WALL_TOP - 2 do
		local depth = if y <= 5 then 3 elseif y <= 8 then 2 else 1
		for d = 1, depth do
			for w = 0, 1 do
				local bx = x + ox * d + (if ox == 0 then w else 0)
				local bz = z + oz * d + (if oz == 0 then w else 0)
				add(bx, y, bz, "stone")
			end
		end
	end
end
for bay = 0, 8 do
	local bx = X0 + bay * BAY
	local underPorch = bx >= PORCH0 - 1 and bx <= PORCH1
	if not underPorch then
		buttress(bx, Z0, 0, -1)
	end
	buttress(bx, Z1, 0, 1)
end
-- The corners' second buttresses, out of the end walls.
for _, bz in { Z0, Z1 - 1 } do
	buttress(X0, bz, -1, 0)
	buttress(X1, bz, 1, 0)
end
-- Two more on the west end, either side of its window.
for _, bz in { ZC - 6, ZC + 5 } do
	buttress(X0, bz, -1, 0)
end

-- The porch: side walls, a front wall with a pointed arch, and a gable.
local PZ0 = Z0 - 6 -- the porch's front
for y = 1, 8 do
	for z = PZ0, Z0 - 1 do
		add(PORCH0, y, z, "stone")
		add(PORCH1, y, z, "stone")
	end
	for x = PORCH0 + 1, PORCH1 - 1 do
		local off = math.abs(x + 0.5 - (XC + 0.5))
		local arch = y <= 6 and off <= 3 or y == 7 and off <= 2 or y == 8 and off <= 1
		if not arch then
			add(x, y, PZ0, "stone")
		end
	end
end
-- Its roof, a slate gable along z, and the stone gable under it at the front.
local PORCH_HALF = (PORCH1 - PORCH0) // 2 + 1
for c = 0, PORCH_HALF do
	local y = 9 + c
	for z = PZ0 - 1, Z0 - 1 do
		for _, x in { PORCH0 - 1 + c, PORCH0 + c, PORCH1 - c, PORCH1 + 1 - c } do
			add(x, y, z, "slate")
		end
	end
	for x = PORCH0 + 1 + c, PORCH1 - 1 - c do
		add(x, y, PZ0, "stone")
	end
end

-- Inside: two rows of timber columns, near enough the walls to be in reach
-- from them, a tie beam across the hall on each pair, and a truss on each
-- beam: a short king post carrying a collar that reaches across to the
-- slopes, which is in reach from the roof.
local COLLAR = WALL_TOP + 5
local beams = {}
for bay = 1, 7 do
	local x = X0 + bay * BAY
	for _, z in { Z0 + 5, Z1 - 5 } do
		box(x, x, 1, WALL_TOP - 1, z, z, "timber")
	end
	for z = Z0 + 2, Z1 - 2 do
		local slot = add(x, WALL_TOP, z, "timber")
		if z == ZC then
			table.insert(beams, { x = x, slot = slot })
		end
	end
	box(x, x, WALL_TOP + 1, COLLAR - 1, ZC, ZC, "timber")
	local k = COLLAR - WALL_TOP - 1 -- the roof course at the collar's layer
	box(x, x, COLLAR, COLLAR, Z0 + k + 1, Z1 - k - 1, "timber")
end
local function beamFor(x: number): number
	local best, bestD = beams[1].slot, math.huge
	for _, b in beams do
		local d = math.abs(b.x - x)
		if d < bestD then
			best, bestD = b.slot, d
		end
	end
	return best
end

-- The west gallery at half height, with a rail along its edge and a stair
-- up to it beside the front wall.
local GALLERY = 7
box(X0 + 2, X0 + 6, GALLERY, GALLERY, Z0 + 2, Z1 - 2, "timber")
for z = Z0 + 3, Z1 - 2, 2 do
	add(X0 + 6, GALLERY + 1, z, "timber")
end
for i = 1, GALLERY - 1 do
	box(X0 + 6 + GALLERY - i, X0 + 6 + GALLERY - i, 1, i, Z0 + 2, Z0 + 3, "timber")
end

-- Dormers, on course DORMER of each slope: a timber front with a glass
-- window, timber cheeks, an open inside, and a small stepped slate gable
-- running back into the roof. side is -1 for the front slope, 1 for the back.
local DORMER = 4
local dormerCells: { { any } } = {}
local function dormer(xd: number, side: number)
	local base = WALL_TOP + 1 + DORMER -- the course it stands on
	local front = if side < 0 then Z0 - 1 + DORMER else Z1 + 1 - DORMER
	local inward = -side -- toward the ridge
	for y = base + 1, base + 3 do
		for x = xd - 1, xd + 1 do
			local window = x == xd and y <= base + 2
			table.insert(dormerCells, { x, y, front, if window then "glass" else "timber" })
		end
		for d = 1, 2 do
			table.insert(dormerCells, { xd - 1, y, front + inward * d, "timber" })
			table.insert(dormerCells, { xd + 1, y, front + inward * d, "timber" })
			clear(xd, y, front + inward * d)
		end
	end
	-- The gable: five wide, then three, then one, each layer reaching back to
	-- the roof's slope.
	for c = 0, 2 do
		local y = base + 4 + c
		local slopeAt = if side < 0 then Z0 - 1 + (y - WALL_TOP - 1) else Z1 + 1 - (y - WALL_TOP - 1)
		local z0, z1 = front - inward, slopeAt - inward
		for z = math.min(z0, z1), math.max(z0, z1) do
			for x = xd - 2 + c, xd + 2 - c do
				table.insert(dormerCells, { x, y, z, "slate" })
			end
		end
	end
end
for _, bay in { 1, 2, 5, 6 } do
	local xd = X0 + bay * BAY + 4
	dormer(xd, -1)
	dormer(xd, 1)
end
for _, c in dormerCells do
	if not isVoid(c[1], c[2], c[3]) then
		add(c[1], c[2], c[3], c[4])
	end
end

-- Gables: stone, two cells thick, filling under the slopes at both ends,
-- with a round window high in the west one.
for k = 0, ZC - Z0 do
	local y = WALL_TOP + 1 + k
	for z = Z0 + k + 1, Z1 - k - 1 do
		for _, x in { X0, X0 + 1, X1 - 1, X1 } do
			local dy, dz = y - (WALL_TOP + 5), z - ZC
			local round = x <= X0 + 1 and dy * dy + dz * dz <= 4
			add(x, y, z, if round then "glass" else "stone")
		end
	end
end

-- The roof: two slate slopes two cells thick, a cell up and in each layer,
-- overhanging the gable ends by a cell. A block resting on a wall or gable
-- waits for the nearest beam.
local roofAt: { [number]: boolean } = {}
for k = 0, ZC - Z0 + 1 do
	local y = WALL_TOP + 1 + k
	for x = X0 - 1, X1 + 1 do
		local cells = {}
		for z = Z0 - 1 + k, math.min(Z0 + k, ZC) do
			table.insert(cells, z)
		end
		for z = math.max(Z1 - k, ZC), Z1 + 1 - k do
			table.insert(cells, z)
		end
		for _, z in cells do
			if not isVoid(x, y, z) and not taken[key(x, y, z)] then
				local below = taken[key(x, y - 1, z)]
				local wait = if below and not roofAt[key(x, y - 1, z)] then { beamFor(x) } else nil
				add(x, y, z, "slate", wait)
				roofAt[key(x, y, z)] = true
			end
		end
	end
end

-- A timber louvre on the ridge over the porch: a solid base, corner posts
-- with glass between, and a small hipped slate cap.
local LX0, LX1 = math.floor(XC) - 1, math.ceil(XC) + 1
for z = ZC - 1, ZC + 1 do
	for x = LX0, LX1 do
		add(x, RIDGE + 1, z, "timber")
		local post = (x == LX0 or x == LX1) and z ~= ZC
		local side = x == LX0 or x == LX1 or z ~= ZC
		for y = RIDGE + 2, RIDGE + 3 do
			if post then
				add(x, y, z, "timber")
			elseif side then
				add(x, y, z, "glass")
			end
		end
	end
end
for c = 0, 2 do
	box(LX0 - 1 + c, LX1 + 1 - c, RIDGE + 4 + c, RIDGE + 4 + c, ZC - 2 + c, ZC + 2 - c, "slate")
end

return {
	name = "GreatHall",
	palette = { "glass", "slate", "stone", "timber" },
	blocks = blocks,
}
