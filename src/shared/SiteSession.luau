--!strict
--[[
	SiteSession: one site during a run, as the server keeps it.

	Owns the site (BuildSite), its index (SiteIndex) and everyone working on
	it. The server's networking calls in and sends out what comes back; this
	module decides what happens. It touches no Roblox instances, so the run
	sim and tests drive it the same way the server does.

	  join, leave     a player starts or stops working the site
	  setStats        a player's stats changed, after a skill or a pet
	  move            where a player's root is, in cell space
	  request         a player's click on a slot, checked and then placed
	  useAbility      starts the ABILITY's band sweeping across the site
	  useTool         swings the POWER_TOOL, for players who own it
	  addPet          puts a player's pet to work
	  step            advances the site, bands, pets and boss
	  takeDelta       a SiteCodec delta of what changed since the last one
	  snapshot        a SiteCodec snapshot, for a player joining
	  takeEvents      what happened that players should see or hear
	  counts          what each player has done on the site, for tasks and
	                  achievements: placed, and every kind of event they caused
	  shares          each player's share of the finished site's pay

	A click passes when the slot exists, the player isn't smothered, is within
	grasp plus slack of the slot's centre in 3D, hasn't run out of rate-limit
	tokens, and is off cooldown less a small grace for network jitter. A click
	the site then refuses, because someone else got there first, doesn't
	start the cooldown.

	Pay. Every first placement pays the player credited with it yield *
	yieldMult in run currency. Clicked blocks, the aimed one and the batch,
	roll perfectChance to pay perfectReward times that. Every teammate also
	earns partyShare of the base pay, so a party's trees grow with the site as
	a solo player's does. A block placed again after an undo pays nothing. The
	tally counts first placements per player and survives leaving, so the
	finished site's pay is split by blocks placed.

	Premium drops. Each step, each player who placed a block for the first
	time in that step rolls premiumChance once.
]]

local BossBrain = require("./BossBrain")
local BuildSite = require("./BuildSite")
local SiteActions = require("./SiteActions")
local SiteCodec = require("./SiteCodec")
local SiteIndex = require("./SiteIndex")

local SiteSession = {}

local Cause = BuildSite.Cause

type Site = BuildSite.Site
type Index = SiteIndex.Index

export type Stats = {
	-- Seconds between clicks.
	cooldown: number,
	-- Reach from the root, in cells.
	grasp: number,
	-- Blocks a click places, the aimed one included.
	batch: number,
	-- Seconds a SETTING block takes to place itself.
	setTime: number,
	chainChance: number,
	chainRadius: number,
	perfectChance: number,
	perfectReward: number,
	-- Run currency a block pays.
	yield: number,
	yieldMult: number,
	-- The ABILITY: a band crewWidth cells wide, moving crewSpeed cells a
	-- second for crewDuration seconds, usable every crewCooldown seconds.
	crewWidth: number,
	crewSpeed: number,
	crewDuration: number,
	crewCooldown: number,
}

export type ToolStats = {
	radius: number,
	halfAngle: number,
	band: number,
	setTime: number,
	cooldown: number,
}

export type PetStats = {
	-- Cells a second it travels.
	speed: number,
	-- How far from its owner it looks for work.
	leash: number,
	-- Cells around its target it also places.
	reach: number,
	-- Cells around its target it starts setting.
	ring: number,
	setTime: number,
	-- Seconds it rests after each job.
	rest: number,
	-- A timed ability, for pets that have one: every interval seconds the
	-- pet lays every workable slot within radius of its owner.
	ability: { interval: number, radius: number }?,
}

export type Rules = {
	-- Cells beyond grasp the server allows, for movement during latency.
	slack: number,
	-- Seconds a click may come early, for network jitter.
	cooldownGrace: number,
	-- Clicks a player may send at once, and how many a second refill.
	burst: number,
	perSecond: number,
	-- Chance, per player per step with a first placement, of a premium drop.
	premiumChance: number,
	-- Blocks a second an ABILITY band places, per cell of its width.
	bandRate: number,
	-- Share of a first placement's base pay every teammate also earns, so a
	-- party climbs the skill tree about as fast per share built as a solo
	-- player does.
	partyShare: number,
	chunkCells: number,
}

