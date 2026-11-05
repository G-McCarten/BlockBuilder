--!strict
--[[
	BuildSite: the live state of one site's blueprint during a run.

	Every slot's state lives in flat arrays indexed by slot, so a site holds no
	per-block objects:

	  progress[s]  0..1. 1 means placed.
	  rate[s]      progress per second. Above 0 the block is setting by itself,
	               below 0 it is being undone.
	  unmet[s]     how many of the slot's supports aren't placed. Kept current so
	               nothing scans the site.
	  spent[s]     true once the block has paid. A block pays once, so undone
	               blocks can't be farmed.
	  cause[s]     what last acted on the slot (BuildSite.Cause)
	  causer[s]    UserId credited for that, 0 for none
	  shield[s]    BuildSite.Shield: which placements the slot refuses
	  placedAt[s]  site clock when the block was last placed, for the timelapse
	  sentRate[s]  the rate clients were last sent. They extrapolate from it.

	  active       dense list of the slots whose rate isn't 0, which step() advances
	  dirty        slots changed in a way clients can't extrapolate. takeDirty()
	               drains them for SiteCodec.
	  bound        while true, nothing places once boundCap blocks stand: the
	               boss's binding holds the site short of finished. Blocks
	               setting when the cap is hit wait at progress 1 until it lifts.
	  boundCap     how many placed blocks the binding allows
	  onPlaced     called as onPlaced(slot, firstTime) whenever a block is placed.
	               firstTime is true only the first time, when the block pays.

	A slot's state follows from those arrays:

	  LOCKED   unmet > 0. Can't be aimed at. Progress and rate are always 0.
	  READY    unmet == 0, progress 0, rate 0. Its ghost shows.
	  SETTING  rate > 0. Places itself when progress reaches 1.
	  PLACED   progress 1, rate 0. Counts as placed for its dependents.
	  UNDOING  rate < 0. No longer counts as placed. Turns READY at progress 0.

	Rules, each with a test in tests/BuildSite.spec.luau:

	  1. Only READY or SETTING slots take a placement, and only if their shield
	     allows the cause.
	  2. Nothing floats. A block can be undone only while none of its dependents
	     is placed. When a block stops counting as placed, every dependent drops
	     back to LOCKED and loses its progress.
	  3. From any state, placing READY slots finishes the site, given a
	     blueprint BlueprintValidator accepts.
	  4. A block pays once.

	A client keeps a mirror: a BuildSite fed by setRemote() from SiteCodec. The
	mirror tracks unmet and placedCount but leaves cascades to the server, which
	sends every slot they touch.
]]

local BuildSite = {}

local LOCKED, READY, SETTING, PLACED, UNDOING = 1, 2, 3, 4, 5
BuildSite.State = table.freeze({
	LOCKED = LOCKED,
	READY = READY,
	SETTING = SETTING,
	PLACED = PLACED,
	UNDOING = UNDOING,
})

local HAND = 1
BuildSite.Cause = table.freeze({
	NONE = 0,
	HAND = HAND,
	BATCH = 2,
	CHAIN = 3,
	PET = 4,
	ABILITY = 5,
	TOOL = 6,
	BOSS = 7,
})

-- Shield flags combine, so one effect can lift its flag without clearing another's.
local HAND_ONLY, BLOCKED = 1, 2
BuildSite.Shield = table.freeze({
	NONE = 0,
	-- Only a player's own click places it.
	HAND_ONLY = HAND_ONLY,
	-- Nothing places it.
	BLOCKED = BLOCKED,
})

-- The fields of a Blueprint a site reads.
export type BlueprintLike = {
	count: number,
	supportStart: { number },
	supportList: { number },
	dependentStart: { number },
	dependentList: { number },
}

export type Site = {
	blueprint: BlueprintLike,
	count: number,
	progress: { number },
	rate: { number },
	unmet: { number },
	spent: { boolean },
	cause: { number },
	causer: { number },
	shield: { number },
	placedAt: { number },
	sentRate: { number },
	active: { number },
	activeCount: number,
	activeAt: { number },
	dirty: { boolean },
	dirtyList: { number },
	dirtyCount: number,
	placedCount: number,
	bound: boolean,
	boundCap: number,
	clock: number,
	onPlaced: ((slot: number, firstTime: boolean) -> ())?,
	finishing: { number },
}

