--[[
	Sim: plays whole runs of a site with bots, through SiteSession, as fast as
	Lune can step them.

	Each bot is a player who, every step:

	  - buys the cheapest skill node it can afford (Tuning)
	  - uses its ABILITY, and its POWER_TOOL if it has the pass, when ready
	  - deals with the boss's works when they matter: breaks the nearest
	    binding while the site is held at its cap, breaks a marker it can reach
	    before the fuse ends, and shoos the boss when it works nearby, makes a
	    stand, or holds a peace circle
	  - otherwise heads for the nearest slot it can place and, when off
	    cooldown, clicks the nearest one within grasp

	Movement is a straight line at walking speed. A climb of more than two
	cells rides a hoist pad, which takes hoistSeconds. Pets ignore collision,
	as in the game.
]]

local BuildSite = require("../../src/shared/BuildSite")
local SiteIndex = require("../../src/shared/SiteIndex")
local SiteSession = require("../../src/shared/SiteSession")
local Tuning = require("./Tuning")

local Sim = {}

local Cause = BuildSite.Cause

export type Options = {
	blueprint: any,
	players: number?,
	seed: number?,
	boss: any?,
	tool: boolean?,
	pets: number?,
	maxMinutes: number?,
	dt: number?,
	tuning: any?,
	partyShare: number?,
}

export type Result = {
	finished: boolean,
	minutes: number,
	percentAt: { number },
	tally: { [number]: number },
	purchases: number,
	events: { [string]: number },
	clicks: number,
	refused: { [string]: number },
	-- Blocks standing at the end, by what last placed them.
	byCause: { [string]: number },
	-- Minute each purchase was made, and what.
	bought: { string },
}

type Bot = {
	id: number,
	x: number,
	y: number,
	z: number,
	levels: { [string]: number },
	target: number,
	busyUntil: number,
}

local function lcg(seed: number): () -> number
	local state = seed % 4294967296
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local found = {}

