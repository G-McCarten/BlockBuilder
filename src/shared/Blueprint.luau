--!strict
--[[
	Blueprint: the fixed plan a site is built from.

	A blueprint decides every block's cell, kind and facing, and the order blocks
	may be placed in. Players choose where to work, never what goes where.

	Slots live in flat arrays indexed by slot (1..count), like a site's runtime
	state, so nothing allocates per block:

	  x[s], y[s], z[s]  integer cell, 0..255 each, y up. y == 0 rests on the ground.
	  kind[s]           index into palette, the site's block types
	  facing[s]         0..3, quarter turns about y
	  physical[s]       where the slot's physical support sits (Blueprint.Dir)

	Supports are the slots that must be placed before a slot can be. They and
	their reverse, dependents, are stored as offset-and-list arrays:

	  supports of s    supportList[supportStart[s] .. supportStart[s + 1] - 1]
	  dependents of s  dependentList[dependentStart[s] .. dependentStart[s + 1] - 1]

	Every slot above the ground has one physical support, listed first: the cell
	beneath it or, for an overhang, a face-adjacent neighbour on the same layer
	that is itself connected to the ground. Authors can add extra ordering on top,
	such as walls before roof. BlueprintValidator proves the supports have no
	cycles, so some order always places every block.

	Authoring: Blueprint.build(source) turns a list of blocks into a blueprint,
	and Blueprint.encode(blueprint) packs it into the compact ASCII string that
	shared/Blueprints/<Site>.luau holds. At runtime Blueprint.load(file) unpacks it.

	Packed layout, little-endian, then base64:
	  header  "BP", u8 version, u16 count
	  slot    u8 x, u8 y, u8 z, u8 kind, u8 flags, then, if flags has the extra
	          bit, u8 n and n u16 extra supports
	  flags   bits 0-1 facing, bits 2-4 physical direction, bit 5 extra
]]

local Blueprint = {}

local SPAN = 256
local VERSION = 1

Blueprint.SPAN = SPAN
Blueprint.VERSION = VERSION
Blueprint.MAX_SLOTS = 65535
Blueprint.MAX_EXTRA = 255

-- Where a slot's physical support sits, relative to the slot.
Blueprint.Dir = table.freeze({
	GROUND = 0,
	BELOW = 1,
	NEG_X = 2,
	POS_X = 3,
	NEG_Z = 4,
	POS_Z = 5,
})

local DIR_DX = { [0] = 0, [1] = 0, [2] = -1, [3] = 1, [4] = 0, [5] = 0 }
local DIR_DY = { [0] = 0, [1] = -1, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
local DIR_DZ = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = -1, [5] = 1 }
Blueprint.DIR_DX = DIR_DX
Blueprint.DIR_DY = DIR_DY
Blueprint.DIR_DZ = DIR_DZ