export type Event = {
	kind: string,
	userId: number?,
	slot: number?,
	amount: number?,
	x: number?,
	y: number?,
	z: number?,
}

export type Worker = {
	userId: number,
	stats: Stats,
	tool: ToolStats?,
	x: number,
	y: number,
	z: number,
	lastClick: number,
	tokens: number,
	tokensAt: number,
	abilityAt: number,
	toolAt: number,
	smotheredUntil: number,
	purse: number,
	-- Everything the player has earned on this site, spent or not.
	earned: number,
	firstThisStep: boolean,
}

export type Band = {
	owner: number,
	axis: number,
	pos: number,
	dir: number,
	width: number,
	speed: number,
	endsAt: number,
	-- Blocks the band may still place, earned at its rate, spent as it goes.
	credit: number,
}

export type Pet = {
	id: number,
	owner: number,
	stats: PetStats,
	x: number,
	y: number,
	z: number,
	travelling: boolean,
	timer: number,
	target: number,
	abilityTimer: number,
}

export type Session = {
	blueprint: any,
	site: Site,
	index: Index,
	rules: Rules,
	random: () -> number,
	clock: number,
	workers: { [number]: Worker },
	tally: { [number]: number },
	counts: { [number]: { [string]: number } },
	bands: { Band },
	pets: { Pet },
	nextPetId: number,
	boss: BossBrain.Brain?,
	events: { Event },
	finished: boolean,
	finishedAt: number,
	dirty: { number },
	placed: { number },
}

SiteSession.DEFAULT_RULES = table.freeze({
	slack = 1.5,
	cooldownGrace = 0.05,
	burst = 6,
	perSecond = 12,
	premiumChance = 0.002,
	bandRate = 6,
	partyShare = 1,
	chunkCells = 8,
})

local function emit(session: Session, event: Event)
	table.insert(session.events, event)
end

function SiteSession.new(blueprint: any, rules: Rules?, random: (() -> number)?): Session
	local site = BuildSite.new(blueprint)
	local chosen: Rules = rules or (SiteSession.DEFAULT_RULES :: any)
	local session: Session = {
		blueprint = blueprint,
		site = site,
		index = SiteIndex.build(blueprint, chosen.chunkCells),
		rules = chosen,
		random = random or math.random,
		clock = 0,
		workers = {},
		tally = {},
		counts = {},
		bands = {},
		pets = {},
		nextPetId = 1,
		boss = nil,
		events = {},
		finished = false,
		finishedAt = 0,
		dirty = {},
		placed = {},
	}

	site.onPlaced = function(slot: number, firstTime: boolean)
		-- Any placement can be the last one, a first or a block laid again.
		if site.placedCount == site.count and not session.finished then
			session.finished = true
			session.finishedAt = session.clock
			emit(session, { kind = "finished" })
		end
		if not firstTime then
			return
		end
		local userId = site.causer[slot]
		session.tally[userId] = (session.tally[userId] or 0) + 1
		local worker = session.workers[userId]
		if worker then
			local stats = worker.stats
			local base = stats.yield * stats.yieldMult
			local pay = base
			local cause = site.cause[slot]
			if (cause == Cause.HAND or cause == Cause.BATCH) and session.random() < stats.perfectChance then
				pay *= stats.perfectReward
				emit(session, { kind = "perfect", userId = userId, slot = slot })
			end
			worker.purse += pay
			worker.earned += pay
			worker.firstThisStep = true
			local share = session.rules.partyShare
			if share > 0 then
				for otherId, other in session.workers do
					if otherId ~= userId then
						other.purse += base * share
						other.earned += base * share
					end
				end
			end
		end
	end
	return session
end

-- Gives the site a boss, with its difficulty's tuning.
function SiteSession.setBoss(session: Session, tuning: BossBrain.Tuning)
	session.boss = BossBrain.new(tuning)
