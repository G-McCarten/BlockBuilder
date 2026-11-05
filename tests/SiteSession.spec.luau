local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local SiteCodec = require("../src/shared/SiteCodec")
local SiteSession = require("../src/shared/SiteSession")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local State = BuildSite.State

local function baseStats(): SiteSession.Stats
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

local function rules(overrides: { [string]: any }?): SiteSession.Rules
	local r = table.clone(SiteSession.DEFAULT_RULES) :: any
	for k, v in overrides or {} do
		r[k] = v
	end
	return r
end

-- A session on the hut with one player standing by the floor slot at (5, 0, 5).
local function hutSession(overrides: { [string]: any }?, random: (() -> number)?)
	local bp = Sites.hut()
	local session = SiteSession.new(bp, rules(overrides), random or function()
		return 0.5
	end)
	SiteSession.join(session, 1, baseStats())
	SiteSession.move(session, 1, 5.5, 1, 5.5)
	return session, bp, Blueprint.slotAt(bp, 5, 0, 5) :: number
end

Test.group("SiteSession")

Test.case("a click in reach places and pays; out of reach it's refused", function()
	local session, bp, floor = hutSession()
	local ok, reason, count = SiteSession.request(session, 1, floor)
	Test.check(ok, reason)
	Test.equal(count, 1, "one block")
	Test.equal(session.workers[1].purse, 1, "paid yield * yieldMult")
	Test.equal(session.tally[1], 1, "tallied")
	local far = Blueprint.slotAt(bp, 10, 0, 10) :: number
	SiteSession.step(session, 1)
	ok, reason = SiteSession.request(session, 1, far)
	Test.check(not ok and reason == "out_of_reach", reason)
end)

Test.case("cooldown, its grace, and the rate limit", function()
	local session, bp = hutSession({ burst = 3, perSecond = 1, cooldownGrace = 0.05 })
	local a = Blueprint.slotAt(bp, 5, 0, 5) :: number
	local b = Blueprint.slotAt(bp, 6, 0, 5) :: number
	local c = Blueprint.slotAt(bp, 4, 0, 5) :: number
	Test.check((SiteSession.request(session, 1, a)), "first click")
	SiteSession.step(session, 0.3)
	local ok, reason = SiteSession.request(session, 1, b)
	Test.check(not ok and reason == "cooling_down", reason)
	SiteSession.step(session, 0.16)
	ok, reason = SiteSession.request(session, 1, b)
	Test.check(ok, `within the grace a click counts: {reason}`)
	-- Three tokens, one a second: two used, one refunded by the time passed. Spam runs out.
	local refused = 0
	for _ = 1, 4 do
		local okSpam, why = SiteSession.request(session, 1, c)
		if not okSpam and why == "rate_limited" then
			refused += 1
		end
	end
	Test.check(refused >= 2, `spam is rate limited, refused {refused}`)
end)

Test.case("a slot someone else took doesn't start the cooldown", function()
	local session, bp, floor = hutSession()
	SiteSession.join(session, 2, baseStats())
	SiteSession.move(session, 2, 5.5, 1, 5.5)
	Test.check((SiteSession.request(session, 2, floor)), "player 2 takes it")
	local ok, reason = SiteSession.request(session, 1, floor)
	Test.check(not ok and reason == "taken", reason)
	local next = Blueprint.slotAt(bp, 6, 0, 5) :: number
	Test.check((SiteSession.request(session, 1, next)), "player 1 can click again at once")
end)

Test.case("refusals: not working, no such slot, smothered", function()
	local session, _, floor = hutSession()
	Test.equal(select(2, SiteSession.request(session, 9, floor)), "not_working", "a stranger")
	Test.equal(select(2, SiteSession.request(session, 1, 0)), "no_slot", "slot 0")
	Test.equal(select(2, SiteSession.request(session, 1, 1.5)), "no_slot", "slot 1.5")
	Test.equal(select(2, SiteSession.request(session, 1, "x" :: any)), "no_slot", "not a number")
	session.workers[1].smotheredUntil = session.clock + 1
	Test.equal(select(2, SiteSession.request(session, 1, floor)), "smothered", "smothered")
end)