function BuildSite.new(blueprint: BlueprintLike): Site
	local count = blueprint.count
	local unmet = table.create(count, 0)
	local supportStart = blueprint.supportStart
	for s = 1, count do
		unmet[s] = supportStart[s + 1] - supportStart[s]
	end
	return {
		blueprint = blueprint,
		count = count,
		progress = table.create(count, 0),
		rate = table.create(count, 0),
		unmet = unmet,
		spent = table.create(count, false),
		cause = table.create(count, 0),
		causer = table.create(count, 0),
		shield = table.create(count, 0),
		placedAt = table.create(count, 0),
		sentRate = table.create(count, 0),
		active = {},
		activeCount = 0,
		activeAt = table.create(count, 0),
		dirty = table.create(count, false),
		dirtyList = {},
		dirtyCount = 0,
		placedCount = 0,
		bound = false,
		boundCap = count,
		clock = 0,
		onPlaced = nil,
		finishing = {},
	}
end

local function isSlot(site: Site, s: number): boolean
	return s >= 1 and s <= site.count and s == s // 1
end

local function isPlaced(site: Site, s: number): boolean
	return site.rate[s] == 0 and site.progress[s] >= 1
end

local function stateOf(site: Site, s: number): number
	local r = site.rate[s]
	if r < 0 then
		return UNDOING
	elseif r > 0 then
		return SETTING
	elseif site.progress[s] >= 1 then
		return PLACED
	elseif site.unmet[s] > 0 then
		return LOCKED
	end
	return READY
end

function BuildSite.state(site: Site, s: number): number
	return stateOf(site, s)
end

function BuildSite.isPlaced(site: Site, s: number): boolean
	return isPlaced(site, s)
end

function BuildSite.percent(site: Site): number
	return if site.count > 0 then site.placedCount / site.count else 1
end

local function markDirty(site: Site, s: number)
	if not site.dirty[s] then
		site.dirty[s] = true
		local n = site.dirtyCount + 1
		site.dirtyCount = n
		site.dirtyList[n] = s
	end
end

local function activate(site: Site, s: number)
	if site.activeAt[s] == 0 then
		local n = site.activeCount + 1
		site.activeCount = n
		site.active[n] = s
		site.activeAt[s] = n
	end
end

local function deactivate(site: Site, s: number)
	local at = site.activeAt[s]
	if at ~= 0 then
		local n = site.activeCount
		local last = site.active[n]
		site.active[at] = last
		site.activeAt[last] = at
		site.active[n] = nil
		site.activeCount = n - 1
		site.activeAt[s] = 0
	end
end

-- s started counting as placed.
local function supportGained(site: Site, s: number)
	site.placedCount += 1
	local bp = site.blueprint
	local list, unmet = bp.dependentList, site.unmet
	for i = bp.dependentStart[s], bp.dependentStart[s + 1] - 1 do
		local d = list[i]
		unmet[d] -= 1
	end
end

-- s stopped counting as placed. With cascade, every dependent with progress or
-- a rate drops back to LOCKED: none of them is placed, as undo() requires.
local function supportLost(site: Site, s: number, cascade: boolean)
	site.placedCount -= 1
	local bp = site.blueprint
	local list, unmet, progress, rate = bp.dependentList, site.unmet, site.progress, site.rate
	for i = bp.dependentStart[s], bp.dependentStart[s + 1] - 1 do
		local d = list[i]
		unmet[d] += 1
		if cascade and (rate[d] ~= 0 or progress[d] ~= 0) then
			progress[d] = 0
			rate[d] = 0
			deactivate(site, d)
			markDirty(site, d)
		end
	end
end

local function finish(site: Site, s: number)
	site.progress[s] = 1
	site.rate[s] = 0
	deactivate(site, s)
	site.placedAt[s] = site.clock
	markDirty(site, s)
	supportGained(site, s)
	local firstTime = not site.spent[s]
	site.spent[s] = true
	local onPlaced = site.onPlaced
	if onPlaced then
		onPlaced(s, firstTime)
	end
end

-- Whether s is READY or SETTING and its shield lets cause place it.
function BuildSite.canPlace(site: Site, s: number, cause: number): boolean
	if not isSlot(site, s) then
		return false
	end
	local state = stateOf(site, s)
	if state ~= READY and state ~= SETTING then
		return false
	end
	if site.bound and site.placedCount >= site.boundCap then
		return false
	end
	local shield = site.shield[s]
	if bit32.btest(shield, BLOCKED) or (bit32.btest(shield, HAND_ONLY) and cause ~= HAND) then
		return false
	end
	return true
end

-- Places s at once. Returns whether it did.
function BuildSite.place(site: Site, s: number, cause: number, causer: number): boolean
	if not BuildSite.canPlace(site, s, cause) then
		return false
	end
	site.cause[s] = cause
	site.causer[s] = causer
	finish(site, s)
	return true