end

-- Starts a player working the site. A player who joins a run in progress
-- starts with the average of what the others have earned, so they can buy
-- their way up the tree to the rest of the party.
function SiteSession.join(session: Session, userId: number, stats: Stats, tool: ToolStats?)
	local total, others = 0, 0
	for otherId, other in session.workers do
		if otherId ~= userId then
			total += other.earned
			others += 1
		end
	end
	local start = if others > 0 then total / others else 0
	session.workers[userId] = {
		userId = userId,
		stats = stats,
		tool = tool,
		x = 0,
		y = 1,
		z = 0,
		lastClick = -math.huge,
		tokens = session.rules.burst,
		tokensAt = session.clock,
		abilityAt = session.clock,
		toolAt = session.clock,
		smotheredUntil = -math.huge,
		purse = start,
		earned = start,
		firstThisStep = false,
	}
	session.tally[userId] = session.tally[userId] or 0
end

-- Stops a player working the site. Their pets go with them; their tally stays.
function SiteSession.leave(session: Session, userId: number)
	session.workers[userId] = nil
	for i = #session.pets, 1, -1 do
		if session.pets[i].owner == userId then
			table.remove(session.pets, i)
		end
	end
end

function SiteSession.setStats(session: Session, userId: number, stats: Stats, tool: ToolStats?)
	local worker = session.workers[userId]
	if worker then
		worker.stats = stats
		worker.tool = tool
	end
end

function SiteSession.move(session: Session, userId: number, x: number, y: number, z: number)
	local worker = session.workers[userId]
	if worker then
		worker.x, worker.y, worker.z = x, y, z
	end
end

