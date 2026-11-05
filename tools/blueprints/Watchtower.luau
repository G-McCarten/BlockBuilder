--[[
	Watchtower: the third site, in graybox. About 8,500 blocks.

	A stone tower seventeen cells square on a broad plinth, its walls three
	cells thick and 40 layers tall, with a door and arrow slits. Timber floors
	every six layers, and a stair that winds up inside the walls. On top, a
	crenellated parapet, a lantern room, and a stepped timber roof over it.
	The roof waits for the lantern room's corners.

	Stamp it with: lune run tools/stamp_blueprint Watchtower
]]

local blocks = {}
local taken: { [number]: number } = {}

local function key(x: number, y: number, z: number): number
	return x + 256 * (y + 256 * z)
end

local function add(x: number, y: number, z: number, kind: string, after: { number }?): number
	local k = key(x, y, z)
	if taken[k] then
		return taken[k]
	end
	table.insert(blocks, { x = x, y = y, z = z, kind = kind, after = after })
	taken[k] = #blocks
	return #blocks
end

-- The tower's walls enclose x and z 4..20; the plinth reaches 2..22.
local LOW, HIGH = 4, 20
local THICK = 3
local HEIGHT = 40
local FLOORS = { 6, 12, 18, 24, 30, 36 }

for y = 0, 1 do
	for z = LOW - 2, HIGH + 2 do
		for x = LOW - 2, HIGH + 2 do
			add(x, y, z, "stone")
		end
	end
end

local function inWall(x: number, z: number): boolean
	local inside = x >= LOW + THICK and x <= HIGH - THICK and z >= LOW + THICK and z <= HIGH - THICK
	return x >= LOW and x <= HIGH and z >= LOW and z <= HIGH and not inside
end

local function opening(x: number, y: number, z: number): boolean
	local mid = (LOW + HIGH) // 2
	-- The door, through the front wall.
	if z <= LOW + THICK - 1 and math.abs(x - mid) <= 1 and y <= 4 then
		return true
	end
	-- Arrow slits: one cell wide, two tall, in the middle of each face, every
	-- six layers. They stop short of the innermost ring, which the stair's
	-- steps lean on.
	local slit = (y - 2) % 6 == 0 or (y - 2) % 6 == 1
	local innermost = x == LOW + THICK - 1 or x == HIGH - THICK + 1 or z == LOW + THICK - 1 or z == HIGH - THICK + 1
	if y > 6 and slit and (x == mid or z == mid) and not innermost then
		return true
	end
	return false
end

for y = 2, HEIGHT + 1 do
	for z = LOW, HIGH do
		for x = LOW, HIGH do
			if inWall(x, z) and not opening(x, y, z) then
				add(x, y, z, "stone")
			end
		end
	end
end

-- Floors inside, leaving a hole by the stair.
local IN_LOW, IN_HIGH = LOW + THICK, HIGH - THICK
for _, y in FLOORS do
	for z = IN_LOW, IN_HIGH do
		for x = IN_LOW, IN_HIGH do
			local stairHole = z == IN_HIGH and x >= IN_HIGH - 2
			if not stairHole then
				add(x, y + 1, z, "timber")
			end
		end
	end
end

-- The stair: one step a layer, winding round inside the walls, each step
-- jutting from the wall it follows.
local ring = {}
for x = IN_LOW, IN_HIGH do
	table.insert(ring, { x, IN_HIGH })
end
for z = IN_HIGH - 1, IN_LOW, -1 do
	table.insert(ring, { IN_HIGH, z })
end
for x = IN_HIGH - 1, IN_LOW, -1 do
	table.insert(ring, { x, IN_LOW })
end
for z = IN_LOW + 1, IN_HIGH - 1 do
	table.insert(ring, { IN_LOW, z })
end
for y = 2, HEIGHT do
	local at = ring[(y - 2) % #ring + 1]
	add(at[1], y, at[2], "timber")
end

-- The top: a parapet of alternate stones round the walls' outer edge.
local top = HEIGHT + 2
for z = LOW, HIGH do
	for x = LOW, HIGH do
		local edge = x == LOW or x == HIGH or z == LOW or z == HIGH
		if edge and (x + z) % 2 == 0 then
			add(x, top, z, "stone")
		end
	end
end

-- The lantern room in the middle of the roof, its four corner posts first.
local corners = {}
local L0, L1 = LOW + 5, HIGH - 5
for y = top, top + 3 do
	for z = L0, L1 do
		for x = L0, L1 do
			local edge = x == L0 or x == L1 or z == L0 or z == L1
			local corner = (x == L0 or x == L1) and (z == L0 or z == L1)
			if corner then
				local slot = add(x, y, z, "timber")
				if y == top + 3 then
					table.insert(corners, slot)
				end
			elseif edge then
				add(x, y, z, "lantern")
			end
		end
	end
end
-- The top of the walls inside the parapet is a floor the lantern room stands on.
for z = LOW + 1, HIGH - 1 do
	for x = LOW + 1, HIGH - 1 do
		add(x, HEIGHT + 1, z, "stone")
	end
end

-- A stepped timber roof over the lantern room, waiting for its corners.
for k = 0, 4 do
	local y = top + 4 + k
	for z = L0 - 2 + k, L1 + 2 - k do
		for x = L0 - 2 + k, L1 + 2 - k do
			add(x, y, z, "timber", if k == 0 then corners else nil)
		end
	end
end

return {
	name = "Watchtower",
	palette = { "lantern", "stone", "timber" },
	blocks = blocks,
}
