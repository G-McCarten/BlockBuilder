--[[
	ModelSource: Studio models read into blueprint sources. Each test builds a
	model in memory with @lune/roblox and reads it back from a serialized file,
	as tools/stamp_blueprint reads an export from Studio.
]]

local roblox = require("@lune/roblox")

local Blueprint = require("../src/shared/Blueprint")
local BlueprintValidator = require("../src/shared/BlueprintValidator")
local ModelSource = require("../tools/lib/ModelSource")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
local STUDS = 3

-- A part filling cell (x, y, z) of a grid whose origin sits at (ox, oy, oz) studs.
local function part(
	parent,
	x: number,
	y: number,
	z: number,
	facing: number,
	kind: string?,
	ox: number?,
	oy: number?,
	oz: number?
)
	local p = Instance.new("Part")
	p.Size = Vector3.new(STUDS, STUDS, STUDS)
	local at = Vector3.new((x + 0.5) * STUDS + (ox or 0), (y + 0.5) * STUDS + (oy or 0), (z + 0.5) * STUDS + (oz or 0))
	p.CFrame = CFrame.new(at.X, at.Y, at.Z) * CFrame.Angles(0, facing * math.pi / 2, 0)
	if kind then
		p:SetAttribute("Kind", kind)
	end
	p.Name = "Block"
	p.Parent = parent
	return p
end

-- A part filling the cells from (x, y, z), sx by sy by sz cells across the
-- world, turned facing quarter turns. A quarter turn lays the part's own x
-- along the world's z, so its Size swaps them back.
local function box(
	parent,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	facing: number?
)
	local f = facing or 0
	local p = Instance.new("Part")
	p.Name = name
	if f % 2 == 1 then
		p.Size = Vector3.new(sz * STUDS, sy * STUDS, sx * STUDS)
	else
		p.Size = Vector3.new(sx * STUDS, sy * STUDS, sz * STUDS)
	end
	p.CFrame = CFrame.new((x + sx / 2) * STUDS, (y + sy / 2) * STUDS, (z + sz / 2) * STUDS)
		* CFrame.Angles(0, f * math.pi / 2, 0)
	p.Parent = parent
	return p
end

-- A Model or Folder with the given attributes.
local function group(className: string, name: string, parent, attributes: { [string]: any }?)
	local g = Instance.new(className)
	g.Name = name
	for key, value in attributes or {} do
		g:SetAttribute(key, value)
	end
	g.Parent = parent
	return g
end

local function read(model, xml: boolean?)
	return ModelSource.fromContents(roblox.serializeModel({ model }, xml), "Test", STUDS)
end

-- Each block's index in a source, by cell.
local function cellMap(source): { [number]: number }
	local map = {}
	for i, b in source.blocks do
		map[Blueprint.key(b.x, b.y, b.z)] = i
	end
	return map
end

local function blockAt(source, x: number, y: number, z: number)
	local i = cellMap(source)[Blueprint.key(x, y, z)]
	Test.check(i ~= nil, `a block at ({x}, {y}, {z})`)
	return source.blocks[i :: number]
end

-- A slot's extra supports, as the sorted cells of the slots they name,
-- shifted by (dx, dz).
local function extraCells(bp: Blueprint.Blueprint, s: number, dx: number, dz: number): string
	local cells = {}
	for i = bp.supportStart[s] + (if bp.physical[s] ~= 0 then 1 else 0), bp.supportStart[s + 1] - 1 do
		local t = bp.supportList[i]
		table.insert(cells, Blueprint.key(bp.x[t] - dx, bp.y[t], bp.z[t] - dz))
	end
	table.sort(cells)
	return table.concat(cells, ",")
end

-- The slots of a source's blocks at the given cells, sorted, as after lists them.
local function slotsAt(source, cells: { { number } }): string
	local map = cellMap(source)
	local slots = {}
	for _, c in cells do
		table.insert(slots, map[Blueprint.key(c[1], c[2], c[3])])
	end
	table.sort(slots)
	return table.concat(slots, ",")
end

local function afterOf(block): string
	return if block.after then table.concat(block.after, ",") else ""
end

local function says(message: string, ...: string)
	for _, piece in { ... } do
		Test.check(string.find(message, piece, 1, true) ~= nil, `"{message}" should say "{piece}"`)
	end
end