Test.case("perfects pay their reward, and a block placed again pays nothing", function()
	local session, _, floor = hutSession(nil, function()
		return 0
	end)
	session.workers[1].stats.perfectChance = 1
	session.workers[1].stats.perfectReward = 3
	session.workers[1].stats.yield = 2
	Test.check((SiteSession.request(session, 1, floor)), "placed")
	Test.equal(session.workers[1].purse, 6, "yield 2 times reward 3")
	local events = SiteSession.takeEvents(session)
	Test.equal(events[1].kind, "perfect", "a perfect event")
	BuildSite.undo(session.site, floor, math.huge, BuildSite.Cause.BOSS, 0)
	SiteSession.step(session, 1)
	Test.check((SiteSession.request(session, 1, floor)), "placed again")
	Test.equal(session.workers[1].purse, 6, "no second pay")
	Test.equal(session.tally[1], 1, "tallied once")
end)

Test.case("one premium roll per player per step with a first placement", function()
	local session, bp = hutSession({ premiumChance = 1 }, function()
		return 0.5
	end)
	session.workers[1].stats.batch = 5
	SiteSession.request(session, 1, Blueprint.slotAt(bp, 5, 0, 5) :: number)
	SiteSession.step(session, 0.1)
	local drops = 0
	for _, e in SiteSession.takeEvents(session) do
		if e.kind == "drop" then
			drops += 1
		end
	end
	Test.equal(drops, 1, "five blocks, one roll")
	SiteSession.step(session, 0.1)
	for _, e in SiteSession.takeEvents(session) do
		Test.check(e.kind ~= "drop", "no roll without a placement")
	end
end)

Test.case("teammates earn the party share of each first placement", function()
	local session, _, floor = hutSession({ partyShare = 0.5 })
	SiteSession.join(session, 2, baseStats())
	session.workers[1].stats.yield = 4
	Test.check((SiteSession.request(session, 1, floor)), "placed")
	Test.equal(session.workers[1].purse, 4, "the placer earns the pay")
	Test.equal(session.workers[2].purse, 2, "a teammate earns half the base pay")
	Test.equal(session.tally[2], 0, "the tally stays with the placer")
end)

Test.case("a player joining a run in progress starts at the average earned", function()
	local session, bp = hutSession({ partyShare = 0 })
	SiteSession.join(session, 2, baseStats())
	SiteSession.move(session, 2, 5.5, 1, 5.5)
	session.workers[1].stats.yield = 10
	SiteSession.request(session, 1, Blueprint.slotAt(bp, 5, 0, 5) :: number)
	SiteSession.request(session, 2, Blueprint.slotAt(bp, 6, 0, 5) :: number)
	-- Player 1 spends some; spending doesn't lower what they earned.
	session.workers[1].purse -= 8
	SiteSession.join(session, 3, baseStats())
	Test.equal(session.workers[3].purse, (10 + 1) / 2, "the average of 10 and 1 earned")
	Test.equal(session.workers[3].earned, 5.5, "counted as earned, for the next to join")
end)

Test.case("shares follow blocks placed, and survive leaving", function()
	local session, bp = hutSession()
	SiteSession.join(session, 2, baseStats())
	SiteSession.move(session, 2, 5.5, 1, 5.5)
	local slots = {}
	for x = 3, 8 do
		table.insert(slots, Blueprint.slotAt(bp, x, 0, 5) :: number)
	end
	for i, s in slots do
		SiteSession.request(session, if i <= 4 then 1 else 2, s)
		SiteSession.step(session, 1)
	end
	SiteSession.leave(session, 2)
	local shares = SiteSession.shares(session)
	Test.check(math.abs(shares[1] - 4 / 6) < 1e-9, `player 1 share {shares[1]}`)
	Test.check(math.abs(shares[2] - 2 / 6) < 1e-9, `player 2 share {shares[2]}`)
end)

