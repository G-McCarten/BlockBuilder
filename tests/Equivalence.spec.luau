--[[
	The quick paths choose what the plain ones did.

	The spatial queries, the band's sweep, canPlace and the snapshot's bitset
	were made quicker without changing what they return. Each case here keeps
	the plain version they replaced as its reference, and compares the two on
	many random states of several sites, slot for slot and in order, since
	orders reach the wire and the sim's results.
]]

local Blueprint = require("../src/shared/Blueprint")
local BuildSite = require("../src/shared/BuildSite")
local SiteActions = require("../src/shared/SiteActions")
local SiteCodec = require("../src/shared/SiteCodec")
local SiteIndex = require("../src/shared/SiteIndex")
local Rng = require("./lib/Rng")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

local Cause = BuildSite.Cause
local State = BuildSite.State
local Shield = BuildSite.Shield

-- References: the plain versions ------------------------------------------------

local function plainNearest(index, px, py, pz, radius, accept, maxCount, out): number
	if maxCount < 1 or not (radius >= 0) then
		return 0
	end
	local bp = index.blueprint
	local x, y, z = bp.x, bp.y, bp.z
	local n = index.chunkCells
	local nx, nz = index.nx, index.nz
	local slotStart, slotList = index.slotStart, index.slotList
	local bestDist = {}
	local r2 = radius * radius
	local found = 0
	local cx0 = math.max(0, (px - radius) // n)
	local cx1 = math.min(nx - 1, (px + radius) // n)
	local cy0 = math.max(0, (py - radius) // n)
	local cy1 = math.min(index.ny - 1, (py + radius) // n)
	local cz0 = math.max(0, (pz - radius) // n)
	local cz1 = math.min(nz - 1, (pz + radius) // n)
	for cy = cy0, cy1 do
		for cz = cz0, cz1 do
			for cx = cx0, cx1 do
				local c = 1 + cx + nx * (cz + nz * cy)
				for i = slotStart[c], slotStart[c + 1] - 1 do
					local s = slotList[i]
					local dx, dy, dz = x[s] + 0.5 - px, y[s] + 0.5 - py, z[s] + 0.5 - pz
					local d2 = dx * dx + dy * dy + dz * dz
					local worst = bestDist[found]
					local better = found < maxCount or d2 < worst or (d2 == worst and s < out[found])
					if d2 <= r2 and better and accept(s) then
						local j = if found < maxCount then found + 1 else found
						while j > 1 and (bestDist[j - 1] > d2 or (bestDist[j - 1] == d2 and out[j - 1] > s)) do
							bestDist[j] = bestDist[j - 1]
							out[j] = out[j - 1]
							j -= 1
						end
						bestDist[j] = d2
						out[j] = s
						if found < maxCount then
							found += 1
						end
					end
				end
			end
		end
	end
	return found
end

-- A click, with its batch found by plainNearest and a grasp test in accept.
local function plainHand(site, index, slot, px, py, pz, stats, causer, random, placed): (number, number)
	if not BuildSite.place(site, slot, Cause.HAND, causer) then
		return 0, 0
	end
	placed[1] = slot
	local count = 1
	if stats.batch > 1 then
		local bp = index.blueprint
		local grasp2 = stats.grasp * stats.grasp
		local cx, cy, cz = bp.x[slot] + 0.5, bp.y[slot] + 0.5, bp.z[slot] + 0.5
		local batch = {}
		local n = plainNearest(index, cx, cy, cz, 2 * stats.grasp, function(s)
			if not BuildSite.canPlace(site, s, Cause.BATCH) then
				return false
			end
			local dx, dy, dz = bp.x[s] + 0.5 - px, bp.y[s] + 0.5 - py, bp.z[s] + 0.5 - pz
			return dx * dx + dy * dy + dz * dz <= grasp2
		end, stats.batch - 1, batch)
		for i = 1, n do
			if BuildSite.place(site, batch[i], Cause.BATCH, causer) then
				count += 1
				placed[count] = batch[i]
			end
		end
	end
	local started = 0
	if stats.chainChance > 0 then
		for i = 1, count do
			if random() < stats.chainChance then
				started += SiteActions.chain(site, index, placed[i], stats.chainRadius, stats.setRate, causer)
			end
		end
	end
	return count, started
end

local function plainWithin(index, px, py, pz, radius, accept, out): number
	if not (radius >= 0) then
		return 0
	end
	local bp = index.blueprint
	local x, y, z = bp.x, bp.y, bp.z
	local r2 = radius * radius
	local far = radius + 1e-6
	return SiteIndex.inBox(index, px - radius, py - radius, pz - radius, px + far, py + far, pz + far, function(s)
		local dx, dy, dz = x[s] + 0.5 - px, y[s] + 0.5 - py, z[s] + 0.5 - pz
		return dx * dx + dy * dy + dz * dz <= r2 and accept(s)
	end, out)
end

local function plainSweep(site, index, axis, lo, hi, causer, maxPlace, placed): number
	local bp = index.blueprint
	local x0, x1, z0, z1 = 0, bp.sizeX, 0, bp.sizeZ
	if axis == 1 then
		x0, x1 = lo, hi
	else
		z0, z1 = lo, hi
	end
	local list = {}
	local n = SiteIndex.inBox(index, x0, 0, z0, x1, bp.sizeY, z1, function(s)
		return not BuildSite.isPlaced(site, s)
	end, list)
	for i = n + 1, #list do
		list[i] = nil
	end
	local y = bp.y
	table.sort(list, function(a, b)
		return y[a] < y[b] or (y[a] == y[b] and a < b)
	end)
	local count = 0
	local progressed = true
	while progressed and count < maxPlace do
		progressed = false
		for i = 1, n do
			if count >= maxPlace then
				break
			end
			local s = list[i]
			if BuildSite.place(site, s, Cause.ABILITY, causer) then
				count += 1
				placed[count] = s
				progressed = true
			end
		end
	end
	return count
end

local function plainCanPlace(site, s, cause): boolean
	if not (s >= 1 and s <= site.count and s == s // 1) then
		return false
	end
	local state = BuildSite.state(site, s)
	if state ~= State.READY and state ~= State.SETTING then
		return false
	end
	if site.bound and site.placedCount >= site.boundCap then
		return false
	end
	local shield = site.shield[s]
	if bit32.btest(shield, Shield.BLOCKED) or (bit32.btest(shield, Shield.HAND_ONLY) and cause ~= Cause.HAND) then
		return false
	end
	return true
end

local function plainSnapshot(site): buffer
	local count = site.count
	local progress, rate, active = site.progress, site.rate, site.active
	local bitBytes = (count + 7) // 8
	local n = site.activeCount
	local buf = buffer.create(5 + bitBytes + n * 8)
	buffer.writeu8(buf, 0, SiteCodec.SNAPSHOT)
	buffer.writeu16(buf, 1, count)
	for s = 1, count do
		if rate[s] == 0 and progress[s] >= 1 then
			local i = s - 1
			local at = 3 + i // 8
			buffer.writeu8(buf, at, bit32.bor(buffer.readu8(buf, at), bit32.lshift(1, i % 8)))
		end
	end
	buffer.writeu16(buf, 3 + bitBytes, n)
	local o = 5 + bitBytes
	for i = 1, n do
		local s = active[i]
		buffer.writeu16(buf, o, s)
		buffer.writeu16(buf, o + 2, SiteCodec.quantize(progress[s]))
		buffer.writef32(buf, o + 4, rate[s])
		o += 8
	end
	return buf
end

-- Sites -----------------------------------------------------------------------

-- A small site whose ordering runs every way: ledges that lean on their
-- neighbours, blocks that wait on blocks above them or in other columns, and
-- the odd cycle, so some slots never ready.
local function tangle(seed: number): Blueprint.Blueprint
	local rng = Rng.new(seed)
	local blocks = {}
	local taken = {}
	for z = 0, 9 do
		for x = 0, 11 do
			for y = 0, rng:int(0, 6) do
				taken[Blueprint.key(x, y, z)] = true
				table.insert(blocks, { x = x, y = y, z = z, kind = 1 })
			end
		end
	end
	for _ = 1, 40 do
		local x, y, z = rng:int(0, 11), rng:int(1, 6), rng:int(0, 9)
		if not taken[Blueprint.key(x, y, z)] and taken[Blueprint.key(x + 1, y, z)] then
			taken[Blueprint.key(x, y, z)] = true
			table.insert(blocks, { x = x, y = y, z = z, kind = 1 })
		end
	end
	for _ = 1, #blocks // 6 do
		local a, b = rng:int(1, #blocks), rng:int(1, #blocks)
		if a ~= b then
			local after = blocks[a].after or {}
			table.insert(after, b)
			blocks[a].after = after
		end
	end
	return Blueprint.build({ name = `Tangle{seed}`, palette = { "a" }, blocks = blocks })
end

local function sites(): { Blueprint.Blueprint }
	return { Sites.hut(), Sites.lodge(), Blueprint.build(Sites.terrain(5, 20, 14)), tangle(1), tangle(2) }
end

-- A part-built site with stubborn slots, a peace circle and sometimes a
-- binding, as a boss leaves it. Some keep blocks that set while the binding
-- held them at progress 1, with the binding lifted before they finish.
local function scene(bp: Blueprint.Blueprint, seed: number, share: number): BuildSite.Site
	local rng = Rng.new(seed * 977)
	local site = Sites.partlyBuilt(bp, seed, math.floor(bp.count * share))
	for _ = 1, bp.count // 25 do
		BuildSite.flagShield(
			site,
			rng:int(1, bp.count),
			if rng:next() < 0.5 then Shield.HAND_ONLY else Shield.BLOCKED,
			true
		)
	end
	local roll = rng:next()
	if roll < 0.3 then
		BuildSite.bind(site, true, site.placedCount + rng:int(0, 30))
	elseif roll < 0.6 then
		BuildSite.bind(site, true, site.placedCount)
		BuildSite.step(site, 2)
		BuildSite.bind(site, false)
	end
	return site
end

-- What a client's mirror can hold for a moment: slots setting before the
-- server's word on their supports arrives.
local function mirrorScene(bp: Blueprint.Blueprint, seed: number, share: number): BuildSite.Site
	local rng = Rng.new(seed * 131)
	local site = scene(bp, seed, share)
	for s = 1, bp.count do
		if site.unmet[s] > 0 and rng:next() < 0.1 then
			BuildSite.setRemote(site, s, rng:next(), rng:range(0.5, 2))
		end
	end
	return site
end

local function sameList(a: { number }, b: { number }, n: number, label: string)
	for i = 1, n do
		Test.equal(a[i], b[i], `{label} #{i}`)
	end
end

local function sameSite(a: BuildSite.Site, b: BuildSite.Site, label: string)
	for s = 1, a.count do
		if a.progress[s] ~= b.progress[s] or a.rate[s] ~= b.rate[s] or a.causer[s] ~= b.causer[s] then
			error(`{label}: slot {s} differs`)
		end
	end
	Test.equal(a.placedCount, b.placedCount, `{label}: placed`)
	Test.equal(a.dirtyCount, b.dirtyCount, `{label}: dirty`)
	sameList(a.dirtyList, b.dirtyList, a.dirtyCount, `{label}: dirty order`)
end

-- Cases -------------------------------------------------------------------------

Test.group("Equivalence")

Test.case("slices list every slot once, in its plane and layer, in slot order", function()
	for _, bp in sites() do
		local index = SiteIndex.build(bp, 8)
		for _, axis in { 1, 3 } do
			local slices = SiteIndex.slices(index, axis)
			Test.equal(SiteIndex.slices(index, axis), slices, "made once")
			local across = if axis == 1 then bp.x else bp.z
			local seen = table.create(bp.count, 0)
			for p = 0, slices.planes - 1 do
				for y = 0, slices.layers - 1 do
					local b = p * slices.layers + y + 1
					local last = 0
					for i = slices.start[b], slices.start[b + 1] - 1 do
						local s = slices.list[i]
						seen[s] += 1
						Test.check(across[s] == p and bp.y[s] == y, `{bp.name}: slot {s} filed under ({p}, {y})`)
						Test.check(s > last, `{bp.name}: plane {p} layer {y} out of slot order`)
						last = s
					end
				end
			end
			for s = 1, bp.count do
				Test.equal(seen[s], 1, `{bp.name}: slot {s} listed`)
			end
		end
	end
end)

Test.case("nearest picks what the full scan did, from anywhere and at any range", function()
	local rng = Rng.new(41)
	local out, want = {}, {}
	for k, bp in sites() do
		local index = SiteIndex.build(bp, if k == 3 then 4 else 8)
		for seed = 1, 3 do
			local site = scene(bp, seed + 10 * k, ({ 0.1, 0.5, 0.9 })[seed])
			local accepts = {
				function(s)
					return BuildSite.canPlace(site, s, Cause.HAND)
				end,
				function(s)
					return BuildSite.canUndo(site, s)
				end,
				function(s)
					return s % 7 == 3
				end,
				-- Few and far between, so the answer is often several chunks out.
				function(s)
					return s % 97 == 13
				end,
			}
			local cell = index.chunkCells
			for _ = 1, 160 do
				-- Points on cell centres and corners make ties, points by a chunk's
				-- faces test where rings start, and the rest are anywhere.
				local px, py, pz =
					rng:range(-12, bp.sizeX + 12), rng:range(-4, bp.sizeY + 4), rng:range(-12, bp.sizeZ + 12)
				local pick = rng:next()
				if pick < 0.2 then
					px, py, pz = math.floor(px) + 0.5, math.floor(py) + 0.5, math.floor(pz) + 0.5
				elseif pick < 0.3 then
					px, py, pz = math.floor(px), math.floor(py), math.floor(pz)
				elseif pick < 0.6 then
					local nudges = { -0.001, 0, 0.001, -0.5, 0.5 }
					px = rng:int(0, index.nx) * cell + nudges[rng:int(1, 5)]
					py = rng:int(0, index.ny) * cell + nudges[rng:int(1, 5)]
					pz = rng:int(0, index.nz) * cell + nudges[rng:int(1, 5)]
				end
				local radius = ({ 0, 0.5, 1, 3, 5, 8, 16, 40, 400, math.huge })[rng:int(1, 10)]
				if rng:next() < 0.3 then
					radius = rng:range(0, 25)
				end
				local maxCount = ({ 1, 1, 2, 5, 12, 60, 1000 })[rng:int(1, 7)]
				local accept = accepts[rng:int(1, #accepts)]
				local n = SiteIndex.nearest(index, px, py, pz, radius, accept, maxCount, out)
				local m = plainNearest(index, px, py, pz, radius, accept, maxCount, want)
				Test.equal(n, m, `{bp.name}: how many near ({px}, {py}, {pz}) within {radius}`)
				sameList(out, want, n, `{bp.name}: nearest`)

				-- The same search fenced to a sphere around a second point, against
				-- the full scan with the fence's test in accept.
				local fx, fy, fz = px + rng:range(-6, 6), py + rng:range(-3, 3), pz + rng:range(-6, 6)
				if rng:next() < 0.5 then
					-- On a cell's centre, so whole-number fences pass exactly through others'.
					fx, fy, fz = math.floor(fx) + 0.5, math.floor(fy) + 0.5, math.floor(fz) + 0.5
				end
				local fence = ({ 0, 1, 2, 2.5, 3, 5, 9, math.huge })[rng:int(1, 8)]
				local f2 = fence * fence
				n = SiteIndex.nearestFenced(index, px, py, pz, radius, fx, fy, fz, fence, accept, maxCount, out)
				m = plainNearest(index, px, py, pz, radius, function(s)
					local dx, dy, dz = bp.x[s] + 0.5 - fx, bp.y[s] + 0.5 - fy, bp.z[s] + 0.5 - fz
					return dx * dx + dy * dy + dz * dz <= f2 and accept(s)
				end, maxCount, want)
				Test.equal(n, m, `{bp.name}: how many fenced within {fence} of ({fx}, {fy}, {fz})`)
				sameList(out, want, n, `{bp.name}: fenced nearest`)
			end
		end
	end
end)

Test.case("a click places what it did with its batch found by the full scan", function()
	local rng = Rng.new(53)
	local placed, want = {}, {}
	for k, bp in sites() do
		local index = SiteIndex.build(bp, 8)
		for trial = 1, 25 do
			local seed = 300 * k + trial
			local share = rng:range(0.05, 0.9)
			local site, twin = scene(bp, seed, share), scene(bp, seed, share)
			local stats = {
				grasp = rng:range(1, 8),
				batch = rng:int(1, 9),
				chainChance = if rng:next() < 0.5 then 0 else 0.4,
				chainRadius = rng:range(1, 2.5),
				setRate = 1,
			}
			for _ = 1, 6 do
				local slot = rng:int(1, bp.count)
				local px = bp.x[slot] + rng:range(-stats.grasp, stats.grasp + 1)
				local py = bp.y[slot] + rng:range(-1, 3)
				local pz = bp.z[slot] + rng:range(-stats.grasp, stats.grasp + 1)
				local a, b = Rng.new(seed), Rng.new(seed)
				local n, started = SiteActions.hand(site, index, slot, px, py, pz, stats, 3, function()
					return a:next()
				end, placed)
				local m, wantStarted = plainHand(twin, index, slot, px, py, pz, stats, 3, function()
					return b:next()
				end, want)
				Test.equal(n, m, `{bp.name} trial {trial}: blocks a click placed`)
				Test.equal(started, wantStarted, `{bp.name} trial {trial}: chains started`)
				sameList(placed, want, n, `{bp.name} trial {trial}: click order`)
				sameSite(site, twin, `{bp.name} trial {trial}`)
			end
		end
	end
end)

Test.case("within lists what the box query did, in the same order", function()
	local rng = Rng.new(43)
	local out, want = {}, {}
	for k, bp in sites() do
		local index = SiteIndex.build(bp, if k == 3 then 4 else 8)
		local site = scene(bp, k, 0.5)
		for _ = 1, 200 do
			local px, py, pz = rng:range(-6, bp.sizeX + 6), rng:range(-3, bp.sizeY + 3), rng:range(-6, bp.sizeZ + 6)
			if rng:next() < 0.3 then
				px, py, pz = math.floor(px) + 0.5, math.floor(py) + 0.5, math.floor(pz) + 0.5
			end
			local radius = if rng:next() < 0.2 then ({ 0, 1, 2.5, 50 })[rng:int(1, 4)] else rng:range(0, 12)
			local accept = if rng:next() < 0.5
				then function(s)
					return BuildSite.state(site, s) == State.READY
				end
				else function()
					return true
				end
			local n = SiteIndex.within(index, px, py, pz, radius, accept, out)
			local m = plainWithin(index, px, py, pz, radius, accept, want)
			Test.equal(n, m, `{bp.name}: how many within {radius}`)
			sameList(out, want, n, `{bp.name}: within`)
		end
	end
end)

Test.case("a band places what sorting and retrying its whole box did", function()
	local rng = Rng.new(47)
	local placed, want = {}, {}
	for k, bp in sites() do
		local index = SiteIndex.build(bp, 8)
		for trial = 1, 30 do
			local seed = 100 * k + trial
			local share = rng:next()
			local site, twin = scene(bp, seed, share), scene(bp, seed, share)
			local causer = rng:int(1, 4)
			-- A few sweeps on the same site, as a band moves and dwells.
			for _ = 1, 4 do
				local axis = if rng:next() < 0.5 then 1 else 3
				local size = if axis == 1 then bp.sizeX else bp.sizeZ
				local lo = rng:range(-3, size + 1)
				if rng:next() < 0.3 then
					lo = math.floor(lo) + (if rng:next() < 0.5 then 0 else 0.5)
				end
				local hi = lo + ({ 0, 0.5, 1, 2, 3.5, 5, size + 6 })[rng:int(1, 7)]
				local maxPlace = ({ 0, 1, 1, 2, 3, 0.5, 7, 40, math.huge })[rng:int(1, 9)]
				local n = SiteActions.sweep(site, index, axis, lo, hi, causer, maxPlace, placed)
				local m = plainSweep(twin, index, axis, lo, hi, causer, maxPlace, want)
				Test.equal(n, m, `{bp.name} trial {trial}: placed over [{lo}, {hi}) up to {maxPlace}`)
				sameList(placed, want, n, `{bp.name} trial {trial}: placement order`)
				sameSite(site, twin, `{bp.name} trial {trial}`)
			end
		end
	end
end)

Test.case("canPlace answers as the state and shields say, on a server or a mirror", function()
	for k, bp in sites() do
		for seed = 1, 4 do
			local share = ({ 0.2, 0.6, 1, 0.5 })[seed]
			local site = if seed == 4 then mirrorScene(bp, 50 * k, share) else scene(bp, 50 * k + seed, share)
			for s = 0, bp.count + 1 do
				for _, cause in Cause do
					Test.equal(BuildSite.canPlace(site, s, cause), plainCanPlace(site, s, cause), `{bp.name}: slot {s}`)
				end
			end
			Test.equal(BuildSite.canPlace(site, 1.5, Cause.HAND), false, "not a slot")
		end
	end
end)

Test.case("a snapshot packs the same bytes", function()
	for k, bp in sites() do
		for seed = 1, 3 do
			local site = scene(bp, 70 * k + seed, ({ 0.05, 0.5, 1 })[seed])
			local got, expected = SiteCodec.encodeSnapshot(site), plainSnapshot(site)
			Test.equal(buffer.tostring(got), buffer.tostring(expected), `{bp.name}: snapshot bytes`)
		end
	end
end)

return nil
