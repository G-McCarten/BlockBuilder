local BossBrain = require("../src/shared/BossBrain")
local BossConfig = require("../src/shared/BossConfig")
local BuildSite = require("../src/shared/BuildSite")
local SiteSession = require("../src/shared/SiteSession")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Cause = BuildSite.Cause
local Shield = BuildSite.Shield

local function stats(): SiteSession.Stats
	return {
		cooldown = 0.5,
		grasp = 5,
		batch = 1,
		setTime = 2,
		chainChance = 0,
		chainRadius = 0,
		perfectChance = 0,
		perfectReward = 2,
		yield = 1,
		yieldMult = 1,
		crewWidth = 3,
		crewSpeed = 6,
		crewDuration = 8,
		crewCooldown = 30,
	}
end

-- A session on the lodge with a boss, and a player parked far away.
local function lodgeWithBoss(tuning, seed: number)
	local rng = Rng.new(seed)
	local session = SiteSession.new(Sites.lodge(), nil, function()
		return rng:next()
	end)
	SiteSession.setBoss(session, tuning)
	SiteSession.join(session, 1, stats())
	SiteSession.move(session, 1, -40, 1, -40)
	return session, rng
end

-- Places READY slots in slot order until share of the site is built.
local function buildTo(session, share: number)
	local site = session.site
	local goal = math.ceil(share * site.count)
	while site.placedCount < goal do
		local before = site.placedCount
		for s = 1, site.count do
			if site.placedCount >= goal then
				break
			end
			BuildSite.place(site, s, Cause.HAND, 1)
		end
		if site.placedCount == before then
			break
		end
	end
end

local function kinds(events): { [string]: number }
	local seen = {}
	for _, e in events do
		seen[e.kind] = (seen[e.kind] or 0) + 1
	end
	return seen
end

local function run(session, seconds: number, dt: number?)
	local step = dt or 0.1
	for _ = 1, math.floor(seconds / step) do
		SiteSession.step(session, step)
	end
end

Test.group("BossBrain")

Test.case("each difficulty keeps its works, and Hard binds the site early", function()
	local normal, hard, nightmare = BossConfig.Normal :: any, BossConfig.Hard :: any, BossConfig.Nightmare :: any
	for _, tuning in { normal, hard, nightmare } do
		Test.check(tuning.markers ~= nil, "markers at every difficulty")
		Test.check(tuning.riseAt < tuning.relentAt, "rises before it relents")
	end
	for _, key in { "stubborn", "peace", "binding" } do
		Test.check(normal[key] == nil, `Normal has no {key}`)
		Test.check(hard[key] ~= nil and nightmare[key] ~= nil, `Hard and Nightmare have {key}`)
	end
	for _, key in { "minions", "collapse", "strike", "finalStand" } do
		Test.check(hard[key] == nil, `Hard has no {key}`)
		Test.check(nightmare[key] ~= nil, `Nightmare has {key}`)
	end
	-- The prototype's test plays a Hard site until it binds.
	Test.check(hard.binding.at < 0.6, `Hard binds at {hard.binding.at}`)
	Test.check(hard.binding.at < hard.binding.cap, "binds before the cap it holds the site at")
end)

Test.case("it rises at its share built, not before", function()
	local riseAt = BossConfig.Normal.riseAt
	local session = lodgeWithBoss(BossConfig.Normal, 1)
	buildTo(session, riseAt - 0.05)
	run(session, 1)
	Test.check(not (session.boss :: any).risen, "not just short of riseAt")
	buildTo(session, riseAt + 0.01)
	run(session, 0.2)
	Test.check((session.boss :: any).risen, "risen just past riseAt")
	Test.check(kinds(SiteSession.takeEvents(session)).boss_rise == 1, "announced")
end)

Test.case("left alone it undoes exposed blocks; a player near shoos it", function()
	local session = lodgeWithBoss(BossConfig.Normal, 2)
	buildTo(session, 0.5)
	local before = session.site.placedCount
	run(session, 30)
	Test.check(session.site.placedCount < before - 10, `it undid blocks: {before} to {session.site.placedCount}`)
	local boss = session.boss :: BossBrain.Brain
	SiteSession.move(session, 1, boss.x, boss.y, boss.z)
	SiteSession.step(session, 0.1)
	Test.check(kinds(SiteSession.takeEvents(session)).boss_shooed == 1, "shooed")
	Test.check(session.clock < boss.shooedUntil, "away for a while")
	SiteSession.move(session, 1, -40, 1, -40)
	local after = session.site.placedCount
	run(session, BossConfig.Normal.shooedFor - 1)
	Test.check(session.site.placedCount >= after - 1, "while away it undoes nothing")
end)

Test.case("it relents at relentAt and stops", function()
	local session = lodgeWithBoss(BossConfig.Normal, 3)
	buildTo(session, 0.96)
	run(session, 0.5)
	local boss = session.boss :: BossBrain.Brain
	Test.check(boss.relented, "relented")
	local placed = session.site.placedCount
	run(session, 20)
	Test.equal(session.site.placedCount, placed, "nothing undone after relenting")
end)

