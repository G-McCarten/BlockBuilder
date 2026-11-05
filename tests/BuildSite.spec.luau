local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local SiteCodec = require("../src/shared/SiteCodec")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local State = BuildSite.State
local Cause = BuildSite.Cause
local Shield = BuildSite.Shield

-- A column of three, and one block beside its foot.
local function column()
	local bp = Blueprint.build({
		name = "Column",
		palette = { "a" },
		blocks = {
			{ x = 0, y = 0, z = 0, kind = 1 },
			{ x = 0, y = 1, z = 0, kind = 1 },
			{ x = 0, y = 2, z = 0, kind = 1 },
			{ x = 1, y = 0, z = 0, kind = 1 },
		},
	})
	return bp, BuildSite.new(bp)
end

Test.group("BuildSite")

Test.case("a new site has its ground slots READY and the rest LOCKED", function()
	local _, site = column()
	Test.equal(BuildSite.state(site, 1), State.READY, "ground")
	Test.equal(BuildSite.state(site, 2), State.LOCKED, "above")
	Test.equal(BuildSite.state(site, 4), State.READY, "beside")
	Test.equal(BuildSite.percent(site), 0, "percent built")
end)

Test.case("place takes READY slots and opens their dependents", function()
	local _, site = column()
	Test.check(not BuildSite.place(site, 2, Cause.HAND, 1), "LOCKED is refused")
	Test.check(BuildSite.place(site, 1, Cause.HAND, 1), "READY is placed")
	Test.equal(BuildSite.state(site, 1), State.PLACED, "placed")
	Test.equal(BuildSite.state(site, 2), State.READY, "the block above opens")
	Test.check(not BuildSite.place(site, 1, Cause.HAND, 1), "PLACED is refused")
	Test.equal(site.placedCount, 1, "placedCount")
end)

