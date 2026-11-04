--!strict
--[[
	SiteCodec: packs a site's state into buffers for the wire.

	Two messages:

	  snapshot  every slot, for a player who joins a site in progress
	  delta     the slots BuildSite.takeDirty() returned since the last send

	Slot indices are u16, which caps a site at 65,535 slots (MAX_SLOTS).
	Progress is quantised to u16 with 0 and 1 kept exact, so placed and empty
	never blur. Rates are f32. Between messages, clients extrapolate progress
	from the rate.

	Layouts, little-endian:

	  snapshot  u8 1, u16 count, ceil(count / 8) bytes of placed bits
	            (slot s is bit (s - 1) % 8 of byte (s - 1) // 8),
	            u16 n, then n entries for the slots whose rate isn't 0
	  delta     u8 2, u16 n, then n entries
	  entry     u16 slot, u16 progress, f32 rate
]]

local SiteCodec = {}

SiteCodec.MAX_SLOTS = 65535
SiteCodec.SNAPSHOT = 1
SiteCodec.DELTA = 2

local ENTRY = 8

-- The fields of a BuildSite this reads.
export type SiteLike = {
	count: number,
	progress: { number },
	rate: { number },
	active: { number },
	activeCount: number,
}

export type Apply = (slot: number, progress: number, rate: number) -> ()

local function quantize(p: number): number
	if p >= 1 then
		return 65535
	elseif p <= 0 then
		return 0
	end
	local q = math.floor(p * 65535 + 0.5)
	if q >= 65535 then
		return 65534
	elseif q < 1 then
		return 1
	end
	return q
end
SiteCodec.quantize = quantize

function SiteCodec.unquantize(q: number): number
	return q / 65535
end

local function writeEntry(buf: buffer, o: number, s: number, p: number, r: number)
	buffer.writeu16(buf, o, s)
	buffer.writeu16(buf, o + 2, quantize(p))
	buffer.writef32(buf, o + 4, r)
end

local function readEntries(buf: buffer, o: number, n: number, apply: Apply)
	for _ = 1, n do
		apply(buffer.readu16(buf, o), buffer.readu16(buf, o + 2) / 65535, buffer.readf32(buf, o + 4))
		o += ENTRY
	end
end

function SiteCodec.encodeDelta(site: SiteLike, slots: { number }, n: number): buffer
	if n > SiteCodec.MAX_SLOTS then
		error(string.format("a delta holds at most %d slots, not %d", SiteCodec.MAX_SLOTS, n))
	end
	local progress, rate = site.progress, site.rate
	local buf = buffer.create(3 + n * ENTRY)
	buffer.writeu8(buf, 0, SiteCodec.DELTA)
	buffer.writeu16(buf, 1, n)
	local o = 3
	for i = 1, n do
		local s = slots[i]
		writeEntry(buf, o, s, progress[s], rate[s])
		o += ENTRY
	end
	return buf
end

function SiteCodec.encodeSnapshot(site: SiteLike): buffer
	local count = site.count
	if count > SiteCodec.MAX_SLOTS then
		error(string.format("a site holds at most %d slots, not %d", SiteCodec.MAX_SLOTS, count))
	end
	local progress, rate, active = site.progress, site.rate, site.active
	local bitBytes = (count + 7) // 8
	local n = site.activeCount
	local buf = buffer.create(5 + bitBytes + n * ENTRY)
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
		writeEntry(buf, o, s, progress[s], rate[s])
		o += ENTRY
	end
	return buf
end

-- Calls apply(slot, progress, rate) for every slot the message carries and
-- returns the message's kind. A snapshot sets every slot of the site.
function SiteCodec.decode(buf: buffer, apply: Apply): number
	local kind = buffer.readu8(buf, 0)
	if kind == SiteCodec.DELTA then
		readEntries(buf, 3, buffer.readu16(buf, 1), apply)
	elseif kind == SiteCodec.SNAPSHOT then
		local count = buffer.readu16(buf, 1)
		local bitBytes = (count + 7) // 8
		for s = 1, count do
			local i = s - 1
			local placed = bit32.btest(buffer.readu8(buf, 3 + i // 8), bit32.lshift(1, i % 8))
			apply(s, if placed then 1 else 0, 0)
		end
		readEntries(buf, 5 + bitBytes, buffer.readu16(buf, 3 + bitBytes), apply)
	else
		error(string.format("unknown site message kind %d", kind))
	end
	return kind
end

return SiteCodec
