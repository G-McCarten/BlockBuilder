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

local function read(model)
	return ModelSource.fromContents(roblox.serializeModel({ model }), "Test", STUDS)
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

Test.case("a part's name is its kind when it has no Kind attribute", function()
	local model = Instance.new("Model")
	local p = part(model, 0, 0, 0, 0)
	p.Name = "granite"
	local source = read(model)
	Test.equal(source.palette[1], "granite", "kind")
	Test.equal(source.blocks[1].x, 0, "cell")
end)

Test.case("parts that aren't one upright, quarter-turned cell on the grid are refused", function()
	local function refuses(make, what: string)
		local model = Instance.new("Model")
		make(model)
		local ok, err = pcall(read, model)
		Test.check(not ok, `{what} should be refused`)
		return tostring(err)
	end
	Test.check(
		string.find(
			refuses(function(m)
				part(m, 0, 0, 0, 0).Size = Vector3.new(3, 6, 3)
			end, "a tall part"),
			"isn't one",
			1,
			true
		),
		"size message"
	)
	Test.check(
		string.find(
			refuses(function(m)
				local p = part(m, 0, 0, 0, 0)
				p.CFrame = p.CFrame + Vector3.new(1, 0, 0)
			end, "an off-grid part"),
			"off the",
			1,
			true
		),
		"grid message"
	)
	Test.check(
		string.find(
			refuses(function(m)
				local p = part(m, 0, 0, 0, 0)
				p.CFrame = p.CFrame * CFrame.Angles(math.rad(90), 0, 0)
			end, "a part on its side"),
			"upright",
			1,
			true
		),
		"upright message"
	)
	Test.check(
		string.find(
			refuses(function(m)
				local p = part(m, 0, 0, 0, 0)
				p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(45), 0)
			end, "a part turned 45 degrees"),
			"quarter turn",
			1,
			true
		),
		"turn message"
	)
	Test.check(
		string.find(
			refuses(function(m)
				part(m, 2, 0, 2, 0)
				part(m, 2, 0, 2, 1)
			end, "two parts in one cell"),
			"shares cell",
			1,
			true
		),
		"overlap message"
	)
	Test.check(string.find(refuses(function() end, "an empty model"), "no parts", 1, true), "empty message")
end)

return nil
