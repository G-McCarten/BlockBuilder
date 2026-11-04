local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Blueprint = require("../src/shared/Blueprint")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Dir = Blueprint.Dir

local FIELDS = {
	"x",
	"y",
	"z",
	"kind",
	"facing",
	"physical",
	"supportStart",
	"supportList",
	"dependentStart",
	"dependentList",
}

local function sameBlueprint(a: Blueprint.Blueprint, b: Blueprint.Blueprint)
	Test.equal(b.count, a.count, "count")
	Test.equal(b.sizeX, a.sizeX, "sizeX")
	Test.equal(b.sizeY, a.sizeY, "sizeY")
	Test.equal(b.sizeZ, a.sizeZ, "sizeZ")
	for _, field in FIELDS do
		local x, y = (a :: any)[field], (b :: any)[field]
		Test.equal(#y, #x, `length of {field}`)
		for i = 1, #x do
			Test.equal(y[i], x[i], `{field}[{i}]`)
		end
	end
end

local function supportsOf(bp: Blueprint.Blueprint, s: number): { number }
	local list = {}
	for i = bp.supportStart[s], bp.supportStart[s + 1] - 1 do
		table.insert(list, bp.supportList[i])
	end
	return list
end

Test.group("Blueprint")

Test.case("base64 round-trips every length from 0 to 64 bytes", function()
	local rng = Rng.new(7)
	for len = 0, 64 do
		local buf = buffer.create(len)
		for i = 0, len - 1 do
			buffer.writeu8(buf, i, rng:int(0, 255))
		end
		local text = Blueprint.toBase64(buf)
		Test.equal(#text % 4, 0, "padded length")
		Test.equal(buffer.tostring(Blueprint.fromBase64(text)), buffer.tostring(buf), `bytes of length {len}`)
	end
	Test.equal(Blueprint.toBase64(buffer.fromstring("Man")), "TWFu", "known value")
	Test.equal(Blueprint.toBase64(buffer.fromstring("Ma")), "TWE=", "known value with padding")
end)

Test.case("base64 rejects malformed text", function()
	Test.check(not pcall(Blueprint.fromBase64, "abc"), "length not a multiple of 4")
	Test.check(not pcall(Blueprint.fromBase64, "ab!d"), "character outside the alphabet")
end)

Test.case("default supports: ground, beneath, overhang, floating", function()
	local bp = Blueprint.build({
		name = "Small",
		palette = { "a" },
		blocks = {
			{ x = 0, y = 0, z = 0, kind = 1 },
			{ x = 0, y = 1, z = 0, kind = 1 },
			{ x = 1, y = 1, z = 0, kind = 1 },
			{ x = 2, y = 1, z = 0, kind = 1 },
			{ x = 9, y = 3, z = 9, kind = 1 },
		},
	})
	Test.equal(bp.physical[1], Dir.GROUND, "on the ground")
	Test.equal(bp.physical[2], Dir.BELOW, "on the cell beneath")
	Test.equal(bp.physical[3], Dir.NEG_X, "overhang leans on its connected neighbour")
	Test.equal(bp.physical[4], Dir.NEG_X, "overhang two out leans on the first")
	Test.equal(bp.physical[5], Dir.GROUND, "floating block gets no support")
	Test.equal(#supportsOf(bp, 1), 0, "ground block has no supports")
	Test.equal(supportsOf(bp, 3)[1], 2, "overhang's support is the block it leans on")
	Test.equal(supportsOf(bp, 4)[1], 3, "chain of overhangs")
end)

Test.case("a lintel over the hut's door leans on the wall beside it", function()
	local bp = Sites.hut()
	local lintel = Blueprint.slotAt(bp, 6, 3, 2)
	Test.check(lintel ~= nil, "lintel slot exists")
	Test.check(Blueprint.slotAt(bp, 6, 2, 2) == nil, "door is open beneath it")
	local dir = bp.physical[lintel :: number]
	Test.check(dir >= Dir.NEG_X and dir <= Dir.POS_Z, `lintel leans sideways, got {dir}`)
end)

Test.case("extra ordering adds supports after the physical one, without repeats", function()
	local bp = Blueprint.build({
		name = "Ordered",
		palette = { "a" },
		blocks = {
			{ x = 0, y = 0, z = 0, kind = 1 },
			{ x = 5, y = 0, z = 0, kind = 1 },
			{ x = 0, y = 1, z = 0, kind = 1, after = { 1, 2, 2 } },
		},
	})
	local supports = supportsOf(bp, 3)
	Test.equal(#supports, 2, "physical support plus one extra")
	Test.equal(supports[1], 1, "physical support first")
	Test.equal(supports[2], 2, "then the extra")
end)

Test.case("supports and dependents mirror each other", function()
	local bp = Blueprint.build(Sites.terrain(11, 24, 20))
	local seen = 0
	for s = 1, bp.count do
		for i = bp.supportStart[s], bp.supportStart[s + 1] - 1 do
			local t = bp.supportList[i]
			local found = false
			for j = bp.dependentStart[t], bp.dependentStart[t + 1] - 1 do
				if bp.dependentList[j] == s then
					found = true
				end
			end
			Test.check(found, `slot {s} rests on {t}, but {t} doesn't list it as a dependent`)
			seen += 1
		end
	end
	Test.equal(#bp.dependentList, seen, "every dependent entry matches a support")
	Test.check(bp.count > 6000, `terrain is about 6,000 slots, got {bp.count}`)
end)

Test.case("encode and decode round-trip", function()
	for seed = 1, 3 do
		local bp = Blueprint.build(Sites.terrain(seed, 24, 20))
		sameBlueprint(bp, Blueprint.decode(Blueprint.encode(bp), bp.name, bp.palette))
	end
	local hut = Blueprint.build(luau.load(fs.readFile("tools/blueprints/TestHut.luau"))())
	sameBlueprint(hut, Sites.hut())
end)

Test.case("the stamped TestHut matches its source", function()
	local source = luau.load(fs.readFile("tools/blueprints/TestHut.luau"))()
	local file = require("../src/shared/Blueprints/TestHut")
	Test.equal(file.data, Blueprint.encode(Blueprint.build(source)), "stamped data is current")
	Test.equal(file.count, 508, "slot count")
end)

Test.case("encode refuses more than 65,535 slots", function()
	local ok = pcall(Blueprint.encode, Blueprint.build(Sites.floor(65536)))
	Test.check(not ok, "65,536 slots can't be packed")
	local full = Blueprint.build(Sites.floor(65535))
	Test.equal(Blueprint.decode(Blueprint.encode(full), full.name, full.palette).count, 65535, "65,535 slots can")
end)

Test.case("decode rejects data that isn't a packed blueprint", function()
	Test.check(not pcall(Blueprint.decode, Blueprint.toBase64(buffer.fromstring("XX\1\0\0")), "Bad", {}), "magic")
	Test.check(not pcall(Blueprint.decode, Blueprint.toBase64(buffer.fromstring("BP\9\0\0")), "Bad", {}), "version")
	Test.check(
		not pcall(Blueprint.load, { name = "Bad", palette = {}, count = 3, data = "QlABAAA=" }),
		"count mismatch"
	)
end)

Test.case("build rejects cells outside 0..255 and unknown kinds", function()
	local function source(block)
		return { name = "Bad", palette = { "a" }, blocks = { block } }
	end
	Test.check(not pcall(Blueprint.build, source({ x = -1, y = 0, z = 0, kind = 1 })), "negative cell")
	Test.check(not pcall(Blueprint.build, source({ x = 256, y = 0, z = 0, kind = 1 })), "cell past 255")
	Test.check(not pcall(Blueprint.build, source({ x = 0.5, y = 0, z = 0, kind = 1 })), "fractional cell")
	Test.check(not pcall(Blueprint.build, source({ x = 0, y = 0, z = 0, kind = "nope" })), "unknown kind")
	Test.check(
		not pcall(Blueprint.build, source({ x = 0, y = 0, z = 0, kind = 1, after = { 2 } })),
		"after past the end"
	)
end)

return nil
