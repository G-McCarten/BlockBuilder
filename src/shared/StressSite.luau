--!strict
--[[
	StressSite: generated sites of 1,000 to 65,535 blocks, for the renderer's
	stress test (formula 4.5): how many blocks a client can draw and still
	hold its frame rate.

	source(count) lays out a district the way the real sites are built, as a
	Blueprint.Source of exactly count blocks. Hollow buildings stand on lots
	14 cells square, with streets between: a stone floor, then storeys of
	floor and wall four cells tall, with glazed windows and a door, then a
	roof, flat behind a parapet or hipped in steps, some with a chimney.
	Every roof waits for the nearest corner of the walls under it to be
	topped out. Every seventh lot holds a tower, and the towers all rise to
	one height, so the site's top layer is their parapets. A lamp post
	stands at each lot's corner. Lots fill outward from the front corner in
	a growing square, so a bigger district grows from a smaller one. The
	last building is cut down to fit, and a stretch of street is paved to
	make up the count.

	It is worked out from the count alone, with no outside randomness, so
	the server and every client build the same blueprint from the same count,
	and only the count crosses the network.

	  plan(value)    what the workspace's StressTest attribute asks for
	  id, parse      a stress site's id, as CurrentSite names it: Stress:<count>
	  name(count)    what the sign and the HUD call it
	  layOrder(bp)   every slot below the top layer, each after its supports,
	                 for the server to lay at once
]]

local StressSite = {}

StressSite.MIN_BLOCKS = 1000
StressSite.MAX_BLOCKS = 65535
-- The ladder's steps, in blocks.
StressSite.LADDER = table.freeze({ 5000, 10000, 15000, 20000, 30000, 40000, 50000, 65535 })
-- Seconds a ladder step holds when StressStepSeconds doesn't say.
StressSite.STEP_SECONDS = 20

export type SourceBlock = {
	x: number,
	y: number,
	z: number,
	kind: string,
	after: { number }?,
}

export type Source = {
	name: string,
	palette: { string },
	blocks: { SourceBlock },
}

-- The fields of a Blueprint layOrder reads.
type BlueprintLike = {
	count: number,
	y: { number },
	sizeY: number,
	supportStart: { number },
	dependentStart: { number },
	dependentList: { number },
}

local PALETTE = { "stone", "timber", "glass", "slate", "thatch", "lantern" }
local PREFIX = "Stress:"
-- Cells on a side of a lot, its streets included.
local LOT = 14
-- Layers in a storey: its floor, then three of wall.
local STOREY = 4
local TOWER_STOREYS = 11
local SEED = 20261105

-- A whole count in MIN_BLOCKS..MAX_BLOCKS.
function StressSite.clamp(count: number): number
	if count ~= count then
		return StressSite.MIN_BLOCKS
	end
	return math.clamp(math.floor(count + 0.5), StressSite.MIN_BLOCKS, StressSite.MAX_BLOCKS)
end

-- The CurrentSite id of the stress site of count blocks.
function StressSite.id(count: number): string
	return PREFIX .. tostring(StressSite.clamp(count))
end

-- The count a stress site's id names, or nil for any other id.
function StressSite.parse(id: any): number?
	if type(id) ~= "string" then
		return nil
	end
	local digits = string.match(id, "^Stress:(%d+)$")
	local count = if digits then tonumber(digits) else nil
	if count and count >= StressSite.MIN_BLOCKS and count <= StressSite.MAX_BLOCKS then
		return count
	end
	return nil
end

-- 65535 as "65,535".
local function thousands(n: number): string
	local text = string.reverse((string.gsub(string.reverse(tostring(math.floor(n))), "(%d%d%d)", "%1,")))
	return if string.sub(text, 1, 1) == "," then string.sub(text, 2) else text
end

function StressSite.name(count: number): string
	return `Stress test {thousands(count)}`
end

-- What a StressTest attribute asks for: the sizes to play, in order, and
-- whether to step through them as a ladder. A number, or a string holding
-- one, plays one site of that size. "Ladder" steps through LADDER, and a
-- list of sizes such as "30000, 35000, 40000" steps through those. Anything
-- else asks for nothing.
function StressSite.plan(value: any): ({ number }?, boolean)
	if type(value) == "number" then
		if value ~= value then
			return nil, false
		end
		return { StressSite.clamp(value) }, false
	end
	if type(value) ~= "string" then
		return nil, false
	end
	if string.lower((string.gsub(value, "%s", ""))) == "ladder" then
		return table.clone(StressSite.LADDER), true
	end
	local sizes = {}
	for word in string.gmatch(value, "[^,%s]+") do
		local n = tonumber(word)
		if n == nil or n ~= n then
			return nil, false
		end
		table.insert(sizes, StressSite.clamp(n))
	end
	if #sizes == 0 then
		return nil, false
	end
	return sizes, #sizes > 1
end