-- The house's wall corners on its top layer, in the cells the stamp gives it.
local HOUSE_WALL_CORNERS = { { 1, 3, 1 }, { 7, 3, 1 }, { 1, 3, 7 }, { 7, 3, 7 } }

-- A small house, on the grid at cell (10, 2, -5): a floor, walls with a door
-- (Stage 1) and a stepped roof with a chimney (Stage 2) that overhangs the
-- walls by a cell. Its parts span many cells, the side walls are turned,
-- and most parts take their kind from the groups around them. 236 blocks.
local function house()
	local ox, oy, oz = 10, 2, -5
	local function add(
		parent,
		name: string,
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		f: number?
	)
		return box(parent, name, x + ox, y + oy, z + oz, sx, sy, sz, f)
	end
	local model = group("Model", "House", nil, { Kind = "stone" })
	local floor = group("Folder", "Floor", model)
	add(floor, "Slab", 1, 0, 1, 7, 1, 7)
	local walls = group("Model", "Walls", model, { Kind = "timber", Stage = 1 })
	add(walls, "FrontLeft", 1, 1, 1, 3, 3, 1)
	add(walls, "FrontRight", 5, 1, 1, 3, 3, 1)
	add(walls, "Lintel", 4, 3, 1, 1, 1, 1)
	add(walls, "Back", 1, 1, 7, 7, 3, 1, 2)
	add(walls, "Left", 1, 1, 2, 1, 3, 5, 1)
	add(walls, "Right", 7, 1, 2, 1, 3, 5, 3)
	local roof = group("Model", "Roof", model, { Kind = "thatch", Stage = 2 })
	add(roof, "Eaves", 0, 4, 0, 9, 1, 9)
	add(roof, "Ridge", 2, 5, 2, 5, 1, 5)
	add(roof, "Cap", 3, 6, 3, 3, 1, 3, 2)
	add(roof, "Chimney", 7, 5, 7, 1, 2, 1):SetAttribute("Kind", "stone")
	return model
end

-- Puts every group's children back in the opposite order.
local function reverseChildren(instance)
	local children = instance:GetChildren()
	for _, child in children do
		child.Parent = nil
	end
	for i = #children, 1, -1 do
		children[i].Parent = instance
		reverseChildren(children[i])
	end
end

Test.group("ModelSource")

Test.case("a model of the TestHut stamps to the same cells, kinds and facings", function()
	local hut = Sites.hut()
	local model = Instance.new("Model")
	-- Somewhere in the world on the grid, with parts in no useful order.
	for s = hut.count, 1, -1 do
		part(model, hut.x[s], hut.y[s], hut.z[s], hut.facing[s], hut.palette[hut.kind[s]], 30, 9, -60)
	end
	local bp = Blueprint.build(read(model))
	Test.equal(bp.count, hut.count, "count")
	Test.equal(table.concat(bp.palette, ","), "base,roof,step,wall", "palette in alphabetical order")
	-- The hut's lowest corner is at x 1, z 0, so the model's cells shift by that.
	local minX, minZ = math.huge, math.huge
	for s = 1, hut.count do
		minX, minZ = math.min(minX, hut.x[s]), math.min(minZ, hut.z[s])
	end
	for s = 1, hut.count do
		local t = Blueprint.slotAt(bp, hut.x[s] - minX, hut.y[s], hut.z[s] - minZ)
		Test.check(t ~= nil, `cell of hut slot {s}`)
		Test.equal(bp.palette[bp.kind[t :: number]], hut.palette[hut.kind[s]], `kind of {s}`)
		Test.equal(bp.facing[t :: number], hut.facing[s], `facing of {s}`)
	end
	local report = BlueprintValidator.validate(bp)
	Test.check(report.ok, table.concat(report.errors, "\n"))
end)

