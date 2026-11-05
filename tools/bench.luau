--[[
	bench: times the work a site does each tick, at scale. From the repo root:

	  lune run tools/bench                      every scenario
	  lune run tools/bench -- --ticks 1000      a shorter window
	  lune run tools/bench -- --site GreatHall --bots 8 --no-client

	The server half plays a site with bots (BotBrain), a Nightmare boss and
	two pets a bot, the way the sim does, until it is --from (0.35) built.
	Then it times --ticks (3000) ticks at dt = 1/60, each part on its own:

	  step     SiteSession.step
	  bots     every bot's BotBrain.step, which clicks through the session
	  tick     the whole tick: bots, step, takeEvents and takeDelta
	  delta    bytes a tick from takeDelta, 0 on a tick with no delta
	  sim      a whole tick of the warm-up, which plays at the sim's dt = 0.1

	It plays GreatHall and a generated site near SiteCodec's 65,535-slot cap
	(tests/lib/Sites.terrain), each with 1, 4 and 8 bots, and prints the
	snapshot's size at the end and how long it takes to encode. The checksum
	hashes every delta and event from the start and the final snapshot, so
	two runs that print the same one played the same.

	The client half runs the prototype the way tests/Prototype.spec.luau does,
	under tests/lib/FakeRoblox, on GreatHall with 4 bots at TestSpeed 5, and
	times each frame for --frames (1800) frames: the RenderStepped handler and
	the remote handlers that apply the server's messages. Then it plays the
	same frames again with probes, for where that time goes: the shared calls
	inside those handlers, each timed with what it calls, and the instance
	properties they write, the Roblox methods they call and the instances
	they make, a frame each. Lune stands in for Roblox's engine there, so
	instance work costs more than it would in Studio: compare those numbers
	with each other, not with a frame budget.

	Times are in milliseconds, from os.clock.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Blueprint = require("../src/shared/Blueprint")
local BossConfig = require("../src/shared/BossConfig")
local BotBrain = require("../src/shared/BotBrain")
local BuildSite = require("../src/shared/BuildSite")
local SiteSession = require("../src/shared/SiteSession")
local SkillTuning = require("../src/shared/SkillTuning")
local FakeRoblox = require("../tests/lib/FakeRoblox")
local PlaceBuilder = require("../tests/lib/PlaceBuilder")
local Sites = require("../tests/lib/Sites")

local args = process.args
local function option(name: string): string?
	for i, a in args do
		if a == name then
			return args[i + 1] or ""
		end
	end
	return nil
end
local function flag(name: string): boolean
	return table.find(args, name) ~= nil
end

local TICKS = tonumber(option("--ticks") or "3000") or 3000
local FRAMES = tonumber(option("--frames") or "1800") or 1800
local FROM = tonumber(option("--from") or "0.35") or 0.35
local DT = 1 / 60
-- The warm-up plays at the sim's tick, which is quicker and reaches the same kind of site.
local WARM_DT = 0.1
local WARM_LIMIT = 6 * 60 * 60

-- Statistics -----------------------------------------------------------------

local function stats(samples: { number }): (number, number, number)
	local n = #samples
	if n == 0 then
		return 0, 0, 0
	end
	local total = 0
	for _, v in samples do
		total += v
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	return total / n, sorted[math.max(1, math.ceil(n * 0.95))], sorted[n]
end

local function row(label: string, what: string, samples: { number }, scale: number, format: string)
	local mean, p95, max = stats(samples)
	print(
		string.format(
			"  %-26s %-10s " .. format .. "  " .. format .. "  " .. format,
			label,
			what,
			mean * scale,
			p95 * scale,
			max * scale
		)
	)
end

-- A polynomial hash mod a prime under 2^32, so two runs can show they played the same.
local MOD = 4294967291
local function hashString(h: number, text: string): number
	for i = 1, #text do
		h = (h * 257 + string.byte(text, i)) % MOD
	end
	return h
end
local function hashBuffer(h: number, buf: buffer): number
	for i = 0, buffer.len(buf) - 1 do
		h = (h * 257 + buffer.readu8(buf, i)) % MOD
	end
	return h
end
local function hashEvent(h: number, e: any): number
	return hashString(
		h,
		string.format(
			"%s|%s|%s|%.17g|%.17g|%.17g|%.17g;",
			e.kind,
			tostring(e.userId),
			tostring(e.slot),
			e.amount or 0,
			e.x or 0,
			e.y or 0,
			e.z or 0
		)
	)
end

-- The server half ------------------------------------------------------------

local function lcg(seed: number): () -> number
	local state = seed % 4294967296
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local SNAPSHOT_REPEATS = 20

local function scenario(name: string, bp: any, botCount: number)
	local session = SiteSession.new(bp, nil, lcg(botCount * 7919 + bp.count))
	SiteSession.setBoss(session, BossConfig.Nightmare)
	local site = session.site
	local bots = {}
	for id = 1, botCount do
		-- Spread along the front of the site, as the sim starts them.
		local bot = BotBrain.new(session, id, bp.sizeX * id / (botCount + 1), 1, -2)
		bots[id] = bot
		SiteSession.join(session, id, SkillTuning.stats(bot.levels) :: any)
		SiteSession.move(session, id, bot.x, bot.y, bot.z)
		for _ = 1, 2 do
			SiteSession.addPet(session, id, SkillTuning.pet :: any)
		end
	end

	local hash = 0
	local kinds: { [string]: number } = {}
	-- One server tick, timed part by part. Returns bots, step and whole-tick seconds and the delta's bytes.
	local function tick(dt: number, count: boolean): (number, number, number, number)
		local t0 = os.clock()
		for _, bot in bots do
			BotBrain.step(bot, session, SkillTuning, dt, false)
		end
		local t1 = os.clock()
		SiteSession.step(session, dt)
		local t2 = os.clock()
		local events = SiteSession.takeEvents(session)
		local delta = SiteSession.takeDelta(session)
		local t3 = os.clock()
		if delta then
			hash = hashBuffer(hash, delta)
		end
		for _, e in events do
			hash = hashEvent(hash, e)
			if count then
				kinds[e.kind] = (kinds[e.kind] or 0) + 1
			end
		end
		return t1 - t0, t2 - t1, t3 - t0, if delta then buffer.len(delta) else 0
	end

	-- The warm-up, at the sim's tick: its ticks are what a sim run costs.
	local warmTimes = {}
	while BuildSite.percent(site) < FROM and session.clock < WARM_LIMIT and not session.finished do
		local _, _, whole = tick(WARM_DT, false)
		table.insert(warmTimes, whole)
	end
	local fromPercent, fromPlaced, fromClock = BuildSite.percent(site), site.placedCount, session.clock

	local stepTimes = table.create(TICKS, 0)
	local botTimes = table.create(TICKS, 0)
	local tickTimes = table.create(TICKS, 0)
	local deltaBytes = table.create(TICKS, 0)
	for t = 1, TICKS do
		botTimes[t], stepTimes[t], tickTimes[t], deltaBytes[t] = tick(DT, true)
	end
	local snapshot = SiteSession.snapshot(session)
	local snapStarted = os.clock()
	for _ = 1, SNAPSHOT_REPEATS do
		SiteSession.snapshot(session)
	end
	local snapSeconds = (os.clock() - snapStarted) / SNAPSHOT_REPEATS
	hash = hashBuffer(hash, snapshot)

	local label = `{name} {botCount} bot{if botCount == 1 then "" else "s"}`
	row(label, "step ms", stepTimes, 1000, "%8.4f")
	row(label, "bots ms", botTimes, 1000, "%8.4f")
	row(label, "tick ms", tickTimes, 1000, "%8.4f")
	row(label, "delta B", deltaBytes, 1, "%8.1f")
	row(label, "sim ms", warmTimes, 1000, "%8.4f")
	local seen = {}
	for kind, n in kinds do
		table.insert(seen, `{kind} {n}`)
	end
	table.sort(seen)
	print(
		string.format(
			"  %-26s snapshot %d B, encoded in %.3f ms; built %.1f%% to %.1f%%, %d placed in the window",
			label,
			buffer.len(snapshot),
			snapSeconds * 1000,
			fromPercent * 100,
			BuildSite.percent(site) * 100,
			site.placedCount - fromPlaced
		)
	)
	print(
		string.format(
			"  %-26s sim ms: %d ticks at dt = %.1f to %.0f%% built, %.1f min of play; checksum %08x",
			label,
			#warmTimes,
			WARM_DT,
			fromPercent * 100,
			fromClock / 60,
			hash
		)
	)
	print(string.format("  %-26s events in the window: %s", label, table.concat(seen, ", ")))
end

-- The client half ------------------------------------------------------------

-- The shared functions the client calls itself, timed with what they call.
local PROBES = {
	SiteIndex = { "nearest", "within" },
	SiteRay = { "cast" },
	Access = { "workingLayer", "freeSurface", "canStand" },
	CollisionBoxes = { "build" },
	SiteCodec = { "decode" },
	Prediction = { "predict", "answer", "expire" },
	BuildSite = { "setRemote" },
	Hints = { "pick" },
	WorldArc = { "at" },
	Timelapse = { "shown", "decode" },
}

local function probeClient(world, totals: { [string]: { number } })
	for module, cached in world.modules.client do
		local moduleName = world.reals[module].Name
		local functions = PROBES[moduleName]
		if functions then
			local value = cached.value
			for _, fname in functions do
				local fn = value[fname]
				local total = { 0, 0 }
				totals[`{moduleName}.{fname}`] = total
				value[fname] = function(...)
					local started = os.clock()
					local a, b, c, d = fn(...)
					total[1] += os.clock() - started
					total[2] += 1
					return a, b, c, d
				end
			end
		end
	end
end

-- Wraps each connected handler of signal: before(), the handler, then after(seconds).
local function aroundHandlers(signal, before: () -> (), after: (seconds: number) -> ())
	for _, entry in signal.handlers do
		local fn = entry.fn
		entry.fn = function(...)
			before()
			local started = os.clock()
			fn(...)
			after(os.clock() - started)
		end
	end
end

local function nothing() end

-- The prototype on GreatHall with 4 bots at TestSpeed 5, through its first
-- frames, which take the snapshot and draw the site. Returns the world and
-- the seconds that took.
local function bootPrototype()
	local game = PlaceBuilder.build("default.project.json")
	local workspace = game:GetService("Workspace")
	workspace:SetAttribute("BotPlayers", 4)
	workspace:SetAttribute("TestSpeed", 5)
	workspace:SetAttribute("Site", "GreatHall")
	local world = FakeRoblox.new(game)
	local started = os.clock()
	world:runScripts("server")
	world:addPlayer(1)
	world:runScripts("client")
	-- Over the site's front half, so some chunks are near and some far.
	world.camera.CFrame = roblox.CFrame.new(workspace:GetAttribute("SiteOrigin") + roblox.Vector3.new(60, 30, 40))
	for _ = 1, 10 do
		world:step(1 / 60)
	end
	return world, os.clock() - started
end

-- One frame, the mouse over a different column of the site each time, as an
-- idle player's might wander.
local function playFrame(world, frame: number)
	local Vector3 = roblox.Vector3
	local origin = world.realGame:GetService("Workspace"):GetAttribute("SiteOrigin")
	local x, z = (frame * 7) % 67, (frame * 11) % 36
	world.aimRay = roblox.Ray.new(origin + Vector3.new(x + 0.5, 40, z + 0.5) * 3, Vector3.new(0, -1, 0))
	world:step(1 / 60)
end

-- Prints the largest counts, a frame each, under label.
local function topCounts(label: string, counts: { [string]: number }, limit: number)
	local names = {}
	for name in counts do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return counts[a] > counts[b] or (counts[a] == counts[b] and a < b)
	end)
	for i = 1, math.min(limit, #names) do
		print(string.format("  %-26s %-30s %8.2f a frame", label, names[i], counts[names[i]] / FRAMES))
	end
end

local function client()
	-- The timed run: nothing in the frames but the handlers' own clocks.
	local world, bootSeconds = bootPrototype()
	local render, remotes, beat = 0, 0, 0
	aroundHandlers(world.runService.RenderStepped, nothing, function(t)
		render += t
	end)
	aroundHandlers(world.runService.Heartbeat, nothing, function(t)
		beat += t
	end)
	for _, signals in world.signals do
		if signals.OnClientEvent then
			aroundHandlers(signals.OnClientEvent, nothing, function(t)
				remotes += t
			end)
		end
	end
	local renderTimes, remoteTimes, clientTimes, beatTimes = {}, {}, {}, {}
	for frame = 1, FRAMES do
		render, remotes, beat = 0, 0, 0
		playFrame(world, frame)
		renderTimes[frame] = render
		remoteTimes[frame] = remotes
		clientTimes[frame] = render + remotes
		beatTimes[frame] = beat
	end
	local label = "client GreatHall 4 bots"
	row(label, "render ms", renderTimes, 1000, "%8.4f")
	row(label, "remote ms", remoteTimes, 1000, "%8.4f")
	row(label, "frame ms", clientTimes, 1000, "%8.4f")
	row("server GreatHall 4 bots", "beat ms", beatTimes, 1000, "%8.4f")
	print(
		string.format(
			"  %-26s booted and drew the site in %.0f ms; %d placed after %d frames; %d errors",
			label,
			bootSeconds * 1000,
			world.realGame:GetService("Workspace"):GetAttribute("SitePlaced") or 0,
			FRAMES,
			#world.errors
		)
	)
	for _, e in world.errors do
		print(`  error: {e}`)
	end
	local clientTotal = 0
	for _, v in clientTimes do
		clientTotal += v
	end

	-- The same frames again, probed: the shared calls inside the client's
	-- handlers, and what those handlers do to instances.
	print("\n  The same frames again, with probes, for where the client's time goes:")
	world = bootPrototype()
	local inClient = false
	local enter = function()
		inClient = true
	end
	local leave = function()
		inClient = false
	end
	aroundHandlers(world.runService.RenderStepped, enter, leave)
	for _, signals in world.signals do
		if signals.OnClientEvent then
			aroundHandlers(signals.OnClientEvent, enter, leave)
		end
	end
	local totals: { [string]: { number } } = {}
	probeClient(world, totals)
	local writes, calls, made = {}, {}, {}
	local newindex, index = FakeRoblox.newindex, FakeRoblox.index
	world.newindex = function(self, proxy, key, value)
		if inClient then
			local name = `{self.reals[proxy].ClassName}.{key}`
			writes[name] = (writes[name] or 0) + 1
		end
		return newindex(self, proxy, key, value)
	end
	world.index = function(self, proxy, key)
		local value = index(self, proxy, key)
		if inClient and type(value) == "function" then
			local name = `{self.reals[proxy].ClassName}:{key}`
			calls[name] = (calls[name] or 0) + 1
		end
		return value
	end
	-- Every script's Instance is this one table, so this sees both sides' calls.
	local instanceNew = world.globals.Instance.new
	world.globals.Instance.new = function(className: string)
		if inClient then
			made[className] = (made[className] or 0) + 1
		end
		return instanceNew(className)
	end
	for frame = 1, FRAMES do
		playFrame(world, frame)
	end
	local names = {}
	for name, total in totals do
		if total[2] > 0 then
			table.insert(names, name)
		end
	end
	table.sort(names, function(a, b)
		return totals[a][1] > totals[b][1]
	end)
	for _, name in names do
		local total = totals[name]
		print(
			string.format(
				"  %-26s %-30s %8.4f ms a frame, %7.2f calls a frame, %5.1f%% of the timed client's time",
				"client calls",
				name,
				total[1] * 1000 / FRAMES,
				total[2] / FRAMES,
				100 * total[1] / clientTotal
			)
		)
	end
	topCounts("client writes", writes, 10)
	topCounts("client calls Roblox", calls, 6)
	topCounts("instances made", made, 4)
end

-- Run -------------------------------------------------------------------------

local onlySite = option("--site")
local botCounts = {}
for n in string.gmatch(option("--bots") or "1,4,8", "%d+") do
	table.insert(botCounts, tonumber(n) :: number)
end

local SITES = {
	{
		name = "GreatHall",
		load = function()
			return Blueprint.load(require("../src/shared/Blueprints/GreatHall") :: any)
		end,
	},
	{
		name = "Terrain64900",
		load = function()
			-- Columns over a 72 by 72 square, 24 high at most: 64,900 slots, near the cap.
			return Blueprint.build(Sites.terrain(1, 72, 24))
		end,
	},
}

if not flag("--no-server") then
	print(`{TICKS} ticks at dt = 1/60 from {FROM * 100}% built, Nightmare boss, 2 pets a bot`)
	print(string.format("  %-26s %-10s %8s  %8s  %8s", "scenario", "", "mean", "p95", "max"))
	for _, entry in SITES do
		if onlySite == nil or onlySite == entry.name then
			local bp = entry.load()
			for _, n in botCounts do
				scenario(entry.name, bp, n)
			end
		end
	end
end
if not flag("--no-client") then
	print(`\nThe prototype under FakeRoblox, {FRAMES} frames at 1/60`)
	print(string.format("  %-26s %-10s %8s  %8s  %8s", "scenario", "", "mean", "p95", "max"))
	client()
end
