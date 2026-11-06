--[[
	WoodcuttersLodge: the first site, in graybox. About 20,000 blocks.

	A woodcutters' camp round a big lodge. The lodge stands on a stone
	plinth: a stone sill and timber walls with doors front and back and rows
	of windows, interior posts, an upper floor, an attic floor, and a
	thatched roof two cells thick that steps up one cell a layer, with eaves
	and timber gable ends, its top third hipped at both ends. A stone
	chimney stands against each gable end. In front, a paved porch with
	posts and a thatched lean-to roof, which waits for the front wall to be
	topped out.

	Beside the lodge, the sawpit shed: an open shed on posts over a stone-lined
	sawpit, with a log lying on trestles across it, and woodpiles behind it,
	one stacked and one in steps. Behind the lodge, across a paved yard with
	a well, the workshop, a small timber house with a forge chimney, a hearth
	and a workbench, and the log store, a long open-fronted shed with logs
	stacked in its bays. Every roof on posts waits for its corner posts to be
	topped out.

	Front is low z. x runs along the lodge.

	BLOCKS sets the camp's size: every length scales by one factor, and the
	stamp picks the factor that lands nearest it. Storey heights and the
	windows and doors stay as they are.

	Stamp it with: lune run tools/stamp_blueprint WoodcuttersLodge
]]

-- The camp's size in blocks.
local BLOCKS = 20000

