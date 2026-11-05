--!strict
--[[
	BlueprintValidator: proves a blueprint can be built before it ships.

	validate(blueprint, options) checks that:

	  - the site has 1 to 65,535 slots, the most a u16 slot index can name
	  - every cell is in 0..255, every kind is in the palette, every facing is 0..3
	  - no two slots share a cell
	  - supports name real slots, never the slot itself and never twice
	  - every slot above the ground rests on the cell beneath it or a connected
	    neighbour, and no ground slot claims a physical support
	  - supports have no cycles. With every slot connected to the ground this
	    means some order places every block, so a site can always be finished
	  - every slot is within base grasp of a cell a player can stand in

	Reach is checked layer by layer. While a layer is worked, the layers below
	it are built, the layers above it aren't, and the layer itself is part
	built. So for a slot on layer L, a stand cell is a cell with headroom above
	it where nothing below layer L stands, resting on the ground or on a
	blueprint block no higher than layer L. Neither the stand cell, its
	headroom, nor its floor may be the slot itself: nobody stands where they are
	placing. A player's reach starts half a cell above the stand cell's centre.
	The check doesn't prove a player can walk to the stand cell; hoist pads lift
	players to the working height for that.

	The report also gives stats: layers, overhangs, extra supports, and depth,
	the longest chain of supports from the ground.
]]

local BlueprintValidator = {}

local SPAN = 256
local MAX_SLOTS = 65535

export type Options = {
	graspCells: number?,
	headroomCells: number?,
	checkReach: boolean?,
	maxErrors: number?,
}

export type Stats = {
	count: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	overhangs: number,
	extraSupports: number,
	depth: number,
	unreachable: number,
}

export type Report = {
	ok: boolean,
	errors: { string },
	errorCount: number,
	stats: Stats,
}

-- The fields of a Blueprint this reads.
type BlueprintLike = {
	name: string,
	palette: { string },
	count: number,
	x: { number },
	y: { number },
	z: { number },
	kind: { number },
	facing: { number },
	physical: { number },
	supportStart: { number },
	supportList: { number },
	dependentStart: { number },
	dependentList: { number },
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	cellSlot: { [number]: number },
}

BlueprintValidator.DEFAULT_GRASP_CELLS = 5
BlueprintValidator.DEFAULT_HEADROOM_CELLS = 2

local function isInt(v: number): boolean
	return v == v // 1
end