export type Blueprint = {
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

export type SourceBlock = {
	x: number,
	y: number,
	z: number,
	kind: number | string,
	facing: number?,
	-- Blocks, by their index in Source.blocks, that must be placed before this one.
	after: { number }?,
}

export type Source = {
	name: string,
	palette: { string },
	blocks: { SourceBlock },
}

export type File = {
	name: string,
	palette: { string },
	count: number,
	data: string,
}

local function key(x: number, y: number, z: number): number
	return x + SPAN * (y + SPAN * z)
end
Blueprint.key = key

function Blueprint.slotAt(bp: Blueprint, x: number, y: number, z: number): number?
	if x < 0 or y < 0 or z < 0 or x >= SPAN or y >= SPAN or z >= SPAN then
		return nil
	end
	return bp.cellSlot[key(x, y, z)]
end

-- Base64 ------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD = 61 -- "="
local ENCODE: { number } = {}
local DECODE: { [number]: number } = {}
for i = 1, 64 do
	local c = string.byte(ALPHABET, i)
	ENCODE[i] = c
	DECODE[c] = i - 1
end

function Blueprint.toBase64(buf: buffer): string
	local len = buffer.len(buf)
	local out = buffer.create(((len + 2) // 3) * 4)
	local o = 0
	for i = 0, len - 1, 3 do
		local b0 = buffer.readu8(buf, i)
		local b1 = if i + 1 < len then buffer.readu8(buf, i + 1) else 0
		local b2 = if i + 2 < len then buffer.readu8(buf, i + 2) else 0
		local n = b0 * 65536 + b1 * 256 + b2
		buffer.writeu8(out, o, ENCODE[n // 262144 + 1])
		buffer.writeu8(out, o + 1, ENCODE[(n // 4096) % 64 + 1])
		buffer.writeu8(out, o + 2, if i + 1 < len then ENCODE[(n // 64) % 64 + 1] else PAD)
		buffer.writeu8(out, o + 3, if i + 2 < len then ENCODE[n % 64 + 1] else PAD)
		o += 4
	end
	return buffer.tostring(out)
end

function Blueprint.fromBase64(text: string): buffer
	local src = buffer.fromstring(text)
	local len = buffer.len(src)
	if len % 4 ~= 0 then
		error("blueprint data is not base64: its length isn't a multiple of 4")
	end
	local pad = 0
	if len > 0 and buffer.readu8(src, len - 1) == PAD then
		pad += 1
	end
	if len > 1 and buffer.readu8(src, len - 2) == PAD then
		pad += 1
	end
	local out = buffer.create(len // 4 * 3 - pad)
	local outLen = buffer.len(out)
	local o = 0
	for i = 0, len - 1, 4 do
		local n = 0
		for j = 0, 3 do
			local c = buffer.readu8(src, i + j)
			local v = if c == PAD then 0 else DECODE[c]
			if v == nil then
				error(string.format("blueprint data is not base64: byte %d at %d", c, i + j))
			end
			n = n * 64 + v
		end
		buffer.writeu8(out, o, n // 65536)
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

-- Linking -----------------------------------------------------------------

-- Fills supports (physical first, then extras, without repeats) and dependents.
local function link(bp: Blueprint, extras: { [number]: { number } })
	local count = bp.count
	local supportStart = table.create(count + 1, 0)
	local supportList: { number } = {}
	local dependentCount = table.create(count, 0)
	local n = 0
	for s = 1, count do
		supportStart[s] = n + 1
		local dir = bp.physical[s]
		if dir ~= 0 then
			local support = Blueprint.slotAt(bp, bp.x[s] + DIR_DX[dir], bp.y[s] + DIR_DY[dir], bp.z[s] + DIR_DZ[dir])
			if support == nil then
				error(string.format("slot %d: its physical support cell is empty", s))
			end
			n += 1
			supportList[n] = support
			dependentCount[support] += 1
		end
		local extra = extras[s]
		if extra then
			for _, t in extra do
				if t ~= t // 1 or t < 1 or t > count then
					error(string.format("slot %d: extra support %s isn't a slot", s, tostring(t)))
				end
				local repeated = false
				for i = supportStart[s], n do
					if supportList[i] == t then
						repeated = true
						break
					end
				end
				if not repeated then
					n += 1
					supportList[n] = t
					dependentCount[t] += 1
				end
			end
		end
	end
	supportStart[count + 1] = n + 1

	local dependentStart = table.create(count + 1, 0)
	local at = 1
	for s = 1, count do
		dependentStart[s] = at
		at += dependentCount[s]
	end
	dependentStart[count + 1] = at
	local cursor = table.clone(dependentStart)
	local dependentList = table.create(at - 1, 0)
	for s = 1, count do
		for i = supportStart[s], supportStart[s + 1] - 1 do
			local t = supportList[i]
			dependentList[cursor[t]] = s
			cursor[t] += 1
		end
	end

	bp.supportStart = supportStart
	bp.supportList = supportList
	bp.dependentStart = dependentStart
	bp.dependentList = dependentList
end

local function blank(name: string, palette: { string }, count: number): Blueprint
	return {
		name = name,
		palette = palette,
		count = count,
		x = table.create(count, 0),
		y = table.create(count, 0),
		z = table.create(count, 0),
		kind = table.create(count, 0),
		facing = table.create(count, 0),
		physical = table.create(count, 0),
		supportStart = {},
		supportList = {},
		dependentStart = {},
		dependentList = {},
		sizeX = 0,
		sizeY = 0,
		sizeZ = 0,
		cellSlot = {},
	}
end

-- Records a slot's cell. When two slots share a cell the first keeps it, and
-- BlueprintValidator reports the overlap.
local function place(bp: Blueprint, s: number, x: number, y: number, z: number)
	bp.x[s], bp.y[s], bp.z[s] = x, y, z
	local k = key(x, y, z)
	if bp.cellSlot[k] == nil then
		bp.cellSlot[k] = s
	end
	if x >= bp.sizeX then
		bp.sizeX = x + 1
	end
	if y >= bp.sizeY then
		bp.sizeY = y + 1
	end
	if z >= bp.sizeZ then
		bp.sizeZ = z + 1
	end
end

-- Authoring ---------------------------------------------------------------

local function isCoord(v: number): boolean
	return v == v // 1 and v >= 0 and v < SPAN
end

-- Builds a blueprint from a list of blocks, giving every block its default
-- physical support. Blocks become slots in list order.
function Blueprint.build(source: Source): Blueprint
	local blocks = source.blocks
	local count = #blocks
	local kindIndex: { [string]: number } = {}
	for i, name in source.palette do
		kindIndex[name] = i
	end

	local bp = blank(source.name, source.palette, count)
	local extras: { [number]: { number } } = {}
	local layers: { [number]: { number } } = {}
	for s, block in blocks do
		if not (isCoord(block.x) and isCoord(block.y) and isCoord(block.z)) then
			error(
				string.format(
					"block %d: cell (%s, %s, %s) isn't integers in 0..255",
					s,
					tostring(block.x),
					tostring(block.y),
					tostring(block.z)
				)
			)
		end
		local kind = block.kind
		if type(kind) == "string" then
			local index = kindIndex[kind]
			if index == nil then
				error(string.format("block %d: kind %q isn't in the palette", s, kind))
			end
			bp.kind[s] = index
		else
			bp.kind[s] = kind
		end
		bp.facing[s] = block.facing or 0
		place(bp, s, block.x, block.y, block.z)
		if block.after then
			extras[s] = block.after
		end
		local layer = layers[block.y]
		if layer == nil then
			layer = {}
			layers[block.y] = layer
		end
		table.insert(layer, s)
	end

	-- Layer by layer: a block rests on the cell beneath it, and a block with an
	-- empty cell beneath rests on a neighbour already connected to the ground,
	-- found breadth first so overhangs lean on the nearest connected block.
	local physical = bp.physical
	local connected = table.create(count, false)
	local queue = table.create(count, 0)
	for y = 0, bp.sizeY - 1 do
		local layer = layers[y]
		if layer then
			local head, tail = 1, 0
			for _, s in layer do
				if y == 0 then
					connected[s] = true
					tail += 1
					queue[tail] = s
				elseif Blueprint.slotAt(bp, bp.x[s], y - 1, bp.z[s]) ~= nil then
					physical[s] = Blueprint.Dir.BELOW
					connected[s] = true
					tail += 1
					queue[tail] = s
				end
			end
			while head <= tail do
				local r = queue[head]
				head += 1
				for dir = 2, 5 do
					-- A neighbour n with physical[n] == dir rests on r.
					local n = Blueprint.slotAt(bp, bp.x[r] - DIR_DX[dir], y, bp.z[r] - DIR_DZ[dir])
					if n ~= nil and not connected[n] then
						connected[n] = true
						physical[n] = dir
						tail += 1
						queue[tail] = n
					end
				end
			end
		end
	end

	link(bp, extras)
	return bp
end

-- Packing -----------------------------------------------------------------

function Blueprint.encode(bp: Blueprint): string
	local count = bp.count
	if count > Blueprint.MAX_SLOTS then
		error(string.format("blueprint %s has %d slots, more than %d", bp.name, count, Blueprint.MAX_SLOTS))
	end
	local supportStart, supportList, physical = bp.supportStart, bp.supportList, bp.physical

	local size = 5
	for s = 1, count do
		local extra = supportStart[s + 1] - supportStart[s] - (if physical[s] ~= 0 then 1 else 0)
		if extra > Blueprint.MAX_EXTRA then
			error(string.format("slot %d has %d extra supports, more than %d", s, extra, Blueprint.MAX_EXTRA))
		end
		if bp.kind[s] < 1 or bp.kind[s] > 255 then
			error(string.format("slot %d has kind %d, outside 1..255", s, bp.kind[s]))
		end
		size += 5 + (if extra > 0 then 1 + 2 * extra else 0)
	end

	local buf = buffer.create(size)
	buffer.writeu8(buf, 0, 66) -- B
	buffer.writeu8(buf, 1, 80) -- P
	buffer.writeu8(buf, 2, VERSION)
	buffer.writeu16(buf, 3, count)
	local o = 5
	for s = 1, count do
		local first = supportStart[s] + (if physical[s] ~= 0 then 1 else 0)
		local last = supportStart[s + 1] - 1
		local extra = last - first + 1
		buffer.writeu8(buf, o, bp.x[s])
		buffer.writeu8(buf, o + 1, bp.y[s])
		buffer.writeu8(buf, o + 2, bp.z[s])
		buffer.writeu8(buf, o + 3, bp.kind[s])
		buffer.writeu8(buf, o + 4, bp.facing[s] + physical[s] * 4 + (if extra > 0 then 32 else 0))
		o += 5
		if extra > 0 then
			buffer.writeu8(buf, o, extra)
			o += 1
			for i = first, last do
				buffer.writeu16(buf, o, supportList[i])
				o += 2
			end
		end
	end
	return Blueprint.toBase64(buf)
end

function Blueprint.decode(data: string, name: string, palette: { string }): Blueprint
	local buf = Blueprint.fromBase64(data)
	if buffer.len(buf) < 5 or buffer.readu8(buf, 0) ~= 66 or buffer.readu8(buf, 1) ~= 80 then
		error(string.format("blueprint %s: data isn't a packed blueprint", name))
	end
	local version = buffer.readu8(buf, 2)
	if version ~= VERSION then
		error(string.format("blueprint %s: packed with version %d, this reads %d", name, version, VERSION))
	end
	local count = buffer.readu16(buf, 3)
	local bp = blank(name, palette, count)
	local extras: { [number]: { number } } = {}
	local o = 5
	for s = 1, count do
		place(bp, s, buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2))
		bp.kind[s] = buffer.readu8(buf, o + 3)
		local flags = buffer.readu8(buf, o + 4)
		o += 5
		bp.facing[s] = flags % 4
		bp.physical[s] = (flags // 4) % 8
		if bp.physical[s] > 5 or flags >= 64 then
			error(string.format("blueprint %s: slot %d has unknown flags %d", name, s, flags))
		end
		if flags >= 32 then
			local n = buffer.readu8(buf, o)
			o += 1
			local list = table.create(n, 0)
			for i = 1, n do
				list[i] = buffer.readu16(buf, o)
				o += 2
			end
			extras[s] = list
		end
	end
	link(bp, extras)
	return bp
end

function Blueprint.load(file: File): Blueprint
	local bp = Blueprint.decode(file.data, file.name, file.palette)
	if bp.count ~= file.count then
		error(string.format("blueprint %s: data holds %d slots, the file says %d", file.name, bp.count, file.count))
	end
	return bp
end

return Blueprint