function Sim.run(options: Options): Result
	local tuning = options.tuning or Tuning
	local bp = options.blueprint
	local players = options.players or 1
	local dt = options.dt or 0.1
	local maxSeconds = (options.maxMinutes or 180) * 60
	local random = lcg(options.seed or 1)
	local rules = table.clone(SiteSession.DEFAULT_RULES) :: any
	if options.partyShare then
		rules.partyShare = options.partyShare
	end
	local session = SiteSession.new(bp, rules, random)
	if options.boss then
		SiteSession.setBoss(session, options.boss)
	end
	local site, index = session.site, session.index

	local bots: { Bot } = {}
	for id = 1, players do
		local bot = {
			id = id,
			-- Players arrive spread along the front of the site.
			x = bp.sizeX * id / (players + 1),
			y = 1,
			z = -2,
			levels = {},
			target = 0,
			busyUntil = 0,
		}
		table.insert(bots, bot)
		SiteSession.join(session, id, tuning.stats(bot.levels) :: any, if options.tool then tuning.tool else nil)
		SiteSession.move(session, id, bot.x, bot.y, bot.z)
		for _ = 1, options.pets or 0 do
			SiteSession.addPet(session, id, tuning.pet)
		end
	end

	local result: Result = {
		finished = false,
		minutes = 0,
		percentAt = {},
		tally = {},
		purchases = 0,
		events = {},
		clicks = 0,
		refused = {},
		byCause = {},
		bought = {},
	}

	local function placeable(s: number): boolean
		return BuildSite.canPlace(site, s, Cause.HAND)
	end

	local function nearestWork(x: number, y: number, z: number): number
		for _, radius in { 6, 16, 40, 400 } do
			if SiteIndex.nearest(index, x, y, z, radius, placeable, 1, found) > 0 then
				return found[1]
			end
		end
		return 0
	end

	-- Moves the bot toward (gx, gy, gz). Returns the distance left.
	local function moveToward(bot: Bot, gx: number, gy: number, gz: number): number
		if session.clock < bot.busyUntil then
			return math.huge
		end
		if gy - bot.y > 2 then
			bot.busyUntil = session.clock + tuning.hoistSeconds
			bot.y = gy
			return math.huge
		end
		local dx, dy, dz = gx - bot.x, gy - bot.y, gz - bot.z
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local stepLen = tuning.walkSpeed * dt
		if d <= stepLen then
			bot.x, bot.y, bot.z = gx, gy, gz
			return 0
		end
		bot.x += dx / d * stepLen
		bot.y += dy / d * stepLen
		bot.z += dz / d * stepLen
		return d - stepLen
	end

	local function buy(bot: Bot)
		local worker = session.workers[bot.id]
		local best, bestPrice = nil, math.huge
		for _, node in tuning.nodes do
			local level = bot.levels[node.id] or 0
			if level < node.max and not node.clientOnly then
				local price = tuning.price(node, level)
				if price < bestPrice then
					best, bestPrice = node, price
				end
			end
		end
		if best and worker.purse >= bestPrice then
			worker.purse -= bestPrice
			bot.levels[best.id] = (bot.levels[best.id] or 0) + 1
			table.insert(result.bought, string.format("%s%d@%.1f", best.id, bot.levels[best.id], session.clock / 60))
			SiteSession.setStats(
				session,
				bot.id,
				tuning.stats(bot.levels) :: any,
				if options.tool then tuning.tool else nil
			)
			result.purchases += 1
		end
	end

	-- Where the boss's works call the bot, if anywhere.
	local function bossGoal(bot: Bot): (number?, number?, number?)
		local boss = session.boss
		if boss == nil or not boss.risen or boss.relented then
			return nil, nil, nil
		end
		local function near(x: number, y: number, z: number, within: number): boolean
			return (x - bot.x) ^ 2 + (y - bot.y) ^ 2 + (z - bot.z) ^ 2 <= within * within
		end
		if site.bound and site.placedCount >= site.boundCap - 5 then
			local best, bestD = nil, math.huge
			for _, b in boss.bindings do
				if not b.broken then
					local d = (b.x - bot.x) ^ 2 + (b.z - bot.z) ^ 2
					if d < bestD then
						best, bestD = b, d
					end
				end
			end
			if best then
				return best.x, best.y, best.z
			end
		end
		for _, m in boss.markers do
			local d = math.sqrt((m.x - bot.x) ^ 2 + (m.y - bot.y) ^ 2 + (m.z - bot.z) ^ 2)
			if d < 30 and d / tuning.walkSpeed < m.fuseEnd - session.clock then
				return m.x, m.y, m.z
			end
		end
		local active = session.clock >= boss.shooedUntil
		if active and (boss.standing or boss.peaceOn or (boss.arrived and near(boss.x, boss.y, boss.z, 20))) then
			return boss.x, boss.y, boss.z
		end
		return nil, nil, nil
	end

	local nextMinute = 60
	while session.clock < maxSeconds and not session.finished do
		for _, bot in bots do
			local worker = session.workers[bot.id]
			buy(bot)
			if session.clock >= worker.smotheredUntil then
				if (bot.levels[tuning.abilityNode] or 0) >= 1 and session.clock >= worker.abilityAt then
					SiteSession.useAbility(session, bot.id)
				end
				local gx, gy, gz = bossGoal(bot)
				if gx then
					moveToward(bot, gx, gy :: number, gz :: number)
				else
					if bot.target == 0 or not placeable(bot.target) then
						bot.target = nearestWork(bot.x, bot.y, bot.z)
					end
					local t = bot.target
					if t ~= 0 then
						local cx, cy, cz = bp.x[t] + 0.5, bp.y[t] + 0.5, bp.z[t] + 0.5
						local d = math.sqrt((cx - bot.x) ^ 2 + (cy + 0.5 - bot.y) ^ 2 + (cz - bot.z) ^ 2)
						if d > worker.stats.grasp - 0.5 then
							moveToward(bot, cx, cy + 0.5, cz)
						end
						if options.tool and session.clock >= worker.toolAt then
							SiteSession.useTool(session, bot.id, cx - bot.x, cz - bot.z)
						end
					end
				end
				SiteSession.move(session, bot.id, bot.x, bot.y, bot.z)
				if session.clock - worker.lastClick >= worker.stats.cooldown then
					local n = SiteIndex.nearest(index, bot.x, bot.y, bot.z, worker.stats.grasp, placeable, 1, found)
					if n > 0 then
						local ok, reason = SiteSession.request(session, bot.id, found[1])
						result.clicks += 1
						if not ok then
							result.refused[reason] = (result.refused[reason] or 0) + 1
						end
					end
				end
			end
		end
		SiteSession.step(session, dt)
		for _, e in SiteSession.takeEvents(session) do
			result.events[e.kind] = (result.events[e.kind] or 0) + 1
		end
		SiteSession.takeDelta(session)
		if session.clock >= nextMinute then
			table.insert(result.percentAt, BuildSite.percent(site))
			nextMinute += 60
		end
	end

	result.finished = session.finished
	result.minutes = (if session.finished then session.finishedAt else session.clock) / 60
	for id, n in session.tally do
		result.tally[id] = n
	end
	local names = {}
	for name, value in Cause do
		names[value] = name
	end
	for s = 1, site.count do
		if BuildSite.isPlaced(site, s) then
			local name = names[site.cause[s]] or "?"
			result.byCause[name] = (result.byCause[name] or 0) + 1
		end
	end
	return result
end

return Sim