Test.case("the ability's band crosses the site placing blocks, then ends", function()
	local session = hutSession()
	Test.check(SiteSession.useAbility(session, 1), "starts")
	Test.check(not SiteSession.useAbility(session, 1), "on cooldown")
	for _ = 1, 100 do
		SiteSession.step(session, 0.1)
	end
	-- bandRate blocks a second per cell of width, for the seconds it spends over the hut.
	local stats = baseStats()
	local seconds = (session.blueprint.sizeX + stats.crewWidth) / stats.crewSpeed
	local most = SiteSession.DEFAULT_RULES.bandRate * stats.crewWidth * seconds
	local placed = session.site.placedCount
	Test.check(placed > most / 2 and placed <= most + 2, `the band placed {placed}, at most {most}`)
	Test.equal(#session.bands, 0, "the band has ended")
	Test.check(session.tally[1] == session.site.placedCount, "all credited to its owner")
end)

Test.case("the power tool needs its pass and has a cooldown", function()
	local session = hutSession()
	Test.check(not (SiteSession.useTool(session, 1, 0, 1)), "no tool, no swing")
	local tool = { radius = 4, halfAngle = math.rad(60), band = 2, setTime = 1, cooldown = 10 }
	SiteSession.setStats(session, 1, session.workers[1].stats, tool)
	local ok, count = SiteSession.useTool(session, 1, 0, 1)
	Test.check(ok and count > 0, `swung, placed {count}`)
	Test.check(not (SiteSession.useTool(session, 1, 0, 1)), "cooling down")
end)

Test.case("a pet works near its owner and pays them", function()
	local session = hutSession()
	SiteSession.addPet(session, 1, { speed = 8, leash = 6, reach = 1, ring = 2, setTime = 1, rest = 0.5 })
	for _ = 1, 100 do
		SiteSession.step(session, 0.1)
	end
	Test.check(session.site.placedCount > 5, `the pet placed {session.site.placedCount}`)
	Test.equal(session.workers[1].purse, session.site.placedCount, "the owner was paid for all of it")
	SiteSession.leave(session, 1)
	Test.equal(#session.pets, 0, "pets leave with their owner")
end)

Test.case("finishing the site is announced once", function()
	local bp = Sites.hut()
	local session = SiteSession.new(bp, rules(), function()
		return 0.5
	end)
	SiteSession.join(session, 1, baseStats())
	local site = session.site
	while site.placedCount < site.count do
		for s = 1, site.count do
			BuildSite.place(site, s, BuildSite.Cause.HAND, 1)
		end
	end
	Test.check(session.finished, "finished")
	local finishes = 0
	for _, e in SiteSession.takeEvents(session) do
		if e.kind == "finished" then
			finishes += 1
		end
	end
	Test.equal(finishes, 1, "announced once")
	Test.equal(session.workers[1].purse, bp.count, "every block paid")
end)

Test.case("a site finished by laying an undone block again still finishes", function()
	local bp = Sites.hut()
	local session = SiteSession.new(bp, rules(), function()
		return 0.5
	end)
	SiteSession.join(session, 1, baseStats())
	local site = session.site
	-- Two blocks nothing rests on.
	local tops = {}
	for s = 1, bp.count do
		if bp.dependentStart[s + 1] == bp.dependentStart[s] then
			table.insert(tops, s)
		end
	end
	local a, b = tops[1], tops[2]
	local rounds = 0
	while site.placedCount < site.count - 1 do
		rounds += 1
		assert(rounds < 100, "stuck")
		for s = 1, bp.count do
			if s ~= a then
				BuildSite.place(site, s, BuildSite.Cause.HAND, 1)
			end
		end
	end
	BuildSite.undo(site, b, math.huge, BuildSite.Cause.BOSS, 0)
	BuildSite.place(site, a, BuildSite.Cause.HAND, 1)
	Test.check(not session.finished, "one block short")
	BuildSite.place(site, b, BuildSite.Cause.HAND, 1)
	Test.check(session.finished, "finished by a block laid again")
end)

Test.case("deltas keep a client's mirror in step with the server", function()
	local rng = Rng.new(17)
	local bp = Sites.lodge()
	local session = SiteSession.new(bp, rules(), function()
		return rng:next()
	end)
	local stats = baseStats()
	stats.batch = 3
	stats.chainChance = 0.3
	stats.chainRadius = 2
	SiteSession.join(session, 1, stats)
	SiteSession.addPet(session, 1, { speed = 8, leash = 8, reach = 1.5, ring = 2, setTime = 1, rest = 0.3 })
	local mirror = BuildSite.new(bp)
	SiteCodec.decode(SiteSession.snapshot(session), function(s, p, r)
		BuildSite.setRemote(mirror, s, p, r)
	end)
	for _ = 1, 600 do
		local s = rng:int(1, bp.count)
		if BuildSite.state(session.site, s) == State.READY then
			SiteSession.move(session, 1, bp.x[s] + 0.5, bp.y[s] + 1, bp.z[s] + 0.5)
			SiteSession.request(session, 1, s)
		end
		if rng:next() < 0.05 then
			SiteSession.useAbility(session, 1)
		end
		SiteSession.step(session, 0.25)
		local delta = SiteSession.takeDelta(session)
		if delta then
			SiteCodec.decode(delta, function(slot, p, r)
				BuildSite.setRemote(mirror, slot, p, r)
			end)
		end
	end
	Test.check(session.site.placedCount > 500, `built {session.site.placedCount}`)
	for s = 1, bp.count do
		Test.equal(BuildSite.state(mirror, s), BuildSite.state(session.site, s), `slot {s}`)
	end
	Test.equal(mirror.placedCount, session.site.placedCount, "placedCount")
end)

return nil
