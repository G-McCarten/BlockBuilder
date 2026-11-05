local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local CollisionBoxes = require("../src/shared/CollisionBoxes")
local SiteIndex = require("../src/shared/SiteIndex")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local function standing(site: BuildSite.Site, s: number): boolean
	local state = BuildSite.state(site, s)
	return state == BuildSite.State.PLACED or state == BuildSite.State.UNDOING
end

-- Checks the boxes of every chunk cover exactly its standing blocks, once each.
local function checkCover(bp: Blueprint.Blueprint, site: BuildSite.Site, index: SiteIndex.Index): (number, number)
	local out = {}
	local boxes, cells = 0, 0
	for c = 1, index.chunkCount do
		local n = CollisionBoxes.build(index, site, c, out)
		local x0, y0, z0, x1, y1, z1 = SiteIndex.bounds(index, c)
		local covered: { [number]: boolean } = {}
		for b = 0, n - 1 do
			local bx0, by0, bz0 = out[b * 6 + 1], out[b * 6 + 2], out[b * 6 + 3]
			local bx1, by1, bz1 = out[b * 6 + 4], out[b * 6 + 5], out[b * 6 + 6]
			Test.check(bx0 >= x0 and by0 >= y0 and bz0 >= z0, `box {b} of chunk {c} starts outside it`)
			Test.check(bx1 <= x1 and by1 <= y1 and bz1 <= z1, `box {b} of chunk {c} ends outside it`)
			Test.check(bx0 < bx1 and by0 < by1 and bz0 < bz1, `box {b} of chunk {c} is empty`)
			for y = by0, by1 - 1 do
				for z = bz0, bz1 - 1 do
					for x = bx0, bx1 - 1 do
						local k = Blueprint.key(x, y, z)
						Test.check(not covered[k], `cell ({x}, {y}, {z}) covered twice`)
						covered[k] = true
						local s = Blueprint.slotAt(bp, x, y, z)
						Test.check(
							s ~= nil and standing(site, s),
							`box covers ({x}, {y}, {z}), which has no standing block`
						)
					end
				end
			end
		end
		for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
			local s = index.slotList[i]
			if standing(site, s) then
				cells += 1
				Test.check(covered[Blueprint.key(bp.x[s], bp.y[s], bp.z[s])], `standing slot {s} has no box`)
			end
		end
		boxes += n
	end
	return boxes, cells
end

Test.group("CollisionBoxes")

Test.case("a solid chunk is one box", function()
	local blocks = {}
	for y = 0, 7 do
		for z = 0, 7 do
			for x = 0, 7 do
				table.insert(blocks, { x = x, y = y, z = z, kind = 1 })
			end
		end
	end
	local bp = Blueprint.build({ name = "Cube", palette = { "a" }, blocks = blocks })
	local site = BuildSite.new(bp)
	for s = 1, bp.count do
		BuildSite.place(site, s, BuildSite.Cause.HAND, 1)
	end
	local index = SiteIndex.build(bp, 8)
	local out = {}
	Test.equal(CollisionBoxes.build(index, site, 1, out), 1, "one box")
	Test.equal(table.concat(out, ","), "0,0,0,8,8,8", "covering the chunk")
end)

Test.case("an empty chunk has no boxes", function()
	local bp = Sites.hut()
	local index = SiteIndex.build(bp, 8)
	Test.equal(CollisionBoxes.build(index, BuildSite.new(bp), 1, {}), 0, "nothing placed")
end)

Test.case("boxes cover exactly the standing blocks of part-built and finished sites", function()
	for _, bp in { Sites.lodge(), Sites.hut() } do
		local index = SiteIndex.build(bp, 8)
		for seed = 1, 3 do
			checkCover(bp, Sites.partlyBuilt(bp, seed, bp.count // 2), index)
		end
		local boxes, cells = checkCover(bp, Sites.finished(bp), index)
		print(`        {bp.name} finished: {cells} blocks in {boxes} boxes over {index.chunkCount} chunks`)
	end
end)

return nil
