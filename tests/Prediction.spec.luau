local BossConfig = require("../src/shared/BossConfig")
local BuildSite = require("../src/shared/BuildSite")
local Prediction = require("../src/shared/Prediction")
local SiteCodec = require("../src/shared/SiteCodec")
local SiteIndex = require("../src/shared/SiteIndex")
local SiteSession = require("../src/shared/SiteSession")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Cause = BuildSite.Cause

local function stats(): SiteSession.Stats
	return {
		cooldown = 0.15,
		grasp = 6,
		batch = 2,
		setTime = 1,
		chainChance = 0.1,
		chainRadius = 1.5,
		perfectChance = 0,
		perfectReward = 2,
		yield = 1,
		yieldMult = 1,
		crewWidth = 2,
		crewSpeed = 4,
		crewDuration = 4,
		crewCooldown = 20,
	}
end

-- Checks the mirror's own bookkeeping: unmet counts its unplaced supports.
local function checkBookkeeping(mirror: BuildSite.Site)
	local bp = mirror.blueprint
	local placed = 0
	for s = 1, mirror.count do
		local missing = 0
		for i = bp.supportStart[s], bp.supportStart[s + 1] - 1 do
			if not BuildSite.isPlaced(mirror, bp.supportList[i]) then
				missing += 1
			end
		end
		if mirror.unmet[s] ~= missing then
			error(`mirror slot {s}: unmet {mirror.unmet[s]}, {missing} supports unplaced`)
		end
		if BuildSite.isPlaced(mirror, s) then
			placed += 1
		end
	end
	if mirror.placedCount ~= placed then
		error(`mirror placedCount {mirror.placedCount}, {placed} placed`)
	end
end

Test.group("Prediction")

Test.case("a predicted click shows at once and opens the slot above", function()
	local bp = Sites.hut()
	local mirror = BuildSite.new(bp)
	local pred = Prediction.new(mirror)
	local floor = 1
	Test.check(Prediction.predict(pred, floor, 1, 0), "predicted")
	Test.check(BuildSite.isPlaced(mirror, floor), "shows placed")
	Test.check(not Prediction.predict(pred, floor, 2, 0), "can't predict it twice")
	Prediction.answer(pred, 1, false)
	Test.check(not BuildSite.isPlaced(mirror, floor), "a refusal rolls it back")
	Test.equal(pred.count, 0, "nothing pending")
end)

Test.case("rolling back a block rolls back the predictions resting on it", function()
	local bp = Sites.hut()
	local mirror = BuildSite.new(bp)
	local pred = Prediction.new(mirror)
	-- The floor under the wall's corner, then the wall above it.
	local floor, wall = 1, nil
	for i = bp.dependentStart[floor], bp.dependentStart[floor + 1] - 1 do
		wall = bp.dependentList[i]
	end
	Test.check(Prediction.predict(pred, floor, 1, 0), "floor")
	Test.check(Prediction.predict(pred, wall :: number, 2, 0), "wall on the predicted floor")
	Prediction.answer(pred, 2, true)
	Prediction.answer(pred, 1, false)
	Test.check(not BuildSite.isPlaced(mirror, floor), "floor rolled back")
	Test.check(not BuildSite.isPlaced(mirror, wall :: number), "and the wall with it")
	checkBookkeeping(mirror)
end)

Test.case("a stale state waits behind a prediction, a placed one confirms it", function()
	local bp = Sites.hut()
	local mirror = BuildSite.new(bp)
	local pred = Prediction.new(mirror)
	Prediction.predict(pred, 1, 1, 0)
	Prediction.receive(pred, 1, 0, 0)
	Test.check(BuildSite.isPlaced(mirror, 1), "a state from before the click doesn't take the block away")
	Prediction.receive(pred, 1, 1, 0)
	Test.equal(pred.count, 0, "the server's placed state confirms it")
	Prediction.answer(pred, 1, true)
	Test.check(BuildSite.isPlaced(mirror, 1), "a late yes changes nothing")

	Prediction.predict(pred, 2, 2, 0)
	Prediction.receive(pred, 2, 0, 0)
	Prediction.answer(pred, 2, false)
	Test.check(not BuildSite.isPlaced(mirror, 2), "a no restores the server's state")
end)