Test.case("a part a whole number of cells across becomes a block in each cell it covers", function()
	local model = Instance.new("Model")
	-- A wall 10 cells long and 4 high, and a turned one 4 cells long along z.
	box(model, "Wall", 0, 0, 0, 10, 4, 1)
	local turned = box(model, "Turned", 12, 0, 2, 1, 2, 4, 1)
	Test.equal(tostring(turned.Size), tostring(Vector3.new(12, 6, 3)), "the turned wall's own size")
	local source = read(model)
	Test.equal(#source.blocks, 40 + 8, "one block per cell")
	for y = 0, 3 do
		for x = 0, 9 do
			local b = blockAt(source, x, y, 0)
			Test.equal(b.kind, "Wall", "the wall's kind")
			Test.equal(b.facing, 0, "the wall's facing")
		end
	end
	for y = 0, 1 do
		for z = 2, 5 do
			local b = blockAt(source, 12, y, z)
			Test.equal(b.kind, "Turned", "the turned wall's kind")
			Test.equal(b.facing, 1, "the turned wall's facing")
		end
	end
	-- Lowest layer first, then by z, then by x.
	for i = 2, #source.blocks do
		local a, b = source.blocks[i - 1], source.blocks[i]
		Test.check(a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x))), `order at {i}`)
	end
	-- A part 2 cells wide on each side, turned half way, fills its 8 cells.
	local cube = Instance.new("Model")
	box(cube, "Cube", 3, 5, 3, 2, 2, 2, 2)
	local cubeSource = read(cube)
	Test.equal(#cubeSource.blocks, 8, "a 2-cell cube")
	Test.equal(blockAt(cubeSource, 1, 1, 1).facing, 2, "the cube's facing")
end)

Test.case("a part's kind is its Kind, else its nearest Model's or Folder's, else its name", function()
	local model = group("Model", "House", nil, { Kind = "stone" })
	local walls = group("Folder", "Walls", model)
	part(walls, 0, 0, 0, 0).Name = "Plain"
	local roof = group("Folder", "Roof", model, { Kind = "thatch" })
	part(roof, 1, 0, 0, 0)
	part(roof, 2, 0, 0, 0, "slate")
	-- A part inside a part takes its kind from the group around them both.
	part(part(roof, 3, 0, 0, 0, "glass"), 4, 0, 0, 0)
	-- An empty Kind is no Kind, and a nested group without one passes the outer one on.
	part(group("Model", "Shed", model, { Kind = "" }), 5, 0, 0, 0)
	local loose = Instance.new("Model")
	loose.Name = "Loose"
	part(loose, 0, 0, 0, 0).Name = "granite"
	local source = read(model)
	Test.equal(blockAt(source, 0, 0, 0).kind, "stone", "from the model, through a folder without a Kind")
	Test.equal(blockAt(source, 1, 0, 0).kind, "thatch", "from the nearest folder")
	Test.equal(blockAt(source, 2, 0, 0).kind, "slate", "its own Kind")
	Test.equal(blockAt(source, 3, 0, 0).kind, "glass", "the outer part's own Kind")
	Test.equal(blockAt(source, 4, 0, 0).kind, "thatch", "a part in a part")
	Test.equal(blockAt(source, 5, 0, 0).kind, "stone", "through an empty Kind")
	Test.equal(table.concat(source.palette, ","), "glass,slate,stone,thatch", "palette")
	Test.equal(read(loose).palette[1], "granite", "with no Kind anywhere, its name")
end)