local function camp(scale: number)
	local blocks = {}
	local taken: { [number]: number } = {}

	local function key(x: number, y: number, z: number): number
		return x + 256 * (y + 256 * z)
	end

	-- Adds a block unless the cell is taken. Returns its index, or the index
	-- of the block already there.
	local function add(x: number, y: number, z: number, kind: string, facing: number?, after: { number }?): number
		local k = key(x, y, z)
		local existing = taken[k]
		if existing then
			return existing
		end
		table.insert(blocks, { x = x, y = y, z = z, kind = kind, facing = facing, after = after })
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
		return math.max(4, math.floor(n * scale + 0.5))
	end

	local function inRange(v: number, lo: number, hi: number): boolean
		return v >= lo and v <= hi
	end

	-- Where windows two cells wide go along a wall from a0 to a1: one every
	-- `every` cells, centred, at least two cells from the corners. Returns
	-- a set of the cells they cover.
	local function windowsAlong(a0: number, a1: number, every: number): { [number]: boolean }
		local set = {}
		local span = a1 - a0 + 1
		local count = math.max(0, (span - 6) // every + 1)
		if count == 0 then
			return set
		end
		local start = a0 + (span - ((count - 1) * every + 2)) // 2
		for i = 0, count - 1 do
			set[start + i * every] = true
			set[start + i * every + 1] = true
		end
		return set
	end

	-- Hollow walls round x0..x1, z0..z1 from layer y0 to y1, leaving out the
	-- cells opening() names. kindAt(y) gives each layer's kind.
	local function walls(
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		y0: number,
		y1: number,
		kindAt: (number) -> string,
		opening: (number, number, number) -> boolean
	)
		for y = y0, y1 do
			for z = z0, z1 do
				for x = x0, x1 do
					local edge = x == x0 or x == x1 or z == z0 or z == z1
					if edge and not opening(x, y, z) then
						add(x, y, z, kindAt(y))
					end
				end
			end
		end
	end

	-- A gable roof two cells thick over walls x0..x1, z0..z1 topped out at
	-- layer y0 - 1: each course a cell up and in, overhanging the gable ends
	-- by a cell and meeting at a ridge along x, with eaves over the long
	-- walls. With after, the cells resting on the walls wait for those
	-- slots, and the rest of the roof waits through them. From course hip
	-- on, the ends step in a cell a course too, two cells thick like the
	-- slopes, so the gables' tops are hipped.
	local function gableRoof(
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		y0: number,
		kind: string,
		after: { number }?,
		hip: number?
	)
		for x = x0 - 1, x1 + 1 do
			add(x, y0, z0, kind, 0, after)
			add(x, y0, z1, kind, 2, after)
		end
		local k = 0
		while z0 + k <= z1 - k do
			local y = y0 + k
			local hipped = hip ~= nil and k >= hip
			local inset = if hipped then k - (hip :: number) - 1 else -1
			for x = x0 + inset, x1 - inset do
				for z = z0 + k, math.min(z0 + k + 1, z1 - k) do
					add(x, y, z, kind, 0)
				end
				for z = math.max(z1 - k - 1, z0 + k), z1 - k do
					add(x, y, z, kind, 2)
				end
			end
			if hipped then
				for z = z0 + k, z1 - k do
					for d = 0, 1 do
						add(x0 + inset + d, y, z, kind, 1)
						add(x1 - inset - d, y, z, kind, 3)
					end
				end
			end
			k += 1
		end
		for x = x0 - 1, x1 + 1 do
			add(x, y0, z0 - 1, kind, 0)
			add(x, y0, z1 + 1, kind, 2)
		end
	end

	-- Gable ends filling the triangle under a gableRoof at x0 and x1, up to
	-- course hip where the roof's ends are hipped.
	local function gableEnds(x0: number, x1: number, z0: number, z1: number, y0: number, kind: string, hip: number?)
		local k = 0
		while z0 + k + 2 <= z1 - k - 2 and (hip == nil or k < hip) do
			for z = z0 + k + 2, z1 - k - 2 do
				add(x0, y0 + k, z, kind, 1)
				add(x1, y0 + k, z, kind, 3)
			end
			k += 1
		end
	end

	-- The lodge -------------------------------------------------------------

	-- Its walls enclose X0..X1 and Z0..Z1.
	local X0, Z0 = 2, 4
	local X1, Z1 = X0 + len(48) - 1, Z0 + len(30) - 1
	local ZC = (Z0 + Z1) // 2
	local DOOR0 = X0 + (X1 - X0 - 1) // 2

	local frontWindows = windowsAlong(X0, X1, 8)
	local sideWindows = windowsAlong(Z0, Z1, 8)
	local function opening(x: number, y: number, z: number): boolean
		local front, back = z == Z0, z == Z1
		local side = x == X0 or x == X1
		local low, high = inRange(y, 4, 5), inRange(y, 10, 11)
		if (front or back) and inRange(x, DOOR0, DOOR0 + 1) and inRange(y, 2, 4) then
			return true -- the doors, front and back
		end
		if (front or back) and low and inRange(x, DOOR0 - 2, DOOR0 + 3) then
			return false -- the wall beside a door stays whole
		end
		if (front or back) and frontWindows[x] and (low or high) then
			return true
		end
		return side and sideWindows[z] == true and (low or high)
	end
	local function wallKind(y: number): string
		return if y == 2 then "stone" else "timber"
	end

	-- Plinth, two layers of stone.
	box(X0, X1, 0, 1, Z0, Z1, "stone")

	-- Ground floor: walls, and two rows of posts holding up the upper floor.
	walls(X0, X1, Z0, Z1, 2, 7, wallKind, opening)
	for x = X0 + 8, X1 - 8, 9 do
		for _, z in { Z0 + len(7), Z1 - len(7) } do
			box(x, x, 2, 7, z, z, "timber")
		end
	end

	-- Upper floor, upper walls and attic floor.
	box(X0, X1, 8, 8, Z0, Z1, "timber")
	walls(X0, X1, Z0, Z1, 9, 13, wallKind, opening)
	box(X0, X1, 14, 14, Z0, Z1, "timber")

	-- Chimneys against both gable ends, first so the roof's overhang stops
	-- at them, rising three cells past the ridge.
	local ridge = 15 + (Z1 - Z0) // 2
	for _, cx in { X0 - 2, X1 + 1 } do
		box(cx, cx + 1, 0, ridge + 3, ZC - 1, ZC + 1, "stone")
	end

	-- The roof, its top third hipped at both ends, and its gable ends.
	local hip = (Z1 - Z0 + 2) // 3
	gableRoof(X0, X1, Z0, Z1, 15, "thatch", nil, hip)
	gableEnds(X0, X1, Z0, Z1, 15, "timber", hip)

	-- Porch: paving, posts, and a lean-to roof of two courses, stepping up
	-- to the wall, that waits for the front wall's top at both ends. Its
	-- lower course rests on the posts and the rest of it on that; the upper
	-- course's back row, beside the upper floor, waits too.
	local PX0, PX1 = X0 + 4, X1 - 4
	box(PX0, PX1, 0, 0, 0, Z0 - 1, "stone")
	local porchPosts = { PX1, DOOR0 - 1, DOOR0 + 2 }
	for x = PX0, PX1 - 3, 7 do
		table.insert(porchPosts, x)
	end
	for _, x in porchPosts do
		box(x, x, 1, 6, 0, 0, "timber")
	end
	local frontTop = { taken[key(PX0, 7, Z0)], taken[key(PX1, 7, Z0)] }
	for x = PX0 - 1, PX1 + 1 do
		for z = 0, Z0 - 1 do
			if z <= 2 then
				add(x, 7, z, "thatch", 0, if z == 0 then frontTop else nil)
			end
		end
		for z = 2, Z0 - 1 do
			add(x, 8, z, "thatch", 0, if z == Z0 - 1 then frontTop else nil)
		end
	end

	-- The yard behind the lodge, paved, between it and the workshop and the
	-- log store.
	local YZ0 = Z1 + 2
	local YZ1 = YZ0 + len(6) - 1

	-- The sawpit shed ------------------------------------------------------

	local SX0 = X1 + 8
	local SX1, SZ0 = SX0 + len(20) - 1, Z0 + 2
	local SZ1 = SZ0 + len(14) - 1
	local SZC = (SZ0 + SZ1) // 2
	-- The sawpit: a stone kerb three layers tall round the pit, timber
	-- trestles across it, and a log on the trestles.
	local PIT0, PIT1 = SX0 + 2, SX1 - 2
	walls(PIT0, PIT1, SZC - 2, SZC + 2, 0, 2, function()
		return "stone"
	end, function()
		return false
	end)
	for x = PIT0 + 2, PIT1 - 2, 4 do
		box(x, x, 3, 3, SZC - 2, SZC + 2, "timber")
	end
	box(PIT0 + 1, PIT1 - 1, 4, 5, SZC, SZC, "timber")
	-- Posts along the long sides carry a plate along each at layer 6, and
	-- the roof waits for the plates' corners.
	local shedTops = {}
	for _, z in { SZ0, SZ1 } do
		for x = SX0, SX1 do
			if (x - SX0) % 5 == 0 or x == SX1 then
				box(x, x, 0, 5, z, z, "timber")
			end
		end
		for x = SX0, SX1 do
			local slot = add(x, 6, z, "timber")
			if x == SX0 or x == SX1 then
				table.insert(shedTops, slot)
			end
		end
	end
	gableRoof(SX0, SX1, SZ0, SZ1, 7, "thatch", shedTops)

	-- Woodpiles behind the sawpit shed: a stack, and logs piled in steps.
	local WY = SZ1 + 3
	local pile = (SX1 - SX0 + 1) // 2 - 1
	box(SX0, SX0 + pile - 1, 0, 3, WY, WY + 3, "timber")
	for y = 0, 3 do
		box(SX1 - pile + 1, SX1, y, y, WY + y, WY + 6 - y, "timber")
	end

	-- The workshop ---------------------------------------------------------

	local WX0 = X0 + 3
	local WX1, WZ0 = WX0 + len(20) - 1, YZ1 + 2
	local WZ1 = WZ0 + len(14) - 1
	local WZC = (WZ0 + WZ1) // 2
	local wDoor = WX0 + (WX1 - WX0 - 1) // 2
	local wWindows = windowsAlong(WX0, WX1, 6)
	box(WX0, WX1, 0, 0, WZ0, WZ1, "stone")
	walls(WX0, WX1, WZ0, WZ1, 1, 5, function(y)
		return if y == 1 then "stone" else "timber"
	end, function(x, y, z)
		if z == WZ0 and inRange(x, wDoor, wDoor + 1) and inRange(y, 1, 3) then
			return true
		end
		local beside = inRange(x, wDoor - 1, wDoor + 2)
		if (z == WZ0 or z == WZ1) and wWindows[x] and inRange(y, 3, 4) and not beside then
			return true
		end
		return x == WX1 and inRange(z, WZC, WZC + 1) and inRange(y, 3, 4)
	end)
	-- The forge's chimney on the far gable end, with its hearth inside, and
	-- a workbench along the back wall.
	local wRidge = 6 + (WZ1 - WZ0) // 2
	box(WX0 - 2, WX0 - 1, 0, wRidge + 3, WZC - 1, WZC + 1, "stone")
	box(WX0 + 1, WX0 + 2, 1, 2, WZC - 1, WZC + 1, "stone")
	box(WX0 + 5, WX1 - 3, 1, 1, WZ1 - 2, WZ1 - 1, "timber")
	gableRoof(WX0, WX1, WZ0, WZ1, 6, "thatch")
	gableEnds(WX0, WX1, WZ0, WZ1, 6, "timber")

	-- The log store --------------------------------------------------------

	local LX0 = WX1 + 8
	local LX1, LZ0 = LX0 + len(40) - 1, WZ0
	local LZ1 = LZ0 + len(12) - 1
	box(LX0, LX1, 0, 0, LZ0, LZ1, "stone")
	-- Back and end walls, posts along the open front, and a plate all round
	-- at layer 6. The roof waits for the plate's corners.
	local function frontPost(x: number): boolean
		return x == LX0 or x == LX1 or (x - LX0) % 6 == 0
	end
	walls(LX0, LX1, LZ0, LZ1, 1, 5, function()
		return "timber"
	end, function(x, _y, z)
		return z == LZ0 and not frontPost(x)
	end)
	walls(LX0, LX1, LZ0, LZ1, 6, 6, function()
		return "timber"
	end, function()
		return false
	end)
	local storeTops = {}
	for _, x in { LX0, LX1 } do
		for _, z in { LZ0, LZ1 } do
			table.insert(storeTops, taken[key(x, 6, z)])
		end
	end
	gableRoof(LX0, LX1, LZ0, LZ1, 7, "thatch", storeTops)
	gableEnds(LX0, LX1, LZ0, LZ1, 7, "timber")
	-- Logs stacked in each bay between the front posts.
	for x = LX0 + 1, LX1 - 1 do
		if not frontPost(x) then
			box(x, x, 1, 4, LZ0 + 3, LZ1 - 1, "timber")
		end
	end

	-- The yard and its well, between the workshop and the log store: a
	-- stone ring, two posts on it carrying a beam, and a little stepped
	-- thatch cap.
	box(X0, LX1, 0, 0, YZ0, YZ1, "stone")
	local WCX, WCZ = (WX1 + LX0) // 2, (YZ0 + YZ1) // 2
	walls(WCX - 2, WCX + 2, WCZ - 2, WCZ + 2, 1, 2, function()
		return "stone"
	end, function()
		return false
	end)
	for _, x in { WCX - 2, WCX + 2 } do
		box(x, x, 3, 5, WCZ, WCZ, "timber")
	end
	box(WCX - 2, WCX + 2, 6, 6, WCZ, WCZ, "timber")
	for c = 0, 2 do
		box(WCX - 3 + c, WCX + 3 - c, 7 + c, 7 + c, WCZ - 2 + c, WCZ + 2 - c, "thatch")
	end

	return blocks
end

-- The camp at the scale whose count lands nearest target. The count grows
-- with the scale, so a bisection finds where it crosses the target.
local function fit(build: (number) -> { any }, target: number): { any }
	local lo, hi = 0.5, 2
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
	name = "WoodcuttersLodge",
	palette = { "stone", "timber", "thatch" },
	blocks = fit(camp, BLOCKS),
}
