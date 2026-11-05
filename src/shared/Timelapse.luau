--!strict
--[[
	Timelapse: the end of a run, the build rising again in the order it was
	placed.

	  order   the placed slots sorted by when they were last placed (BuildSite
	          placedAt), earliest first, ties by slot
	  shown   how many of them show after elapsed seconds of a timelapse
	          lasting duration seconds. It eases in and out, so the first
	          blocks and the last land slowly and the middle rushes.
	  encode, decode   the order as a buffer of u16 slots, for the wire
]]

local Timelapse = {}

export type SiteLike = {
	count: number,
	progress: { number },
	rate: { number },
	placedAt: { number },
}

function Timelapse.order(site: SiteLike): { number }
	local list = {}
	for s = 1, site.count do
		if site.rate[s] == 0 and site.progress[s] >= 1 then
			table.insert(list, s)
		end
	end
	local at = site.placedAt
	table.sort(list, function(a, b)
		return at[a] < at[b] or (at[a] == at[b] and a < b)
	end)
	return list
end

function Timelapse.shown(elapsed: number, duration: number, total: number): number
	if elapsed <= 0 then
		return 0
	elseif elapsed >= duration then
		return total
	end
	local t = elapsed / duration
	local eased = t * t * (3 - 2 * t)
	return math.floor(eased * total + 0.5)
end

function Timelapse.encode(order: { number }): buffer
	local buf = buffer.create(#order * 2)
	for i, s in order do
		buffer.writeu16(buf, (i - 1) * 2, s)
	end
	return buf
end

function Timelapse.decode(buf: buffer): { number }
	local n = buffer.len(buf) // 2
	local order = table.create(n, 0)
	for i = 1, n do
		order[i] = buffer.readu16(buf, (i - 1) * 2)
	end
	return order
end

return Timelapse
