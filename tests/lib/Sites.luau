--[[
	Blueprints for tests: the stamped TestHut, and generated ones.
]]

local Blueprint = require("../../src/shared/Blueprint")
local Rng = require("./Rng")

local Sites = {}

function Sites.hut(): Blueprint.Blueprint
	return Blueprint.load(require("../../src/shared/Blueprints/TestHut"))
end

-- Columns of random height over a size x size square, with overhanging
-- ledges off column tops and extra ordering from lower layers to higher ones.
-- About 6,200 slots at size 24 and maxHeight 20.
function Sites.terrain(seed: number, size: number, maxHeight: number): Blueprint.Source
	local rng = Rng.new(seed)
	local palette = { "a", "b", "c", "d" }
	local blocks = {}
	local taken: { [number]: boolean } = {}
	local heights = {}
	local function add(x: number, y: number, z: number)
		taken[Blueprint.key(x, y, z)] = true
		table.insert(blocks, { x = x, y = y, z = z, kind = rng:int(1, #palette), facing = rng:int(0, 3) })
	end

	for z = 0, size - 1 do
		for x = 0, size - 1 do
			local h = rng:int(1, maxHeight)
			heights[x + z * size] = h
			for y = 0, h - 1 do
				add(x, y, z)
			end
		end
	end

	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for z = 0, size - 1 do
		for x = 0, size - 1 do
			local y = heights[x + z * size] - 1
			if y >= 1 and rng:next() < 0.15 then
				local d = dirs[rng:int(1, 4)]
				for k = 1, rng:int(1, 3) do
					local cx, cz = x + d[1] * k, z + d[2] * k
					if cx < 0 or cz < 0 or cx >= size or cz >= size or taken[Blueprint.key(cx, y, cz)] then
						break
					end
					add(cx, y, cz)
				end
			end
		end
	end

	local count = #blocks
	for _ = 1, count // 20 do
		local a, b = rng:int(1, count), rng:int(1, count)
		if blocks[a].y < blocks[b].y then
			local after = blocks[b].after or {}
			table.insert(after, a)
			blocks[b].after = after
		end
	end

	return { name = `Terrain{seed}`, palette = palette, blocks = blocks }
end

-- count slots: a floor filling layer 0 row by row, then layer 1.
function Sites.floor(count: number): Blueprint.Source
	local blocks = table.create(count)
	local side = 255
	for i = 0, count - 1 do
		local layer = i // (side * side)
		local rest = i % (side * side)
		local row = rest // side
		blocks[i + 1] = { x = rest % side, y = layer, z = row, kind = 1 }
	end
	return { name = `Floor{count}`, palette = { "a" }, blocks = blocks }
end

-- A one-cell column, optionally with steps spiralling up it. Each step juts out
-- from the column on its own layer, a quarter turn and one cell above the last.
function Sites.tower(height: number, withSteps: boolean): Blueprint.Source
	local blocks = {}
	for y = 0, height - 1 do
		table.insert(blocks, { x = 2, y = y, z = 2, kind = 1 })
	end
	if withSteps then
		local around = { { 3, 2 }, { 2, 3 }, { 1, 2 }, { 2, 1 } }
		for y = 0, height - 2 do
			local at = around[y % 4 + 1]
			table.insert(blocks, { x = at[1], y = y, z = at[2], kind = 1 })
		end
	end
	return { name = "Tower", palette = { "a" }, blocks = blocks }
end

return Sites
