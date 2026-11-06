--[[
	GreatHall: the fourth site, in graybox. About 42,000 blocks.

	A long stone hall on a plinth, its walls two cells thick and, at this
	size, twenty-four layers tall. Stepped stone buttresses divide the long
	walls into bays, each with a tall glass window under a pointed head, and
	pairs of buttresses brace the corners. A stone porch with a pointed arch
	and its own slate gable stands in front of the door.

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

	Two annexes stand against the back wall. At the west corner a square
	tower, its walls three cells thick, rises far past the ridge: a door from
	the hall, timber floors, glass slits on every face of every storey, a
	parapet of merlons, and a slate spire that steps in every second layer
	and waits for the walls' top corners. At the east end a stone kitchen,
	lower than the hall's eaves, with its own slate roof, windows, a door to
	the yard and a big chimney on its back wall.

	The hall runs along x. Front is low z.

	BLOCKS sets the site's size: every length and height scales by one
	factor, and the stamp picks the factor that lands nearest it. The bays
	keep their width, so a longer hall has more of them, and the windows,
	doors, porch and dormers keep their size.

	Stamp it with: lune run tools/stamp_blueprint GreatHall
]]

-- The site's size in blocks.
local BLOCKS = 42000

local function greatHall(scale: number)
	local blocks = {}
	local taken: { [number]: number } = {}

	local function key(x: number, y: number, z: number): number
		return x + 256 * (y + 256 * z)
	end

	-- A length of n cells at this scale.
	local function len(n: number): number
		return math.max(1, math.floor(n * scale + 0.5))
	end

	-- The tower's footprint, which the hall's own blocks leave to it.
	local TW = len(16) // 2 * 2 + 1 -- the tower's width, odd so it has a middle
	local TO = len(5) -- how far it stands out past the hall's west and back walls
	local BAY = 7 -- a buttress every seventh cell along the long walls
	local BAYS = math.max(6, len(8))
	local PORCH_DEPTH = 6
	local X0 = math.max(5, TO + 3) -- the walls' outer faces along x
	local X1 = X0 + BAYS * BAY + 1
	local Z0 = PORCH_DEPTH + 3 -- and along z
	local Z1 = Z0 + len(32) // 2 * 2 -- an odd depth, so the ridge is one cell
	local TX0, TZ1 = X0 - TO, Z1 + TO
	local TX1, TZ0 = TX0 + TW - 1, TZ1 - TW + 1
	local function inTower(x: number, z: number): boolean
		return x >= TX0 and x <= TX1 and z >= TZ0 and z <= TZ1
	end

	-- Adds a block unless the cell is taken. Returns its index, or the index
	-- of the block already there. Blocks of the hall pass hall = true and
	-- are left out where the tower stands.
	local function add(x: number, y: number, z: number, kind: string, after: { number }?, hall: boolean?): number?
		if hall and inTower(x, z) then
			return nil
		end
		local k = key(x, y, z)
		local existing = taken[k]
		if existing then
			return existing
		end
		table.insert(blocks, { x = x, y = y, z = z, kind = kind, after = after })
		taken[k] = #blocks
		return #blocks
	end
	local function hallAdd(x: number, y: number, z: number, kind: string, after: { number }?): number?
		return add(x, y, z, kind, after, true)
	end

	local function box(
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		kind: string,
		hall: boolean?
	)
		for y = y0, y1 do
			for z = z0, z1 do
				for x = x0, x1 do
					add(x, y, z, kind, nil, hall)
				end
			end
		end
	end

	local ZC = (Z0 + Z1) // 2 -- the ridge's line
	local XC = (X0 + X1) / 2 -- the middle of the front, between two cells
	local WALL_TOP = len(20)
	local WINDOW_HEAD = WALL_TOP - 3 -- the windows' pointed heads, a cell wide
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

	-- The tower ------------------------------------------------------------

	-- First, so the hall stops at its walls. Square rings round its middle:
	-- 0 at the middle, TR on the outer face.
	local TXC, TZC = TX0 + (TW - 1) // 2, TZ0 + (TW - 1) // 2
	local TR = (TW - 1) // 2
	local THICK = 3
	local TOWER_TOP = math.max(RIDGE + 12, len(58))
	local STOREY = 8
	local function ringOf(x: number, z: number): number
		return math.max(math.abs(x - TXC), math.abs(z - TZC))
	end
	-- A plinth under it, the walls with a door from the hall and a slit on
	-- every face of every storey, and a timber floor each storey. The door
	-- is in the front wall, where it stands inside the hall.
	box(TX0 - 2, TX1 + 2, 0, 0, TZ0 - 2, TZ1 + 2, "stone")
	local TDOOR = math.max(TX0 + THICK, X0 + 2)
	local corners = {}
	for y = 1, TOWER_TOP do
		local storeyLayer = (y - 1) % STOREY
		for z = TZ0, TZ1 do
			for x = TX0, TX1 do
				local r = ringOf(x, z)
				if r > TR - THICK then
					local alongX = math.abs(z - TZC) == r
					local offset = if alongX then x - TXC else z - TZC
					local slit = offset == 0 and storeyLayer >= 3 and storeyLayer <= 5 and y > STOREY
					local door = z <= TZ0 + THICK - 1 and x >= TDOOR and x <= TDOOR + 2 and y <= 3
					if not door then
						local slot = add(x, y, z, if slit then "glass" else "stone")
						if y == TOWER_TOP and r == TR and math.abs(x - TXC) == TR and math.abs(z - TZC) == TR then
							table.insert(corners, slot)
						end
					end
				elseif storeyLayer == 0 and y > 1 then
					add(x, y, z, "timber")
				end
			end
		end
	end
	add(TXC, TOWER_TOP, TZC, "timber")
	for z = TZ0 + THICK, TZ1 - THICK do
		for x = TX0 + THICK, TX1 - THICK do
			add(x, TOWER_TOP, z, "timber")
		end
	end
	-- The parapet: merlons on every other cell of the outer ring.
	for z = TZ0, TZ1 do
		for x = TX0, TX1 do
			if ringOf(x, z) == TR and (x + z) % 2 == 0 then
				add(x, TOWER_TOP + 1, z, "stone")
			end
		end
	end
	-- The spire: slate two cells thick, stepping in a cell every second
	-- layer from the inner ring of the walls to a timber finial. Its first
	-- course waits for the walls' top corners.
	local spireLayer = TOWER_TOP + 1
	local outer = TR - THICK + 1
	while outer >= 0 do
		for step = 0, 1 do
			local y = spireLayer + step
			for z = TZC - outer, TZC + outer do
				for x = TXC - outer, TXC + outer do
					local r = ringOf(x, z)
					if r >= outer - 1 and r <= outer then
						add(x, y, z, "slate", if y == TOWER_TOP + 1 then corners else nil)
					end
				end
			end
		end
		spireLayer += 2
		outer -= 1
	end
	add(TXC, spireLayer, TZC, "timber")
	add(TXC, spireLayer + 1, TZC, "timber")

	-- The hall -------------------------------------------------------------

	-- Plinth: one layer under the hall, its buttresses and the porch.
	box(X0 - 4, X1 + 4, 0, 0, Z0 - 4, Z1 + 4, "stone", true)
	box(math.floor(XC) - 5, math.ceil(XC) + 5, 0, 0, Z0 - PORCH_DEPTH - 1, Z0 - 5, "stone", true)

	-- The kitchen's span along the back wall, which has no buttresses.
	local KX1 = X1
	local KX0 = KX1 - len(28) + 1
	local KZ1 = Z1 + len(15)

	-- The long walls' windows: three wide, with a pointed head one cell above.
	-- The porch covers the two bays either side of the middle.
	local DOOR0, DOOR1 = math.floor(XC) - 1, math.ceil(XC) + 1
	local PORCH0, PORCH1 = math.floor(XC) - 4, math.ceil(XC) + 4
	for bay = 0, BAYS - 1 do
		local wx = X0 + bay * BAY + 3
		for _, wz in { Z0, Z1 } do
			local hidden = (wz == Z0 and wx >= PORCH0 and wx <= PORCH1) or (wz == Z1 and wx + 2 >= KX0)
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
					hallAdd(x, y, z, if glazed[key(x, y, z)] then "glass" else "stone")
				end
			end
		end
	end

	-- Buttresses: two cells wide, three deep at the foot, stepping back to two
	-- and then one before the wall's top. (ox, oz) points out of the wall.
	local STEP1, STEP2 = WALL_TOP * 5 // 13, WALL_TOP * 8 // 13
	local function buttress(x: number, z: number, ox: number, oz: number)
		for y = 1, WALL_TOP - 2 do
			local depth = if y <= STEP1 then 3 elseif y <= STEP2 then 2 else 1
			for d = 1, depth do
				for w = 0, 1 do
					local bx = x + ox * d + (if ox == 0 then w else 0)
					local bz = z + oz * d + (if oz == 0 then w else 0)
					hallAdd(bx, y, bz, "stone")
				end
			end
		end
	end
	for bay = 0, BAYS do
		local bx = X0 + bay * BAY
		local underPorch = bx >= PORCH0 - 1 and bx <= PORCH1
		if not underPorch then
			buttress(bx, Z0, 0, -1)
		end
		if bx + 1 < KX0 then
			buttress(bx, Z1, 0, 1)
		end
	end
	-- The corners' second buttresses, out of the end walls, but for the
	-- tower's corner.
	buttress(X0, Z0, -1, 0)
	buttress(X1, Z0, 1, 0)
	buttress(X1, Z1 - 1, 1, 0)
	-- Two more on the west end, either side of its window, unless the tower
	-- stands there.
	for _, bz in { ZC - 6, ZC + 5 } do
		if bz + 2 < TZ0 then
			buttress(X0, bz, -1, 0)
		end
	end

	-- The porch: side walls, a front wall with a pointed arch, and a gable.
	local PZ0 = Z0 - PORCH_DEPTH -- the porch's front
	for y = 1, 8 do
		for z = PZ0, Z0 - 1 do
			hallAdd(PORCH0, y, z, "stone")
			hallAdd(PORCH1, y, z, "stone")
		end
		for x = PORCH0 + 1, PORCH1 - 1 do
			local off = math.abs(x + 0.5 - (XC + 0.5))
			local arch = y <= 6 and off <= 3 or y == 7 and off <= 2 or y == 8 and off <= 1
			if not arch then
				hallAdd(x, y, PZ0, "stone")
			end
		end
	end
	-- Its roof, a slate gable along z, and the stone gable under it at the front.
	local PORCH_HALF = (PORCH1 - PORCH0) // 2 + 1
	for c = 0, PORCH_HALF do
		local y = 9 + c
		for z = PZ0 - 1, Z0 - 1 do
			for _, x in { PORCH0 - 1 + c, PORCH0 + c, PORCH1 - c, PORCH1 + 1 - c } do
				hallAdd(x, y, z, "slate")
			end
		end
		for x = PORCH0 + 1 + c, PORCH1 - 1 - c do
			hallAdd(x, y, PZ0, "stone")
		end
	end

	-- Inside: two rows of timber columns, near enough the walls to be in reach
	-- from them, a tie beam across the hall on each pair, and a truss on each
	-- beam: a short king post carrying a collar that reaches across to the
	-- slopes, which is in reach from the roof.
	local COLLAR = WALL_TOP + len(5)
	local beams = {}
	for bay = 1, BAYS - 1 do
		local x = X0 + bay * BAY
		for _, z in { Z0 + 5, Z1 - 5 } do
			box(x, x, 1, WALL_TOP - 1, z, z, "timber", true)
		end
		for z = Z0 + 2, Z1 - 2 do
			local slot = hallAdd(x, WALL_TOP, z, "timber")
			if z == ZC and slot then
				table.insert(beams, { x = x, slot = slot })
			end
		end
		box(x, x, WALL_TOP + 1, COLLAR - 1, ZC, ZC, "timber", true)
		local k = COLLAR - WALL_TOP - 1 -- the roof course at the collar's layer
		box(x, x, COLLAR, COLLAR, Z0 + k + 1, Z1 - k - 1, "timber", true)
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
	local GALLERY = WALL_TOP // 2
	box(X0 + 2, X0 + 6, GALLERY, GALLERY, Z0 + 2, Z1 - 2, "timber", true)
	for z = Z0 + 3, Z1 - 2, 2 do
		hallAdd(X0 + 6, GALLERY + 1, z, "timber")
	end
	for i = 1, GALLERY - 1 do
		box(X0 + 6 + GALLERY - i, X0 + 6 + GALLERY - i, 1, i, Z0 + 2, Z0 + 3, "timber", true)
	end

	-- Dormers, on course DORMER of each slope: a timber front with a glass
	-- window, timber cheeks, an open inside, and a small stepped slate gable
	-- running back into the roof. side is -1 for the front slope, 1 for the back.
	local DORMER = len(5)
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
	-- One in every other bay, clear of the porch, the louvre and the tower.
	for bay = 1, BAYS - 2, 2 do
		local xd = X0 + bay * BAY + 4
		if xd + 2 < PORCH0 - 1 or xd - 2 > PORCH1 + 1 then
			dormer(xd, -1)
			if xd - 2 > TX1 + 1 then
				dormer(xd, 1)
			end
		end
	end
	for _, c in dormerCells do
		if not isVoid(c[1], c[2], c[3]) then
			hallAdd(c[1], c[2], c[3], c[4])
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
				hallAdd(x, y, z, if round then "glass" else "stone")
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
					if hallAdd(x, y, z, "slate", wait) then
						roofAt[key(x, y, z)] = true
					end
				end
			end
		end
	end

	-- A timber louvre on the ridge over the porch: a solid base, corner posts
	-- with glass between, and a small hipped slate cap.
	local LX0, LX1 = math.floor(XC) - 1, math.ceil(XC) + 1
	for z = ZC - 1, ZC + 1 do
		for x = LX0, LX1 do
			hallAdd(x, RIDGE + 1, z, "timber")
			local post = (x == LX0 or x == LX1) and z ~= ZC
			local side = x == LX0 or x == LX1 or z ~= ZC
			for y = RIDGE + 2, RIDGE + 3 do
				if post then
					hallAdd(x, y, z, "timber")
				elseif side then
					hallAdd(x, y, z, "glass")
				end
			end
		end
	end
	for c = 0, 2 do
		box(LX0 - 1 + c, LX1 + 1 - c, RIDGE + 4 + c, RIDGE + 4 + c, ZC - 2 + c, ZC + 2 - c, "slate", true)
	end

	-- The kitchen ----------------------------------------------------------

	-- Against the back wall at the east end, which is its front wall: stone
	-- walls two cells thick, lower than the hall's eaves, with windows in the
	-- back wall and a door in the west wall to the yard by the tower.
	local KTOP = math.max(6, WALL_TOP - len(9))
	local KZC = (Z1 + 1 + KZ1) // 2
	box(KX0 - 2, KX1 + 2, 0, 0, Z1 + 5, KZ1 + 4, "stone")
	-- The chimney first, so the kitchen's eaves stop at it.
	local KCX = (KX0 + KX1) // 2
	local kitchenWindows = {}
	for x = KX0 + 4, KX1 - 6, 6 do
		if math.abs(x - KCX) > 4 and math.abs(x + 1 - KCX) > 4 then
			kitchenWindows[x], kitchenWindows[x + 1] = true, true
		end
	end
	local kRidge = KTOP + 1 + (KZ1 - Z1 + 1) // 2
	box(KCX - 2, KCX + 2, 0, kRidge + 4, KZ1 + 1, KZ1 + 3, "stone")
	for y = 1, KTOP do
		for z = Z1 + 1, KZ1 do
			for x = KX0, KX1 do
				local wall = x <= KX0 + 1 or x >= KX1 - 1 or z >= KZ1 - 1
				local door = x <= KX0 + 1 and z >= KZC - 1 and z <= KZC and y <= 3
				local window = z >= KZ1 - 1 and kitchenWindows[x] and y >= 3 and y <= 5
				local hearth = z >= KZ1 - 1 and math.abs(x - KCX) <= 1 and y <= 3
				if wall and not door and not hearth then
					add(x, y, z, if window then "glass" else "stone")
				end
			end
		end
	end
	-- Its roof: a slate gable along x, its front slope rising from the
	-- hall's wall, over stone gables at both ends.
	for k = 0, (KZ1 - Z1 + 1) // 2 do
		local y = KTOP + 1 + k
		for x = KX0 - 1, KX1 + 1 do
			for z = Z1 - 1 + k, math.min(Z1 + k, KZC) do
				add(x, y, z, "slate")
			end
			for z = math.max(KZ1 - k, KZC), KZ1 + 1 - k do
				add(x, y, z, "slate")
			end
		end
		for z = Z1 + 1 + k, KZ1 - k - 1 do
			for _, x in { KX0, KX0 + 1, KX1 - 1, KX1 } do
				add(x, y, z, "stone")
			end
		end
	end

	return blocks
end

-- The site at the scale whose count lands nearest target. The count grows
-- with the scale, so a bisection finds where it crosses the target.
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
	return if target - #below <= #above - target then below else above
end

return {
	name = "GreatHall",
	palette = { "glass", "slate", "stone", "timber" },
	blocks = fit(greatHall, BLOCKS),
}
