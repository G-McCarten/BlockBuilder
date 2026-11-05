--[[
	Sim: plays whole runs of a site with bots (BotBrain), through
	SiteSession, as fast as Lune can step them, and reports how long they
	took and what happened on the way.
]]

local BotBrain = require("../../src/shared/BotBrain")
local BuildSite = require("../../src/shared/BuildSite")
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

local function lcg(seed: number): () -> number
	local state = seed % 4294967296
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

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
	local site = session.site

	local bots = {}
	for id = 1, players do
		-- Players arrive spread along the front of the site.
		local bot = BotBrain.new(session, id, bp.sizeX * id / (players + 1), 1, -2)
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

	local hooks = {
		bought = function(_bot, nodeId: string, level: number)
			table.insert(result.bought, string.format("%s%d@%.1f", nodeId, level, session.clock / 60))
			result.purchases += 1
		end,
		clicked = function(_bot, ok: boolean, reason: string)
			result.clicks += 1
			if not ok then
				result.refused[reason] = (result.refused[reason] or 0) + 1
			end
		end,
	}
	local tool = options.tool == true

	local nextMinute = 60
	while session.clock < maxSeconds and not session.finished do
		for _, bot in bots do
			BotBrain.step(bot, session, tuning, dt, tool, hooks)
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
