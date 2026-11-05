local Access = require("../src/shared/Access")
local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Cause = BuildSite.Cause
local HEADROOM = 2

Test.group("Access")

Test.case("stand on the ground or a block, with headroom, never inside a block", function()
	local bp = Sites.hut()
	local site = BuildSite.new(bp)
	Test.check(Access.canStand(bp, site, 5, 0, 5, HEADROOM), "on the ground where the floor isn't laid")
	local floor = Blueprint.slotAt(bp, 5, 0, 5) :: number
	BuildSite.place(site, floor, Cause.HAND, 1)
	Test.check(not Access.canStand(bp, site, 5, 0, 5, HEADROOM), "not inside a placed block")
	Test.check(Access.canStand(bp, site, 5, 1, 5, HEADROOM), "on top of it")
	Test.check(not Access.canStand(bp, site, 5, 2, 5, HEADROOM), "not in mid air")
	Test.check(Access.canStand(bp, site, -4, 0, -4, HEADROOM), "on the ground outside the site")
	Test.check(not Access.canStand(bp, site, 5, -1, 5, HEADROOM), "not below the ground")
end)

Test.case("a ceiling one cell up leaves no headroom", function()
	-- A post with a ledge jutting from its second cell, over open ground.
	local bp = Blueprint.build({
		name = "Ledge",
		palette = { "a" },
		blocks = {
			{ x = 0, y = 0, z = 0, kind = 1 },
			{ x = 0, y = 1, z = 0, kind = 1 },
			{ x = 1, y = 1, z = 0, kind = 1 },
		},
	})
	local site = Sites.finished(bp)
	Test.check(not Access.canStand(bp, site, 1, 0, 0, 2), "under the ledge there's one free cell, not two")
	Test.check(Access.canStand(bp, site, 1, 0, 0, 1), "enough for something one cell tall")
	Test.check(Access.canStand(bp, site, 1, 2, 0, 2), "on top of the ledge")
end)

Test.case("a character a block lands on steps up onto it", function()
	local bp = Sites.hut()
	local site = BuildSite.new(bp)
	-- A character standing on the ground at (5, 0, 5), its root at y 1.
	BuildSite.place(site, Blueprint.slotAt(bp, 5, 0, 5) :: number, Cause.HAND, 1)
	local x, y, z = Access.freeSurface(bp, site, 5.5, 1, 5.5, 4, HEADROOM)
	Test.equal(x, 5, "x")
	Test.equal(y, 1, "onto the block")
	Test.equal(z, 5, "z")
end)

Test.case("freeSurface finds the nearest stand cell, as a scan does", function()
	local rng = Rng.new(12)
	local bp = Sites.lodge()
	for seed = 1, 3 do
		local site = Sites.partlyBuilt(bp, seed, bp.count // 2)
		for _ = 1, 150 do
			local px, py, pz = rng:range(-3, bp.sizeX + 3), rng:range(1, bp.sizeY), rng:range(-3, bp.sizeZ + 3)
			local radius = rng:range(1, 6)
			local x, y, z = Access.freeSurface(bp, site, px, py, pz, radius, HEADROOM)

			-- The scan measures from the root's own cell to each candidate's.
			local fx, fy, fz = math.floor(px), math.floor(py - 0.5), math.floor(pz)
			local best = math.huge
			local r = math.ceil(radius) + 1
			for cy = fy - r, fy + r do
				for cz = fz - r, fz + r do
					for cx = fx - r, fx + r do
						local d2 = (cx - fx) ^ 2 + (cy - fy) ^ 2 + (cz - fz) ^ 2
						if d2 <= radius * radius and d2 < best and Access.canStand(bp, site, cx, cy, cz, HEADROOM) then
							best = d2
						end
					end
				end
			end
			if best == math.huge then
				Test.equal(x, nil, "nothing to stand on in range")
			else
				Test.check(x ~= nil, "found a stand cell")
				local got = ((x :: number) - fx) ^ 2 + ((y :: number) - fy) ^ 2 + ((z :: number) - fz) ^ 2
				Test.equal(got, best, "nearest")
				Test.check(Access.canStand(bp, site, x :: number, y :: number, z :: number, HEADROOM), "standable")
			end
		end
	end
end)

Test.case("workingLayer is the lowest layer with work, and nil when done", function()
	local bp = Sites.lodge()
	local site = BuildSite.new(bp)
	Test.equal(Access.workingLayer(bp, site), 0, "a new site works the ground")
	for seed = 1, 3 do
		local part = Sites.partlyBuilt(bp, seed, bp.count // 2)
		local lowest = nil
		for s = 1, bp.count do
			local state = BuildSite.state(part, s)
			if
				(state == BuildSite.State.READY or state == BuildSite.State.SETTING)
				and (lowest == nil or bp.y[s] < lowest)
			then
				lowest = bp.y[s]
			end
		end
		Test.equal(Access.workingLayer(bp, part), lowest, "matches a scan")
	end
	Test.equal(Access.workingLayer(bp, Sites.finished(bp)), nil, "nothing left to do")
end)

return nil
