--!strict
--[[
	BossBrain: what the boss decides, step by step, on one site.

	Difficulty gives players things to go and do. It never makes a block
	tougher or a wait longer. The boss:

	  rises        when riseAt of the site is built, at an exposed block far
	               from the players
	  works        walks to a spot like that and, every mendInterval seconds,
	               undoes the mendCount exposed blocks nearest it. It stays
	               until a player comes within shooRadius and shoos it; then
	               it vanishes for shooedFor seconds and comes back elsewhere.
	  relents      at relentAt, lifting everything it holds, so the site can
	               always be finished. A final stand replaces relenting: it
	               keeps working until shooed `shoos` more times.

	And, by difficulty, as its tuning lists them:

	  markers      every interval, a marker on a placed block. A player
	               within breakRadius breaks it for a bounty; otherwise, when
	               its fuse runs out, it undoes every exposed block in radius.
	  stubborn     once, at its share built, a band of slots across the site
	               that only a player's own click can place
	  peace        while the boss works a spot, nothing can be placed within
	               radius of it, until it is shooed
	  binding      once, at its share built, three bindings at far corners of
	               the site. While any stands the site can't pass cap of its
	               blocks. A player within breakRadius breaks one for a bounty.
	  minions      helpers that wander the site, each undoing the exposed block
	               nearest it every interval
	  collapse     at each share listed, the section around the boss comes
	               down from the top
	  strike       every interval, the player nearest the boss within radius
	               is smothered: they can't act for smother seconds

	BossBrain reads and changes the session it is given (see SiteSession):
	its site, index, workers, clock, events and random.
]]

local BossEffects = require("./BossEffects")
local BuildSite = require("./BuildSite")

local BossBrain = {}

local Shield = BuildSite.Shield

export type Tuning = {
	riseAt: number,
	relentAt: number,
	speed: number,
	mendInterval: number,
	mendCount: number,
	mendRadius: number,
	undoSpeed: number,
	shooRadius: number,
	shooedFor: number,
	markers: { interval: number, fuse: number, radius: number, breakRadius: number, bounty: number }?,
	stubborn: { at: number, width: number }?,
	peace: { radius: number }?,
	binding: { at: number, cap: number, breakRadius: number, bounty: number }?,
	minions: { count: number, speed: number, interval: number, radius: number }?,
	collapse: { at: { number }, size: number, budget: number }?,
	strike: { interval: number, radius: number, smother: number }?,
	finalStand: { shoos: number }?,
}

export type Marker = { x: number, y: number, z: number, fuseEnd: number }
export type Binding = { x: number, y: number, z: number, broken: boolean }
export type Minion = { x: number, y: number, z: number, tx: number, ty: number, tz: number, timer: number }

export type Brain = {
	tuning: Tuning,
	risen: boolean,
	relented: boolean,
	standing: boolean,
	standShoos: number,
	x: number,
	y: number,
	z: number,
	tx: number,
	ty: number,
	tz: number,
	arrived: boolean,
	mendTimer: number,
	shooedUntil: number,
	peaceOn: boolean,
	peaceX: number,
	peaceZ: number,
	markers: { Marker },
	markerTimer: number,
	stubbornDone: boolean,
	bindingDone: boolean,
	bindings: { Binding },
	minions: { Minion },
	collapseNext: number,
	strikeTimer: number,
}

-- The parts of a SiteSession the brain uses.
type Worker = {
	userId: number,
	x: number,
	y: number,
	z: number,
	purse: number,
	earned: number,
	smotheredUntil: number,
}
type SessionLike = {
	site: BuildSite.Site,
	index: any,
	blueprint: any,
	workers: { [number]: Worker },
	clock: number,
	events: { any },
	random: () -> number,
}

function BossBrain.new(tuning: Tuning): Brain
	return {
		tuning = tuning,
		risen = false,
		relented = false,
		standing = false,
		standShoos = 0,
		x = 0,
		y = 0,
		z = 0,
		tx = 0,
		ty = 0,
		tz = 0,
		arrived = false,
		mendTimer = tuning.mendInterval,
		shooedUntil = -math.huge,
		peaceOn = false,
		peaceX = 0,
		peaceZ = 0,
		markers = {},
		markerTimer = if tuning.markers then tuning.markers.interval else 0,
		stubbornDone = false,
		bindingDone = false,
		bindings = {},
		minions = {},
		collapseNext = 1,
		strikeTimer = if tuning.strike then tuning.strike.interval else 0,
	}
