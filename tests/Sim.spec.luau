local Blueprint = require("../src/shared/Blueprint")
local BossConfig = require("../src/shared/BossConfig")
local BotBrain = require("../src/shared/BotBrain")
local Sim = require("../tools/sim/Sim")
local SiteSession = require("../src/shared/SiteSession")
local SkillTuning = require("../src/shared/SkillTuning")
local StressSite = require("../src/shared/StressSite")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

Test.group("Sim")

Test.case("bots finish the TestHut solo, in co-op, and against every boss", function()
	local hut = Sites.hut()
	for _, name in { "none", "Normal", "Hard", "Nightmare" } do
		for _, players in { 1, 3 } do
			local r = Sim.run({
				blueprint = hut,
				players = players,
				seed = 7,
				boss = if name == "none" then nil else (BossConfig :: any)[name],
				maxMinutes = 60,
			})
			Test.check(r.finished, `{name}, {players} players: unfinished after {r.minutes} minutes`)
		end
	end
end)

Test.case("a party finishes faster than one player", function()
	local hut = Sites.hut()
	local solo = Sim.run({ blueprint = hut, players = 1, seed = 3 })
	local party = Sim.run({ blueprint = hut, players = 3, seed = 3 })
	Test.check(party.minutes < solo.minutes * 0.6, `solo {solo.minutes}, party of 3 {party.minutes}`)
end)