Test.case("a SETTING block places itself and pays its causer once", function()
	local _, site = column()
	local paid = {}
	site.onPlaced = function(slot, firstTime)
		table.insert(paid, { slot, firstTime })
	end
	Test.check(BuildSite.startSetting(site, 1, 2, Cause.CHAIN, 42), "starts")
	Test.equal(BuildSite.state(site, 1), State.SETTING, "setting")
	Test.check(not BuildSite.startSetting(site, 1, 2, Cause.CHAIN, 7), "can't restart a SETTING slot")
	BuildSite.step(site, 0.25)
	Test.equal(site.progress[1], 0.5, "half way")
	BuildSite.step(site, 0.25)
	Test.equal(BuildSite.state(site, 1), State.PLACED, "placed at progress 1")
	Test.equal(site.causer[1], 42, "credit stays with whoever started it")
	Test.equal(site.placedAt[1], 0.5, "placedAt is the site clock")
	Test.equal(#paid, 1, "one placement")
	Test.check(paid[1][2], "first placement pays")
	Test.equal(site.activeCount, 0, "nothing left active")
end)

Test.case("a hand placement finishes a SETTING block at once", function()
	local _, site = column()
	BuildSite.startSetting(site, 1, 0.1, Cause.PET, 3)
	Test.check(BuildSite.place(site, 1, Cause.HAND, 9), "SETTING takes a placement")
	Test.equal(BuildSite.state(site, 1), State.PLACED, "placed")
	Test.equal(site.causer[1], 9, "the hand gets the credit")
	Test.equal(site.activeCount, 0, "no longer active")
end)

Test.case("nothing floats: undo waits until no placed block rests on it", function()
	local _, site = column()
	BuildSite.place(site, 1, Cause.HAND, 1)
	BuildSite.place(site, 2, Cause.HAND, 1)
	Test.check(not BuildSite.canUndo(site, 1), "block 2 rests on block 1")
	Test.check(not BuildSite.undo(site, 1, 1, Cause.BOSS, 0), "refused")
	Test.check(BuildSite.undo(site, 2, 1, Cause.BOSS, 0), "the top block can be undone")
	Test.equal(BuildSite.state(site, 2), State.UNDOING, "undoing")
	Test.check(not BuildSite.isPlaced(site, 2), "an UNDOING block doesn't count as placed")
	Test.check(BuildSite.canUndo(site, 1), "now nothing placed rests on block 1")
end)

Test.case("undo drops a SETTING dependent back to LOCKED and clears its progress", function()
	local _, site = column()
	BuildSite.place(site, 1, Cause.HAND, 1)
	BuildSite.startSetting(site, 2, 1, Cause.CHAIN, 1)
	BuildSite.step(site, 0.5)
	Test.check(BuildSite.undo(site, 1, math.huge, Cause.BOSS, 0), "undo at once")
	Test.equal(BuildSite.state(site, 1), State.READY, "undone at once is READY")
	Test.equal(BuildSite.state(site, 2), State.LOCKED, "dependent is LOCKED")
	Test.equal(site.progress[2], 0, "and lost its progress")
	Test.equal(site.activeCount, 0, "and stopped setting")
	Test.equal(site.placedCount, 0, "placedCount")
end)

Test.case("an undone block placed again doesn't pay again", function()
	local _, site = column()
	local firsts = 0
	site.onPlaced = function(_, firstTime)
		if firstTime then
			firsts += 1
		end
	end
	for _ = 1, 5 do
		BuildSite.place(site, 1, Cause.HAND, 1)
		BuildSite.undo(site, 1, math.huge, Cause.BOSS, 0)
	end
	Test.equal(firsts, 1, "paid once in five placements")
	Test.check(site.spent[1], "spent")
end)

Test.case("UNDOING slots take no placement and turn READY at progress 0", function()
	local _, site = column()
	BuildSite.place(site, 4, Cause.HAND, 1)
	BuildSite.undo(site, 4, 2, Cause.BOSS, 0)
	Test.check(not BuildSite.place(site, 4, Cause.HAND, 1), "UNDOING is refused")
	BuildSite.step(site, 0.3)
	Test.equal(BuildSite.state(site, 4), State.UNDOING, "still undoing")
	BuildSite.step(site, 0.3)
	Test.equal(BuildSite.state(site, 4), State.READY, "READY again")
	Test.equal(site.progress[4], 0, "at progress 0")
	Test.check(BuildSite.place(site, 4, Cause.HAND, 1), "and placeable")
end)

Test.case("shields: HAND_ONLY takes only a hand, BLOCKED takes nothing", function()
	local _, site = column()
	BuildSite.setShield(site, 1, Shield.HAND_ONLY)
	Test.check(not BuildSite.place(site, 1, Cause.PET, 1), "a pet can't")
	Test.check(not BuildSite.startSetting(site, 1, 1, Cause.CHAIN, 1), "a chain can't")
	Test.check(BuildSite.place(site, 1, Cause.HAND, 1), "a hand can")
	BuildSite.setShield(site, 4, Shield.BLOCKED)
	Test.check(not BuildSite.place(site, 4, Cause.HAND, 1), "nothing places a BLOCKED slot")
end)

Test.case("shield flags combine and lift one at a time", function()
	local _, site = column()
	BuildSite.flagShield(site, 1, Shield.HAND_ONLY, true)
	BuildSite.flagShield(site, 1, Shield.BLOCKED, true)
	Test.equal(site.shield[1], 3, "both flags")
	Test.check(not BuildSite.canPlace(site, 1, Cause.HAND), "blocked, even for a hand")
	BuildSite.flagShield(site, 1, Shield.BLOCKED, false)
	Test.equal(site.shield[1], Shield.HAND_ONLY, "lifting BLOCKED keeps HAND_ONLY")
	Test.check(BuildSite.canPlace(site, 1, Cause.HAND), "a hand can again")
	Test.check(not BuildSite.canPlace(site, 1, Cause.PET, 1), "a pet still can't")
	BuildSite.flagShield(site, 1, Shield.BLOCKED, false)
	Test.equal(site.shield[1], Shield.HAND_ONLY, "lifting a flag that isn't raised changes nothing")
end)

Test.case("slots that don't exist are refused", function()
	local _, site = column()
	for _, s in { 0, -1, 5, 1.5, 0 / 0, math.huge } do
		Test.check(not BuildSite.place(site, s, Cause.HAND, 1), `place {s}`)
		Test.check(not BuildSite.startSetting(site, s, 1, Cause.HAND, 1), `startSetting {s}`)
		Test.check(not BuildSite.undo(site, s, 1, Cause.BOSS, 0), `undo {s}`)
	end
end)

Test.case("takeDirty reports each changed slot once", function()
	local _, site = column()
	BuildSite.startSetting(site, 1, 4, Cause.HAND, 1)
	BuildSite.step(site, 1)
	BuildSite.place(site, 4, Cause.HAND, 1)
	local out = {}
	local n = BuildSite.takeDirty(site, out)
	Test.equal(n, 2, "two slots changed")
	Test.equal(out[1], 1, "first the setting one")
	Test.equal(out[2], 4, "then the placed one")
	Test.equal(BuildSite.takeDirty(site, out), 0, "drained")
end)

-- Random play against a reference model ------------------------------------

-- The model holds only progress and rate, and works everything else out by
-- scanning, so it is slow but plainly right.
type Model = {
	bp: Blueprint.Blueprint,
	progress: { number },
	rate: { number },
	shield: { number },
	everPlaced: { boolean },
}

local function newModel(bp: Blueprint.Blueprint): Model
	return {
		bp = bp,
		progress = table.create(bp.count, 0),
		rate = table.create(bp.count, 0),
		shield = table.create(bp.count, 0),
		everPlaced = table.create(bp.count, false),
	}
end

local function mPlaced(m: Model, s: number): boolean
	return m.rate[s] == 0 and m.progress[s] >= 1
end

local function mUnmet(m: Model, s: number): number
	local n = 0
	for i = m.bp.supportStart[s], m.bp.supportStart[s + 1] - 1 do
		if not mPlaced(m, m.bp.supportList[i]) then
			n += 1
		end
	end
	return n
end

local function mState(m: Model, s: number): number
	if m.rate[s] < 0 then
		return State.UNDOING
	elseif m.rate[s] > 0 then
		return State.SETTING
	elseif m.progress[s] >= 1 then
		return State.PLACED
	elseif mUnmet(m, s) > 0 then
		return State.LOCKED
	end
	return State.READY
end

local function mCanPlace(m: Model, s: number, cause: number): boolean
	local state = mState(m, s)
	if state ~= State.READY and state ~= State.SETTING then
		return false
	end
	-- Shields are 0 none, 1 hand only, 2 blocked, 3 both.
	local shield = m.shield[s]
	local blocked = shield == 2 or shield == 3
	local handOnly = shield == 1 or shield == 3
	return not blocked and not (handOnly and cause ~= Cause.HAND)
end

local function mCanUndo(m: Model, s: number): boolean
	if not mPlaced(m, s) then
		return false
	end
	for i = m.bp.dependentStart[s], m.bp.dependentStart[s + 1] - 1 do
		if mPlaced(m, m.bp.dependentList[i]) then
			return false
		end
	end
	return true
end

local function mFinish(m: Model, s: number, events: { [number]: boolean })
	m.progress[s] = 1
	m.rate[s] = 0
	events[s] = not m.everPlaced[s]
	m.everPlaced[s] = true
end

local function mUndo(m: Model, s: number, speed: number)
	if speed == math.huge then
		m.progress[s] = 0
		m.rate[s] = 0
	else
		m.rate[s] = -speed
	end
	for i = m.bp.dependentStart[s], m.bp.dependentStart[s + 1] - 1 do
		local d = m.bp.dependentList[i]
		m.progress[d] = 0
		m.rate[d] = 0
	end
end

local function mStep(m: Model, dt: number, events: { [number]: boolean })
	for s = 1, m.bp.count do
		local r = m.rate[s]
		if r ~= 0 then
			local p = m.progress[s] + r * dt
			if r > 0 and p >= 1 then
				mFinish(m, s, events)
			elseif r < 0 and p <= 0 then
				m.progress[s] = 0
				m.rate[s] = 0
			else
				m.progress[s] = p
			end
		end
	end
end

local f32 = buffer.create(4)
local function asF32(v: number): number
	buffer.writef32(f32, 0, v)
	return buffer.readf32(f32, 0)
end

local function checkSlot(site: BuildSite.Site, m: Model, s: number)
	if site.progress[s] ~= m.progress[s] or site.rate[s] ~= m.rate[s] then
		error(`slot {s}: site has progress {site.progress[s]} rate {site.rate[s]}, model {m.progress[s]} {m.rate[s]}`)
	end
	local state = mState(m, s)
	if BuildSite.state(site, s) ~= state then
		error(`slot {s}: site state {BuildSite.state(site, s)}, model {state}`)
	end
	if site.unmet[s] ~= mUnmet(m, s) then
		error(`slot {s}: unmet {site.unmet[s]}, but {mUnmet(m, s)} supports aren't placed`)
	end
	if state == State.LOCKED and (site.progress[s] ~= 0 or site.rate[s] ~= 0) then
		error(`slot {s}: LOCKED with progress or rate`)
	end
	if mPlaced(m, s) then
		for i = m.bp.supportStart[s], m.bp.supportStart[s + 1] - 1 do
			if not mPlaced(m, m.bp.supportList[i]) then
				error(`slot {s} is placed but floats: support {m.bp.supportList[i]} isn't placed`)
			end
		end
	end
	if site.spent[s] ~= m.everPlaced[s] then
		error(`slot {s}: spent {site.spent[s]}, but placed before is {m.everPlaced[s]}`)
	end
	if (site.activeAt[s] ~= 0) ~= (site.rate[s] ~= 0) then
		error(`slot {s}: active list disagrees with rate {site.rate[s]}`)
	end
end

local function checkMirror(site: BuildSite.Site, mirror: BuildSite.Site, s: number)
	if BuildSite.isPlaced(mirror, s) ~= BuildSite.isPlaced(site, s) then
		error(`mirror slot {s}: placed {BuildSite.isPlaced(mirror, s)}, server {BuildSite.isPlaced(site, s)}`)
	end
	if mirror.rate[s] ~= asF32(site.rate[s]) then
		error(`mirror slot {s}: rate {mirror.rate[s]}, server {site.rate[s]}`)
	end
	if site.rate[s] == 0 and mirror.progress[s] ~= SiteCodec.unquantize(SiteCodec.quantize(site.progress[s])) then
		error(`mirror slot {s}: progress {mirror.progress[s]}, server {site.progress[s]}`)
	end
	if mirror.unmet[s] ~= site.unmet[s] then
		error(`mirror slot {s}: unmet {mirror.unmet[s]}, server {site.unmet[s]}`)
	end
	if BuildSite.state(mirror, s) ~= BuildSite.state(site, s) then
		error(`mirror slot {s}: state {BuildSite.state(mirror, s)}, server {BuildSite.state(site, s)}`)
	end
end

local function checkAll(site: BuildSite.Site, m: Model, mirror: BuildSite.Site)
	local placed, active = 0, 0
	for s = 1, site.count do
		checkSlot(site, m, s)
		checkMirror(site, mirror, s)
		if mPlaced(m, s) then
			placed += 1
		end
		if m.rate[s] ~= 0 then
			active += 1
		end
	end
	Test.equal(site.placedCount, placed, "placedCount")
	Test.equal(mirror.placedCount, placed, "mirror placedCount")
	Test.equal(site.activeCount, active, "activeCount")
end

local function sameEvents(got: { [number]: boolean }, want: { [number]: boolean }, op: string)
	for s, first in want do
		if got[s] ~= first then
			error(`{op}: slot {s} should have been placed (firstTime {first}), got {tostring(got[s])}`)
		end
	end
	for s in got do
		if want[s] == nil then
			error(`{op}: slot {s} was placed unexpectedly`)
		end
	end
end

export type Counts = { placements: number, undos: number, refused: number, steps: number, ops: number }

-- Plays ops random operations on bp, checking the site against the model and
-- a mirror fed through SiteCodec. Checks every slot every fullEvery ops, and
-- the touched slots after every op. Then finishes the site from where it is.
local function play(bp: Blueprint.Blueprint, seed: number, ops: number, fullEvery: number): Counts
	local rng = Rng.new(seed)
	local site = BuildSite.new(bp)
	local mirror = BuildSite.new(bp)
	local m = newModel(bp)
	local count = bp.count
	local counts: Counts = { placements = 0, undos = 0, refused = 0, steps = 0, ops = ops }

	local events: { [number]: boolean } = {}
	local paidTimes = table.create(count, 0)
	site.onPlaced = function(slot, firstTime)
		events[slot] = firstTime
		if firstTime then
			paidTimes[slot] += 1
			if paidTimes[slot] > 1 then
				error(`slot {slot} paid twice`)
			end
		end
	end

	local dirty = {}
	local function sync(): number
		local n = BuildSite.takeDirty(site, dirty)
		SiteCodec.decode(SiteCodec.encodeDelta(site, dirty, n), function(s, p, r)
			BuildSite.setRemote(mirror, s, p, r)
		end)
		return n
	end

	local function find(want: (number) -> boolean): number
		for _ = 1, 30 do
			local s = rng:int(1, count)
			if want(s) then
				return s
			end
		end
		return rng:int(1, count)
	end
	local function workable(s: number): boolean
		local state = mState(m, s)
		return state == State.READY or state == State.SETTING
	end
	local function exposed(s: number): boolean
		return mCanUndo(m, s)
	end
	local function randomCause(): number
		return if rng:next() < 0.6 then Cause.HAND else rng:int(2, 7)
	end

	local touched = {}
	local function touch(s: number)
		table.insert(touched, s)
		for i = bp.dependentStart[s], bp.dependentStart[s + 1] - 1 do
			table.insert(touched, bp.dependentList[i])
		end
	end

	for op = 1, ops do
		table.clear(events)
		table.clear(touched)
		local want: { [number]: boolean } = {}
		local roll = rng:next()
		local name
		if roll < 0.4 then
			name = "place"
			local s = if rng:next() < 0.85 then find(workable) else rng:int(1, count)
			local cause = randomCause()
			local expected = mCanPlace(m, s, cause)
			Test.equal(BuildSite.canPlace(site, s, cause), expected, `canPlace({s})`)
			Test.equal(BuildSite.place(site, s, cause, 1), expected, `place({s})`)
			if expected then
				mFinish(m, s, want)
				counts.placements += 1
			else
				counts.refused += 1
			end
			touch(s)
		elseif roll < 0.55 then
			name = "startSetting"
			local s = if rng:next() < 0.85 then find(workable) else rng:int(1, count)
			local cause = randomCause()
			local rate = rng:range(0.5, 4)
			local expected = mCanPlace(m, s, cause) and m.rate[s] == 0
			Test.equal(BuildSite.startSetting(site, s, rate, cause, 1), expected, `startSetting({s})`)
			if expected then
				m.rate[s] = rate
				counts.placements += 1
			else
				counts.refused += 1
			end
			touch(s)
		elseif roll < 0.75 then
			name = "undo"
			local s = if rng:next() < 0.8 then find(exposed) else rng:int(1, count)
			local speed = if rng:next() < 0.3 then math.huge else rng:range(0.5, 4)
			local expected = mCanUndo(m, s)
			Test.equal(BuildSite.canUndo(site, s), expected, `canUndo({s})`)
			Test.equal(BuildSite.undo(site, s, speed, Cause.BOSS, 0), expected, `undo({s})`)
			if expected then
				mUndo(m, s, speed)
				counts.undos += 1
			else
				counts.refused += 1
			end
			touch(s)
		elseif roll < 0.8 then
			name = "shield"
			local s = rng:int(1, count)
			local r = rng:next()
			if r < 0.5 then
				local shield = if r < 0.35 then Shield.NONE elseif r < 0.45 then Shield.HAND_ONLY else Shield.BLOCKED
				BuildSite.setShield(site, s, shield)
				m.shield[s] = shield
			else
				-- Raise or lower one flag, as boss effects do.
				local flag = if rng:next() < 0.5 then 1 else 2
				local on = rng:next() < 0.4
				BuildSite.flagShield(site, s, flag, on)
				local hand = m.shield[s] == 1 or m.shield[s] == 3
				local blocked = m.shield[s] == 2 or m.shield[s] == 3
				if flag == 1 then
					hand = on
				else
					blocked = on
				end
				m.shield[s] = (if hand then 1 else 0) + (if blocked then 2 else 0)
			end
		else
			name = "step"
			for i = 1, site.activeCount do
				touch(site.active[i])
			end
			local dt = rng:range(0.01, 0.6)
			BuildSite.step(site, dt)
			mStep(m, dt, want)
			counts.steps += 1
		end
		sameEvents(events, want, `op {op} {name}`)

		local n = sync()
		for i = 1, n do
			touch(dirty[i])
		end
		for _, s in touched do
			checkSlot(site, m, s)
			checkMirror(site, mirror, s)
		end
		if op % fullEvery == 0 then
			checkAll(site, m, mirror)
		end
		if op % 1000 == 0 then
			local fresh = BuildSite.new(bp)
			SiteCodec.decode(SiteCodec.encodeSnapshot(site), function(s, p, r)
				BuildSite.setRemote(fresh, s, p, r)
			end)
			checkAll(site, m, fresh)
		end
	end
	checkAll(site, m, mirror)

	-- Rule 3: from wherever play left it, placing READY slots finishes the site.
	for s = 1, count do
		BuildSite.setShield(site, s, Shield.NONE)
		m.shield[s] = Shield.NONE
	end
	local rounds = 0
	while site.placedCount < count do
		rounds += 1
		if rounds > count + 2 then
			error(`the site got stuck at {site.placedCount} of {count}`)
		end
		table.clear(events)
		local want: { [number]: boolean } = {}
		BuildSite.step(site, 1e6)
		mStep(m, 1e6, want)
		for s = 1, count do
			if mState(m, s) == State.READY then
				Test.check(BuildSite.place(site, s, Cause.HAND, 1), `finishing: place({s})`)
				mFinish(m, s, want)
			end
		end
		sameEvents(events, want, `finishing round {rounds}`)
		sync()
	end
	checkAll(site, m, mirror)
	Test.equal(BuildSite.percent(site), 1, "finished")
	local paid = 0
	for s = 1, count do
		paid += paidTimes[s]
	end
	Test.equal(paid, count, "every block paid exactly once")
	return counts
end

local function report(label: string, c: Counts)
	print(
		`        {label}: {c.ops} ops, {c.placements} placements, {c.undos} undos, {c.refused} refused, {c.steps} steps`
	)
end

Test.case("random play on the TestHut keeps every rule, checking every slot after every op", function()
	local hut = Sites.hut()
	for seed = 1, 3 do
		report(`TestHut seed {seed}`, play(hut, seed, 5000, 1))
	end
end)

Test.case("random play on 6,000-slot terrain keeps every rule", function()
	local total = 0
	for seed = 1, 2 do
		local bp = Blueprint.build(Sites.terrain(100 + seed, 24, 20))
		local c = play(bp, seed, 15000, 250)
		report(`terrain seed {seed} ({bp.count} slots)`, c)
		total += c.placements + c.undos
	end
	Test.check(total >= 10000, `at least 10,000 placements and undos, got {total}`)
end)

return nil