end

-- Starts a READY slot setting by itself at rate progress per second. A rate of
-- math.huge places it at once. Returns whether it started.
function BuildSite.startSetting(site: Site, s: number, rate: number, cause: number, causer: number): boolean
	if not (rate > 0) or not BuildSite.canPlace(site, s, cause) or site.rate[s] ~= 0 then
		return false
	end
	if rate == math.huge then
		return BuildSite.place(site, s, cause, causer)
	end
	site.rate[s] = rate
	site.cause[s] = cause
	site.causer[s] = causer
	activate(site, s)
	markDirty(site, s)
	return true
end

-- Whether s is placed with no placed block resting on it.
function BuildSite.canUndo(site: Site, s: number): boolean
	if not isSlot(site, s) or not isPlaced(site, s) then
		return false
	end
	local bp = site.blueprint
	local list = bp.dependentList
	for i = bp.dependentStart[s], bp.dependentStart[s + 1] - 1 do
		if isPlaced(site, list[i]) then
			return false
		end
	end
	return true
end

-- Starts undoing s at speed progress per second. math.huge undoes it at once.
-- Returns whether it started.
function BuildSite.undo(site: Site, s: number, speed: number, cause: number, causer: number): boolean
	if not (speed > 0) or not BuildSite.canUndo(site, s) then
		return false
	end
	site.cause[s] = cause
	site.causer[s] = causer
	if speed == math.huge then
		site.progress[s] = 0
		site.rate[s] = 0
	else
		site.rate[s] = -speed
		activate(site, s)
	end
	markDirty(site, s)
	supportLost(site, s, true)
	return true
end

-- Sets the slot's shield flags outright.
function BuildSite.setShield(site: Site, s: number, shield: number)
	site.shield[s] = shield
end

-- Raises or lowers one shield flag, leaving the others as they are.
function BuildSite.flagShield(site: Site, s: number, flag: number, on: boolean)
	local shield = site.shield[s]
	site.shield[s] = if on then bit32.bor(shield, flag) else bit32.band(shield, bit32.bnot(flag))
end

-- Advances every active slot by dt seconds.
function BuildSite.step(site: Site, dt: number)
	site.clock += dt
	local active, progress, rate = site.active, site.progress, site.rate
	local finishing = site.finishing
	local done = 0
	-- Backwards, so removing the current slot only moves an already advanced one.
	for i = site.activeCount, 1, -1 do
		local s = active[i]
		local r = rate[s]
		local p = progress[s] + r * dt
		if r > 0 then
			if p >= 1 then
				p = 1
				done += 1
				finishing[done] = s
			end
			progress[s] = p
		elseif p <= 0 then
			-- Undone. unmet is 0: had a support gone, the slot would have reset.
			progress[s] = 0
			rate[s] = 0
			deactivate(site, s)
			markDirty(site, s)
		else
			progress[s] = p
		end
	end
	-- Finish after advancing, so onPlaced can change the site freely.
	for i = 1, done do
		local s = finishing[i]
		finishing[i] = nil
		if rate[s] > 0 and progress[s] >= 1 and not (site.bound and site.placedCount >= site.boundCap) then
			finish(site, s)
		end
	end
end

-- Binds the site so no more than cap blocks can stand, or lifts the binding.
-- Lifting it lets blocks held at the cap finish on the next step.
function BuildSite.bind(site: Site, on: boolean, cap: number?)
	site.bound = on
	site.boundCap = cap or site.count
end

-- Moves the dirty slots into out and returns how many there are.
function BuildSite.takeDirty(site: Site, out: { number }): number
	local n = site.dirtyCount
	local list, dirty, rate, sentRate = site.dirtyList, site.dirty, site.rate, site.sentRate
	for i = 1, n do
		local s = list[i]
		out[i] = s
		list[i] = nil
		dirty[s] = false
		sentRate[s] = rate[s]
	end
	site.dirtyCount = 0
	return n
end

-- Applies a slot's state as the server sent it, on a client's mirror.
function BuildSite.setRemote(site: Site, s: number, progress: number, rate: number)
	local wasPlaced = isPlaced(site, s)
	site.progress[s] = progress
	site.rate[s] = rate
	if rate ~= 0 then
		activate(site, s)
	else
		deactivate(site, s)
	end
	local nowPlaced = isPlaced(site, s)
	if nowPlaced and not wasPlaced then
		site.spent[s] = true
		site.placedAt[s] = site.clock
		supportGained(site, s)
	elseif wasPlaced and not nowPlaced then
		supportLost(site, s, false)
	end
end

return BuildSite
