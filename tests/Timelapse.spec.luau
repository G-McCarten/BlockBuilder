local BuildSite = require("../src/shared/BuildSite")
local Timelapse = require("../src/shared/Timelapse")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

Test.group("Timelapse")

Test.case("orders placed slots by when they were last placed", function()
	local bp = Sites.hut()
	local site = BuildSite.new(bp)
	local placedOrder = {}
	while site.placedCount < site.count do
		for s = site.count, 1, -1 do
			if BuildSite.place(site, s, BuildSite.Cause.HAND, 1) then
				table.insert(placedOrder, s)
				BuildSite.step(site, 0.01)
			end
		end
	end
	local order = Timelapse.order(site)
	Test.equal(#order, site.count, "every placed slot")
	for i, s in order do
		Test.equal(s, placedOrder[i], `position {i}`)
	end
	-- Undone and laid again, a block moves to its latest placement.
	local first = order[#order]
	BuildSite.undo(site, first, math.huge, BuildSite.Cause.BOSS, 0)
	BuildSite.step(site, 1)
	BuildSite.place(site, first, BuildSite.Cause.HAND, 1)
	local again = Timelapse.order(site)
	Test.equal(again[#again], first, "relaid last")
end)

Test.case("eases from none to all over its duration", function()
	Test.equal(Timelapse.shown(0, 10, 500), 0, "none at the start")
	Test.equal(Timelapse.shown(10, 10, 500), 500, "all at the end")
	Test.equal(Timelapse.shown(5, 10, 500), 250, "half at the middle")
	Test.check(Timelapse.shown(1, 10, 500) < 50, "slow to start")
	local last = 0
	for t = 0, 10, 0.1 do
		local n = Timelapse.shown(t, 10, 500)
		Test.check(n >= last, "never goes back")
		last = n
	end
end)

Test.case("round-trips through a buffer", function()
	local order = { 5, 1, 65535, 300 }
	local back = Timelapse.decode(Timelapse.encode(order))
	Test.equal(table.concat(back, ","), "5,1,65535,300", "same slots")
end)

return nil