-- Handles a click on slot. Returns whether it placed, why not if it didn't,
-- and how many blocks it placed.
function SiteSession.request(session: Session, userId: number, slot: number): (boolean, string, number)
	local worker = session.workers[userId]
	if worker == nil then
		return false, "not_working", 0
	end
	local site = session.site
	if type(slot) ~= "number" or not (slot >= 1 and slot <= site.count and slot == slot // 1) then
		return false, "no_slot", 0
	end
	local now = session.clock
	if now < worker.smotheredUntil then
		return false, "smothered", 0
	end

	-- Every request spends a token, so spamming refused clicks still runs dry.
	local rules = session.rules
	worker.tokens = math.min(rules.burst, worker.tokens + (now - worker.tokensAt) * rules.perSecond)
	worker.tokensAt = now
	if worker.tokens < 1 then
		return false, "rate_limited", 0
	end
	worker.tokens -= 1

	local stats = worker.stats
	local bp = session.blueprint
	local dx, dy, dz = bp.x[slot] + 0.5 - worker.x, bp.y[slot] + 0.5 - worker.y, bp.z[slot] + 0.5 - worker.z
	local reach = stats.grasp + rules.slack
	if dx * dx + dy * dy + dz * dz > reach * reach then
		return false, "out_of_reach", 0
	end
	if now - worker.lastClick < stats.cooldown - rules.cooldownGrace then
		return false, "cooling_down", 0
	end

	local count = SiteActions.hand(site, session.index, slot, {
		batch = stats.batch,
		chainChance = stats.chainChance,
		chainRadius = stats.chainRadius,
		setRate = 1 / stats.setTime,
	}, userId, session.random, session.placed)
	if count == 0 then
		return false, "taken", 0
	end
	worker.lastClick = now
	return true, "ok", count
end

-- Starts the player's ABILITY band from the edge of the site nearest them,
-- across the site's longer side. Returns whether it started.
function SiteSession.useAbility(session: Session, userId: number): boolean
	local worker = session.workers[userId]
	if worker == nil or session.clock < worker.abilityAt or session.clock < worker.smotheredUntil then
		return false
	end
	local stats = worker.stats
	local bp = session.blueprint
	local axis = if bp.sizeX >= bp.sizeZ then 1 else 3
	local size = if axis == 1 then bp.sizeX else bp.sizeZ
	local mine = if axis == 1 then worker.x else worker.z
	local fromLow = mine < size / 2
	table.insert(session.bands, {
		owner = userId,
		axis = axis,
		pos = if fromLow then 0 else size,
		dir = if fromLow then 1 else -1,
		width = stats.crewWidth,
		speed = stats.crewSpeed,
		endsAt = session.clock + stats.crewDuration,
		credit = 0,
	})
	worker.abilityAt = session.clock + stats.crewCooldown
	emit(session, { kind = "ability", userId = userId })
	return true
end

-- Swings the POWER_TOOL facing (fx, fz). Returns whether it swung and how
-- many blocks it placed.
function SiteSession.useTool(session: Session, userId: number, fx: number, fz: number): (boolean, number)
	local worker = session.workers[userId]
	if
		worker == nil
		or worker.tool == nil
		or session.clock < worker.toolAt
		or session.clock < worker.smotheredUntil
	then
		return false, 0
	end
	local tool = worker.tool :: ToolStats
	local count = SiteActions.arc(session.site, session.index, worker.x, worker.y, worker.z, fx, fz, {
		radius = tool.radius,
		halfAngle = tool.halfAngle,
		band = tool.band,
		setRate = 1 / tool.setTime,
	}, userId, session.placed)
	worker.toolAt = session.clock + tool.cooldown
	emit(session, { kind = "tool", userId = userId, amount = count })
	return true, count
end

-- Puts a player's pet to work next to them. Returns its id.
function SiteSession.addPet(session: Session, userId: number, stats: PetStats): number
	local worker = session.workers[userId]
	local id = session.nextPetId
	session.nextPetId += 1
	table.insert(session.pets, {
		id = id,
		owner = userId,
		stats = stats,
		x = if worker then worker.x else 0,
		y = if worker then worker.y else 1,
		z = if worker then worker.z else 0,
		travelling = false,
		timer = stats.rest,
		target = 0,
		abilityTimer = if stats.ability then stats.ability.interval else 0,
	})
	return id
end

local function stepBands(session: Session, dt: number)
	local bp = session.blueprint
	for i = #session.bands, 1, -1 do
		local band = session.bands[i]
		band.pos += band.dir * band.speed * dt
		local size = if band.axis == 1 then bp.sizeX else bp.sizeZ
		local half = band.width / 2
		local gone = (band.dir > 0 and band.pos - half >= size) or (band.dir < 0 and band.pos + half <= 0)
		if session.clock >= band.endsAt or gone then
			table.remove(session.bands, i)
		else
			-- Unspent credit carries over a step, not longer, so a band can't hoard.
			-- It can always save up one block, or a narrow band at 60 steps a
			-- second would never afford one.
			local rate = session.rules.bandRate * band.width
			band.credit = math.min(band.credit + rate * dt, math.max(1, rate * dt * 2))
			local budget = math.floor(band.credit)
			if budget > 0 then
				band.credit -= SiteActions.sweep(
					session.site,
					session.index,
					band.axis,
					band.pos - half,
					band.pos + half,
					band.owner,
					budget,
					session.placed
				)
			end
		end
	end
end

local abilityFound: { number } = {}

local function stepPets(session: Session, dt: number)
	local site, index, bp = session.site, session.index, session.blueprint
	for _, pet in session.pets do
		local ability = pet.stats.ability
		local owner = session.workers[pet.owner]
		if ability and owner then
			pet.abilityTimer -= dt
			if pet.abilityTimer <= 0 then
				-- The timed ability: everything workable around the owner, at once.
				pet.abilityTimer = ability.interval
				local n = SiteIndex.within(index, owner.x, owner.y, owner.z, ability.radius, function(s)
					return BuildSite.canPlace(site, s, Cause.PET)
				end, abilityFound)
				local count = 0
				for i = 1, n do
					if BuildSite.place(site, abilityFound[i], Cause.PET, pet.owner) then
						count += 1
					end
				end
				emit(session, { kind = "pet_ability", userId = pet.owner, amount = count })
			end
		end
		pet.timer -= dt
		if pet.timer <= 0 then
			local stats = pet.stats
			if pet.travelling then
				-- Arrived. The target may have been taken on the way.
				pet.travelling = false
				pet.timer = stats.rest
				local t = pet.target
				pet.x, pet.y, pet.z = bp.x[t] + 0.5, bp.y[t] + 1, bp.z[t] + 0.5
				if BuildSite.canPlace(site, t, Cause.PET) then
					local count = SiteActions.forage(
						site,
						index,
						t,
						stats.reach,
						stats.ring,
						1 / stats.setTime,
						pet.owner,
						session.placed
					)
					emit(session, { kind = "pet", userId = pet.owner, slot = t, amount = count })
				end
			else
				local ox, oy, oz = pet.x, pet.y, pet.z
				if owner then
					ox, oy, oz = owner.x, owner.y, owner.z
				end
				local target = SiteActions.forageTarget(site, index, ox, oy, oz, stats.leash)
				if target then
					local dx, dy, dz = bp.x[target] + 0.5 - pet.x, bp.y[target] + 1 - pet.y, bp.z[target] + 0.5 - pet.z
					pet.target = target
					pet.travelling = true
					pet.timer = math.sqrt(dx * dx + dy * dy + dz * dz) / stats.speed
				else
					pet.timer = stats.rest
				end
			end
		end
	end
end

function SiteSession.step(session: Session, dt: number)
	session.clock += dt
	local site = session.site
	BuildSite.step(site, dt)
	-- Once the site is finished, nothing more works it: bands and pets stop,
	-- and the boss relents.
	if not session.finished then
		stepBands(session, dt)
	end
	if not session.finished then
		stepPets(session, dt)
	end
	local boss = session.boss
	if boss then
		BossBrain.step(boss, session, dt)
	end

	-- Premium drops: one roll per player who placed a first block this step.
	for userId, worker in session.workers do
		if worker.firstThisStep then
			worker.firstThisStep = false
			if session.random() < session.rules.premiumChance then
				emit(session, { kind = "drop", userId = userId })
			end
		end
	end
end

-- The delta of slots changed since the last call, or nil if none did.
function SiteSession.takeDelta(session: Session): buffer?
	local n = BuildSite.takeDirty(session.site, session.dirty)
	if n == 0 then
		return nil
	end
	return SiteCodec.encodeDelta(session.site, session.dirty, n)
end

function SiteSession.snapshot(session: Session): buffer
	return SiteCodec.encodeSnapshot(session.site)
end

function SiteSession.takeEvents(session: Session): { Event }
	local events = session.events
	session.events = {}
	-- Every event a player caused counts toward their tasks and achievements.
	for _, event in events do
		local userId = event.userId
		if userId then
			local mine = session.counts[userId]
			if mine == nil then
				mine = {}
				session.counts[userId] = mine
			end
			mine[event.kind] = (mine[event.kind] or 0) + 1
		end
	end
	return events
end

-- What a player has done on the site: blocks placed for the first time,
-- and how many of each kind of event they caused, counted as events are
-- taken.
function SiteSession.counts(session: Session, userId: number): { [string]: number }
	local counts = table.clone(session.counts[userId] or {})
	counts.placed = session.tally[userId] or 0
	return counts
end

-- Each player's share of the finished site's pay, by first placements.
function SiteSession.shares(session: Session): { [number]: number }
	local total = 0
	for _, n in session.tally do
		total += n
	end
	local shares = {}
	for userId, n in session.tally do
		shares[userId] = if total > 0 then n / total else 0
	end
	return shares
end

-- Hands a bounty to a player, for breaking something of the boss's.
function SiteSession.pay(session: Session, userId: number, amount: number)
	local worker = session.workers[userId]
	if worker then
		worker.purse += amount
		worker.earned += amount
	end
end

SiteSession.emit = emit

return SiteSession