Test.case("each minute's record adds up to the run", function()
	local hut = Sites.hut()
	for _, name in { "none", "Nightmare" } do
		local r = Sim.run({
			blueprint = hut,
			seed = 7,
			boss = if name == "none" then nil else BossConfig.Nightmare,
			maxMinutes = 60,
		})
		Test.check(r.finished, `{name}: finished`)
		local placed, undone, seconds = 0, 0, 0
		for m, minute in r.byMinute do
			for _, n in minute.placed do
				placed += n
			end
			undone += minute.undone
			seconds += minute.seconds
			if minute.clicks > 0 then
				Test.check(minute.perClick >= 1, `{name}, minute {m}: a click places its aimed block`)
			end
			Test.check(minute.earned[1] >= minute.purse[1], `{name}, minute {m}: nobody holds more than they earned`)
		end
		-- Every placement less every undo is the finished site.
		Test.equal(placed - undone, hut.count, `{name}: placements less undos`)
		Test.equal(undone, r.undone, `{name}: undos by minute`)
		Test.check(
			math.abs(seconds - r.minutes * 60) <= 0.11,
			`{name}: {seconds} s of minutes in a {r.minutes} min run`
		)
		Test.equal(r.byMinute[#r.byMinute].built, 1, `{name}: the last minute ends finished`)
		local by = r.undoneBy
		Test.equal(by.nearest + by.marker + by.collapse, r.undone, `{name}: undos by how`)
		if name == "none" then
			Test.equal(r.undone, 0, "no boss, nothing undone")
			Test.check(r.roseAt == nil, "no boss, no rise")
		else
			-- It may still be making its final stand when the site is finished.
			local rose, relented = r.roseAt, r.relentedAt
			Test.check(rose ~= nil and rose < r.minutes, "rose before the end")
			Test.check(relented == nil or relented > (rose :: number), "relented after it rose")
			Test.check(r.undone > 0 and by.nearest >= 0 and by.collapse > 0, `{name}: undid {r.undone}`)
		end
	end
end)

Test.case("skill levels are recorded in the order they're bought", function()
	local r = Sim.run({ blueprint = Sites.hut(), seed = 3 })
	local count = 0
	for _, levels in r.boughtAt[1] do
		local last = 0
		for level, at in levels do
			Test.check(at >= last and at <= r.minutes, `level {level} bought at {at}`)
			last = at
			count += 1
		end
	end
	Test.equal(count, r.purchases, "every purchase recorded")
end)

Test.case("a finished site's payout is split by blocks placed", function()
	local hut = Sites.hut()
	local solo = Sim.run({ blueprint = hut, seed = 3, payout = 100 })
	Test.equal(solo.shares[1], 1, "one player takes it all")
	Test.check(math.abs(solo.payPerMinute[1] - 100 / solo.minutes) < 1e-9, "solo payout a minute")

	local party = Sim.run({ blueprint = hut, players = 3, seed = 3, payout = 100 })
	local total = 0
	for id, share in party.shares do
		total += share
		Test.check(math.abs(party.payPerMinute[id] - 100 * share / party.minutes) < 1e-9, `player {id}`)
	end
	Test.check(math.abs(total - 1) < 1e-9, `shares add to {total}`)

	local cut = Sim.run({ blueprint = hut, seed = 3, payout = 100, maxMinutes = 1 })
	Test.check(not cut.finished and cut.payPerMinute[1] == 0, "an unfinished site pays nothing")
	Test.equal(Sim.run({ blueprint = Sites.lodge(), seed = 1, maxMinutes = 1 }).payout, 100, "SiteList's payout")
end)

Test.case("summarise averages runs, minute by minute", function()
	local hut = Sites.hut()
	local results = {}
	local total = 0
	for seed = 1, 3 do
		local r = Sim.run({ blueprint = hut, seed = seed, boss = BossConfig.Normal })
		table.insert(results, r)
		total += r.minutes
	end
	local s = Sim.summarise(results)
	Test.equal(s.runs, 3, "runs")
	Test.equal(s.unfinished, 0, "all finished")
	Test.check(math.abs(s.mean - total / 3) < 1e-9, "mean minutes")
	Test.check(s.best <= s.mean and s.mean <= s.worst, "mean between best and worst")
	Test.equal(s.byMinute[1].runs, 3, "every run has a first minute")
	Test.check(s.byMinute[#s.byMinute].runs >= 1, "the last minute has a run")
	Test.check(s.undone > 0 and s.undoneRate > 0, "the boss undid blocks")
	Test.check(s.undoneWhileUp >= s.undoneRate, "faster while it's up than over the whole run")
	for _, row in s.byMinute do
		Test.check(row.earned >= row.purse and row.built > 0 and row.built <= 1, "rows in range")
	end
	for nodeId, levels in s.boughtAt do
		for level, cell in levels do
			Test.check(cell.share > 0 and cell.share <= 1, `{nodeId} {level}: share {cell.share}`)
		end
	end
end)

-- Where in a run's purchases a level was bought, or nil.
local function boughtAt(r: Sim.Result, level: string): number?
	for i, entry in r.bought do
		if string.find(entry, "^" .. level .. "@") then
			return i
		end
	end
	return nil
end

Test.case("bots buy cheapest first by default, or by value", function()
	local lodge = Sites.lodge()
	local default = Sim.run({ blueprint = lodge, seed = 3 })
	local cheapest = Sim.run({ blueprint = lodge, seed = 3, buying = "cheapest" })
	Test.equal(default.minutes, cheapest.minutes, "the default is cheapest first")
	Test.check(string.find(default.bought[1], "^batch") ~= nil, `cheapest first starts with {default.bought[1]}`)
	local third, double = boughtAt(default, "batch3"), boughtAt(default, "hands1")
	Test.check(third and double and third < double, "cheapest first takes all of Armful before Many Hands")

	-- Doubling three bricks a click beats adding a fourth.
	local value = Sim.run({ blueprint = lodge, seed = 3, buying = "value" })
	Test.check(value.finished, "a bot buying by value finishes")
	Test.check(string.find(value.bought[1], "^batch") ~= nil, `by value it starts with {value.bought[1]}`)
	local valueThird, valueDouble = boughtAt(value, "batch3"), boughtAt(value, "hands1")
	Test.check(valueDouble ~= nil and (valueThird == nil or valueDouble < valueThird), "by value it doubles first")
	Test.check(value.minutes < default.minutes, `by value {value.minutes}, cheapest first {default.minutes}`)
end)

Test.case("Many Hands doubles what Armful adds", function()
	Test.equal(SkillTuning.stats({}).batch, 1, "one block a click to start")
	Test.equal(SkillTuning.stats({ batch = 3 }).batch, 4, "Armful adds a block a level")
	Test.equal(SkillTuning.stats({ hands = 1 }).batch, 2, "Many Hands doubles")
	Test.equal(SkillTuning.stats({ batch = 3, hands = 3 }).batch, 32, "both, at the top")
end)

Test.case("the value model counts both batch nodes, chains, perfect and the ability, not setTime", function()
	local function earning(levels: { [string]: number }): number
		local ability = (levels[SkillTuning.abilityNode] or 0) >= 1
		return BotBrain.earning(SkillTuning.stats(levels), ability, 6)
	end
	local base = earning({})
	Test.check(base > 0, "earns something")
	for _, node in { "batch", "hands", "chain", "perfect", "crew" } do
		Test.check(earning({ [node] = 1 }) > base, `{node} adds to earning`)
	end
	Test.equal(earning({ setTime = 2 }), base, "setTime adds nothing")
	Test.check(earning({ crew = 2 }) > earning({ crew = 1 }), "a wider, longer band earns more")
	Test.check(
		earning({ batch = 2, hands = 1 }) - earning({ batch = 2 }) > earning({ batch = 3 }) - earning({ batch = 2 }),
		"doubling three bricks adds more than a fourth"
	)
end)

Test.case("a bot leaves work a teammate could lay from where they stand to that teammate", function()
	local lodge = Sites.lodge()
	local stats = SkillTuning.stats({})
	local grasp2 = stats.grasp * stats.grasp
	local function session(players: { { number } }): (any, { any })
		local s = SiteSession.new(lodge, nil, function()
			return 0.5
		end)
		local bots = {}
		for id, at in players do
			local bot = BotBrain.new(s, id, at[1], at[2], at[3])
			SiteSession.join(s, id, stats)
			SiteSession.move(s, id, bot.x, bot.y, bot.z)
			table.insert(bots, bot)
		end
		return s, bots
	end
	local function within(target: number, at: { number }): boolean
		local dx, dy, dz = lodge.x[target] + 0.5 - at[1], lodge.y[target] + 0.5 - at[2], lodge.z[target] + 0.5 - at[3]
		return dx * dx + dy * dy + dz * dz <= grasp2
	end
	local here, teammate = { 10, 1, -2 }, { 10.5, 1, -2 }

	-- Alone, a bot heads for the nearest slot, which its teammate could reach.
	local alone, solo = session({ here })
	BotBrain.step(solo[1], alone, SkillTuning, 0.1, false)
	Test.check(solo[1].target ~= 0 and within(solo[1].target, teammate), "alone, the nearest")

	-- With the teammate beside it, it heads for work out of their reach.
	local party, bots = session({ here, teammate })
	BotBrain.step(bots[1], party, SkillTuning, 0.1, false)
	Test.check(bots[1].target ~= 0 and not within(bots[1].target, teammate), "work out of the teammate's grasp")

	-- When every slot left is within a teammate's grasp, it still takes the nearest.
	local blocks = {}
	for x = 0, 2 do
		table.insert(blocks, { x = x, y = 0, z = 0, kind = "a" })
	end
	local tiny = Blueprint.build({ name = "Tiny", palette = { "a" }, blocks = blocks })
	local last = SiteSession.new(tiny, nil, function()
		return 0.5
	end)
	local a, b = BotBrain.new(last, 1, 6, 1, 0.5), BotBrain.new(last, 2, 1.5, 1, 0.5)
	for _, bot in { a, b } do
		SiteSession.join(last, bot.id, stats)
		SiteSession.move(last, bot.id, bot.x, bot.y, bot.z)
	end
	BotBrain.step(a, last, SkillTuning, 0.1, false)
	Test.check(a.target ~= 0, "a teammate's work, when there's nothing else")
end)

Test.case("on a 20,000-block district, a click lays dozens through a run's last minutes", function()
	local bp = Blueprint.build(StressSite.source(20000))
	for _, buying in { "cheapest", "value" } do
		local r = Sim.run({ blueprint = bp, seed = 1, buying = buying })
		Test.check(r.finished and r.minutes > 20 and r.minutes < 40, `{buying}: {r.minutes} minutes`)
		-- The last five whole minutes; the site's last few layers may come after.
		local last = #r.byMinute
		if r.byMinute[last].seconds < 60 then
			last -= 1
		end
		for m = last - 4, last do
			local median = r.byMinute[m].perClick
			Test.check(median >= 24, `{buying}, minute {m}: a click lays {median}`)
		end
	end
end)

return nil
