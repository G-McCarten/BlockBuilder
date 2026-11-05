--!strict
--[[
	WorldArc: how the world looks as a site is built, from start to finished.

	A content config (WorldArcConfig) lists keyframes, each a share built in
	0..1 and the look's values there. at() blends the keyframes either side of
	a share. A value is a number, or a colour as { r, g, b } in 0..255; both
	blend linearly. Shares outside the keyframes take the nearest one.
]]

local WorldArc = {}

export type Key = { [string]: any }

local function blend(a: any, b: any, t: number): any
	if type(a) == "number" then
		return a + (b - a) * t
	end
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- The look at share, written into out (a new table if none is given).
function WorldArc.at(keys: { Key }, share: number, out: { [string]: any }?): { [string]: any }
	local result = out or {}
	local first, last = keys[1], keys[#keys]
	local lo, hi, t = first, first, 0
	if share >= last.at then
		lo, hi = last, last
	elseif share > first.at then
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if share >= a.at and share <= b.at then
				lo, hi = a, b
				t = if b.at > a.at then (share - a.at) / (b.at - a.at) else 0
				break
			end
		end
	end
	for name, value in lo do
		if name ~= "at" then
			result[name] = blend(value, hi[name], t)
		end
	end
	return result
end

return WorldArc
