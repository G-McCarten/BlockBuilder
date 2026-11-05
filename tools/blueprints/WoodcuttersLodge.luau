--[[
	WoodcuttersLodge: the first site, in graybox. About 6,000 blocks.

	A two-storey lodge on a stone plinth: stone sill and timber walls with a
	door and windows, interior posts, an upper floor, an attic floor, and a
	thatched gable roof two cells thick that steps up one cell a layer, with
	eaves and gable ends. A stone chimney stands against the back wall. In
	front, a paved porch with posts and a thatched porch roof, which waits for
	the front wall to be topped out. A woodpile and a small shed sit beside it.

	Front is low z. x runs along the lodge.

	Stamp it with: lune run tools/stamp_blueprint WoodcuttersLodge
]]

local blocks = {}
local taken: { [number]: number } = {}

local function key(x: number, y: number, z: number): number
	return x + 256 * (y + 256 * z)
end

-- Adds a block unless the cell is taken. Returns its index, or the index of
-- the block already there.
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

-- The lodge's walls enclose x 2..31 and z 4..25.
local X0, X1, Z0, Z1 = 2, 31, 4, 25

local function inRange(v: number, lo: number, hi: number): boolean
	return v >= lo and v <= hi
end

-- Window and door openings, as cells left out of the walls.
local function opening(x: number, y: number, z: number): boolean
	local front, back = z == Z0, z == Z1
	local side = x == X0 or x == X1
	if front and inRange(x, 16, 17) and inRange(y, 2, 4) then
		return true -- door
	end
	if (front or back) and (inRange(x, 6, 7) or inRange(x, 26, 27)) and (inRange(y, 4, 5) or inRange(y, 10, 11)) then
		return true
	end
	if back and inRange(x, 16, 17) and inRange(y, 10, 11) then
		return true
	end
	if side and inRange(z, 14, 15) and (inRange(y, 4, 5) or inRange(y, 10, 11)) then
		return true
	end
	return false
end

local function walls(y0: number, y1: number)
	for y = y0, y1 do
		for z = Z0, Z1 do
			for x = X0, X1 do
				local edge = x == X0 or x == X1 or z == Z0 or z == Z1
				if edge and not opening(x, y, z) then
					add(x, y, z, if y == 2 then "stone" else "timber")
				end
			end
		end
	end
end

-- Plinth, two layers of stone.
box(X0, X1, 0, 1, Z0, Z1, "stone")

-- Ground floor: walls, and posts holding up the upper floor.
walls(2, 7)
for _, post in { { 9, 11 }, { 24, 11 }, { 9, 18 }, { 24, 18 } } do
	box(post[1], post[1], 2, 7, post[2], post[2], "timber")
end

-- Upper floor, upper walls and attic floor.
box(X0, X1, 8, 8, Z0, Z1, "timber")
walls(9, 13)
box(X0, X1, 14, 14, Z0, Z1, "timber")

-- Chimney against the back wall.
box(27, 28, 0, 26, Z1 + 1, Z1 + 2, "stone")

-- Gable roof: two slopes two cells thick, each layer one cell up and one in,
-- overhanging the gable ends by a cell, meeting at a ridge.
for k = 0, 10 do
	local y = 15 + k
	for x = X0 - 1, X1 + 1 do
		for z = Z0 + k, math.min(Z0 + k + 1, 14 + 1) do
			add(x, y, z, "thatch", 0)
		end
		for z = math.max(Z1 - k - 1, 14), Z1 - k do
			add(x, y, z, "thatch", 2)
		end
	end
end
-- Eaves over the front and back walls.
for x = X0 - 1, X1 + 1 do
	add(x, 15, Z0 - 1, "thatch", 0)
	add(x, 15, Z1 + 1, "thatch", 2)
end
-- Gable ends fill the triangle under the slopes.
for k = 0, 9 do
	for z = Z0 + k + 2, Z1 - k - 2 do
		add(X0, 15 + k, z, "timber", 1)
		add(X1, 15 + k, z, "timber", 3)
	end
end

-- Porch: paving, posts, and a roof that waits for the front wall's top at both ends.
box(6, 27, 0, 0, 0, Z0 - 1, "stone")
for _, x in { 6, 16, 17, 27 } do
	box(x, x, 1, 6, 0, 0, "timber")
end
local frontTop = { taken[key(6, 7, Z0)], taken[key(27, 7, Z0)] }
for z = 0, Z0 - 1 do
	for x = 5, 28 do
		add(x, 7, z, "thatch", 0, frontTop)
	end
end

-- Woodpile.
box(34, 39, 0, 3, 8, 13, "timber")

-- Shed: stone floor, timber walls with a doorway, thatched roof.
local SX0, SX1, SZ0, SZ1 = 34, 39, 17, 22
box(SX0, SX1, 0, 0, SZ0, SZ1, "stone")
for y = 1, 4 do
	for z = SZ0, SZ1 do
		for x = SX0, SX1 do
			local edge = x == SX0 or x == SX1 or z == SZ0 or z == SZ1
			local door = x == SX0 and inRange(z, 19, 20) and y <= 2
			if edge and not door then
				add(x, y, z, "timber")
			end
		end
	end
end
box(SX0 - 1, SX1 + 1, 5, 5, SZ0 - 1, SZ1 + 1, "thatch")

return {
	name = "WoodcuttersLodge",
	palette = { "stone", "timber", "thatch" },
	blocks = blocks,
}