Test.case("markers: a player breaks one for a bounty, an unbroken one bursts", function()
	local session = lodgeWithBoss(BossConfig.Normal, 4)
	buildTo(session, 0.5)
	local boss = session.boss :: BossBrain.Brain
	run(session, BossConfig.Normal.markers.interval + 1, 0.25)
	Test.check(#boss.markers >= 1, "a marker is out")
	local m = boss.markers[1]
	local purse = session.workers[1].purse
	SiteSession.move(session, 1, m.x, m.y, m.z)
	SiteSession.step(session, 0.1)
	Test.equal(session.workers[1].purse, purse + BossConfig.Normal.markers.bounty, "bounty paid")
	SiteSession.move(session, 1, -40, 1, -40)
	run(session, BossConfig.Normal.markers.interval + BossConfig.Normal.markers.fuse + 2, 0.25)
	Test.check((kinds(SiteSession.takeEvents(session)).marker_burst or 0) >= 1, "a marker burst")
end)

Test.case("hard: stubborn band, peace circle, and bindings that cap the site", function()
	local hard = BossConfig.Hard
	Test.check(hard.binding.cap > hard.stubborn.at + 0.02, "the cap leaves room past the band's share")
	local session = lodgeWithBoss(hard, 5)
	-- Past the shares the stubborn band and the bindings come at.
	buildTo(session, math.max(hard.stubborn.at, hard.binding.at) + 0.02)
	run(session, 0.5)
	local hand = 0
	for s = 1, session.site.count do
		if bit32.btest(session.site.shield[s], Shield.HAND_ONLY) then
			hand += 1
		end
	end
	Test.check(hand > 0, `a stubborn band of {hand} slots`)
	local boss = session.boss :: BossBrain.Brain
	Test.check(session.site.bound, "bound")
	Test.equal(#boss.bindings, 3, "three bindings")

	run(session, 30, 0.25)
	Test.check(boss.arrived and boss.peaceOn, "it stopped and raised a peace circle")
	SiteSession.move(session, 1, boss.x, boss.y, boss.z)
	SiteSession.step(session, 0.1)
	Test.check(not boss.peaceOn, "shooing lifts the circle")
	SiteSession.move(session, 1, -40, 1, -40)

	buildTo(session, 0.9)
	Test.check(session.site.placedCount <= session.site.boundCap, "held at the cap")
	for _, b in boss.bindings do
		SiteSession.move(session, 1, b.x, b.y, b.z)
		SiteSession.step(session, 0.1)
	end
	Test.check(not session.site.bound, "breaking all three lifts it")
end)

Test.case("nightmare: strikes smother, and a final stand takes shoos to end", function()
	local session = lodgeWithBoss(BossConfig.Nightmare, 6)
	buildTo(session, 0.3)
	run(session, 1)
	local boss = session.boss :: BossBrain.Brain
	Test.equal(#boss.minions, BossConfig.Nightmare.minions.count, "minions out")

	-- Stand just outside shooing range, inside striking range.
	SiteSession.move(session, 1, boss.x + 3.5, boss.y, boss.z)
	local smothered = false
	for _ = 1, 200 do
		SiteSession.move(session, 1, boss.x + 3.5, boss.y, boss.z)
		SiteSession.step(session, 0.1)
		if session.clock < session.workers[1].smotheredUntil then
			smothered = true
			break
		end
	end
	Test.check(smothered, "struck")

	-- Shoo it first: its peace circle would hold back the last blocks.
	run(session, BossConfig.Nightmare.shooedFor + 0.5)
	SiteSession.move(session, 1, boss.x, boss.y, boss.z)
	SiteSession.step(session, 0.1)
	SiteSession.move(session, 1, -40, 1, -40)
	Test.check(not boss.peaceOn, "no peace circle")
	buildTo(session, 0.97)
	Test.check(session.site.placedCount >= 0.95 * session.site.count, "built past relentAt")
	run(session, 0.2)
	Test.check(boss.standing and not boss.relented, "a final stand, not a relent")
	for i = 1, BossConfig.Nightmare.finalStand.shoos do
		run(session, BossConfig.Nightmare.shooedFor + 0.5)
		SiteSession.move(session, 1, boss.x, boss.y, boss.z)
		SiteSession.step(session, 0.1)
		SiteSession.move(session, 1, -40, 1, -40)
		if i < BossConfig.Nightmare.finalStand.shoos then
			Test.check(not boss.relented, `still standing after {i} shoos`)
		end
	end
	Test.check(boss.relented, "relents after its shoos")
end)

Test.case("relenting lifts every hold, so the site can be finished", function()
	for seed = 1, 5 do
		local session = lodgeWithBoss(BossConfig.Nightmare, 10 + seed)
		buildTo(session, 0.6)
		run(session, 20, 0.25)
		BossBrain.step(session.boss :: BossBrain.Brain, session, 0) -- no-op step
		-- Force the end of the stand.
		local boss = session.boss :: BossBrain.Brain
		boss.standing = true
		boss.standShoos = BossConfig.Nightmare.finalStand.shoos - 1
		boss.shooedUntil = -math.huge
		SiteSession.move(session, 1, boss.x, boss.y, boss.z)
		SiteSession.step(session, 0.1)
		Test.check(boss.relented, "relented")
		Test.check(not session.site.bound, "no binding left")
		for s = 1, session.site.count do
			Test.check(not bit32.btest(session.site.shield[s], Shield.BLOCKED), `slot {s} still blocked`)
		end
		session.site.onPlaced = nil
		run(session, 60)
		while session.site.placedCount < session.site.count do
			local before = session.site.placedCount
			for s = 1, session.site.count do
				BuildSite.place(session.site, s, Cause.HAND, 1)
			end
			BuildSite.step(session.site, 1e6)
			Test.check(session.site.placedCount > before or session.site.activeCount > 0, "progress")
		end
	end
end)

return nil
