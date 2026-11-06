--!strict
--[[
	BotBrain: a bot that plays a site the way a steady player would, through
	SiteSession. The run sim plays whole runs with them, and the prototype
	server adds them to a live site for testing alone.

	Each step, a bot:

	  - buys a skill level, skipping nodes that only change how a client
	    aims. By default it buys the cheapest it can afford. Buying by value,
	    it saves for the level that adds the most to its pay a second for the
	    price, by a rough model of its play (BotBrain.earning).
	  - uses its ABILITY, and its POWER_TOOL if it has one, when ready
	  - deals with the boss's works when they matter: breaks the nearest
	    binding while the site is held at its cap, breaks a marker it can
	    reach before the fuse ends, and shoos the boss when it works nearby,
	    makes a stand, or holds a peace circle
	  - otherwise heads for the nearest slot it can place that no teammate
	    could lay from where they stand, and, when off cooldown, clicks the
	    nearest one within grasp

	Movement is a straight line at walking speed. A climb of more than two
	cells rides a hoist pad, which takes hoistSeconds. All in cell space.
]]

local BuildSite = require("./BuildSite")
local SiteIndex = require("./SiteIndex")
local SiteSession = require("./SiteSession")

local BotBrain = {}

local HAND = BuildSite.Cause.HAND

export type Bot = {
	id: number,
	x: number,
	y: number,
	z: number,
	levels: { [string]: number },
	target: number,
	busyUntil: number,
	placeable: (slot: number) -> boolean,
	-- "cheapest" or "value": how it chooses skill levels.
	buying: string,
	-- The node it is saving for, buying by value. Chosen again after each buy.
	want: any?,
}

export type Options = {
	-- "cheapest", the default, or "value".
	buying: string?,
}

-- What a bot's owner can listen for. clicked gets the blocks a click placed.
export type Hooks = {
	bought: ((bot: Bot, nodeId: string, level: number) -> ())?,
	clicked: ((bot: Bot, ok: boolean, reason: string, count: number) -> ())?,
}

-- The parts of SkillTuning a bot plays by.
export type Tuning = {
	walkSpeed: number,
	hoistSeconds: number,
	nodes: { any },
	abilityNode: string,
	tool: any,
	price: (node: any, level: number) -> number,
	stats: (levels: { [string]: number }) -> any,
}

local found: { number } = {}

-- A bot for session, standing at (x, y, z). It isn't working the site until
-- SiteSession.join is called for its id.
function BotBrain.new(session: any, id: number, x: number, y: number, z: number, options: Options?): Bot
	local site = session.site
	return {
		id = id,
		x = x,
		y = y,
		z = z,
		levels = {},
		target = 0,
		busyUntil = 0,
		placeable = function(s: number): boolean
			return BuildSite.canPlace(site, s, HAND)
		end,
		buying = if options and options.buying then options.buying else "cheapest",
		want = nil,
	}
end

-- The model's rough rates, measured by the sim with bots on every site.
-- Share of its cooldowns a bot clicks on (0.83 to 0.92); the rest go on
-- walking and lifts.
local CLICK_SHARE = 0.88
-- Share of the cells within a chain's radius READY when a chain starts (0.01
-- to 0.03). A click's batch has just taken the nearest, so few are.
local CHAIN_READY = 0.02
-- Share of an ABILITY band's budget it finds work for (0.44 to 0.94).
local BAND_SHARE = 0.75

-- Cells within radius of a cell, not counting it.
local function cellsWithin(radius: number): number
	local r = math.floor(radius)
	local n = 0
	for dx = -r, r do
		for dy = -r, r do
			for dz = -r, r do
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 > 0 and d2 <= radius * radius then
					n += 1
				end
			end
		end
	end
	return n
end

-- Run currency a second a bot earns with these stats, by a rough model of
-- its play: it clicks on most cooldowns, each click placing its batch and
-- sometimes a chain, and its ABILITY's band, once unlocked, places at
-- bandRate per cell of its width while it runs. Every block pays its yield
-- once; clicked ones also roll for perfect.
function BotBrain.earning(stats: any, ability: boolean, bandRate: number): number
	local clicked = CLICK_SHARE / stats.cooldown * stats.batch
	local chained = clicked * stats.chainChance * CHAIN_READY * cellsWithin(stats.chainRadius)
	local band = 0
	if ability then
		band = BAND_SHARE * bandRate * stats.crewWidth * stats.crewDuration / stats.crewCooldown
	end
	local perfect = 1 + stats.perfectChance * (stats.perfectReward - 1)
	return stats.yield * stats.yieldMult * (clicked * perfect + chained + band)
end

-- The node whose next level adds the most to the bot's earning for its
-- price. Levels the model sees no gain in, such as setTime's, which only
-- hurries a chain's blocks, wait until nothing else is left, cheapest first.
local function bestValue(bot: Bot, session: any, tuning: Tuning): any?
	local bandRate = session.rules.bandRate
	local ability = (bot.levels[tuning.abilityNode] or 0) >= 1
	local now = BotBrain.earning(tuning.stats(bot.levels), ability, bandRate)
	local best, bestScore = nil, 0
	local cheapest, cheapestPrice = nil, math.huge
	for _, node in tuning.nodes do
		local level = bot.levels[node.id] or 0
		if level < node.max and not node.clientOnly then
			local price = tuning.price(node, level)
			local levels = table.clone(bot.levels)
			levels[node.id] = level + 1
			local unlocks = ability or node.id == tuning.abilityNode
			local score = (BotBrain.earning(tuning.stats(levels), unlocks, bandRate) - now) / price
			if score > bestScore then
				best, bestScore = node, score
			end
			if price < cheapestPrice then
				cheapest, cheapestPrice = node, price
			end
		end
	end
	return best or cheapest