Test.case("every change to the mirror is reported", function()
	local bp = Sites.hut()
	local mirror = BuildSite.new(bp)
	local pred = Prediction.new(mirror)
	local changed = {}
	pred.onChange = function(slot)
		table.insert(changed, slot)
	end
	Prediction.predict(pred, 1, 1, 0)
	Prediction.answer(pred, 1, false)
	Prediction.receive(pred, 2, 1, 0)
	Test.equal(table.concat(changed, ","), "1,1,2", "predict, roll back, receive")
end)

Test.case("unanswered predictions expire", function()
	local bp = Sites.hut()
	local mirror = BuildSite.new(bp)
	local pred = Prediction.new(mirror)
	Prediction.predict(pred, 1, 1, 0)
	Prediction.expire(pred, 1, 2)
	Test.check(BuildSite.isPlaced(mirror, 1), "still predicted inside the timeout")
	Prediction.expire(pred, 3, 2)
	Test.check(not BuildSite.isPlaced(mirror, 1), "rolled back after it")
end)

Test.case("over a laggy network with rivals and a boss, the mirror ends equal to the server", function()
	for seed = 1, 4 do
		local rng = Rng.new(seed)
		local bp = Sites.hut()
		local session = SiteSession.new(bp, nil, function()
			return rng:next()
		end)
		SiteSession.setBoss(session, BossConfig.Hard)
		SiteSession.join(session, 1, stats())
		SiteSession.join(session, 2, stats())
		local mirror = BuildSite.new(bp)
		SiteCodec.decode(SiteSession.snapshot(session), function(s, p, r)
			BuildSite.setRemote(mirror, s, p, r)
		end)
		local pred = Prediction.new(mirror)
		local index = SiteIndex.build(bp, 8)
		local toServer, toClient = {}, {}
		local nextId, now, dt = 1, 0, 0.05
		local predicted, refused = 0, 0

		local function deliver(final: boolean)
			-- Requests reach the server after their latency, in order.
			local acks = {}
			while #toServer > 0 and (final or toServer[1].at <= now) do
				local req = table.remove(toServer, 1)
				local ok = SiteSession.request(session, 1, req.slot)
				table.insert(acks, { req.id, ok })
			end
			-- The server ticks, then sends its delta and this tick's answers together.
			SiteSession.step(session, dt)
			local delta = SiteSession.takeDelta(session)
			table.insert(toClient, { at = now + rng:range(0.02, 0.25), delta = delta, acks = acks })
			while #toClient > 0 and (final or toClient[1].at <= now) do
				local msg = table.remove(toClient, 1)
				if msg.delta then
					SiteCodec.decode(msg.delta, function(s, p, r)
						Prediction.receive(pred, s, p, r)
					end)
				end
				for _, ack in msg.acks do
					if not ack[2] then
						refused += 1
					end
					Prediction.answer(pred, ack[1], ack[2])
				end
			end
		end

		local found = {}
		for _ = 1, 1500 do
			now += dt
			-- Player 1 clicks the nearest slot its mirror says it can place.
			local px, py, pz = rng:range(0, bp.sizeX), rng:range(1, bp.sizeY), rng:range(0, bp.sizeZ)
			SiteSession.move(session, 1, px, py, pz)
			local n = SiteIndex.nearest(index, px, py, pz, 6, function(s)
				return BuildSite.canPlace(mirror, s, Cause.HAND)
			end, 1, found)
			if n > 0 and Prediction.predict(pred, found[1], nextId, now) then
				predicted += 1
				table.insert(toServer, { at = now + rng:range(0.02, 0.25), slot = found[1], id = nextId })
				nextId += 1
			end
			-- Player 2, unseen by the client, races for slots.
			local rival = rng:int(1, bp.count)
			local rw = session.workers[2]
			rw.x, rw.y, rw.z = bp.x[rival] + 0.5, bp.y[rival] + 1, bp.z[rival] + 0.5
			SiteSession.request(session, 2, rival)
			deliver(false)
			Prediction.expire(pred, now, 5)
			checkBookkeeping(mirror)
		end
		-- Let everything land.
		for _ = 1, 20 do
			deliver(true)
		end
		Test.equal(pred.count, 0, "nothing left pending")
		for s = 1, bp.count do
			Test.equal(BuildSite.state(mirror, s), BuildSite.state(session.site, s), `slot {s}`)
		end
		Test.check(predicted > 300 and refused > 10, `predicted {predicted}, refused {refused}`)
	end
end)

return nil
