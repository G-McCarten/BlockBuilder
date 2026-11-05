--[[
	Sim: plays whole runs of a site with bots (BotBrain), through
	SiteSession, as fast as Lune can step them, and reports how long they
	took and what happened on the way.

	Each run keeps a record of every minute: how many blocks a click placed,
	what placed blocks and how many the boss undid, and each player's run
	currency. At the end it works out what each player's share of the site's
	payout pays per minute played. Sim.summarise averages a set of runs,
	minute by minute.
]]

local BotBrain = require("../../src/shared/BotBrain")
local BuildSite = require("../../src/shared/BuildSite")
local SiteList = require("../../src/shared/SiteList")
local SiteSession = require("../../src/shared/SiteSession")
local Tuning = require("./Tuning")

local Sim = {}

local Cause = BuildSite.Cause

-- Cause names by value, for the tables.
local causeNames: { [number]: string } = {}
for name, value in Cause do
	causeNames[value] = name
end

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
	-- META_CURRENCY a finished site pays its party. Defaults to the site's
	-- payout in SiteList, found by the blueprint's name, or 0.
	payout: number?,
}

-- One minute of a run.
export type Minute = {
	-- Seconds of the run it covers: 60, or fewer for the last.
	seconds: number,
	-- Clicks that placed blocks, and the median a click placed itself: the
	-- aimed block and its batch.
	clicks: number,
	perClick: number,
	-- Blocks placed, first placements and blocks laid again alike, by cause.
	placed: { [string]: number },
	-- Placed blocks the boss and its works undid.
	undone: number,
	-- Share of the site built at its end.
	built: number,
	-- Run currency each player held at its end, and had earned in all.
	purse: { [number]: number },
	earned: { [number]: number },
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
	-- Every minute of the run, in order.
	byMinute: { Minute },
	-- The minute each player bought each level of each node:
	-- boughtAt[player][node][level].
	boughtAt: { [number]: { [string]: { number } } },
	-- Placed blocks the boss undid in all, and how: "marker" by markers whose
	-- fuse ran out, "collapse" by collapses, and "nearest" by the boss and
	-- its minions undoing the exposed blocks nearest them.
	undone: number,
	undoneBy: { [string]: number },
	-- The site's payout, each player's share of it (SiteSession.shares), and
	-- what that share pays per minute played. An unfinished site pays nothing.
	payout: number,
	shares: { [number]: number },
	payPerMinute: { [number]: number },
}

-- A set of runs, averaged.
export type MinuteSummary = {
	-- Runs that reached this minute.
	runs: number,
	-- The mean of those runs' median blocks per click.
	perClick: number,
	-- Blocks clicks placed, with the chains they set off, per click.
	withChains: number,
	-- Placed blocks the boss undid, per minute.
	undone: number,
	-- Means over the runs, and over each run's players.
	built: number,
	purse: number,
	earned: number,
}

export type Summary = {
	runs: number,
	unfinished: number,
	mean: number,
	best: number,
	worst: number,
	byMinute: { MinuteSummary },
	-- boughtAt[node][level]: the mean minute it was bought, over the players
	-- who bought it, and the share of all players who did.
	boughtAt: { [string]: { { minute: number, share: number } } },
	-- Placed blocks the boss undid per run, in all and by how, and per minute
	-- over whole runs.
	undone: number,
	undoneBy: { [string]: number },
	undoneRate: number,
	-- What each player's share of the payout pays per minute played: the
	-- mean over every player of every run, and the lowest and highest.
	pay: number,
	payLow: number,
	payHigh: number,
}