function BlueprintValidator.validate(bp: BlueprintLike, options: Options?): Report
	local opts: Options = options or {}
	local grasp = opts.graspCells or BlueprintValidator.DEFAULT_GRASP_CELLS
	local headroom = opts.headroomCells or BlueprintValidator.DEFAULT_HEADROOM_CELLS
	local maxErrors = opts.maxErrors or 20
	local checkReach = opts.checkReach ~= false

	local count = bp.count
	local x, y, z = bp.x, bp.y, bp.z
	local cellSlot = bp.cellSlot
	local supportStart, supportList = bp.supportStart, bp.supportList
	local dependentStart, dependentList = bp.dependentStart, bp.dependentList

	local errors: { string } = {}
	local errorCount = 0
	local function fail(message: string)
		errorCount += 1
		if errorCount <= maxErrors then
			table.insert(errors, message)
		end
	end
	local function failSlot(s: number, message: string)
		fail(string.format("slot %d at (%s, %s, %s): %s", s, tostring(x[s]), tostring(y[s]), tostring(z[s]), message))
	end
	local function lookup(cx: number, cy: number, cz: number): number?
		if cx < 0 or cy < 0 or cz < 0 or cx >= SPAN or cy >= SPAN or cz >= SPAN then
			return nil
		end
		return cellSlot[cx + SPAN * (cy + SPAN * cz)]
	end

	local stats: Stats = {
		count = count,
		sizeX = bp.sizeX,
		sizeY = bp.sizeY,
		sizeZ = bp.sizeZ,
		overhangs = 0,
		extraSupports = 0,
		depth = 0,
		unreachable = 0,
	}

	if count < 1 then
		fail("the blueprint has no slots")
	elseif count > MAX_SLOTS then
		fail(string.format("the blueprint has %d slots, more than the %d a slot index can name", count, MAX_SLOTS))
	end

	-- Cells, kinds, facings and overlaps.
	local cellsOk = true
	local paletteSize = #bp.palette
	for s = 1, count do
		local sx, sy, sz = x[s], y[s], z[s]
		if
			not (
				isInt(sx)
				and isInt(sy)
				and isInt(sz)
				and sx >= 0
				and sy >= 0
				and sz >= 0
				and sx < SPAN
				and sy < SPAN
				and sz < SPAN
			)
		then
			failSlot(s, "cell isn't integers in 0..255")
			cellsOk = false
		else
			local holder = cellSlot[sx + SPAN * (sy + SPAN * sz)]
			if holder ~= s then
				failSlot(s, string.format("overlaps slot %s", tostring(holder)))
			end
		end
		local kind = bp.kind[s]
		if not (isInt(kind) and kind >= 1 and kind <= paletteSize) then
			failSlot(s, string.format("kind %s isn't in the palette of %d", tostring(kind), paletteSize))
		end
		local facing = bp.facing[s]
		if not (isInt(facing) and facing >= 0 and facing <= 3) then
			failSlot(s, string.format("facing %s isn't 0..3", tostring(facing)))
		end
	end

	-- Supports.
	local supportsOk = true
	for s = 1, count do
		local first, last = supportStart[s], supportStart[s + 1] - 1
		local dir = bp.physical[s]
		if y[s] == 0 then
			if dir ~= 0 then
				failSlot(s, "rests on the ground but claims a physical support")
			end
		elseif dir == 0 then
			failSlot(s, "floats: no block beneath it and no connected neighbour")
		elseif dir >= 2 then
			stats.overhangs += 1
		end
		stats.extraSupports += last - first + 1 - (if dir ~= 0 then 1 else 0)
		for i = first, last do
			local t = supportList[i]
			if not (isInt(t) and t >= 1 and t <= count) then
				failSlot(s, string.format("support %s isn't a slot", tostring(t)))
				supportsOk = false
			elseif t == s then
				failSlot(s, "supports itself")
			else
				for j = first, i - 1 do
					if supportList[j] == t then
						failSlot(s, string.format("lists support %d twice", t))
						break
					end
				end
			end
		end
	end

	-- Cycles, by placing every slot whose supports are all placed until none is left.
	if supportsOk and count <= MAX_SLOTS then
		local unmet = table.create(count, 0)
		local depth = table.create(count, 1)
		local queue = table.create(count, 0)
		local head, tail = 1, 0
		for s = 1, count do
			unmet[s] = supportStart[s + 1] - supportStart[s]
			if unmet[s] == 0 then
				tail += 1
				queue[tail] = s
			end
		end
		while head <= tail do
			local s = queue[head]
			head += 1
			if depth[s] > stats.depth then
				stats.depth = depth[s]
			end
			for i = dependentStart[s], dependentStart[s + 1] - 1 do
				local d = dependentList[i]
				if depth[s] + 1 > depth[d] then
					depth[d] = depth[s] + 1
				end
				unmet[d] -= 1
				if unmet[d] == 0 then
					tail += 1
					queue[tail] = d
				end
			end
		end
		if tail < count then
			local stuck = {}
			for s = 1, count do
				if unmet[s] > 0 then
					table.insert(stuck, s)
					if #stuck >= 5 then
						break
					end
				end
			end
			fail(
				string.format(
					"supports form a cycle: %d slots can never be placed, including %s",
					count - tail,
					table.concat(stuck, ", ")
				)
			)
		end
	end

	-- Reach. Offsets from a slot to candidate stand cells, nearest first, so
	-- most slots find one in a few lookups.
	if checkReach and cellsOk and count <= MAX_SLOTS then
		local ox: { number }, oy: { number }, oz: { number } = {}, {}, {}
		local offsets = {}
		local r = math.ceil(grasp) + 1
		for dx = -r, r do
			for dy = -r - 1, r do
				for dz = -r, r do
					local d2 = dx * dx + (dy + 0.5) * (dy + 0.5) + dz * dz
					if d2 <= grasp * grasp then
						table.insert(offsets, { dx, dy, dz, d2 })
					end
				end
			end
		end
		table.sort(offsets, function(a, b)
			return a[4] < b[4]
		end)
		for i, o in offsets do
			ox[i], oy[i], oz[i] = o[1], o[2], o[3]
		end
		local offsetCount = #offsets

		for s = 1, count do
			local px, py, pz = x[s], y[s], z[s]
			local found = false
			for i = 1, offsetCount do
				local sx, sy, sz = px + ox[i], py + oy[i], pz + oz[i]
				if sy >= 0 then
					-- No block below the slot's layer stands in the stand cell
					-- or its headroom, and neither is the slot itself.
					local clear = true
					for h = 0, headroom - 1 do
						local cy = sy + h
						local there = lookup(sx, cy, sz)
						if there == s or (there ~= nil and cy < py) then
							clear = false
							break
						end
					end
					if clear then
						if sy == 0 then
							found = true
							break
						end
						local floor = lookup(sx, sy - 1, sz)
						if floor ~= nil and floor ~= s and sy - 1 <= py then
							found = true
							break
						end
					end
				end
			end
			if not found then
				stats.unreachable += 1
				failSlot(s, string.format("is out of reach: no stand cell within %s cells", tostring(grasp)))
			end
		end
	end

	return {
		ok = errorCount == 0,
		errors = errors,
		errorCount = errorCount,
		stats = stats,
	}
end

return BlueprintValidator
