--[[
	IceBridge: the second site, in graybox. About 7,300 blocks.

	An ice bridge on stone piers. Arches spring between the piers, carrying
	a deck two cells thick, eleven wide and 72 long. A ramp climbs to the deck
	at each end, and rope rails on posts run along both sides.

	The bridge runs along x; its deck spans z 4..14.

	Stamp it with: lune run tools/stamp_blueprint IceBridge
]]

local blocks = {}
local taken: { [number]: boolean } = {}

local function add(x: number, y: number, z: number, kind: string, facing: number?)
	local k = x + 256 * (y + 256 * z)
	if taken[k] then
		return
	end
	taken[k] = true
	table.insert(blocks, { x = x, y = y, z = z, kind = kind, facing = facing })
end

local X0, X1 = 20, 91 -- the deck's length
local Z0, Z1 = 4, 14 -- its width
local DECK = 8 -- the deck's lower layer
local PIER_EVERY = 12
local RAMP = 18 -- cells each ramp runs

-- Piers: stone, three cells long, from the ground to the deck.
local piers = {}
for x = X0, X1, PIER_EVERY do
	table.insert(piers, x)
	for px = x, math.min(x + 2, X1) do
		for y = 0, DECK - 1 do
			for z = Z0, Z1 do
				add(px, y, z, "stone")
			end
		end
	end
end

-- Arches: ice, filling under the deck above an arched opening between piers.
for i = 1, #piers - 1 do
	local from, to = piers[i] + 3, piers[i + 1] - 1
	local span = to - from + 1
	for x = from, to do
		local t = (x - from + 0.5) / span
		local opening = math.floor(6 * math.sin(math.pi * t) + 0.5)
		for y = opening, DECK - 1 do
			for z = Z0, Z1 do
				add(x, y, z, "ice")
			end
		end
	end
end

-- The deck, two cells thick.
for y = DECK, DECK + 1 do
	for z = Z0, Z1 do
		for x = X0, X1 do
			add(x, y, z, "ice")
		end
	end
end

-- Ramps: a solid wedge at each end, one cell up every two cells along.
for i = 0, RAMP - 1 do
	local height = math.floor(i / 2) + 1
	for z = Z0, Z1 do
		for y = 0, math.min(height, DECK + 2) - 1 do
			add(X0 - RAMP + i, y, z, "ice", 3)
			add(X1 + RAMP - i, y, z, "ice", 1)
		end
	end
end

-- Rope rails: posts every third cell along both edges, a rail on top between them.
local top = DECK + 2
for _, z in { Z0, Z1 } do
	for x = X0, X1 do
		if (x - X0) % 3 == 0 then
			add(x, top, z, "rope")
		end
		add(x, top + 1, z, "rope")
	end
end

return {
	name = "IceBridge",
	palette = { "ice", "rope", "stone" },
	blocks = blocks,
}
