--[[
	ModelSource: reads a Studio model of grid-aligned parts into a Blueprint.Source.

	Build a site in Studio from parts BLOCK_STUDS on a side, snapped to a grid of
	that size, and export it as .rbxm or .rbxmx to tools/blueprints/<Name>. Each
	part becomes one block:

	  cell    the part's centre on the grid, shifted so the lowest cells sit at
	          0 on every axis. The lowest layer rests on the ground.
	  kind    the part's Kind attribute, or its name. The palette lists the
	          kinds in alphabetical order.
	  facing  quarter turns about y: 0 faces -z, 1 faces -x, 2 faces +z, 3 faces +x

	Parts must be exactly one cell, upright, and turned only in quarter turns
	about y. Supports are the defaults; extra ordering isn't read from models yet.
]]

local roblox = require("@lune/roblox")

local ModelSource = {}

local EPSILON = 0.01

local function near(v: number, target: number): boolean
	return math.abs(v - target) <= EPSILON
end

local function describe(part): string
	return `{part:GetFullName()}`
end

-- Reads parts from the given instances and their descendants.
function ModelSource.fromInstances(roots: { any }, name: string, blockStuds: number)
	local parts = {}
	for _, root in roots do
		if root:IsA("BasePart") then
			table.insert(parts, root)
		end
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	if #parts == 0 then
		error(`{name}: the model has no parts`)
	end

	local cells = {}
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local kinds: { [string]: boolean } = {}
	for _, part in parts do
		local size = part.Size
		if not (near(size.X, blockStuds) and near(size.Y, blockStuds) and near(size.Z, blockStuds)) then
			error(`{describe(part)}: size {size} isn't one {blockStuds}-stud cell`)
		end
		local cf = part.CFrame
		local up = cf.UpVector
		if not near(up.Y, 1) then
			error(`{describe(part)}: isn't upright`)
		end
		local look = cf.LookVector
		local turn = math.atan2(-look.X, -look.Z) / (math.pi / 2)
		if not near(turn, math.round(turn)) then
			error(`{describe(part)}: isn't turned a whole quarter turn`)
		end
		local p = cf.Position
		local fx, fy, fz = p.X / blockStuds - 0.5, p.Y / blockStuds - 0.5, p.Z / blockStuds - 0.5
		local cx, cy, cz = math.round(fx), math.round(fy), math.round(fz)
		if not (near(fx, cx) and near(fy, cy) and near(fz, cz)) then
			error(`{describe(part)}: at {p}, off the {blockStuds}-stud grid`)
		end
		local kind = part:GetAttribute("Kind")
		if type(kind) ~= "string" or kind == "" then
			kind = part.Name
		end
		kinds[kind] = true
		table.insert(cells, { cx, cy, cz, kind, math.round(turn) % 4, describe(part) })
		minX, minY, minZ = math.min(minX, cx), math.min(minY, cy), math.min(minZ, cz)
	end

	local palette = {}
	for kind in kinds do
		table.insert(palette, kind)
	end
	table.sort(palette)

	-- Lowest layer first, so slot order doesn't depend on the model's.
	table.sort(cells, function(a, b)
		if a[2] ~= b[2] then
			return a[2] < b[2]
		elseif a[3] ~= b[3] then
			return a[3] < b[3]
		end
		return a[1] < b[1]
	end)

	local blocks = table.create(#cells)
	local seen: { [string]: string } = {}
	for i, c in cells do
		local x, y, z = c[1] - minX, c[2] - minY, c[3] - minZ
		local cellKey = `{x},{y},{z}`
		if seen[cellKey] then
			error(`{c[6]}: shares cell ({x}, {y}, {z}) with {seen[cellKey]}`)
		end
		seen[cellKey] = c[6]
		blocks[i] = { x = x, y = y, z = z, kind = c[4], facing = c[5] }
	end
	return { name = name, palette = palette, blocks = blocks }
end

-- Reads a .rbxm or .rbxmx file's contents.
function ModelSource.fromContents(contents: string, name: string, blockStuds: number)
	return ModelSource.fromInstances(roblox.deserializeModel(contents), name, blockStuds)
end

return ModelSource
