--[[
	GreatHall: the fourth site, in graybox. About 11,000 blocks.

	A long stone hall on a plinth, its walls two cells thick and ten layers
	tall, set with tall glass windows. Inside, two rows of timber columns, a
	gallery along each long side at half height, and timber beams across
	under the roof. A slate gable roof two cells thick
	steps up one cell a layer to its ridge, over stone gable ends. Broad steps
	climb to the door, and a stone hearth and chimney stand at the far end.
	The roof waits for the beams.

	The hall runs along x. Front is low z.

	Stamp it with: lune run tools/stamp_blueprint GreatHall
]]

local blocks = {}
local taken: { [number]: number } = {}

local function key(x: number, y: number, z: number): number
	return x + 256 * (y + 256 * z)
end

local function add(x: number, y: number, z: number, kind: string, facing: number?, after: { number }?): number
	local k = key(x, y, z)
	if taken[k] then
		return taken[k]
	end
	table.insert(blocks, { x = x, y = y, z = z, kind = kind, facing = facing, after = after })
	taken[k] = #blocks
	return #blocks
end

local X0, X1, Z0, Z1 = 3, 62, 7, 34 -- inside the walls' outer faces
local WALL_TOP = 10
local MID_Z = (Z0 + Z1) // 2

-- Plinth, one layer, a cell wider than the walls all round.
for z = Z0 - 1, Z1 + 1 do
	for x = X0 - 1, X1 + 1 do
		add(x, 0, z, "stone")
	end
end

local function window(x: number, y: number, z: number): boolean
	local long = z == Z0 or z == Z0 + 1 or z == Z1 or z == Z1 - 1
	return long and y >= 3 and y <= 7 and (x - X0) % 6 >= 2 and (x - X0) % 6 <= 3
end

local function door(x: number, y: number, z: number): boolean
	local centre = (X0 + X1) // 2
	return (z == Z0 or z == Z0 + 1) and math.abs(x - centre) <= 1 and y <= 4
end

-- Walls, two cells thick, windows of glass.
for y = 1, WALL_TOP do
	for z = Z0, Z1 do
		for x = X0, X1 do
			local wall = x <= X0 + 1 or x >= X1 - 1 or z <= Z0 + 1 or z >= Z1 - 1
			if wall and not door(x, y, z) then
				add(x, y, z, if window(x, y, z) then "glass" else "stone")
			end
		end
	end
end

-- Two rows of timber columns, holding the beams.
for x = X0 + 6, X1 - 6, 6 do
	for _, z in { Z0 + 8, Z1 - 8 } do
		for y = 1, WALL_TOP do
			add(x, y, z, "timber")
		end
	end
end

-- Galleries along both long sides, on the columns at half height, so the
-- columns' tops and the beams are in reach.
local GALLERY = 5
for x = X0 + 2, X1 - 2 do
	for z = Z0 + 2, Z0 + 7 do
		add(x, GALLERY, z, "timber")
	end
	for z = Z1 - 7, Z1 - 2 do
		add(x, GALLERY, z, "timber")
	end
end

-- Beams across the hall on top of the walls and columns, every sixth cell.
local beams = {}
for x = X0 + 6, X1 - 6, 6 do
	for z = Z0 + 2, Z1 - 2 do
		local slot = add(x, WALL_TOP, z, "timber")
		if z == MID_Z then
			table.insert(beams, slot)
		end
	end
end

-- The roof: two slate slopes two cells thick, each layer one cell up and
-- one in, overhanging the gable ends by a cell, meeting at a ridge.
local RISE = (Z1 - Z0) // 2
for k = 0, RISE do
	local y = WALL_TOP + 1 + k
	for x = X0 - 1, X1 + 1 do
		for z = Z0 + k, math.min(Z0 + k + 1, MID_Z) do
			add(x, y, z, "slate", 0, if k == 0 then beams else nil)
		end
		for z = math.max(Z1 - k - 1, MID_Z), Z1 - k do
			add(x, y, z, "slate", 2, if k == 0 then beams else nil)
		end
	end
end

-- Gable ends: stone, two cells thick, filling the triangle under the slopes.
for k = 0, RISE do
	for z = Z0 + k + 2, Z1 - k - 2 do
		for _, x in { X0, X0 + 1, X1 - 1, X1 } do
			add(x, WALL_TOP + 1 + k, z, "stone")
		end
	end
end

-- Steps up to the door: five, ten cells wide.
local centre = (X0 + X1) // 2
for i = 1, 5 do
	for x = centre - 5, centre + 4 do
		for y = 0, 5 - i do
			add(x, y, Z0 - 1 - i, "stone")
		end
	end
end

-- A hearth and chimney against the far end wall, outside it.
for y = 0, WALL_TOP + RISE + 3 do
	for z = MID_Z - 1, MID_Z + 2 do
		for x = X1 + 1, X1 + 4 do
			add(x, y, z, "stone")
		end
	end
end

return {
	name = "GreatHall",
	palette = { "glass", "slate", "stone", "timber" },
	blocks = blocks,
}