-- How long a ladder step holds, from the StressStepSeconds attribute.
function StressSite.stepSeconds(value: any): number
	if type(value) == "number" and value > 0 and value < math.huge then
		return value
	end
	return StressSite.STEP_SECONDS
end

-- Building -------------------------------------------------------------------

-- Blocks as they're made, and the block in each taken cell.
type Builder = {
	blocks: { SourceBlock },
	taken: { [number]: number },
}

-- A lot's building: its footprint, x0..x1 by z0..z1, and how it's made.
type Plan = {
	lot: number,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	storeys: number,
	hipped: boolean,
	walls: string,
	roof: string,
	chimney: boolean,
}

local function key(x: number, y: number, z: number): number
	return x + 256 * (y + 256 * z)
end

-- Adds a block unless its cell is taken. Returns its index, or the index of
-- the block already there.
local function add(b: Builder, x: number, y: number, z: number, kind: string, after: { number }?): number
	local k = key(x, y, z)
	local existing = b.taken[k]
	if existing then
		return existing
	end
	table.insert(b.blocks, { x = x, y = y, z = z, kind = kind, after = after })
	b.taken[k] = #b.blocks
	return #b.blocks
end

-- The border of the rectangle x0..x1 by z0..z1 on layer y, all of it when
-- it's a cell wide.
local function ring(b: Builder, x0: number, x1: number, z0: number, z1: number, y: number, kind: string)
	for z = z0, z1 do
		for x = x0, x1 do
			if x == x0 or x == x1 or z == z0 or z == z1 then
				add(b, x, y, z, kind)
			end
		end
	end
end

-- Lot n's place in the district, counting from 0. Lots fill outward from the
-- front corner in a growing square, each ring adding a column, then a row.
local function lotAt(n: number): (number, number)
	local r = math.floor(math.sqrt(n))
	while (r + 1) * (r + 1) <= n do
		r += 1
	end
	while r * r > n do
		r -= 1
	end
	local k = n - r * r
	if k < r then
		return r, k
	end
	return k - r, r
end

-- Whole numbers lo..hi from a linear congruential generator, exact in
-- doubles, so every Luau draws the same ones from the same seed.
local function roller(seed: number): (number, number) -> number
	local state = seed % 4294967296
	return function(lo: number, hi: number): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return lo + math.floor(state / 4294967296 * (hi - lo + 1))
	end
end

-- Lot n's building, drawn from roll. Every lot draws the same number of
-- rolls, so lot n's building is the same in a district of any size.
local function planFor(n: number, roll: (number, number) -> number): Plan
	local i, j = lotAt(n)
	local tower = n % 7 == 3
	local w = roll(7, 11)
	local d = roll(7, 11)
	local storeys = roll(5, 9)
	local hipped = roll(0, 1) == 1 and not tower
	local walls = if roll(0, 2) == 0 then "stone" else "timber"
	local roof = if roll(0, 1) == 0 and hipped then "thatch" else "slate"
	local chimney = roll(0, 1) == 0 and hipped
	local shiftX, shiftZ = roll(0, 4), roll(0, 4)
	if tower then
		-- Towers are narrower, and all one height, above every other roof.
		w, d, storeys = 6 + (w - 7) // 2, 6 + (d - 7) // 2, TOWER_STOREYS
	end
	-- Two cells of street in front and to the left, at least one behind and to the right.
	local x0 = i * LOT + 2 + math.min(shiftX, LOT - 3 - w)
	local z0 = j * LOT + 2 + math.min(shiftZ, LOT - 3 - d)
	return {
		lot = n,
		x0 = x0,
		z0 = z0,
		x1 = x0 + w - 1,
		z1 = z0 + d - 1,
		storeys = storeys,
		hipped = hipped,
		walls = walls,
		roof = roof,
		chimney = chimney,
	}
end