local function lcg(seed: number): () -> number
	local state = seed % 4294967296
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Sorts list in place and returns its median, or 0 for an empty list.
local function median(list: { number }): number
	local n = #list
	if n == 0 then
		return 0
	end
	table.sort(list)
	if n % 2 == 1 then
		return list[(n + 1) // 2]
	end
	return (list[n // 2] + list[n // 2 + 1]) / 2
end

local function payoutOf(bp: any): number
	for _, entry in SiteList do
		if entry.id == bp.name then
			return entry.payout
		end
	end
	return 0
end

local function newMinute(): Minute
	return { seconds = 0, clicks = 0, perClick = 0, placed = {}, undone = 0, built = 0, purse = {}, earned = {} }
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
		byMinute = {},
		boughtAt = {},
		undone = 0,
		undoneBy = { nearest = 0, marker = 0, collapse = 0 },
		payout = options.payout or payoutOf(bp),
		shares = {},
		payPerMinute = {},
	}

	local minute = newMinute()
	local clickCounts: { number } = {}
	local function closeMinute(seconds: number)
		minute.seconds = seconds
		minute.perClick = median(clickCounts)
		minute.built = BuildSite.percent(site)
		for id, worker in session.workers do
			minute.purse[id] = worker.purse
			minute.earned[id] = worker.earned
		end
		table.insert(result.byMinute, minute)
		minute = newMinute()
		table.clear(clickCounts)
	end

	-- Every placement, whatever made it, passes through the site's onPlaced.
	local stepPlaced = 0
	local onPlaced = site.onPlaced
	site.onPlaced = function(slot: number, firstTime: boolean)
		stepPlaced += 1
		local name = causeNames[site.cause[slot]] or "?"
		minute.placed[name] = (minute.placed[name] or 0) + 1
		if onPlaced then
			onPlaced(slot, firstTime)
		end
	end

	local hooks = {
		bought = function(bot, nodeId: string, level: number)
			table.insert(result.bought, string.format("%s%d@%.1f", nodeId, level, session.clock / 60))
			result.purchases += 1
			local mine = result.boughtAt[bot.id]
			if mine == nil then
				mine = {}
				result.boughtAt[bot.id] = mine
			end
			local levels = mine[nodeId]
			if levels == nil then
				levels = {}
				mine[nodeId] = levels
			end
			levels[level] = session.clock / 60
		end,
		clicked = function(_bot, ok: boolean, reason: string, count: number)
			result.clicks += 1
			if ok then
				minute.clicks += 1
				table.insert(clickCounts, count)
			else
				result.refused[reason] = (result.refused[reason] or 0) + 1
			end
		end,
	}
	local tool = options.tool == true

	local nextMinute = 60
	while session.clock < maxSeconds and not session.finished do
		local before = site.placedCount
		stepPlaced = 0
		for _, bot in bots do
			BotBrain.step(bot, session, tuning, dt, tool, hooks)
		end
		SiteSession.step(session, dt)
		-- Only the boss undoes placed blocks, so whatever of this step's
		-- placements doesn't show in the change of placed blocks, it undid.
		local undone = stepPlaced - (site.placedCount - before)
		minute.undone += undone
		result.undone += undone
		for _, e in SiteSession.takeEvents(session) do
			result.events[e.kind] = (result.events[e.kind] or 0) + 1
			if e.kind == "marker_burst" then
				result.undoneBy.marker += e.amount or 0
			elseif e.kind == "collapse" then
				result.undoneBy.collapse += e.amount or 0
			end
		end
		SiteSession.takeDelta(session)
		if session.clock >= nextMinute then
			table.insert(result.percentAt, BuildSite.percent(site))
			closeMinute(60)
			nextMinute += 60
		end
	end
	-- The last minute, cut short by the finish.
	local left = session.clock - (nextMinute - 60)
	if left > 1e-6 then
		closeMinute(left)
	end
	result.undoneBy.nearest = result.undone - result.undoneBy.marker - result.undoneBy.collapse

	result.finished = session.finished
	result.minutes = (if session.finished then session.finishedAt else session.clock) / 60
	for id, n in session.tally do
		result.tally[id] = n
	end
	for s = 1, site.count do
		if BuildSite.isPlaced(site, s) then
			local name = causeNames[site.cause[s]] or "?"
			result.byCause[name] = (result.byCause[name] or 0) + 1
		end
	end
	result.shares = SiteSession.shares(session)
	for id, share in result.shares do
		result.payPerMinute[id] = if result.finished and result.minutes > 0
			then result.payout * share / result.minutes
			else 0
	end
	return result
end

local function mean(values: { [number]: number }): number
	local total, n = 0, 0
	for _, v in values do
		total += v
		n += 1
	end
	return if n > 0 then total / n else 0
end

-- Averages a set of runs of the same site, minute by minute.
function Sim.summarise(results: { Result }): Summary
	local runs = #results
	local summary: Summary = {
		runs = runs,
		unfinished = 0,
		mean = 0,
		best = if runs > 0 then math.huge else 0,
		worst = 0,
		byMinute = {},
		boughtAt = {},
		undone = 0,
		undoneBy = {},
		undoneRate = 0,
		pay = 0,
		payLow = 0,
		payHigh = 0,
	}
	if runs == 0 then
		return summary
	end

	type Row = {
		runs: number,
		perClick: number,
		clickRuns: number,
		clicks: number,
		clickPlaced: number,
		undone: number,
		seconds: number,
		built: number,
		purse: number,
		earned: number,
	}
	local rows: { Row } = {}
	local bought: { [string]: { { sum: number, count: number } } } = {}
	local players, totalMinutes = 0, 0
	local pays: { number } = {}

	for _, r in results do
		if not r.finished then
			summary.unfinished += 1
		end
		summary.mean += r.minutes / runs
		summary.best = math.min(summary.best, r.minutes)
		summary.worst = math.max(summary.worst, r.minutes)
		summary.undone += r.undone / runs
		for how, n in r.undoneBy do
			summary.undoneBy[how] = (summary.undoneBy[how] or 0) + n / runs
		end
		totalMinutes += r.minutes
		for _ in r.tally do
			players += 1
		end
		for _, pay in r.payPerMinute do
			table.insert(pays, pay)
		end
		for _, nodes in r.boughtAt do
			for nodeId, levels in nodes do
				local sums = bought[nodeId]
				if sums == nil then
					sums = {}
					bought[nodeId] = sums
				end
				for level, at in levels do
					local cell = sums[level]
					if cell == nil then
						cell = { sum = 0, count = 0 }
						sums[level] = cell
					end
					cell.sum += at
					cell.count += 1
				end
			end
		end
		for m, minute in r.byMinute do
			local row = rows[m]
			if row == nil then
				row = {
					runs = 0,
					perClick = 0,
					clickRuns = 0,
					clicks = 0,
					clickPlaced = 0,
					undone = 0,
					seconds = 0,
					built = 0,
					purse = 0,
					earned = 0,
				}
				rows[m] = row
			end
			row.runs += 1
			if minute.clicks > 0 then
				row.perClick += minute.perClick
				row.clickRuns += 1
			end
			local placed = minute.placed
			row.clicks += minute.clicks
			row.clickPlaced += (placed.HAND or 0) + (placed.BATCH or 0) + (placed.CHAIN or 0)
			row.undone += minute.undone
			row.seconds += minute.seconds
			row.built += minute.built
			row.purse += mean(minute.purse)
			row.earned += mean(minute.earned)
		end
	end

	for m, row in rows do
		summary.byMinute[m] = {
			runs = row.runs,
			perClick = if row.clickRuns > 0 then row.perClick / row.clickRuns else 0,
			withChains = if row.clicks > 0 then row.clickPlaced / row.clicks else 0,
			undone = if row.seconds > 0 then row.undone / row.seconds * 60 else 0,
			built = row.built / row.runs,
			purse = row.purse / row.runs,
			earned = row.earned / row.runs,
		}
	end
	for nodeId, sums in bought do
		local levels = {}
		for level, cell in sums do
			levels[level] = { minute = cell.sum / cell.count, share = cell.count / players }
		end
		summary.boughtAt[nodeId] = levels
	end
	summary.undoneRate = if totalMinutes > 0 then summary.undone * runs / totalMinutes else 0
	if #pays > 0 then
		summary.pay = mean(pays)
		summary.payLow = math.huge
		for _, pay in pays do
			summary.payLow = math.min(summary.payLow, pay)
			summary.payHigh = math.max(summary.payHigh, pay)
		end
	end
	return summary
end

return Sim