Test.case("the roof's lowest blocks wait for the walls' top corners", function()
	local source = read(house())
	Test.equal(#source.blocks, 236, "count")
	local corners = slotsAt(source, HOUSE_WALL_CORNERS)
	for i, b in source.blocks do
		if b.y == 4 then
			Test.equal(afterOf(b), corners, `eaves block {i} waits for the four corners`)
		else
			-- Walls are the first stage, the floor has none, and the rest of
			-- the roof rests on roof blocks, so waits through them.
			Test.equal(afterOf(b), "", `block {i} at layer {b.y} waits only on its supports`)
		end
	end
	Test.equal(blockAt(source, 7, 5, 7).kind, "stone", "the chimney's own Kind")
	Test.equal(blockAt(source, 7, 4, 7).kind, "thatch", "the roof's Kind")
	Test.equal(blockAt(source, 4, 3, 1).kind, "timber", "the walls' Kind")
	Test.equal(blockAt(source, 4, 0, 4).kind, "stone", "the house's Kind")
	Test.equal(table.concat(source.stages, "; "), "House: 1 (70 blocks), 2 (117 blocks)", "stage summary")
end)

Test.case("a staged model of the TestHut orders its roof as the script does", function()
	local hut = Sites.hut()
	local model = group("Model", "Hut")
	local groups = {
		base = group("Folder", "Floor", model, { Kind = "base" }),
		wall = group("Model", "Walls", model, { Kind = "wall", Stage = 1 }),
		roof = group("Model", "Roof", model, { Kind = "roof", Stage = 2 }),
		step = group("Folder", "Steps", model, { Kind = "step" }),
	}
	for s = 1, hut.count do
		part(groups[hut.palette[hut.kind[s]]], hut.x[s], hut.y[s], hut.z[s], hut.facing[s])
	end
	local bp = Blueprint.build(read(model))
	Test.equal(bp.count, hut.count, "count")
	-- The script waits on the wall's four top corners from every block of the
	-- slab roof, and on nothing else.
	local waiting = 0
	for s = 1, hut.count do
		local t = Blueprint.slotAt(bp, hut.x[s] - 1, hut.y[s], hut.z[s]) :: number
		Test.equal(extraCells(bp, t, 0, 0), extraCells(hut, s, 1, 0), `extra supports of hut slot {s}`)
		if hut.supportStart[s + 1] - hut.supportStart[s] > 1 then
			waiting += 1
		end
	end
	Test.equal(waiting, 121, "the slab roof waits")
	Test.check(BlueprintValidator.validate(bp).ok, "validates")
end)

Test.case("stages run in order, nest, and leave blocks without a Stage alone", function()
	-- Pillars on the ground, each a stage of the site: A at 1, D at 1.5, B
	-- at 2, and C at 3, which holds stages of its own. X has no Stage.
	local site = group("Model", "Site")
	box(group("Model", "A", site, { Stage = 1 }), "A", 0, 0, 0, 1, 2, 1)
	box(group("Folder", "D", site, { Stage = 1.5 }), "D", 2, 0, 0, 1, 3, 1)
	box(group("Model", "B", site, { Stage = 2 }), "B", 4, 0, 0, 1, 2, 1)
	local c = group("Model", "C", site, { Stage = 3 })
	box(c, "First", 6, 0, 0, 1, 2, 1):SetAttribute("Stage", 1)
	box(c, "Second", 8, 0, 0, 1, 1, 1):SetAttribute("Stage", 2)
	box(site, "X", 10, 0, 0, 1, 3, 1)
	local source = read(site)
	local function after(x: number, y: number): string
		return afterOf(blockAt(source, x, y, 0))
	end
	local function slot(x: number, y: number): string
		return slotsAt(source, { { x, y, 0 } })
	end
	Test.equal(after(0, 0), "", "the first stage waits for nothing")
	Test.equal(after(2, 0), slot(0, 1), "1.5 waits for the top of 1")
	Test.equal(after(4, 0), slot(2, 2), "2 waits for the top of 1.5, not of 1")
	Test.equal(after(4, 1), "", "a block resting on its own stage waits through it")
	Test.equal(after(6, 0), slot(4, 1), "3 waits for the top of 2")
	Test.equal(after(6, 1), "", "the first stage inside C rests on its own stage")
	Test.equal(after(8, 0), slotsAt(source, { { 4, 1, 0 }, { 6, 1, 0 } }), "C's second stage waits in both groups")
	for y = 0, 2 do
		Test.equal(after(10, y), "", "no Stage, no waiting")
	end
	Test.equal(
		table.concat(source.stages, "; "),
		"Site: 1 (2 blocks), 1.5 (3 blocks), 2 (2 blocks), 3 (3 blocks); Site.C: 1 (2 blocks), 2 (1 block)",
		"stage summary"
	)
	local bp = Blueprint.build(source)
	Test.check(BlueprintValidator.validate(bp).ok, "validates")
end)

Test.case("a Stage on loose parts orders them within their group", function()
	-- Three columns side by side in one model, staged part by part: the last
	-- waits for the top corners of the middle one's top layer, a 2 x 2 slab.
	local model = group("Model", "Yard")
	box(model, "Low", 0, 0, 0, 2, 1, 2):SetAttribute("Stage", 1)
	box(model, "Mid", 3, 0, 0, 2, 3, 2):SetAttribute("Stage", 2)
	box(model, "High", 6, 0, 0, 1, 4, 1):SetAttribute("Stage", 3)
	local source = read(model)
	local mid = slotsAt(source, { { 3, 2, 0 }, { 4, 2, 0 }, { 3, 2, 1 }, { 4, 2, 1 } })
	Test.equal(afterOf(blockAt(source, 6, 0, 0)), mid, "waits for all four corners of a 2 x 2 top")
	Test.equal(
		afterOf(blockAt(source, 4, 0, 1)),
		slotsAt(source, { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { 1, 0, 1 } })
	)
	Test.equal(afterOf(blockAt(source, 4, 1, 1)), "", "resting on its own stage")
end)

Test.case("the stamp doesn't depend on the order of parts and groups in the model", function()
	local model = house()
	local data = Blueprint.encode(Blueprint.build(read(model)))
	reverseChildren(model)
	Test.check(model:GetChildren()[1].Name == "Roof", "the children were reversed")
	Test.equal(Blueprint.encode(Blueprint.build(read(model))), data, "same stamp reversed")
	Test.equal(Blueprint.encode(Blueprint.build(read(model, true))), data, "same stamp from .rbxmx")
end)

Test.case("a small staged house round trips through a file, Blueprint.build and the validator", function()
	local source = ModelSource.fromContents(roblox.serializeModel({ house() }), "House", STUDS)
	local bp = Blueprint.build(source)
	local report = BlueprintValidator.validate(bp)
	Test.check(report.ok, table.concat(report.errors, "\n"))
	Test.equal(bp.count, 236, "count")
	Test.equal(table.concat(bp.palette, ","), "stone,thatch,timber", "palette")
	Test.equal(bp.sizeX * 100 + bp.sizeY * 10 + bp.sizeZ, 979, "9 x 7 x 9 cells")
	-- 81 eaves blocks wait for 4 corners, less the 4 that rest on one.
	Test.equal(report.stats.extraSupports, 81 * 4 - 4, "extra supports")

	local back = Blueprint.decode(Blueprint.encode(bp), bp.name, bp.palette)
	for _, field in { "x", "y", "z", "kind", "facing", "physical", "supportStart", "supportList" } do
		Test.equal(table.concat((back :: any)[field], ","), table.concat((bp :: any)[field], ","), field)
	end

	-- Placing whatever is ready, with the walls' corners held back, lays the
	-- floor and the rest of the walls but no roof. Then everything goes.
	local corners: { [number]: boolean } = {}
	for _, c in HOUSE_WALL_CORNERS do
		corners[Blueprint.slotAt(bp, c[1], c[2], c[3]) :: number] = true
	end
	local placed = table.create(bp.count, false)
	local function placeReady(holdBack: boolean): number
		local count = 0
		repeat
			local more = false
			for s = 1, bp.count do
				if not placed[s] and not (holdBack and corners[s]) then
					local ready = true
					for i = bp.supportStart[s], bp.supportStart[s + 1] - 1 do
						ready = ready and placed[bp.supportList[i]]
					end
					if ready then
						placed[s], more, count = true, true, count + 1
					end
				end
			end
		until not more
		return count
	end
	Test.equal(placeReady(true), 49 + 70 - 4, "the floor and walls, but the corners")
	for s = 1, bp.count do
		if bp.palette[bp.kind[s]] == "thatch" then
			Test.check(not placed[s], `roof slot {s} waits for the corners`)
		end
	end
	Test.equal(placeReady(false), 4 + 117, "the corners, then the roof")
end)

Test.case("parts that aren't whole cells, upright, quarter-turned and on the grid are refused, naming them", function()
	local function refusal(make, what: string): string
		local model = Instance.new("Model")
		make(model)
		local ok, err = pcall(read, model)
		Test.check(not ok, `{what} should be refused`)
		return tostring(err)
	end
	says(
		refusal(function(m)
			part(m, 0, 0, 0, 0).Size = Vector3.new(3, 4, 3)
		end, "a part 4 studs high"),
		"Model.Block at (1.5, 1.5, 1.5): size (3, 4, 3) isn't a whole number of 3-stud cells on every axis"
	)
	says(
		refusal(function(m)
			part(m, 0, 0, 0, 0).Size = Vector3.new(3, 0.2, 3)
		end, "a thin plate"),
		"isn't a whole number of 3-stud cells"
	)
	says(
		refusal(function(m)
			local p = part(m, 0, 0, 0, 0)
			p.CFrame = p.CFrame + Vector3.new(1, 0, 0)
		end, "an off-grid part"),
		"Model.Block at (2.5, 1.5, 1.5): is off the 3-stud grid along x, by 1 stud"
	)
	says(
		refusal(function(m)
			box(m, "Beam", 0, 0, 0, 2, 1, 1).CFrame = CFrame.new(1.5, 1.5, 1.5)
		end, "a 2-cell part centred on a cell"),
		"Model.Beam at (1.5, 1.5, 1.5): is off the 3-stud grid along x, by 1.5 studs"
	)
	says(
		refusal(function(m)
			local p = part(m, 0, 0, 0, 0)
			p.CFrame = p.CFrame * CFrame.Angles(math.rad(90), 0, 0)
		end, "a part on its side"),
		"Model.Block at (1.5, 1.5, 1.5): isn't upright"
	)
	says(
		refusal(function(m)
			local p = part(m, 0, 0, 0, 0)
			p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(2))
		end, "a part tilted 2 degrees"),
		"isn't upright"
	)
	says(
		refusal(function(m)
			local p = part(m, 0, 0, 0, 0)
			p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(45), 0)
		end, "a part turned 45 degrees"),
		"Model.Block at (1.5, 1.5, 1.5): is turned 45 degrees, not a whole quarter turn"
	)
	says(
		refusal(function(m)
			box(m, "Front", 0, 0, 0, 4, 1, 1)
			box(m, "Side", 3, 0, 0, 1, 1, 4, 1)
		end, "two walls sharing a corner"),
		"Model.Front at (6, 1.5, 1.5) and Model.Side at (10.5, 1.5, 6) both cover the cell centred at (10.5, 1.5, 1.5)"
	)
	says(refusal(function() end, "an empty model"), "Test: the model has no parts")
	says(
		refusal(function(m)
			part(m, 0, 0, 0, 0):SetAttribute("Kind", 5)
		end, "a number for a Kind"),
		"Model.Block at (1.5, 1.5, 1.5): its Kind attribute is a number; make it a string"
	)
	says(
		refusal(function(m)
			part(group("Model", "Roof", m, { Stage = "2" }), 0, 0, 0, 0)
		end, "a string for a Stage"),
		"Model.Roof: its Stage attribute is a string; make it a number"
	)
	says(
		refusal(function(m)
			part(m, 0, 0, 0, 0):SetAttribute("Stage", math.huge)
		end, "an endless Stage"),
		"Model.Block at (1.5, 1.5, 1.5): its Stage is inf; make it a finite number"
	)
	says(
		refusal(function(m)
			part(m, 0, 0, 0, 0).Name = "Near"
			part(m, 300, 0, 0, 0).Name = "Far"
		end, "a model wider than a site"),
		"the model spans 301 cells along x, more than the 256 a site can hold, "
			.. "from Model.Near at (1.5, 1.5, 1.5) to Model.Far at (901.5, 1.5, 1.5)"
	)
	says(
		refusal(function(m)
			box(m, "Field", 0, 0, 0, 256, 1, 256)
		end, "more cells than a site can hold"),
		"the model's parts cover 65536 cells, more than the 65535 blocks a site can hold; "
			.. "the biggest, Model.Field at (384, 1.5, 384), covers 65536"
	)