-- A lot's blocks, from its plan: the building and the lamp post at its corner.
local function makeLot(p: Plan): Builder
	local b: Builder = { blocks = {}, taken = {} }
	local x0, z0, x1, z1 = p.x0, p.z0, p.x1, p.z1
	-- The door, two cells wide, in the middle of the front wall.
	local doorX = (x0 + x1) // 2

	for k = 0, p.storeys - 1 do
		local floorY = k * STOREY
		for z = z0, z1 do
			for x = x0, x1 do
				add(b, x, floorY, z, if k == 0 then "stone" else "timber")
			end
		end
		for y = floorY + 1, floorY + STOREY - 1 do
			for z = z0, z1 do
				for x = x0, x1 do
					-- The front and back walls run along x, the sides along z.
					local alongX = z == z0 or z == z1
					local alongZ = x == x0 or x == x1
					local door = k == 0 and z == z0 and (x == doorX or x == doorX + 1) and y <= 2
					if (alongX or alongZ) and not door then
						-- Every other cell of the middle row is a window, never a corner.
						local along = if alongX then x - x0 else z - z0
						local window = y == floorY + 2 and not (alongX and alongZ) and along % 2 == 0
						add(b, x, y, z, if window then "glass" elseif k == 0 then "stone" else p.walls)
					end
				end
			end
		end
	end

	-- The roof's floor waits for the nearest corner of the walls to be topped out.
	local roofY = p.storeys * STOREY
	local corner = {
		b.taken[key(x0, roofY - 1, z0)],
		b.taken[key(x1, roofY - 1, z0)],
		b.taken[key(x0, roofY - 1, z1)],
		b.taken[key(x1, roofY - 1, z1)],
	}
	for z = z0, z1 do
		for x = x0, x1 do
			local nearest = (if x - x0 <= x1 - x then 1 else 2) + (if z - z0 <= z1 - z then 0 else 2)
			add(b, x, roofY, z, if p.hipped then "timber" else p.roof, { corner[nearest] })
		end
	end

	if p.hipped then
		-- A chimney first, so it shows through the roof: two cells square,
		-- rising a cell past the ridge.
		local layers = (math.min(x1 - x0, z1 - z0) + 2) // 2
		if p.chimney then
			for y = roofY + 1, roofY + layers + 1 do
				for z = z1 - 2, z1 - 1 do
					for x = x1 - 2, x1 - 1 do
						add(b, x, y, z, "stone")
					end
				end
			end
		end
		-- Two cells thick, each layer a cell in from the one below.
		for k = 0, layers - 1 do
			for inset = k, k + 1 do
				if x0 + inset <= x1 - inset and z0 + inset <= z1 - inset then
					ring(b, x0 + inset, x1 - inset, z0 + inset, z1 - inset, roofY + 1 + k, p.roof)
				end
			end
		end
	else
		ring(b, x0, x1, z0, z1, roofY + 1, "stone")
	end

	-- A lamp post at the lot's front corner.
	local i, j = lotAt(p.lot)
	for y = 0, 2 do
		add(b, i * LOT, y, j * LOT, "timber")
	end
	add(b, i * LOT, 3, j * LOT, "lantern")
	return b
end

-- Moves a lot's blocks onto the site, renumbering what they wait for.
local function append(site: Builder, lot: Builder)
	local offset = #site.blocks
	for _, block in lot.blocks do
		local after = block.after
		if after then
			local moved = table.create(#after)
			for i, s in after do
				moved[i] = s + offset
			end
			block.after = moved
		end
		table.insert(site.blocks, block)
		site.taken[key(block.x, block.y, block.z)] = #site.blocks
	end
end

-- A district of count blocks, clamped to MIN_BLOCKS..MAX_BLOCKS.
function StressSite.source(count: number): Source
	local target = StressSite.clamp(count)
	local site: Builder = { blocks = {}, taken = {} }
	local roll = roller(SEED)
	local lot = 0
	while true do
		local plan = planFor(lot, roll)
		local made = makeLot(plan)
		local room = target - #site.blocks
		-- The last building is cut down to fit: fewer storeys, then a flat roof.
		while #made.blocks > room and (plan.storeys > 1 or plan.hipped) do
			if plan.storeys > 1 then
				plan.storeys -= 1
			else
				plan.hipped, plan.chimney, plan.roof = false, false, "slate"
			end
			made = makeLot(plan)
		end
		if #made.blocks > room then
			break
		end
		append(site, made)
		lot += 1
	end

	-- Then the streets are paved, lot by lot from the first, to the count.
	local n = 0
	while #site.blocks < target do
		local i, j = lotAt(n)
		for z = j * LOT, j * LOT + LOT - 1 do
			for x = i * LOT, i * LOT + LOT - 1 do
				if #site.blocks < target and site.taken[key(x, 0, z)] == nil then
					add(site, x, 0, z, "stone")
				end
			end
		end
		n += 1
	end

	return { name = `Stress{target}`, palette = table.clone(PALETTE), blocks = site.blocks }
end

-- Every slot below the blueprint's top layer, each after all of its
-- supports, so laying them in this order never meets a LOCKED slot. The top
-- layer is left as work to do.
function StressSite.layOrder(bp: BlueprintLike): { number }
	local count, y = bp.count, bp.y
	local top = bp.sizeY - 1
	local unmet = table.create(count, 0)
	local order = table.create(count)
	local tail = 0
	for s = 1, count do
		unmet[s] = bp.supportStart[s + 1] - bp.supportStart[s]
		if unmet[s] == 0 and y[s] < top then
			tail += 1
			order[tail] = s
		end
	end
	local head = 1
	while head <= tail do
		local s = order[head]
		head += 1
		for i = bp.dependentStart[s], bp.dependentStart[s + 1] - 1 do
			local d = bp.dependentList[i]
			unmet[d] -= 1
			if unmet[d] == 0 and y[d] < top then
				tail += 1
				order[tail] = d
			end
		end
	end
	return order
end

return StressSite
