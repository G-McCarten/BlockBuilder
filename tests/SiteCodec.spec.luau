local fs = require("@lune/fs")

local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local SiteCodec = require("../src/shared/SiteCodec")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Cause = BuildSite.Cause

Test.group("SiteCodec")

Test.case("progress keeps 0 and 1 exact and never rounds onto them", function()
	Test.equal(SiteCodec.quantize(0), 0, "empty")
	Test.equal(SiteCodec.quantize(1), 65535, "placed")
	Test.equal(SiteCodec.quantize(1e-9), 1, "a sliver of progress isn't empty")
	Test.equal(SiteCodec.quantize(1 - 1e-9), 65534, "almost placed isn't placed")
	Test.equal(SiteCodec.quantize(0.5), 32768, "half")
	Test.equal(SiteCodec.unquantize(65535), 1, "1 comes back exact")
	local worst = 0
	for i = 1, 999 do
		local p = i / 1000
		worst = math.max(worst, math.abs(SiteCodec.unquantize(SiteCodec.quantize(p)) - p))
	end
	Test.check(worst <= 0.5 / 65535 + 1e-12, `quantisation error {worst}`)
end)

Test.case("a delta round-trips every slot it names", function()
	local rng = Rng.new(5)
	local count = 1000
	local site = { count = count, progress = {}, rate = {}, active = {}, activeCount = 0 }
	local slots = {}
	for s = 1, count do
		site.progress[s] = if rng:next() < 0.3 then rng:int(0, 1) else rng:next()
		site.rate[s] = if rng:next() < 0.5 then 0 else rng:range(-4, 4)
		slots[s] = count + 1 - s
	end
	local buf = SiteCodec.encodeDelta(site, slots, count)
	Test.equal(buffer.len(buf), 3 + 8 * count, "8 bytes a slot")
	local seen = 0
	local kind = SiteCodec.decode(buf, function(s, p, r)
		seen += 1
		Test.equal(s, slots[seen], "order")
		Test.equal(p, SiteCodec.unquantize(SiteCodec.quantize(site.progress[s])), `progress of {s}`)
		Test.check(math.abs(r - site.rate[s]) <= 1e-6 * math.abs(site.rate[s]), `rate of {s}`)
	end)
	Test.equal(kind, SiteCodec.DELTA, "kind")
	Test.equal(seen, count, "every slot")
end)

Test.case("a snapshot rebuilds a site in progress", function()
	local bp = Blueprint.build(Sites.terrain(3, 24, 20))
	local site = BuildSite.new(bp)
	local rng = Rng.new(9)
	for _ = 1, 20000 do
		local s = rng:int(1, bp.count)
		if rng:next() < 0.8 then
			BuildSite.place(site, s, Cause.HAND, 1)
		else
			BuildSite.startSetting(site, s, rng:range(0.5, 3), Cause.CHAIN, 1)
		end
	end
	for _ = 1, 500 do
		BuildSite.undo(site, rng:int(1, bp.count), rng:range(0.5, 3), Cause.BOSS, 0)
	end
	BuildSite.step(site, 0.1)
	Test.check(site.placedCount > 1000 and site.activeCount > 10, "the site is part built and moving")

	local mirror = BuildSite.new(bp)
	local kind = SiteCodec.decode(SiteCodec.encodeSnapshot(site), function(s, p, r)
		BuildSite.setRemote(mirror, s, p, r)
	end)
	Test.equal(kind, SiteCodec.SNAPSHOT, "kind")
	Test.equal(mirror.placedCount, site.placedCount, "placedCount")
	Test.equal(mirror.activeCount, site.activeCount, "activeCount")
	for s = 1, bp.count do
		Test.equal(BuildSite.state(mirror, s), BuildSite.state(site, s), `state of {s}`)
		Test.equal(mirror.unmet[s], site.unmet[s], `unmet of {s}`)
	end
end)

Test.case("a full 65,535-slot site fits", function()
	local bp = Blueprint.build(Sites.floor(65535))
	local site = BuildSite.new(bp)
	-- The whole ground layer, then every other slot of the 510 above it.
	local ground = 255 * 255
	for s = 1, ground do
		BuildSite.place(site, s, Cause.HAND, 1)
	end
	for s = ground + 1, bp.count - 1, 2 do
		BuildSite.place(site, s, Cause.HAND, 1)
	end
	Test.check(BuildSite.startSetting(site, 65535, 1, Cause.HAND, 1), "the last slot starts setting")
	local snapshot = SiteCodec.encodeSnapshot(site)
	Test.equal(buffer.len(snapshot), 5 + 8192 + 8, "header, placed bits and one entry")
	local mirror = BuildSite.new(bp)
	SiteCodec.decode(snapshot, function(s, p, r)
		BuildSite.setRemote(mirror, s, p, r)
	end)
	Test.equal(site.placedCount, ground + 255, "placed on the server")
	Test.equal(mirror.placedCount, site.placedCount, "placed on the mirror")
	Test.equal(BuildSite.state(mirror, 65534), BuildSite.State.PLACED, "a placed bit near the end")
	Test.equal(BuildSite.state(mirror, 65535), BuildSite.State.SETTING, "the last slot index survives u16")

	local slots = table.create(65535, 0)
	for s = 1, 65535 do
		slots[s] = s
	end
	Test.equal(buffer.len(SiteCodec.encodeDelta(site, slots, 65535)), 3 + 8 * 65535, "the largest delta")
	Test.check(
		not pcall(SiteCodec.encodeSnapshot, { count = 65536, progress = {}, rate = {}, active = {}, activeCount = 0 }),
		"no bigger"
	)
end)

Test.case("unknown messages are refused", function()
	Test.check(not pcall(SiteCodec.decode, buffer.fromstring("\9\0\0"), function() end), "kind 9")
end)

Test.case("the shared site modules create no Instance per block", function()
	for _, name in
		{
			"Access",
			"Blueprint",
			"BlueprintValidator",
			"BuildSite",
			"CollisionBoxes",
			"SiteCodec",
			"SiteIndex",
			"SiteRay",
		}
	do
		local text = fs.readFile(`src/shared/{name}.luau`)
		for _, banned in { "Instance.new", ":Clone(", "game:", "workspace" } do
			Test.check(not string.find(text, banned, 1, true), `{name} uses {banned}`)
		end
	end
end)

return nil