end)

Test.case("validator messages about a model name the parts behind their slots", function()
	local model = group("Model", "Camp")
	box(model, "Ground", 0, 0, 0, 3, 1, 3)
	box(model, "Lamp", 1, 3, 1, 1, 1, 1)
	local source = read(model)
	local report = BlueprintValidator.validate(Blueprint.build(source))
	Test.equal(report.errorCount, 1, "one problem")
	says(report.errors[1], "floats")
	Test.equal(table.concat(ModelSource.explain(source, report.errors[1]), "; "), "from Camp.Lamp at (4.5, 10.5, 4.5)")

	-- Walls marked after the roof they hold up: a cycle.
	local wrong = group("Model", "Hut")
	box(group("Model", "Walls", wrong, { Stage = 2 }), "Post", 0, 0, 0, 1, 3, 1)
	box(group("Model", "Roof", wrong, { Stage = 1 }), "Top", 0, 3, 0, 1, 1, 1)
	local cyclic = read(wrong)
	local cycle = BlueprintValidator.validate(Blueprint.build(cyclic))
	says(cycle.errors[1], "supports form a cycle", "including 1, 2, 3, 4")
	local lines = ModelSource.explain(cyclic, cycle.errors[1])
	Test.equal(#lines, 5, "four slots and a hint")
	Test.equal(lines[1], "slot 1 from Hut.Walls.Post at (1.5, 4.5, 1.5)", "the first slot's part")
	Test.equal(lines[4], "slot 4 from Hut.Roof.Top at (1.5, 10.5, 1.5)", "the last slot's part")
	says(lines[5], "Stage")

	Test.equal(#ModelSource.explain(Sites.terrain(1, 4, 3), "slot 1 at (0, 0, 0): floats"), 0, "a script's source")
end)

return nil
