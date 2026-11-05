local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local SiteIndex = require("../src/shared/SiteIndex")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

Test.group("SiteIndex")

Test.case("every slot sits in exactly one chunk, inside that chunk's bounds", function()
	for _, bp in { Sites.lodge(), Blueprint.build(Sites.terrain(4, 24, 20)) } do
		for _, size in { 4, 8, 16 } do
			local index = SiteIndex.build(bp, size)
			local seen = table.create(bp.count, 0)
			for c = 1, index.chunkCount do
				local x0, y0, z0, x1, y1, z1 = SiteIndex.bounds(index, c)
				for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
					local s = index.slotList[i]
					seen[s] += 1
					Test.equal(index.chunkOf[s], c, `chunkOf[{s}]`)
					local inside = bp.x[s] >= x0 and bp.x[s] < x1 and bp.y[s] >= y0 and bp.y[s] < y1
					Test.check(inside and bp.z[s] >= z0 and bp.z[s] < z1, `slot {s} outside chunk {c}`)
				end
			end
			for s = 1, bp.count do
				Test.equal(seen[s], 1, `slot {s} listed`)
			end
		end
	end
end)

Test.case("nearest matches a scan of every slot", function()
	local bp = Sites.lodge()
	local site = Sites.partlyBuilt(bp, 2, 2500)
	local index = SiteIndex.build(bp, 8)
	local rng = Rng.new(31)
	local function ready(s: number): boolean
		return BuildSite.state(site, s) == BuildSite.State.READY
	end
	local out = {}
	for _ = 1, 300 do
		local px, py, pz = rng:range(-5, bp.sizeX + 5), rng:range(-2, bp.sizeY + 2), rng:range(-5, bp.sizeZ + 5)
		local radius = rng:range(0, 20)
		local maxCount = ({ 1, 3, 12, 60 })[rng:int(1, 4)]
		local n = SiteIndex.nearest(index, px, py, pz, radius, ready, maxCount, out)

		local all = {}
		for s = 1, bp.count do
			local dx, dy, dz = bp.x[s] + 0.5 - px, bp.y[s] + 0.5 - py, bp.z[s] + 0.5 - pz
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 <= radius * radius and ready(s) then
				table.insert(all, { s, d2 })
			end
		end
		table.sort(all, function(a, b)
			return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1])
		end)
		Test.equal(n, math.min(maxCount, #all), "how many")
		for i = 1, n do
			Test.equal(out[i], all[i][1], `nearest #{i}`)
		end
	end
end)

Test.case("nearest with nothing in range finds nothing", function()
	local bp = Sites.hut()
	local index = SiteIndex.build(bp, 8)
	local out = {}
	Test.equal(
		SiteIndex.nearest(index, 100, 100, 100, 5, function()
			return true
		end, 5, out),
		0,
		"far away"
	)
	Test.equal(
		SiteIndex.nearest(index, 5, 0, 5, 3, function()
			return true
		end, 0, out),
		0,
		"asked for none"
	)
end)

return nil
