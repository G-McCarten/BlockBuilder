--!strict
--[[
	SiteRay: picks the slot a player is aiming at.

	A ray from the camera walks the blueprint cell by cell. It takes the first
	READY or SETTING slot within grasp of the player. A block that is there
	(PLACED or UNDOING) stops it. LOCKED ghosts, empty cells, and workable slots
	beyond the player's grasp let it pass.

	All in cell space (SiteConfig): convert world points with the site's origin
	and BLOCK_STUDS first. The direction needn't be unit length; distances are
	in cells.

	cast() returns the slot taken, or nil, and the distance along the ray where
	the walk ended: the slot's or the stopping block's near face, or maxDistance.
]]

local SiteRay = {}

-- The fields of a Blueprint and a BuildSite this reads.
export type BlueprintLike = {
	x: { number },
	y: { number },
	z: { number },
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	cellSlot: { [number]: number },
}

export type SiteLike = {
	progress: { number },
	rate: { number },
	unmet: { number },
}

local SPAN = 256
local INF = math.huge

-- Where along the ray, from t0 to t1, it is inside [0, size) on one axis.
local function clip(o: number, d: number, size: number, t0: number, t1: number): (number, number)
	if d == 0 then
		if o < 0 or o >= size then
			return 1, 0
		end
		return t0, t1
	end
	local a, b = (0 - o) / d, (size - o) / d
	if a > b then
		a, b = b, a
	end
	return math.max(t0, a), math.min(t1, b)
end

function SiteRay.cast(
	bp: BlueprintLike,
	site: SiteLike,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	maxDistance: number,
	px: number,
	py: number,
	pz: number,
	grasp: number
): (number?, number)
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if not (len > 0) then
		return nil, 0
	end
	dx, dy, dz = dx / len, dy / len, dz / len

	local t0, t1 = 0, maxDistance
	t0, t1 = clip(ox, dx, bp.sizeX, t0, t1)
	t0, t1 = clip(oy, dy, bp.sizeY, t0, t1)
	t0, t1 = clip(oz, dz, bp.sizeZ, t0, t1)
	if t0 > t1 then
		return nil, maxDistance
	end

	-- The cell the ray enters at t0, nudged inside so a face hit counts.
	local function cellOf(o: number, d: number, size: number): number
		local c = math.floor(o + d * t0)
		if d < 0 and o + d * t0 == c then
			c -= 1
		end
		return math.clamp(c, 0, size - 1)
	end
	local cx, cy, cz = cellOf(ox, dx, bp.sizeX), cellOf(oy, dy, bp.sizeY), cellOf(oz, dz, bp.sizeZ)

	local stepX = if dx > 0 then 1 elseif dx < 0 then -1 else 0
	local stepY = if dy > 0 then 1 elseif dy < 0 then -1 else 0
	local stepZ = if dz > 0 then 1 elseif dz < 0 then -1 else 0
	local deltaX = if dx ~= 0 then math.abs(1 / dx) else INF
	local deltaY = if dy ~= 0 then math.abs(1 / dy) else INF
	local deltaZ = if dz ~= 0 then math.abs(1 / dz) else INF
	local nextX = if dx > 0 then (cx + 1 - ox) / dx elseif dx < 0 then (cx - ox) / dx else INF
	local nextY = if dy > 0 then (cy + 1 - oy) / dy elseif dy < 0 then (cy - oy) / dy else INF
	local nextZ = if dz > 0 then (cz + 1 - oz) / dz elseif dz < 0 then (cz - oz) / dz else INF

	local cellSlot = bp.cellSlot
	local progress, rate, unmet = site.progress, site.rate, site.unmet
	local x, y, z = bp.x, bp.y, bp.z
	local grasp2 = grasp * grasp
	local sizeX, sizeY, sizeZ = bp.sizeX, bp.sizeY, bp.sizeZ
	local t = t0

	while true do
		local s = cellSlot[cx + SPAN * (cy + SPAN * cz)]
		if s ~= nil then
			local r = rate[s]
			if r < 0 or (r == 0 and progress[s] >= 1) then
				return nil, t
			elseif unmet[s] == 0 then
				local ex, ey, ez = x[s] + 0.5 - px, y[s] + 0.5 - py, z[s] + 0.5 - pz
				if ex * ex + ey * ey + ez * ez <= grasp2 then
					return s, t
				end
			end
		end

		if nextX <= nextY and nextX <= nextZ then
			t = nextX
			cx += stepX
			nextX += deltaX
		elseif nextY <= nextZ then
			t = nextY
			cy += stepY
			nextY += deltaY
		else
			t = nextZ
			cz += stepZ
			nextZ += deltaZ
		end
		if t > t1 or cx < 0 or cy < 0 or cz < 0 or cx >= sizeX or cy >= sizeY or cz >= sizeZ then
			return nil, maxDistance
		end
	end
end

return SiteRay
