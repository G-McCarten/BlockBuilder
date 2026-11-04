--[[
	TestHut: a small graybox blueprint for tests, made by script.

	A 9 x 9 floor, four layers of wall with a door in the front, a slab roof
	that overhangs the walls by one cell on every side and spans the room, a
	stepped roof above it, and a flight of steps outside. The slab roof waits
	for all four corners of the wall to be topped out.

	Stamp it with: lune run tools/stamp_blueprint TestHut
]]

local blocks = {}

local function add(x: number, y: number, z: number, kind: string, after: { number }?): number
	table.insert(blocks, { x = x, y = y, z = z, kind = kind, after = after })
	return #blocks
end

-- The room spans x and z 2..10, leaving room for the roof's overhang and the steps.
local LOW, HIGH = 2, 10
local DOOR_X = 6

for z = LOW, HIGH do
	for x = LOW, HIGH do
		add(x, 0, z, "base")
	end
end

local corners = {}
for y = 1, 4 do
	for z = LOW, HIGH do
		for x = LOW, HIGH do
			local edge = x == LOW or x == HIGH or z == LOW or z == HIGH
			local door = x == DOOR_X and z == LOW and y <= 2
			if edge and not door then
				local slot = add(x, y, z, "wall")
				local corner = (x == LOW or x == HIGH) and (z == LOW or z == HIGH)
				if y == 4 and corner then
					table.insert(corners, slot)
				end
			end
		end
	end
end

for z = LOW - 1, HIGH + 1 do
	for x = LOW - 1, HIGH + 1 do
		add(x, 5, z, "roof", corners)
	end
end

for step = 0, 4 do
	local inset = step
	for z = LOW + inset, HIGH - inset do
		for x = LOW + inset, HIGH - inset do
			add(x, 6 + step, z, "roof")
		end
	end
end

-- Steps up the front, clear of the roof's overhang.
for i = 0, 4 do
	for y = 0, i do
		add(3 + i, y, 0, "step")
	end
end

return {
	name = "TestHut",
	palette = { "base", "wall", "roof", "step" },
	blocks = blocks,
}