end

local undone: { number } = {}

local function emit(session: SessionLike, kind: string, fields: { [string]: any }?)
	local event: { [string]: any } = fields or {}
	event.kind = kind
	table.insert(session.events, event)
end

local function dist2(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	return (ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2
end

-- The worker nearest (x, y, z) within radius, or nil.
local function nearestWorker(session: SessionLike, x: number, y: number, z: number, radius: number): Worker?
	local best, bestD = nil, radius * radius
	for _, worker in session.workers do
		local d = dist2(worker.x, worker.y, worker.z, x, y, z)
		if d <= bestD then
			best, bestD = worker, d
		end
	end
	return best
end

-- A spot to work: of a few random exposed blocks, the one farthest from every
-- player. Returns its centre, or nil when nothing is exposed among them.
local function pickSpot(session: SessionLike, needExposed: boolean): (number?, number?, number?)
	local site, bp = session.site, session.blueprint
	local bestS, bestScore = nil, -1
	for _ = 1, 32 do
		local s = 1 + math.floor(session.random() * site.count)
		local ok = if needExposed then BuildSite.canUndo(site, s) else BuildSite.isPlaced(site, s)
		if ok then
			local score = math.huge
			for _, worker in session.workers do
				score =
					math.min(score, dist2(worker.x, worker.y, worker.z, bp.x[s] + 0.5, bp.y[s] + 0.5, bp.z[s] + 0.5))
			end
			if score > bestScore then
				bestS, bestScore = s, score
			end
		end
	end
	if bestS == nil then
		return nil, nil, nil
	end
	return bp.x[bestS] + 0.5, bp.y[bestS] + 0.5, bp.z[bestS] + 0.5
end

local function setPeace(brain: Brain, session: SessionLike, on: boolean)
	local peace = brain.tuning.peace
	if peace == nil or brain.peaceOn == on then
		return
	end
	if on then
		brain.peaceX, brain.peaceZ = brain.x, brain.z
	end
	BossEffects.shieldCircle(session.site, session.index, brain.peaceX, brain.peaceZ, peace.radius, Shield.BLOCKED, on)
	brain.peaceOn = on
	emit(session, if on then "peace_on" else "peace_off", { x = brain.peaceX, z = brain.peaceZ })
end

local function setBound(session: SessionLike, on: boolean, cap: number?)
	BuildSite.bind(session.site, on, cap)
end

local function relent(brain: Brain, session: SessionLike)
	brain.relented = true
	brain.standing = false
	setPeace(brain, session, false)
	table.clear(brain.markers)
	table.clear(brain.minions)
	if session.site.bound then
		for _, binding in brain.bindings do
			binding.broken = true
		end
		setBound(session, false)
	end
	emit(session, "boss_relent")
end

local function rise(brain: Brain, session: SessionLike)
	local x, y, z = pickSpot(session, false)
	if x == nil then
		return
	end
	brain.risen = true
	brain.x, brain.y, brain.z = x :: number, y :: number, z :: number
	brain.tx, brain.ty, brain.tz = brain.x, brain.y, brain.z
	brain.arrived = false
	local minions = brain.tuning.minions
	if minions then
		for _ = 1, minions.count do
			table.insert(brain.minions, {
				x = brain.x,
				y = brain.y,
				z = brain.z,
				tx = brain.x,
				ty = brain.y,
				tz = brain.z,
				timer = minions.interval,
			})
		end
	end
	emit(session, "boss_rise", { x = brain.x, y = brain.y, z = brain.z })
end

local function shoo(brain: Brain, session: SessionLike, by: Worker)
	brain.shooedUntil = session.clock + brain.tuning.shooedFor
	setPeace(brain, session, false)
	emit(session, "boss_shooed", { userId = by.userId })
	if brain.standing then
		brain.standShoos += 1
		local stand = brain.tuning.finalStand :: { shoos: number }
		if brain.standShoos >= stand.shoos then
			relent(brain, session)
			return
		end
	end
	-- It comes back somewhere else.
	local x, y, z = pickSpot(session, true)
	if x then
		brain.x, brain.y, brain.z = x, y :: number, z :: number
	end
	brain.arrived = false
	brain.tx, brain.ty, brain.tz = brain.x, brain.y, brain.z
end

local function moveToward(
	obj: { x: number, y: number, z: number },
	tx: number,
	ty: number,
	tz: number,
	speed: number,
	dt: number
): boolean
	local dx, dy, dz = tx - obj.x, ty - obj.y, tz - obj.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	local stepLen = speed * dt
	if d <= stepLen or d < 1e-6 then
		obj.x, obj.y, obj.z = tx, ty, tz
		return true
	end
	obj.x += dx / d * stepLen
	obj.y += dy / d * stepLen
	obj.z += dz / d * stepLen
	return false
end

local function stepMarkers(brain: Brain, session: SessionLike, dt: number, active: boolean)
	local markers = brain.tuning.markers
	if markers == nil then
		return
	end
	if active then
		brain.markerTimer -= dt
		if brain.markerTimer <= 0 then
			brain.markerTimer = markers.interval
			local x, y, z = pickSpot(session, false)
			if x then
				table.insert(
					brain.markers,
					{ x = x, y = y :: number, z = z :: number, fuseEnd = session.clock + markers.fuse }
				)
				emit(session, "marker_on", { x = x, y = y, z = z })
			end
		end
	end
	for i = #brain.markers, 1, -1 do
		local m = brain.markers[i]
		local by = nearestWorker(session, m.x, m.y, m.z, markers.breakRadius)
		if by then
			table.remove(brain.markers, i)
			by.purse += markers.bounty
			by.earned += markers.bounty
			emit(session, "marker_broken", { userId = by.userId, amount = markers.bounty, x = m.x, y = m.y, z = m.z })
		elseif session.clock >= m.fuseEnd then
			table.remove(brain.markers, i)
			local n = BossEffects.burst(
				session.site,
				session.index,
				m.x,
				m.y,
				m.z,
				markers.radius,
				brain.tuning.undoSpeed,
				undone
			)
			emit(session, "marker_burst", { amount = n, x = m.x, y = m.y, z = m.z })
		end
	end
end

local function stepBindings(brain: Brain, session: SessionLike, percent: number)
	local binding = brain.tuning.binding
	if binding == nil then
		return
	end
	if not brain.bindingDone and percent >= binding.at then
		brain.bindingDone = true
		local bp = session.blueprint
		local corners =
			{ { -0.5, -0.5 }, { bp.sizeX + 0.5, -0.5 }, { -0.5, bp.sizeZ + 0.5 }, { bp.sizeX + 0.5, bp.sizeZ + 0.5 } }
		-- Three of the four corners: leave out the one nearest the boss.
		local skip, skipD = 1, math.huge
		for i, c in corners do
			local d = dist2(c[1], 0, c[2], brain.x, 0, brain.z)
			if d < skipD then
				skip, skipD = i, d
			end
		end
		for i, c in corners do
			if i ~= skip then
				table.insert(brain.bindings, { x = c[1], y = 1, z = c[2], broken = false })
			end
		end
		setBound(session, true, math.floor(binding.cap * session.site.count))
		emit(session, "bound")
	end
	if session.site.bound then
		local standing = 0
		for _, b in brain.bindings do
			if not b.broken then
				local by = nearestWorker(session, b.x, b.y, b.z, binding.breakRadius)
				if by then
					b.broken = true
					by.purse += binding.bounty
					by.earned += binding.bounty
					emit(session, "binding_broken", { userId = by.userId, amount = binding.bounty, x = b.x, z = b.z })
				else
					standing += 1
				end
			end
		end
		if standing == 0 then
			setBound(session, false)
			emit(session, "unbound")
		end
	end
end

local function stepMinions(brain: Brain, session: SessionLike, dt: number)
	local minions = brain.tuning.minions
	if minions == nil then
		return
	end
	local bp = session.blueprint
	for _, m in brain.minions do
		if moveToward(m, m.tx, m.ty, m.tz, minions.speed, dt) then
			m.tx = session.random() * bp.sizeX
			m.tz = session.random() * bp.sizeZ
			m.ty = 1 + session.random() * math.max(1, bp.sizeY - 1)
		end
		m.timer -= dt
		if m.timer <= 0 then
			m.timer = minions.interval
			BossEffects.undoNearest(
				session.site,
				session.index,
				m.x,
				m.y,
				m.z,
				minions.radius,
				1,
				brain.tuning.undoSpeed,
				undone
			)
		end
	end
end

function BossBrain.step(brain: Brain, session: SessionLike, dt: number)
	if brain.relented then
		return
	end
	local site = session.site
	local tuning = brain.tuning
	local percent = BuildSite.percent(site)
	if not brain.risen then
		if percent >= tuning.riseAt then
			rise(brain, session)
		end
		if not brain.risen then
			return
		end
	end

	if percent >= tuning.relentAt and not brain.standing then
		if tuning.finalStand then
			brain.standing = true
			emit(session, "boss_stand", { x = brain.x, y = brain.y, z = brain.z })
		else
			relent(brain, session)
			return
		end
	end

	local stubborn = tuning.stubborn
	if stubborn and not brain.stubbornDone and percent >= stubborn.at then
		brain.stubbornDone = true
		local bp = session.blueprint
		local axis = if bp.sizeX >= bp.sizeZ then 1 else 3
		local size = if axis == 1 then bp.sizeX else bp.sizeZ
		local lo = session.random() * math.max(0, size - stubborn.width)
		BossEffects.shieldBand(site, session.index, axis, lo, lo + stubborn.width, Shield.HAND_ONLY, true)
		emit(session, "stubborn", { amount = lo })
	end

	local collapse = tuning.collapse
	if collapse and collapse.at[brain.collapseNext] and percent >= collapse.at[brain.collapseNext] then
		brain.collapseNext += 1
		local half = collapse.size / 2
		local n = BossEffects.collapse(
			site,
			session.index,
			brain.x - half,
			0,
			brain.z - half,
			brain.x + half,
			session.blueprint.sizeY,
			brain.z + half,
			collapse.budget,
			tuning.undoSpeed,
			undone
		)
		emit(session, "collapse", { amount = n, x = brain.x, z = brain.z })
	end

	local active = session.clock >= brain.shooedUntil
	if active then
		local by = nearestWorker(session, brain.x, brain.y, brain.z, tuning.shooRadius)
		if by then
			shoo(brain, session, by)
			if brain.relented then
				return
			end
			active = false
		end
	end

	if active then
		if not brain.arrived then
			if brain.tx == brain.x and brain.ty == brain.y and brain.tz == brain.z then
				local x, y, z = pickSpot(session, true)
				if x then
					brain.tx, brain.ty, brain.tz = x, y :: number, z :: number
				end
			end
			if moveToward(brain, brain.tx, brain.ty, brain.tz, tuning.speed, dt) then
				brain.arrived = true
				setPeace(brain, session, true)
			end
		end
		brain.mendTimer -= dt
		if brain.mendTimer <= 0 then
			brain.mendTimer = tuning.mendInterval
			BossEffects.undoNearest(
				site,
				session.index,
				brain.x,
				brain.y,
				brain.z,
				tuning.mendRadius,
				tuning.mendCount,
				tuning.undoSpeed,
				undone
			)
		end
		local strike = tuning.strike
		if strike then
			brain.strikeTimer -= dt
			if brain.strikeTimer <= 0 then
				brain.strikeTimer = strike.interval
				local victim = nearestWorker(session, brain.x, brain.y, brain.z, strike.radius)
				if victim then
					victim.smotheredUntil = session.clock + strike.smother
					emit(session, "smother", { userId = victim.userId })
				end
			end
		end
	end

	stepMarkers(brain, session, dt, active)
	stepBindings(brain, session, percent)
	stepMinions(brain, session, dt)
end

-- What clients need to draw the boss and its works.
function BossBrain.view(brain: Brain): { [string]: any }
	local markers, bindings, minions = {}, {}, {}
	for _, m in brain.markers do
		table.insert(markers, { m.x, m.y, m.z, m.fuseEnd })
	end
	for _, b in brain.bindings do
		if not b.broken then
			table.insert(bindings, { b.x, b.y, b.z })
		end
	end
	for _, m in brain.minions do
		table.insert(minions, { m.x, m.y, m.z })
	end
	return {
		risen = brain.risen,
		relented = brain.relented,
		standing = brain.standing,
		x = brain.x,
		y = brain.y,
		z = brain.z,
		away = not brain.arrived,
		peace = if brain.peaceOn then { brain.peaceX, brain.peaceZ } else nil,
		markers = markers,
		bindings = bindings,
		minions = minions,
	}
end

return BossBrain