end

local SEARCH_RADII = { 6, 16, 40, 400 }

-- The nearest slot the bot could place, leaving any that a teammate could
-- lay from where they stand, within their grasp, to that teammate. Players
-- can't stand in one another, and a party spreads out over a site rather
-- than crowding onto one spot of work; bots that all head for the nearest
-- slot end up on the same one once their batches clear the work around
-- them. Only when every slot is a teammate's does it take the nearest.
local function nearestWork(bot: Bot, session: any): number
	local index = session.index
	local others: { any } = {}
	for id, worker in session.workers do
		if id ~= bot.id then
			table.insert(others, worker)
		end
	end
	if #others > 0 then
		local bp = session.blueprint
		local x, y, z = bp.x, bp.y, bp.z
		local function free(s: number): boolean
			if not bot.placeable(s) then
				return false
			end
			local cx, cy, cz = x[s] + 0.5, y[s] + 0.5, z[s] + 0.5
			for _, other in others do
				local grasp = other.stats.grasp
				if (other.x - cx) ^ 2 + (other.y - cy) ^ 2 + (other.z - cz) ^ 2 <= grasp * grasp then
					return false
				end
			end
			return true
		end
		for _, radius in SEARCH_RADII do
			if SiteIndex.nearest(index, bot.x, bot.y, bot.z, radius, free, 1, found) > 0 then
				return found[1]
			end
		end
	end
	for _, radius in SEARCH_RADII do
		if SiteIndex.nearest(index, bot.x, bot.y, bot.z, radius, bot.placeable, 1, found) > 0 then
			return found[1]
		end
	end
	return 0
end

-- Moves the bot toward (gx, gy, gz). Returns the distance left.
local function moveToward(
	bot: Bot,
	session: any,
	tuning: Tuning,
	dt: number,
	gx: number,
	gy: number,
	gz: number
): number
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

local function buy(bot: Bot, session: any, tuning: Tuning, tool: boolean, hooks: Hooks?)
	local worker = session.workers[bot.id]
	local best, bestPrice = nil, math.huge
	if bot.buying == "value" then
		if bot.want == nil then
			bot.want = bestValue(bot, session, tuning)
		end
		best = bot.want
		if best then
			bestPrice = tuning.price(best, bot.levels[best.id] or 0)
		end
	else
		for _, node in tuning.nodes do
			local level = bot.levels[node.id] or 0
			if level < node.max and not node.clientOnly then
				local price = tuning.price(node, level)
				if price < bestPrice then
					best, bestPrice = node, price
				end
			end
		end
	end
	if best and worker.purse >= bestPrice then
		worker.purse -= bestPrice
		bot.want = nil
		local level = (bot.levels[best.id] or 0) + 1
		bot.levels[best.id] = level
		SiteSession.setStats(session, bot.id, tuning.stats(bot.levels), if tool then tuning.tool else nil)
		if hooks and hooks.bought then
			hooks.bought(bot, best.id, level)
		end
	end
end

-- Where the boss's works call the bot, if anywhere.
local function bossGoal(bot: Bot, session: any, tuning: Tuning): (number?, number?, number?)
	local boss = session.boss
	if boss == nil or not boss.risen or boss.relented then
		return nil, nil, nil
	end
	local site = session.site
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
	local near = (boss.x - bot.x) ^ 2 + (boss.y - bot.y) ^ 2 + (boss.z - bot.z) ^ 2 <= 400
	if active and (boss.standing or boss.peaceOn or (boss.arrived and near)) then
		return boss.x, boss.y, boss.z
	end
	return nil, nil, nil
end

-- One step of the bot's play, dt seconds long, before the session steps.
function BotBrain.step(bot: Bot, session: any, tuning: Tuning, dt: number, tool: boolean, hooks: Hooks?)
	local worker = session.workers[bot.id]
	if worker == nil then
		return
	end
	local bp = session.blueprint
	buy(bot, session, tuning, tool, hooks)
	if session.clock < worker.smotheredUntil then
		return
	end
	if (bot.levels[tuning.abilityNode] or 0) >= 1 and session.clock >= worker.abilityAt then
		SiteSession.useAbility(session, bot.id)
	end
	local gx, gy, gz = bossGoal(bot, session, tuning)
	if gx then
		moveToward(bot, session, tuning, dt, gx, gy :: number, gz :: number)
	else
		if bot.target == 0 or not bot.placeable(bot.target) then
			bot.target = nearestWork(bot, session)
		end
		local t = bot.target
		if t ~= 0 then
			local cx, cy, cz = bp.x[t] + 0.5, bp.y[t] + 0.5, bp.z[t] + 0.5
			local d = math.sqrt((cx - bot.x) ^ 2 + (cy + 0.5 - bot.y) ^ 2 + (cz - bot.z) ^ 2)
			if d > worker.stats.grasp - 0.5 then
				moveToward(bot, session, tuning, dt, cx, cy + 0.5, cz)
			end
			if tool and session.clock >= worker.toolAt then
				SiteSession.useTool(session, bot.id, cx - bot.x, cz - bot.z)
			end
		end
	end
	SiteSession.move(session, bot.id, bot.x, bot.y, bot.z)
	if session.clock - worker.lastClick >= worker.stats.cooldown then
		local n = SiteIndex.nearest(session.index, bot.x, bot.y, bot.z, worker.stats.grasp, bot.placeable, 1, found)
		if n > 0 then
			local ok, reason, count = SiteSession.request(session, bot.id, found[1])
			if hooks and hooks.clicked then
				hooks.clicked(bot, ok, reason, count)
			end
		end
	end
end

return BotBrain
