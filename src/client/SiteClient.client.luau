--[[
	SiteClient: draws the graybox site and handles the click, to playtest the
	verb before the Unharvester fork. SiteServer runs the site, and names the
	one in play in the workspace's CurrentSite attribute; the client loads
	that site's blueprint, and switches when the server moves on.

	The finished build always shows as one faint silhouette, made of the
	boxes CollisionBoxes merges the whole blueprint into. Chunks near the
	camera draw each block as its own pooled Part, which doesn't collide; a few
	invisible merged boxes per near chunk do, rebuilt on a budget as it
	changes. Far chunks draw their standing blocks as a few merged boxes per
	kind, which collide too. A chunk switches with hysteresis, building its
	new form before dropping the old, so nothing pops. A snapshot, as a late
	joiner gets, is drawn over several frames on a budget, nearest chunk
	first. A finished site plays the ending: the build rises again in the
	order it was placed.

	The client keeps a mirror of the site, fed by SiteRemotes.State, with
	Prediction placing the player's own clicks at once. Blocks are pooled
	Parts that drop in near the camera and land in a puff of dust. READY slots
	near the player pulse as ghosts; the slot the player would place is
	outlined, and its ghost shows brighter. The boss carries its name, and a
	faint ring on the surface under it shows how near a player must come to
	shoo it. The world follows WorldArcConfig as the site rises.

	Controls: click or tap to place, hold to keep placing. Q, the gamepad's X
	or the on-screen button calls the crew (the ABILITY) once its skill is
	bought. F, the gamepad's Y or its button swings the POWER_TOOL for players
	who have it. The gamepad's R2 places at the screen centre. The number keys,
	or the shop's buttons, buy skill levels; with auto-aim bought, a click with
	nothing under the cursor lays the nearest workable slot in reach. Step on
	a hoist pad to ride up to the working height. A click or tap on a button
	never places: Roblox marks that input processed, and placing ignores it.

	On a touch screen every button is thumb-sized, the crew and tool buttons
	sit beside Roblox's jump button, and the shop starts folded. A hold
	follows only the finger that started it, so the thumbstick neither moves
	nor ends it. The settings panel turns sounds and hints on or off and sets
	how far ghosts show; the choices last the session, kept as attributes on
	the local player.

	For the renderer's stress test, a site named Stress:<blocks> is built
	here from its size by StressSite, as the server builds it. A readout of
	the frame rate and what's drawn shows while the StressTest attribute is
	set, and F3 shows or hides it. During a stress ladder the camera tours
	each step near and far, and the last step prints a table of the results.

	Luau allows a function 200 locals, the main chunk included, so each
	section keeps its own in a do block and shares only what others call.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Access = require(Shared:WaitForChild("Access"))
local Blueprint = require(Shared:WaitForChild("Blueprint"))
local KindLooks = require(Shared:WaitForChild("KindLooks"))
local BossConfig = require(Shared:WaitForChild("BossConfig"))
local BuildSite = require(Shared:WaitForChild("BuildSite"))
local CollisionBoxes = require(Shared:WaitForChild("CollisionBoxes"))
local HintConfig = require(Shared:WaitForChild("HintConfig"))
local Hints = require(Shared:WaitForChild("Hints"))
local Prediction = require(Shared:WaitForChild("Prediction"))
local SiteCodec = require(Shared:WaitForChild("SiteCodec"))
local SiteConfig = require(Shared:WaitForChild("SiteConfig"))
local SiteIndex = require(Shared:WaitForChild("SiteIndex"))
local SiteList = require(Shared:WaitForChild("SiteList"))
local SiteRay = require(Shared:WaitForChild("SiteRay"))
local SkillTuning = require(Shared:WaitForChild("SkillTuning"))
local StressSite = require(Shared:WaitForChild("StressSite"))
local Theme = require(Shared:WaitForChild("Theme"))
local Timelapse = require(Shared:WaitForChild("Timelapse"))
local WorldArc = require(Shared:WaitForChild("WorldArc"))
local WorldArcConfig = require(Shared:WaitForChild("WorldArcConfig"))

local remotes = ReplicatedStorage:WaitForChild("SiteRemotes")
local PlaceRemote = remotes:WaitForChild("Place")
local ReadyRemote = remotes:WaitForChild("Ready")
local AbilityRemote = remotes:WaitForChild("Ability")
local BuyRemote = remotes:WaitForChild("Buy")
local ToolRemote = remotes:WaitForChild("Tool")
local StateRemote = remotes:WaitForChild("State")
local BossRemote = remotes:WaitForChild("Boss")
local EventRemote = remotes:WaitForChild("Event")
local StressRemote = remotes:WaitForChild("Stress")

while workspace:GetAttribute("SiteOrigin") == nil do
	task.wait()
end
local ORIGIN: Vector3 = workspace:GetAttribute("SiteOrigin")
local STUDS = SiteConfig.BLOCK_STUDS
local HEADROOM = SiteConfig.HEADROOM_CELLS
local State = BuildSite.State

-- The site in play, which the server names in the workspace's CurrentSite
-- attribute. A snapshot for another site switches to it.
local blueprints = Shared:WaitForChild("Blueprints")

-- A site's blueprint by its id: a stamped one, or a stress site's, built
-- here from the size its id names, as the server builds it.
local function loadBlueprint(id: string): Blueprint.Blueprint
	local count = StressSite.parse(id)
	if count then
		return Blueprint.build(StressSite.source(count))
	end
	return Blueprint.load(require(blueprints:WaitForChild(id)))
end

local siteId = workspace:GetAttribute("CurrentSite") or SiteList[1].id
local bp = loadBlueprint(siteId)
local index = SiteIndex.build(bp, SiteConfig.CHUNK_CELLS)
local found = {}

local function siteName(id: string): string
	local count = StressSite.parse(id)
	if count then
		return StressSite.name(count)
	end
	for _, entry in SiteList do
		if entry.id == id then
			return entry.name
		end
	end
	return id
end

local measureChunks, chunkDistance
do
	-- Each chunk's centre in world space, so distance checks make no Vector3.
	local chunkX: { number }, chunkY: { number }, chunkZ: { number } = {}, {}, {}

	function measureChunks()
		for c = 1, index.chunkCount do
			local x0, y0, z0, x1, y1, z1 = SiteIndex.bounds(index, c)
			chunkX[c] = ORIGIN.X + (x0 + x1) * STUDS / 2
			chunkY[c] = ORIGIN.Y + (y0 + y1) * STUDS / 2
			chunkZ[c] = ORIGIN.Z + (z0 + z1) * STUDS / 2
		end
	end

	function chunkDistance(c: number, from: Vector3): number
		local dx, dy, dz = chunkX[c] - from.X, chunkY[c] - from.Y, chunkZ[c] - from.Z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
end
measureChunks()

-- Settings ------------------------------------------------------------------

-- The player's choices, kept for the session as attributes on the local
-- player, which stay on this client. Every system reads this table.
local GHOST_RADII = { Small = 8, Medium = 14, Large = 20 }
local settings: { [string]: any } = { Sounds = true, Hints = true, GhostRadius = "Medium" }
for name, default in settings do
	local saved = player:GetAttribute(`Setting{name}`)
	if typeof(saved) == typeof(default) and (name ~= "GhostRadius" or GHOST_RADII[saved] ~= nil) then
		settings[name] = saved
	end
end

local function setSetting(name: string, value: any)
	settings[name] = value
	player:SetAttribute(`Setting{name}`, value)
end

-- The device the player last used, so hints name its buttons.
local device: Hints.Device = if UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	then "touch"
	else "mouse"

-- Looks ---------------------------------------------------------------------

-- Each kind's colour and material, from KindLooks.
local KIND_LOOK = {}
for kind, look in KindLooks do
	KIND_LOOK[kind] =
		{ Color3.fromRGB(look.color[1], look.color[2], look.color[3]), (Enum.Material :: any)[look.material] }
end
local FALLBACK_LOOK = { Color3.fromRGB(180, 180, 190), Enum.Material.SmoothPlastic }
local GHOST_COLOR = Color3.fromRGB(170, 215, 255)
local DROP_DISTANCE = 70
local MAX_DROPS_PER_FRAME = 24
-- A chunk draws its blocks one by one inside NEAR_STUDS of the camera, and
-- merged beyond FAR_STUDS; between, it keeps what it has.
local NEAR_STUDS = 90
local FAR_STUDS = 110
local MERGES_PER_FRAME = 2
local COLLISION_REBUILDS_PER_FRAME = 4
-- A snapshot's drawing each frame: a block costs one, a far chunk's merge its slots.
local SNAPSHOT_WORK_PER_FRAME = 400

local function cellPosition(s: number): Vector3
	return ORIGIN + Vector3.new(bp.x[s] + 0.5, bp.y[s] + 0.5, bp.z[s] + 0.5) * STUDS
end

local function cellCFrame(s: number): CFrame
	return CFrame.new(cellPosition(s)) * CFrame.Angles(0, bp.facing[s] * math.pi / 2, 0)
end

local function toCells(p: Vector3): (number, number, number)
	local c = (p - ORIGIN) / STUDS
	return c.X, c.Y, c.Z
end

-- The silhouette ------------------------------------------------------------

local TIMELAPSE_SECONDS = 10

local silhouette: Folder? = nil

local function buildSilhouette()
	if silhouette then
		silhouette:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SiteSilhouette"
	local everyBlock = { progress = table.create(bp.count, 1), rate = table.create(bp.count, 0) }
	local out = {}
	for c = 1, index.chunkCount do
		local n = CollisionBoxes.build(index, everyBlock, c, out)
		for b = 0, n - 1 do
			local o = b * 6
			local x0, y0, z0, x1, y1, z1 = out[o + 1], out[o + 2], out[o + 3], out[o + 4], out[o + 5], out[o + 6]
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = GHOST_COLOR
			part.Transparency = 0.93
			-- A hair smaller than its cells, so it hides inside blocks once they stand.
			part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0) * STUDS - Vector3.one * 0.1
			part.CFrame = CFrame.new(ORIGIN + Vector3.new(x0 + x1, y0 + y1, z0 + z1) * (STUDS / 2))
			part.Parent = folder
		end
	end
	folder.Parent = workspace
	silhouette = folder
end
buildSilhouette()

-- Dust ----------------------------------------------------------------------

local puff, stepDust
do
	-- Landings puff dust from a small pool of emitters, a few a frame. Each
	-- emitter sits in a flat invisible part the size of a block's footprint
	-- and only bursts. An emitter is placed one frame and burst the next, so
	-- the burst comes from where it now stands rather than where it last
	-- rendered; with the pool twice the budget, none moves before it bursts.
	local DUST_POOL = 6
	local MAX_DUST_PER_FRAME = 3
	local DUST_PARTICLES = 7

	local dustFolder = Instance.new("Folder")
	dustFolder.Name = "SiteDust"
	dustFolder.Parent = workspace
	local dustParts: { BasePart } = {}
	local dustEmitters: { ParticleEmitter } = {}
	for i = 1, DUST_POOL do
		local part = Instance.new("Part")
		part.Name = `Dust{i}`
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(STUDS, 0.2, STUDS)
		part.Parent = dustFolder
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.35, 0.6)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(80, 80)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Drag = 5
		emitter.Acceleration = Vector3.new(0, -3, 0)
		emitter.Size = NumberSequence.new(0.5, 1.1)
		emitter.Transparency = NumberSequence.new(0.35, 1)
		emitter.Color = ColorSequence.new(Color3.fromRGB(236, 240, 246))
		emitter.LightEmission = 0.1
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-60, 60)
		emitter.Parent = part
		dustParts[i] = part
		dustEmitters[i] = emitter
	end
	local dustNext = 1
	-- Where blocks landed since the last frame, up to the budget, and the
	-- emitters placed last frame for the ones before.
	local landed: { CFrame } = {}
	local placed: { number } = {}

	-- A puff at the foot of slot s's cell, if this frame's budget allows.
	function puff(s: number)
		if #landed < MAX_DUST_PER_FRAME then
			table.insert(landed, CFrame.new(cellPosition(s) - Vector3.new(0, STUDS * 0.45, 0)))
		end
	end

	-- Once a frame, before drawing: bursts last frame's emitters, then places
	-- emitters for the landings since.
	function stepDust()
		for _, i in placed do
			dustEmitters[i]:Emit(DUST_PARTICLES)
		end
		table.clear(placed)
		for _, at in landed do
			local i = dustNext
			dustNext = dustNext % DUST_POOL + 1
			dustParts[i].CFrame = at
			table.insert(placed, i)
		end
		table.clear(landed)
	end
end

-- Blocks -------------------------------------------------------------------

local blockFolder = Instance.new("Folder")
blockFolder.Name = "SiteBlocks"
blockFolder.Parent = workspace

local blocks: { [number]: BasePart } = {}
local pool: { BasePart } = {}
local tweens: { [BasePart]: Tween } = {}
local settingFrom: { [number]: { number } } = {}
local dropsThisFrame = 0

local function takePart(): BasePart
	local part = table.remove(pool)
	if part == nil then
		part = Instance.new("Part")
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.Size = Vector3.one * STUDS
	return part
end

local function givePart(part: BasePart)
	local tween = tweens[part]
	if tween then
		tween:Cancel()
		tweens[part] = nil
	end
	part.Parent = nil
	table.insert(pool, part)
end

-- While a chunk switches between near and far, its blocks appear without dropping.
local quiet = false

-- Drops a block into slot s's cell with a small squash, near the camera and
-- within the frame's budget; with dust, it lands in a puff.
local function dropIn(part: BasePart, s: number, dust: boolean?)
	local final = cellCFrame(s)
	local camera = workspace.CurrentCamera
	if
		quiet
		or dropsThisFrame >= MAX_DROPS_PER_FRAME
		or (camera.CFrame.Position - final.Position).Magnitude > DROP_DISTANCE
	then
		part.CFrame = final
		return
	end
	dropsThisFrame += 1
	part.CFrame = final + Vector3.new(0, STUDS * 0.6, 0)
	part.Size = Vector3.new(STUDS * 0.9, STUDS * 1.12, STUDS * 0.9)
	local fall = TweenService:Create(
		part,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = final, Size = Vector3.new(STUDS * 1.06, STUDS * 0.9, STUDS * 1.06) }
	)
	tweens[part] = fall
	fall.Completed:Connect(function(status)
		if status ~= Enum.PlaybackState.Completed or tweens[part] ~= fall then
			return
		end
		if dust then
			puff(s)
		end
		local settle =
			TweenService:Create(part, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Size = Vector3.one * STUDS })
		tweens[part] = settle
		settle:Play()
	end)
	fall:Play()
end

local mirror, pred
local redrawQueue: { [number]: boolean } = {}

local function markRedraw(s: number)
	redrawQueue[s] = true
end

local chunkFar: { [number]: boolean } = {}
local farDirty: { [number]: boolean } = {}
local collisionDirty: { [number]: boolean } = {}

local function redraw(s: number)
	local c = index.chunkOf[s]
	collisionDirty[c] = true
	if chunkFar[c] then
		-- Far: the chunk's merged boxes will be rebuilt, on a budget.
		farDirty[c] = true
		local part = blocks[s]
		if part then
			settingFrom[s] = nil
			blocks[s] = nil
			givePart(part)
		end
		return
	end
	local state = BuildSite.state(mirror, s)
	local standing = state == State.PLACED or state == State.UNDOING
	local setting = state == State.SETTING
	local part = blocks[s]
	if standing or setting then
		local fresh = part == nil
		if fresh then
			part = takePart()
			local look = KIND_LOOK[bp.palette[bp.kind[s]]] or FALLBACK_LOOK
			part.Color = look[1]
			part.Material = look[2]
			part.CastShadow = true
			part.CanQuery = false
			part.CanTouch = false
			blocks[s] = part
		end
		-- The chunk's collision boxes do the colliding.
		part.CanCollide = false
		if setting then
			settingFrom[s] = { mirror.progress[s], mirror.rate[s], os.clock() }
			part.Transparency = 0.7
			part.CFrame = cellCFrame(s)
		else
			settingFrom[s] = nil
			part.Transparency = if state == State.UNDOING then 0.4 else 0
			if fresh then
				dropIn(part, s, true)
			elseif tweens[part] == nil then
				part.CFrame = cellCFrame(s)
			end
		end
		part.Parent = blockFolder
	elseif part then
		settingFrom[s] = nil
		blocks[s] = nil
		givePart(part)
	end
end

-- Far chunks ----------------------------------------------------------------

local farFolder = Instance.new("Folder")
farFolder.Name = "SiteFar"
farFolder.Parent = workspace

local collisionFolder = Instance.new("Folder")
collisionFolder.Name = "SiteCollision"
collisionFolder.Parent = workspace
local collisionParts: { [number]: { BasePart } } = {}
-- Scratch for CollisionBoxes.build, which writes six numbers a box.
local boxes: { number } = {}

local function clearCollision(c: number)
	local list = collisionParts[c]
	if list then
		for _, part in list do
			part:Destroy()
		end
		collisionParts[c] = nil
	end
	collisionDirty[c] = nil
end

-- A near chunk's invisible collision: its standing blocks merged into boxes.
local function buildCollision(c: number)
	clearCollision(c)
	local list = {}
	local n = CollisionBoxes.build(index, mirror, c, boxes)
	for b = 0, n - 1 do
		local o = b * 6
		local x0, y0, z0, x1, y1, z1 =
			boxes[o + 1], boxes[o + 2], boxes[o + 3], boxes[o + 4], boxes[o + 5], boxes[o + 6]
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0) * STUDS
		part.CFrame = CFrame.new(ORIGIN + Vector3.new(x0 + x1, y0 + y1, z0 + z1) * (STUDS / 2))
		part.Parent = collisionFolder
		table.insert(list, part)
	end
	collisionParts[c] = list
end
local farParts: { [number]: { BasePart } } = {}
local zeroRate = setmetatable({}, {
	__index = function()
		return 0
	end,
})

local function clearFar(c: number)
	local list = farParts[c]
	if list then
		for _, part in list do
			part:Destroy()
		end
		farParts[c] = nil
	end
end

-- The chunk's standing blocks as merged boxes, one set per kind.
local function buildFar(c: number)
	clearFar(c)
	local byKind: { [number]: { [number]: number } } = {}
	for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
		local s = index.slotList[i]
		local state = BuildSite.state(mirror, s)
		if state == State.PLACED or state == State.UNDOING then
			local kind = bp.kind[s]
			local set = byKind[kind]
			if set == nil then
				set = setmetatable({}, getmetatable(zeroRate))
				byKind[kind] = set
			end
			set[s] = 1
		end
	end
	local list = {}
	for kind, progress in byKind do
		local look = KIND_LOOK[bp.palette[kind]] or FALLBACK_LOOK
		local n = CollisionBoxes.build(index, { progress = progress, rate = zeroRate }, c, boxes)
		for b = 0, n - 1 do
			local o = b * 6
			local x0, y0, z0, x1, y1, z1 =
				boxes[o + 1], boxes[o + 2], boxes[o + 3], boxes[o + 4], boxes[o + 5], boxes[o + 6]
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanQuery = false
			part.CanTouch = false
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Color = look[1]
			part.Material = look[2]
			part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0) * STUDS
			part.CFrame = CFrame.new(ORIGIN + Vector3.new(x0 + x1, y0 + y1, z0 + z1) * (STUDS / 2))
			part.Parent = farFolder
			table.insert(list, part)
		end
	end
	farParts[c] = list
	farDirty[c] = nil
end

-- Switches chunk c to near (individual blocks) or far (merged), building the
-- new form before dropping the old.
local function setFar(c: number, far: boolean)
	if (chunkFar[c] == true) == far then
		return
	end
	quiet = true
	if far then
		buildFar(c)
		clearCollision(c)
		chunkFar[c] = true
		for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
			local s = index.slotList[i]
			redraw(s)
			-- Drawn as part of the boxes just built; nothing left to redraw.
			redrawQueue[s] = nil
		end
		farDirty[c] = nil
	else
		chunkFar[c] = nil
		for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
			redraw(index.slotList[i])
		end
		buildCollision(c)
		clearFar(c)
		farDirty[c] = nil
	end
	quiet = false
end

-- Puts each chunk near or far by its distance from the camera.
local function updateChunkModes()
	local camera = workspace.CurrentCamera.CFrame.Position
	for c = 1, index.chunkCount do
		local d = chunkDistance(c, camera)
		if d > FAR_STUDS then
			setFar(c, true)
		elseif d < NEAR_STUDS then
			setFar(c, false)
		end
	end
end

-- Snapshots -----------------------------------------------------------------

local queueSnapshot, drawBacklog, clearBacklog, backlogLeft
do
	-- A snapshot's drawing waits here, nearest chunk first: a slot to draw on
	-- its own, or minus a far chunk to merge. Each frame spends
	-- SNAPSHOT_WORK_PER_FRAME on it, so joining a big site never draws it all
	-- in one frame.
	local backlog: { number } = {}
	local backlogAt = 1
	local chunkOrder: { number } = {}
	local chunkDist: { number } = {}

	local function nearerChunk(a: number, b: number): boolean
		return chunkDist[a] < chunkDist[b]
	end

	-- Queues a fresh snapshot's drawing. Far chunks are far from the start, so
	-- joining a built site doesn't first draw every block one by one.
	function queueSnapshot()
		clearBacklog()
		table.clear(chunkOrder)
		local camera = workspace.CurrentCamera.CFrame.Position
		for c = 1, index.chunkCount do
			chunkOrder[c] = c
			chunkDist[c] = chunkDistance(c, camera)
		end
		table.sort(chunkOrder, nearerChunk)
		for _, c in chunkOrder do
			local far = chunkDist[c] > FAR_STUDS
			local merged = false
			for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
				local s = index.slotList[i]
				local state = BuildSite.state(mirror, s)
				if far then
					merged = merged or state == State.PLACED or state == State.UNDOING
				elseif state ~= State.LOCKED and state ~= State.READY then
					table.insert(backlog, s)
				end
			end
			if far then
				chunkFar[c] = true
				if merged then
					table.insert(backlog, -c)
				end
			end
		end
	end

	-- Draws the backlog's next entries, up to budget work.
	function drawBacklog(budget: number)
		if backlogAt > #backlog then
			return
		end
		local work = 0
		quiet = true
		while backlogAt <= #backlog and work < budget do
			local entry = backlog[backlogAt]
			backlogAt += 1
			if entry > 0 then
				-- A chunk gone far since shows the slot in its boxes.
				if not chunkFar[index.chunkOf[entry]] then
					redraw(entry)
				end
				work += 1
			else
				local c = -entry
				-- A chunk gone near since, or merged already for a change, is drawn.
				if chunkFar[c] and farParts[c] == nil then
					buildFar(c)
				end
				work += index.slotStart[c + 1] - index.slotStart[c]
			end
		end
		quiet = false
		if backlogAt > #backlog then
			clearBacklog()
		end
	end

	function clearBacklog()
		table.clear(backlog)
		backlogAt = 1
	end

	-- How many entries of the last snapshot are still to draw.
	function backlogLeft(): number
		return #backlog - backlogAt + 1
	end
end

-- Ghosts and aim ------------------------------------------------------------

local ghostClock = 0
local refreshGhosts, shadeGhosts, clearGhosts
do
	-- The aimed slot's ghost is warmer and more solid, so the next block reads at a glance.
	local AIMED_GHOST_COLOR = Color3.fromRGB(255, 236, 170)
	local AIMED_GHOST_TRANSPARENCY = 0.45

	local ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "SiteGhosts"
	ghostFolder.Parent = workspace
	local ghosts: { [number]: BasePart } = {}
	local ghostPool: { BasePart } = {}
	-- The refresh that last wanted each slot's ghost; a ghost the latest didn't
	-- want goes back to the pool. No table is made per refresh.
	local ghostSeen: { [number]: number } = {}
	local ghostRound = 0
	-- The ghost shown lit, as the aimed slot's.
	local litGhost: BasePart? = nil

	local function ghostPart(): BasePart
		local part = table.remove(ghostPool)
		if part == nil then
			part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = GHOST_COLOR
			part.Size = Vector3.one * (STUDS * 0.94)
		end
		return part
	end

	local function dropGhost(s: number, part: BasePart)
		part.Parent = nil
		table.insert(ghostPool, part)
		ghosts[s] = nil
	end

	local function readyForGhost(s: number): boolean
		return BuildSite.state(mirror, s) == State.READY
	end

	-- Shows a ghost on every READY slot within the chosen radius of (x, y, z),
	-- and returns the rest to the pool.
	function refreshGhosts(x: number, y: number, z: number)
		ghostRound += 1
		local n = SiteIndex.within(index, x, y, z, GHOST_RADII[settings.GhostRadius], readyForGhost, found)
		for i = 1, n do
			ghostSeen[found[i]] = ghostRound
		end
		for s, part in ghosts do
			if ghostSeen[s] ~= ghostRound then
				dropGhost(s, part)
			end
		end
		for i = 1, n do
			local s = found[i]
			if ghosts[s] == nil then
				local part = ghostPart()
				part.CFrame = cellCFrame(s)
				part.Parent = ghostFolder
				ghosts[s] = part
			end
		end
	end

	-- Lights the aimed slot's ghost and pulses the others.
	function shadeGhosts(aimed: number?, now: number)
		local lit = if aimed then ghosts[aimed] else nil
		if lit ~= litGhost then
			if litGhost then
				litGhost.Color = GHOST_COLOR
			end
			if lit then
				lit.Color = AIMED_GHOST_COLOR
			end
			litGhost = lit
		end
		local pulse = 0.8 + 0.08 * math.sin(now * 5)
		for _, part in ghosts do
			part.Transparency = if part == lit then AIMED_GHOST_TRANSPARENCY else pulse
		end
	end

	function clearGhosts()
		for s, part in ghosts do
			dropGhost(s, part)
		end
		if litGhost then
			litGhost.Color = GHOST_COLOR
			litGhost = nil
		end
		table.clear(ghostSeen)
	end
end

local showAim
do
	local aimPart = Instance.new("Part")
	aimPart.Name = "SiteAim"
	aimPart.Anchored = true
	aimPart.CanCollide = false
	aimPart.CanQuery = false
	aimPart.CanTouch = false
	aimPart.Transparency = 1
	aimPart.Size = Vector3.one * (STUDS + 0.1)
	aimPart.Parent = workspace
	local aimBox = Instance.new("SelectionBox")
	aimBox.Adornee = aimPart
	aimBox.LineThickness = 0.06
	aimBox.Color3 = Color3.fromRGB(255, 220, 130)
	aimBox.SurfaceColor3 = Color3.fromRGB(255, 220, 130)
	aimBox.SurfaceTransparency = 0.8
	aimBox.Visible = false
	aimBox.Parent = aimPart
	local aimShown: number? = nil

	-- Outlines slot, or nothing; the outline moves only when the aim does.
	function showAim(slot: number?)
		if slot == aimShown then
			return
		end
		aimShown = slot
		if slot then
			aimPart.CFrame = cellCFrame(slot)
		end
		aimBox.Visible = slot ~= nil
	end
end

local function clearAll()
	for s, part in blocks do
		givePart(part)
		blocks[s] = nil
	end
	clearGhosts()
	showAim(nil)
	table.clear(settingFrom)
	table.clear(redrawQueue)
	clearBacklog()
	for c in farParts do
		clearFar(c)
	end
	for c in collisionParts do
		clearCollision(c)
	end
	table.clear(chunkFar)
	table.clear(farDirty)
	table.clear(collisionDirty)
end

local timelapse: { order: { number }, started: number, shown: number }? = nil

local function resetMirror()
	timelapse = nil
	clearAll()
	mirror = BuildSite.new(bp)
	pred = Prediction.new(mirror)
	pred.onChange = function(s: number)
		markRedraw(s)
	end
end
resetMirror()

-- The local character ----------------------------------------------------

local function rootCell(): (number?, number?, number?, BasePart?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil, nil, nil
	end
	local x, y, z = toCells(root.Position)
	return x, y, z, root
end

local function standingAt(x: number, y: number, z: number): boolean
	local s = Blueprint.slotAt(bp, x, y, z)
	if s == nil then
		return false
	end
	local r = mirror.rate[s]
	return r < 0 or (r == 0 and mirror.progress[s] >= 1)
end

local function moveCharacterTo(x: number, y: number, z: number)
	local character = player.Character
	if character then
		-- The root stands about one cell above the feet.
		character:PivotTo(CFrame.new(ORIGIN + Vector3.new(x + 0.5, y + 1, z + 0.5) * STUDS))
	end
end

-- Sound ---------------------------------------------------------------------

local playTick
do
	local ticks: { Sound } = {}
	for i = 1, 4 do
		local sound = Instance.new("Sound")
		sound.Name = `PlaceTick{i}`
		sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		sound.Volume = 0.35
		sound.Parent = SoundService
		table.insert(ticks, sound)
	end
	local tickNext, chainCount, lastTickAt = 1, 0, 0

	-- A tick whose pitch climbs while placements come fast, and resets after a pause.
	function playTick()
		if not settings.Sounds then
			return
		end
		local now = os.clock()
		chainCount = if now - lastTickAt < 0.6 then math.min(chainCount + 1, 16) else 0
		lastTickAt = now
		local sound = ticks[tickNext]
		tickNext = tickNext % #ticks + 1
		sound.PlaybackSpeed = 1 + 0.035 * chainCount
		sound:Play()
	end
end

-- HUD -----------------------------------------------------------------------

-- Blocks this player has laid, and the boss's latest view, for the hints.
local myPlaced = 0
local bossView: { [string]: any }? = nil

local say, capitalise, swingTool, refreshHud, drawHud
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "SiteHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local TEXT_COLOR = Color3.fromRGB(240, 245, 255)
	local PANEL_COLOR = Color3.fromRGB(34, 44, 66)
	local AFFORD_COLOR = Color3.fromRGB(52, 92, 66)
	local OPEN_COLOR = Color3.fromRGB(64, 84, 122)
	local RING_READY = Color3.fromRGB(255, 225, 120)
	local RING_WAIT = Color3.fromRGB(150, 170, 200)
	-- No button is shorter than a comfortable thumb.
	local TOUCH_SIZE = 44
	local ROW = 46
	local ROW_GAP = 6
	local SHOP_WIDTH = 250
	local GHOST_SIZES = { "Small", "Medium", "Large" }

	local function label(name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Size = size
		l.Position = position
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.BackgroundTransparency = 1
		l.TextColor3 = TEXT_COLOR
		l.TextStrokeTransparency = 0.5
		l.Font = Enum.Font.GothamBold
		l.TextSize = textSize
		l.Text = ""
		l.Parent = gui
		return l
	end

	local builtLabel = label("Built", UDim2.fromOffset(300, 26), UDim2.new(0.5, 0, 0, 8), 20)
	local hintLabel = label("Hint", UDim2.new(0.7, 0, 0, 44), UDim2.new(0.5, 0, 1, -150), 18)
	hintLabel.TextWrapped = true
	local hintsShown: { [string]: boolean } = {}
	local hintUntil, nextHintAt = 0, 0
	local announce = label("Announce", UDim2.new(0.8, 0, 0, 52), UDim2.new(0.5, 0, 0, 40), 22)
	announce.TextWrapped = true
	local announceUntil = 0

	local cooldownBack = Instance.new("Frame")
	cooldownBack.Name = "Cooldown"
	cooldownBack.AnchorPoint = Vector2.new(0.5, 1)
	cooldownBack.Position = UDim2.new(0.5, 0, 1, -90)
	cooldownBack.Size = UDim2.fromOffset(160, 8)
	cooldownBack.BackgroundColor3 = Color3.fromRGB(30, 36, 52)
	cooldownBack.BorderSizePixel = 0
	cooldownBack.Parent = gui
	local cooldownFill = Instance.new("Frame")
	cooldownFill.Size = UDim2.fromScale(1, 1)
	cooldownFill.BackgroundColor3 = Color3.fromRGB(255, 205, 120)
	cooldownFill.BorderSizePixel = 0
	cooldownFill.Parent = cooldownBack

	-- The cooldown ring: a circle at the cursor that grows as the next click
	-- comes ready, and turns gold when it is.
	local ring = Instance.new("Frame")
	ring.Name = "CooldownRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromOffset(26, 26)
	ring.Parent = gui
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 2
	ringStroke.Color = RING_READY
	ringStroke.Parent = ring

	local function button(name: string, color: Color3, parent: Instance): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.BackgroundColor3 = color
		b.TextColor3 = TEXT_COLOR
		b.Font = Enum.Font.GothamBold
		b.TextSize = 18
		b.TextWrapped = true
		b.Text = ""
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b
		-- Caps the text when a touch layout scales it to fit a small button.
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 18
		cap.Parent = b
		b.Parent = parent
		return b
	end

	local crewButton = button("Crew", Color3.fromRGB(46, 70, 110), gui)
	crewButton.Activated:Connect(function()
		AbilityRemote:FireServer()
	end)

	function swingTool()
		local look = workspace.CurrentCamera.CFrame.LookVector
		ToolRemote:FireServer(look.X, look.Z)
	end

	local toolButton = button("Tool", Color3.fromRGB(96, 60, 40), gui)
	toolButton.TextColor3 = Color3.fromRGB(250, 240, 230)
	toolButton.Visible = false
	toolButton.Activated:Connect(swingTool)

	-- The skill shop down the left edge: a toggle that folds it, then one
	-- button a node, with its level and next price, in a list that scrolls
	-- when the screen is too short for it. The settings toggle sits beside
	-- the shop's. The list, the panel and a bar behind the toggles take
	-- input too, so a tap in a gap between buttons doesn't reach the site.
	local toggleBar = Instance.new("Frame")
	toggleBar.Name = "ToggleBar"
	toggleBar.BackgroundTransparency = 1
	toggleBar.Active = true
	toggleBar.ZIndex = 0
	toggleBar.Parent = gui
	local shopToggle = button("ShopToggle", PANEL_COLOR, gui)
	local settingsToggle = button("SettingsToggle", PANEL_COLOR, gui)
	settingsToggle.Text = "Settings"

	local shop = Instance.new("ScrollingFrame")
	shop.Name = "Shop"
	shop.Active = true
	shop.BackgroundTransparency = 1
	shop.BorderSizePixel = 0
	shop.ScrollBarThickness = 6
	shop.ScrollingDirection = Enum.ScrollingDirection.Y
	shop.CanvasSize = UDim2.fromOffset(0, #SkillTuning.nodes * (ROW + ROW_GAP))
	shop.Parent = gui
	local shopButtons: { TextButton } = {}
	for i, node in SkillTuning.nodes do
		local b = Instance.new("TextButton")
		b.Name = node.id
		b.Position = UDim2.fromOffset(0, (i - 1) * (ROW + ROW_GAP))
		-- Narrower than the list by its scroll bar.
		b.Size = UDim2.fromOffset(SHOP_WIDTH - 10, ROW)
		b.BackgroundColor3 = PANEL_COLOR
		b.BackgroundTransparency = 0.15
		b.TextColor3 = Color3.fromRGB(235, 240, 250)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Font = Enum.Font.Gotham
		b.TextSize = 14
		b.TextWrapped = true
		b.Parent = shop
		b.Activated:Connect(function()
			BuyRemote:FireServer(node.id)
		end)
		shopButtons[i] = b
	end

	-- The settings panel, shown in the shop's place.
	local settingsPanel = Instance.new("Frame")
	settingsPanel.Name = "Settings"
	settingsPanel.Active = true
	settingsPanel.BackgroundTransparency = 1
	settingsPanel.Size = UDim2.fromOffset(SHOP_WIDTH, 3 * (ROW + ROW_GAP))
	settingsPanel.Visible = false
	settingsPanel.Parent = gui

	local function settingRow(name: string, i: number): TextButton
		local b = button(name, PANEL_COLOR, settingsPanel)
		b.Position = UDim2.fromOffset(0, (i - 1) * (ROW + ROW_GAP))
		b.Size = UDim2.fromOffset(SHOP_WIDTH, ROW)
		b.TextSize = 16
		return b
	end
	local soundsButton = settingRow("Sounds", 1)
	local hintsButton = settingRow("Hints", 2)
	local radiusButton = settingRow("GhostRadius", 3)

	local function onOff(on: boolean): string
		return if on then "On" else "Off"
	end

	local function refreshSettings()
		soundsButton.Text = `Sounds: {onOff(settings.Sounds)}`
		hintsButton.Text = `Hints: {onOff(settings.Hints)}`
		radiusButton.Text = `Ghost radius: {settings.GhostRadius}`
	end
	refreshSettings()

	soundsButton.Activated:Connect(function()
		setSetting("Sounds", not settings.Sounds)
		refreshSettings()
	end)
	hintsButton.Activated:Connect(function()
		setSetting("Hints", not settings.Hints)
		if not settings.Hints then
			hintLabel.Text = ""
		end
		refreshSettings()
	end)
	radiusButton.Activated:Connect(function()
		local pick = 1
		for i, size in GHOST_SIZES do
			if size == settings.GhostRadius then
				pick = i % #GHOST_SIZES + 1
			end
		end
		setSetting("GhostRadius", GHOST_SIZES[pick])
		refreshSettings()
		-- Redraw the ghosts next frame, not at the next refresh.
		ghostClock = math.huge
	end)

	local shopOpen, settingsOpen = true, false

	local function refreshPanels()
		local showing = shopOpen and not settingsOpen
		shop.Visible = showing
		settingsPanel.Visible = settingsOpen
		shopToggle.Text = if showing then "Hide shop" else "Shop"
		shopToggle.BackgroundColor3 = if showing then OPEN_COLOR else PANEL_COLOR
		settingsToggle.BackgroundColor3 = if settingsOpen then OPEN_COLOR else PANEL_COLOR
	end

	shopToggle.Activated:Connect(function()
		shopOpen = not (shopOpen and not settingsOpen)
		settingsOpen = false
		refreshPanels()
	end)
	settingsToggle.Activated:Connect(function()
		settingsOpen = not settingsOpen
		refreshPanels()
	end)

	local laidOutSize: Vector2? = nil
	local laidOutTouch: boolean? = nil

	-- Places the HUD for the screen in use, again whenever its size or kind
	-- changes: on a touch screen the crew and tool buttons sit by the right
	-- thumb, beside the jump button; with a mouse, at the bottom right.
	local function layoutHud()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			-- Not laid out yet.
			size = workspace.CurrentCamera.ViewportSize
		end
		local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		if size == laidOutSize and touch == laidOutTouch then
			return
		end
		if touch ~= laidOutTouch then
			-- A touch screen starts with the shop folded, clear of the thumbstick.
			shopOpen = not touch
		end
		laidOutSize, laidOutTouch = size, touch
		if touch then
			-- Roblox's jump button, as its TouchJump module lays it out: 70 px
			-- square on small screens and 120 on others, at the bottom right.
			local small = math.min(size.X, size.Y) <= 500
			local jump = if small then 70 else 120
			local jumpLeft = jump * 1.5 - 10
			local jumpBottom = if small then 20 else jump * 0.75
			local side = if small then 64 else 80
			local gap = 12
			crewButton.AnchorPoint = Vector2.new(1, 1)
			crewButton.Size = UDim2.fromOffset(side, side)
			crewButton.Position = UDim2.new(1, -(jumpLeft + gap), 1, -jumpBottom)
			toolButton.AnchorPoint = Vector2.new(0.5, 1)
			toolButton.Size = UDim2.fromOffset(side, side)
			toolButton.Position = UDim2.new(1, -(jumpLeft - jump / 2), 1, -(jumpBottom + jump + gap))
			crewButton.Text = Theme.Ability
			toolButton.Text = Theme.PowerTool
		else
			crewButton.AnchorPoint = Vector2.new(1, 1)
			crewButton.Size = UDim2.fromOffset(150, TOUCH_SIZE)
			crewButton.Position = UDim2.new(1, -16, 1, -140)
			toolButton.AnchorPoint = Vector2.new(1, 1)
			toolButton.Size = UDim2.fromOffset(150, TOUCH_SIZE)
			toolButton.Position = UDim2.new(1, -16, 1, -192)
			crewButton.Text = `{Theme.Ability} (Q)`
			toolButton.Text = `{Theme.PowerTool} (F)`
		end
		crewButton.TextScaled = touch
		toolButton.TextScaled = touch
		-- Below the toggles on a touch screen, whose top row they share.
		announce.Position = UDim2.new(0.5, 0, 0, if touch then 62 else 40)

		-- The shop's column: the toggles, then the list, centred down the
		-- left edge where there's room, else from the top.
		local listHeight = #SkillTuning.nodes * (ROW + ROW_GAP)
		local shown = math.min(listHeight, math.max(ROW, size.Y - (TOUCH_SIZE + ROW_GAP) - 24))
		local top = math.max(8, (size.Y - (TOUCH_SIZE + ROW_GAP + shown)) / 2)
		local half = (SHOP_WIDTH - ROW_GAP) / 2
		toggleBar.Position = UDim2.fromOffset(12, top)
		toggleBar.Size = UDim2.fromOffset(SHOP_WIDTH, TOUCH_SIZE)
		shopToggle.Position = UDim2.fromOffset(12, top)
		shopToggle.Size = UDim2.fromOffset(half, TOUCH_SIZE)
		settingsToggle.Position = UDim2.fromOffset(12 + half + ROW_GAP, top)
		settingsToggle.Size = UDim2.fromOffset(half, TOUCH_SIZE)
		shop.Position = UDim2.fromOffset(12, top + TOUCH_SIZE + ROW_GAP)
		shop.Size = UDim2.fromOffset(SHOP_WIDTH, shown)
		settingsPanel.Position = UDim2.fromOffset(12, top + TOUCH_SIZE + ROW_GAP)
		refreshPanels()
	end
	layoutHud()

	local function purse(): number
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild(Theme.RunCurrency)
		return if value and value:IsA("IntValue") then value.Value else 0
	end

	-- Each node's level attribute, named once rather than every refresh.
	local LEVEL_NAMES: { string } = {}
	for i, node in SkillTuning.nodes do
		LEVEL_NAMES[i] = `Level_{node.id}`
	end
	local ABILITY_LEVEL = `Level_{SkillTuning.abilityNode}`
	-- What each shop button shows, so its text is rebuilt only when that changes.
	local shownLevel: { number } = {}
	local shownAfford: { boolean } = {}

	local function refreshShop()
		local have = purse()
		for i, node in SkillTuning.nodes do
			local level = player:GetAttribute(LEVEL_NAMES[i]) or 0
			local price = if level < node.max then SkillTuning.price(node, level) else math.huge
			local afford = have >= price
			if level ~= shownLevel[i] or afford ~= shownAfford[i] then
				shownLevel[i], shownAfford[i] = level, afford
				local b = shopButtons[i]
				if level >= node.max then
					b.Text = `  {i}  {node.name}  (max)\n      {node.blurb}`
				else
					b.Text = `  {i}  {node.name}  {level}/{node.max}   {price} {Theme.RunCurrency}\n      {node.blurb}`
				end
				b.BackgroundColor3 = if afford then AFFORD_COLOR else PANEL_COLOR
			end
		end
		crewButton.Visible = (player:GetAttribute(ABILITY_LEVEL) or 0) >= 1
		toolButton.Visible = player:GetAttribute("HasTool") == true
	end

	-- One context, filled in place each time a hint is picked.
	local hintContext: Hints.Context = {
		placed = 0,
		purse = 0,
		cheapest = 0,
		bought = 0,
		workingLayer = 0,
		bossRisen = false,
		markers = 0,
		bound = false,
		peace = false,
		crewUnlocked = false,
	}

	local function pickHint(now: number)
		local cheapest, bought = math.huge, 0
		for i, node in SkillTuning.nodes do
			local level = player:GetAttribute(LEVEL_NAMES[i]) or 0
			bought += level
			if level < node.max then
				cheapest = math.min(cheapest, SkillTuning.price(node, level))
			end
		end
		local view = bossView
		local context = hintContext
		context.placed = myPlaced
		context.purse = purse()
		context.cheapest = cheapest
		context.bought = bought
		context.workingLayer = Access.workingLayer(bp, mirror) or 0
		context.bossRisen = view ~= nil and view.risen and not view.relented
		context.markers = if view then #view.markers else 0
		context.bound = view ~= nil and #view.bindings > 0
		context.peace = view ~= nil and view.peace ~= nil
		context.crewUnlocked = (player:GetAttribute(ABILITY_LEVEL) or 0) >= 1
		local hint = Hints.pick(context, hintsShown)
		if hint then
			hintsShown[hint] = true
			hintLabel.Text = Hints.words(HintConfig, hint, device)
			hintUntil = now + 7
			nextHintAt = now + 9
		end
	end

	function say(text: string, seconds: number?)
		announce.Text = text
		announceUntil = os.clock() + (seconds or 3.5)
	end

	function capitalise(text: string): string
		return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
	end

	-- What the HUD shows, so each frame writes only what changed.
	local shownReady, shownRingX, shownRingY = -1, -1, -1
	local shownPercent, shownSite = -1, ""

	-- Every frame: the cooldown bar and ring (ready is 0 to 1), the share
	-- built, and the end of an announcement.
	function drawHud(now: number, ready: number)
		if ready ~= shownReady then
			shownReady = ready
			cooldownFill.Size = UDim2.fromScale(ready, 1)
			local size = 10 + 16 * ready
			ring.Size = UDim2.fromOffset(size, size)
			ringStroke.Color = if ready >= 1 then RING_READY else RING_WAIT
		end
		if UserInputService.MouseEnabled then
			local mouse = UserInputService:GetMouseLocation()
			local inset = gui.AbsolutePosition
			local x, y = mouse.X - inset.X, mouse.Y - inset.Y
			if x ~= shownRingX or y ~= shownRingY then
				shownRingX, shownRingY = x, y
				ring.Position = UDim2.fromOffset(x, y)
			end
			ring.Visible = true
		else
			ring.Visible = false
		end
		local percent = math.floor(100 * mirror.placedCount / mirror.count)
		if percent ~= shownPercent or siteId ~= shownSite then
			shownPercent, shownSite = percent, siteId
			builtLabel.Text = string.format("%s: %s %d%%", siteName(siteId), Theme.PlaceVerb.past, percent)
		end
		if announceUntil > 0 and now > announceUntil then
			announce.Text = ""
			announceUntil = 0
		end
	end

	-- Four times a second: the layout, the shop, and the next hint.
	function refreshHud(now: number)
		layoutHud()
		refreshShop()
		if settings.Hints and now >= nextHintAt then
			pickHint(now)
		end
		if now > hintUntil then
			hintLabel.Text = ""
		end
	end
end

-- Clicking ------------------------------------------------------------------

local holding = false
local lastClick = -math.huge
local aimedSlot, tryPlace
do
	local holdPoint: Vector2? = nil
	-- The touch that started the hold. Other fingers, on the thumbstick, the
	-- camera or a button, neither move its aim nor end it.
	local holdTouch: InputObject? = nil
	local nextId = 0

	local function aimRay(): Ray
		local camera = workspace.CurrentCamera
		if holdPoint then
			return camera:ScreenPointToRay(holdPoint.X, holdPoint.Y)
		end
		if UserInputService.MouseEnabled then
			local mouse = UserInputService:GetMouseLocation()
			return camera:ViewportPointToRay(mouse.X, mouse.Y)
		end
		local size = camera.ViewportSize
		return camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end

	local function placeableByHand(s: number): boolean
		return BuildSite.canPlace(mirror, s, BuildSite.Cause.HAND)
	end

	function aimedSlot(): number?
		local rx, ry, rz = rootCell()
		if rx == nil then
			return nil
		end
		local ray = aimRay()
		local ox, oy, oz = toCells(ray.Origin)
		local d = ray.Direction.Unit
		local grasp = player:GetAttribute("Grasp") or SiteConfig.BASE_GRASP_CELLS
		local slot = SiteRay.cast(bp, mirror, ox, oy, oz, d.X, d.Y, d.Z, 120, rx, ry, rz, grasp)
		if slot == nil and (player:GetAttribute("Level_autoAim") or 0) >= 1 then
			-- Auto-aim: the nearest slot a click could lay.
			local n = SiteIndex.nearest(index, rx, ry, rz, grasp, placeableByHand, 1, found)
			if n > 0 then
				slot = found[1]
			end
		end
		return slot
	end

	-- Places slot, the aimed one, if the cooldown allows.
	function tryPlace(slot: number?)
		local now = os.clock()
		local cooldown = player:GetAttribute("Cooldown") or 0.35
		if slot == nil or now - lastClick < cooldown then
			return
		end
		nextId += 1
		if Prediction.predict(pred, slot, nextId, now) then
			lastClick = now
			PlaceRemote:FireServer(nextId, slot)
			playTick()
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch then
			device = "touch"
		elseif kind and string.sub(kind.Name, 1, 7) == "Gamepad" then
			device = "gamepad"
		elseif kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 then
			device = "mouse"
		end
		-- A click or tap a button took, or the thumbstick's touch, never places.
		if processed then
			return
		end
		if kind == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding, holdPoint, holdTouch = true, nil, nil
			tryPlace(aimedSlot())
		elseif kind == Enum.UserInputType.Touch then
			holding, holdPoint, holdTouch = true, Vector2.new(input.Position.X, input.Position.Y), input
			tryPlace(aimedSlot())
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
			AbilityRemote:FireServer()
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonY then
			swingTool()
		else
			local digit = string.match(input.KeyCode.Name, "^(%a+)$")
			local numbers = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8, Nine = 9 }
			local n = digit and numbers[digit]
			local node = n and SkillTuning.nodes[n]
			if node then
				BuyRemote:FireServer(node.id)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if holding and input == holdTouch then
			holdPoint = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or input.KeyCode == Enum.KeyCode.ButtonR2
			or (kind == Enum.UserInputType.Touch and input == holdTouch)
		then
			holding, holdPoint, holdTouch = false, nil, nil
		end
	end)
end

-- Hoist pads ----------------------------------------------------------------

do
	local hoistReadyAt = 0

	local function onPad(pad: BasePart, hit: BasePart)
		local character = player.Character
		if character == nil or not hit:IsDescendantOf(character) or os.clock() < hoistReadyAt then
			return
		end
		hoistReadyAt = os.clock() + 3
		local layer = Access.workingLayer(bp, mirror)
		if layer == nil or layer == 0 then
			return
		end
		local px, _, pz = toCells(pad.Position)
		local n = SiteIndex.nearest(index, px, layer + 0.5, pz, 400, function(s)
			return bp.y[s] == layer and BuildSite.state(mirror, s) == State.READY
		end, 1, found)
		if n == 0 then
			return
		end
		local s = found[1]
		-- Stand beside the slot, a cell toward the pad, not in it.
		local dx, dz = px - (bp.x[s] + 0.5), pz - (bp.z[s] + 0.5)
		local len = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
		local x, y, z =
			Access.freeSurface(bp, mirror, bp.x[s] + 0.5 + dx / len, layer + 1, bp.z[s] + 0.5 + dz / len, 6, HEADROOM)
		if x then
			moveCharacterTo(x, y :: number, z :: number)
			say(`Up to layer {layer}.`)
		end
	end

	task.spawn(function()
		local props = workspace:WaitForChild("SiteProps")
		for _, pad in props:GetChildren() do
			if pad:IsA("BasePart") and pad.Name == "HoistPad" then
				pad.Touched:Connect(function(hit)
					onPad(pad, hit)
				end)
			end
		end
	end)
end

-- The world arc -------------------------------------------------------------

local placeSkyGlow, applyArc, weatherPart
do
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end

	weatherPart = Instance.new("Part")
	weatherPart.Name = "Weather"
	weatherPart.Anchored = true
	weatherPart.CanCollide = false
	weatherPart.CanQuery = false
	weatherPart.CanTouch = false
	weatherPart.Transparency = 1
	weatherPart.Size = Vector3.new(160, 1, 160)
	weatherPart.Parent = workspace
	local weather = Instance.new("ParticleEmitter")
	weather.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
	weather.LightEmission = 0.3
	weather.Size = NumberSequence.new(0.18)
	weather.Lifetime = NumberRange.new(5, 7)
	weather.Speed = NumberRange.new(4, 7)
	weather.SpreadAngle = Vector2.new(25, 25)
	weather.Acceleration = Vector3.new(1.5, -1, 0)
	weather.EmissionDirection = Enum.NormalId.Bottom
	weather.Rate = 0
	weather.Parent = weatherPart

	local skyGlow = Instance.new("Part")
	skyGlow.Name = "SkyGlow"
	skyGlow.Anchored = true
	skyGlow.CanCollide = false
	skyGlow.CanQuery = false
	skyGlow.CanTouch = false
	skyGlow.CastShadow = false
	skyGlow.Material = Enum.Material.Neon
	skyGlow.Size = Vector3.new(600, 30, 2)
	function placeSkyGlow()
		skyGlow.CFrame = CFrame.new(ORIGIN + Vector3.new(bp.sizeX * STUDS / 2, 260, bp.sizeZ * STUDS + 220))
			* CFrame.Angles(math.rad(-20), 0, 0)
	end
	placeSkyGlow()
	skyGlow.Transparency = 1
	skyGlow.Parent = workspace

	local look = {}
	function applyArc()
		WorldArc.at(WorldArcConfig, mirror.placedCount / mirror.count, look)
		Lighting.FogEnd = look.fogEnd
		Lighting.FogColor = Color3.fromRGB(look.fogColor[1], look.fogColor[2], look.fogColor[3])
		Lighting.ClockTime = look.clockTime
		Lighting.Brightness = look.brightness
		-- With an Atmosphere present, it, not Lighting's fog, colours the distance.
		atmosphere.Density = look.density
		atmosphere.Color = Lighting.FogColor
		weather.Rate = look.weather
		skyGlow.Transparency = 1 - 0.65 * look.skyGlow
	end
end

-- The boss ------------------------------------------------------------------

local moveBoss
do
	local bossFolder = Instance.new("Folder")
	bossFolder.Name = "SiteBoss"
	bossFolder.Parent = workspace

	local function bossBall(size: number, color: Color3, transparency: number): BasePart
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.one * size
		part.Color = color
		part.Transparency = transparency
		return part
	end

	local bossPart = bossBall(5, Color3.fromRGB(170, 225, 255), 0.25)
	bossPart.Name = "Boss"
	local bossTarget: Vector3? = nil

	-- Its name above it, shown through the build so players can find it.
	local nameLabel = Instance.new("BillboardGui")
	nameLabel.Name = "NameLabel"
	nameLabel.Adornee = bossPart
	nameLabel.Size = UDim2.fromOffset(220, 32)
	nameLabel.StudsOffset = Vector3.new(0, 4.2, 0)
	nameLabel.AlwaysOnTop = true
	nameLabel.MaxDistance = 400
	nameLabel.LightInfluence = 0
	nameLabel.Parent = bossPart
	local nameText = Instance.new("TextLabel")
	nameText.Name = "Name"
	nameText.Size = UDim2.fromScale(1, 1)
	nameText.BackgroundTransparency = 1
	nameText.Font = Enum.Font.GothamBold
	nameText.TextSize = 20
	nameText.TextColor3 = Color3.fromRGB(215, 240, 255)
	nameText.TextStrokeTransparency = 0.4
	nameText.Text = capitalise(Theme.Boss.name)
	nameText.Parent = nameLabel

	-- Its shoo ring: a faint circle of the shoo radius on the surface under
	-- it, following the ball across and the surface up and down.
	local shooAnchor = Instance.new("Part")
	shooAnchor.Name = "ShooRing"
	shooAnchor.Anchored = true
	shooAnchor.CanCollide = false
	shooAnchor.CanQuery = false
	shooAnchor.CanTouch = false
	shooAnchor.Transparency = 1
	shooAnchor.Size = Vector3.one * 0.2
	shooAnchor.Parent = bossPart
	local shooRing = Instance.new("CylinderHandleAdornment")
	shooRing.Name = "Ring"
	shooRing.Adornee = shooAnchor
	-- A cylinder adornment's axis is its Z; a quarter turn about X lays it flat.
	shooRing.CFrame = CFrame.Angles(math.pi / 2, 0, 0)
	shooRing.Height = 0.12
	shooRing.Color3 = Color3.fromRGB(200, 235, 255)
	shooRing.Transparency = 0.5
	shooRing.AlwaysOnTop = false
	shooRing.Parent = shooAnchor
	local ringY = ORIGIN.Y

	local works: { BasePart } = {}
	local peaceDisc = Instance.new("Part")
	peaceDisc.Name = "Peace"
	peaceDisc.Shape = Enum.PartType.Cylinder
	peaceDisc.Anchored = true
	peaceDisc.CanCollide = false
	peaceDisc.CanQuery = false
	peaceDisc.CanTouch = false
	peaceDisc.Material = Enum.Material.ForceField
	peaceDisc.Color = Color3.fromRGB(150, 200, 255)

	local function cellPoint(x: number, y: number, z: number): Vector3
		return ORIGIN + Vector3.new(x, y, z) * STUDS
	end

	-- The boss's tuning for the site in play. The server names its difficulty
	-- in CurrentDifficulty; Difficulty itself may have changed since.
	local function bossTuning()
		local difficulty = workspace:GetAttribute("CurrentDifficulty") or workspace:GetAttribute("Difficulty")
		return BossConfig[if typeof(difficulty) == "string" then difficulty else "Normal"]
	end

	-- The top of what stands under (x, y, z) in cell space, or the ground's.
	local function surfaceUnder(x: number, y: number, z: number): number
		local cx, cz = math.floor(x), math.floor(z)
		for cy = math.floor(y), 0, -1 do
			if standingAt(cx, cy, cz) then
				return cy + 1
			end
		end
		return 0
	end

	BossRemote.OnClientEvent:Connect(function(view)
		bossView = view
		for _, part in works do
			part:Destroy()
		end
		table.clear(works)
		if view == nil or not view.risen or view.relented then
			bossPart.Parent = nil
			peaceDisc.Parent = nil
			bossTarget = nil
			return
		end
		bossTarget = cellPoint(view.x, view.y, view.z)
		if bossPart.Parent == nil then
			bossPart.Position = bossTarget
		end
		local tuning = bossTuning()
		local radius = (if tuning then tuning.shooRadius else 3) * STUDS
		shooRing.Radius = radius
		shooRing.InnerRadius = math.max(0, radius - 0.4)
		ringY = ORIGIN.Y + surfaceUnder(view.x, view.y, view.z) * STUDS + 0.08
		local at = bossPart.Position
		shooAnchor.Position = Vector3.new(at.X, ringY, at.Z)
		bossPart.Parent = bossFolder
		for _, m in view.markers do
			local part = bossBall(1.6, Color3.fromRGB(190, 140, 255), 0.1)
			part.Position = cellPoint(m[1], m[2], m[3])
			part.Parent = bossFolder
			table.insert(works, part)
		end
		for _, b in view.bindings do
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.Ice
			part.Color = Color3.fromRGB(180, 220, 255)
			part.Size = Vector3.new(2, 14, 2)
			part.Position = cellPoint(b[1], 0, b[3]) + Vector3.new(0, 7, 0)
			part.Parent = bossFolder
			table.insert(works, part)
		end
		for _, m in view.minions do
			local part = bossBall(2, Color3.fromRGB(210, 235, 255), 0.35)
			part.Position = cellPoint(m[1], m[2], m[3])
			part.Parent = bossFolder
			table.insert(works, part)
		end
		if view.peace then
			local peaceRadius = if tuning and tuning.peace then tuning.peace.radius else 5
			peaceDisc.Size = Vector3.new(0.4, peaceRadius * 2 * STUDS, peaceRadius * 2 * STUDS)
			peaceDisc.CFrame = CFrame.new(cellPoint(view.peace[1], 0, view.peace[2]) + Vector3.new(0, 0.3, 0))
				* CFrame.Angles(0, 0, math.pi / 2)
			peaceDisc.Parent = bossFolder
		else
			peaceDisc.Parent = nil
		end
	end)

	-- Each frame: the ball glides toward where the boss is, its ring with it.
	function moveBoss(dt: number)
		if bossTarget then
			local at = bossPart.Position:Lerp(bossTarget, math.min(1, dt * 6))
			bossPart.Position = at
			shooAnchor.Position = Vector3.new(at.X, ringY, at.Z)
		end
	end
end

-- Events --------------------------------------------------------------------

do
	local works_ = Theme.BossWorks
	local bossName = capitalise(Theme.Boss.name)
	local me = player.UserId

	EventRemote.OnClientEvent:Connect(function(events)
		for _, e in events do
			local kind = e.kind
			if kind == "boss_rise" then
				say(`{bossName} rises.`)
			elseif kind == "boss_shooed" then
				say(if e.userId == me then `You shooed {Theme.Boss.name}!` else `{bossName} was shooed.`)
			elseif kind == "boss_stand" then
				say(`{bossName} makes a last stand. Shoo it away!`)
			elseif kind == "boss_relent" then
				say(`{bossName} gives up.`)
			elseif kind == "marker_on" then
				say(`A {works_.marker} is forming. Break it before it bursts!`)
			elseif kind == "marker_burst" then
				say(`A {works_.marker} burst.`)
			elseif kind == "marker_broken" and e.userId == me then
				say(`+{e.amount} {Theme.RunCurrency} for breaking a {works_.marker}.`)
			elseif kind == "bound" then
				say(`{capitalise(works_.binding)}s hold the {Theme.Site.one}. Break them at the corners!`)
			elseif kind == "unbound" then
				say(`The {works_.binding}s are broken.`)
			elseif kind == "peace_on" then
				say(`{bossName}'s {works_.peace}: nothing can be laid near it until it's shooed.`)
			elseif kind == "stubborn" then
				say(`A band of stubborn {Theme.Block.many} only your own hand can lay.`)
			elseif kind == "collapse" then
				say(`Part of the {Theme.Site.one} came down!`)
			elseif kind == "smother" and e.userId == me then
				say(`You're {works_.smother}!`)
			elseif kind == "drop" and e.userId == me then
				say(`You found {Theme.PremiumCurrency}!`)
			elseif kind == "ability" and e.userId == me then
				say(`{Theme.Ability}!`)
			elseif kind == "pet_ability" and e.userId == me then
				say(`Your {Theme.Pet.one} laid {e.amount} {Theme.Block.many} around you!`)
			elseif kind == "tool" and e.userId == me then
				say(`{Theme.PowerTool}: {e.amount} {Theme.Block.many}!`)
			elseif kind == "perfect" and e.userId == me then
				playTick()
			elseif kind == "finished" then
				say(`The {Theme.Site.one} stands! A new one starts soon.`)
			elseif kind == "payout" and e.userId == me then
				local shooed = if e.shooed > 0 then `, shooed {Theme.Boss.name} {e.shooed} times` else ""
				say(
					`The {siteName(siteId)} stands! You laid {e.placed} {Theme.Block.many}{shooed}, and earned {e.amount} {Theme.MetaCurrency}.`,
					12
				)
			end
		end
	end)
end

-- Stress test: readout ------------------------------------------------------

-- A debug readout for the renderer's stress test (formula 4.5): frames a
-- second, and the mean and 95th-percentile frame time over the last two
-- seconds, from RenderStepped's step; then what the client draws: block
-- parts in near chunks, far chunks' merged boxes, and near chunks'
-- collision boxes. It shows whenever the workspace's StressTest attribute
-- is set, and F3 shows or hides it at any time. A ladder's table shows in
-- the middle of the screen once the ladder is done.
local frameSummary, drawCounts, setStressStatus, showStressTable
do
	local WINDOW_SECONDS = 2
	local REFRESH_SECONDS = 0.25
	-- More frames than two seconds hold at any frame rate Roblox runs at.
	local CAPACITY = 1024

	local gui = Instance.new("ScreenGui")
	gui.Name = "SiteStress"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = workspace:GetAttribute("StressTest") ~= nil
	gui.Parent = player:WaitForChild("PlayerGui")

	-- A panel of monospaced text that grows to fit it.
	local function panel(name: string): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AutomaticSize = Enum.AutomaticSize.XY
		l.Size = UDim2.fromOffset(0, 0)
		l.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
		l.BackgroundTransparency = 0.3
		l.BorderSizePixel = 0
		l.Font = Enum.Font.Code
		l.TextSize = 13
		l.TextColor3 = Color3.fromRGB(225, 235, 250)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Text = ""
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.Parent = l
		l.Parent = gui
		return l
	end
	-- By the right edge, below Roblox's player list and above the buttons
	-- beside the jump button.
	local readout = panel("Readout")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, -12, 0, 96)
	local results = panel("Results")
	results.AnchorPoint = Vector2.new(0.5, 0.5)
	results.Position = UDim2.fromScale(0.5, 0.5)
	results.Visible = false

	-- Each frame's step and when it ended, in a ring with the newest at frameAt.
	local frameTimes: { number } = table.create(CAPACITY, 0)
	local frameEnds: { number } = table.create(CAPACITY, -math.huge)
	local frameAt = 0
	local window: { number } = {}
	local status = ""
	local refreshAt = 0

	-- The mean and 95th-percentile of a list of frame steps, which it sorts.
	function frameSummary(steps: { number }): (number, number)
		local n = #steps
		if n == 0 then
			return 0, 0
		end
		local total = 0
		for _, t in steps do
			total += t
		end
		table.sort(steps)
		return total / n, steps[math.max(1, math.ceil(n * 0.95))]
	end

	-- What the client draws: block parts in near chunks, far chunks' merged
	-- boxes, and near chunks' collision boxes.
	function drawCounts(): (number, number, number)
		local near, far, collision = 0, 0, 0
		for _ in blocks do
			near += 1
		end
		for _, list in farParts do
			far += #list
		end
		for _, list in collisionParts do
			collision += #list
		end
		return near, far, collision
	end

	-- A last line for the readout, such as how far the ladder's tour is.
	function setStressStatus(text: string)
		status = text
	end

	-- Shows the ladder's table and the readout with it, or hides the table given nil.
	function showStressTable(lines: { string }?)
		results.Text = if lines then table.concat(lines, "\n") else ""
		results.Visible = lines ~= nil
		if lines then
			gui.Enabled = true
		end
	end

	workspace.AttributeChanged:Connect(function(name)
		if name == "StressTest" then
			gui.Enabled = workspace:GetAttribute("StressTest") ~= nil
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F3 then
			gui.Enabled = not gui.Enabled
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		frameAt = frameAt % CAPACITY + 1
		frameTimes[frameAt], frameEnds[frameAt] = dt, now
		if not gui.Enabled or now < refreshAt then
			return
		end
		refreshAt = now + REFRESH_SECONDS
		table.clear(window)
		for k = 0, CAPACITY - 1 do
			local i = (frameAt - 1 - k) % CAPACITY + 1
			if frameEnds[i] < now - WINDOW_SECONDS then
				break
			end
			table.insert(window, frameTimes[i])
		end
		local mean, p95 = frameSummary(window)
		local near, far, collision = drawCounts()
		readout.Text = string.format(
			"%5.1f FPS  mean %5.1f ms  p95 %5.1f ms  (last %d s)\nnear parts %d  far boxes %d  collision boxes %d%s",
			if mean > 0 then 1 / mean else 0,
			mean * 1000,
			p95 * 1000,
			WINDOW_SECONDS,
			near,
			far,
			collision,
			if status ~= "" then "\n" .. status else ""
		)
	end)
end

-- Stress test: ladder tour --------------------------------------------------

-- While a stress ladder runs, which the server shows in StressStep and
-- StressSteps, the camera tours every step the same way. The client draws
-- the step from the near view, then says so on SiteRemotes.Stress, which
-- starts the server's hold of StressStepSeconds. It spends half the hold in
-- the near view, at the site's edge where the most standing blocks lie in
-- near chunks, and half in a far overview, from where every chunk is far,
-- keeping a twentieth spare so the next step never cuts it short. In each
-- view it times the frames after a short settle, for a row of the table
-- the last step prints to the output and shows on screen. Then the camera
-- goes back as it was.
local stressSnapshot
do
	-- Seconds a view settles before its frames count, so the switch between
	-- near and far drawing isn't timed. A short hold settles for less.
	local SETTLE_SECONDS = 2
	-- How often a view counts what's drawn while it's timed.
	local COUNT_SECONDS = 0.25
	-- The share of the server's hold the two views take, half each, so the
	-- tour is done before the next step starts.
	local TOUR_SHARE = 0.95
	-- Heights, in cells, the near view tries along the site's edges.
	local NEAR_HEIGHTS = { 3, 8, 14 }

	-- The camera as the tour found it, the step being toured, and the table's rows.
	local saved: { [string]: any }? = nil
	local tour: { [string]: any }? = nil
	local rows: { { [string]: any } } = {}

	local function takeCamera()
		local camera = workspace.CurrentCamera
		if saved == nil then
			saved = {
				cameraType = camera.CameraType,
				subject = camera.CameraSubject,
				cframe = camera.CFrame,
				fieldOfView = camera.FieldOfView,
			}
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 70
	end

	local function giveCamera()
		local was = saved
		if was == nil then
			return
		end
		saved = nil
		local camera = workspace.CurrentCamera
		camera.CameraType = was.cameraType
		camera.FieldOfView = was.fieldOfView
		camera.CFrame = was.cframe
		-- The character may have respawned since.
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		camera.CameraSubject = humanoid or was.subject
	end

	-- The tour's two views of the site in play. Near: two cells out from an
	-- edge and looking in, where the most standing blocks lie in chunks
	-- within NEAR_STUDS, which updateChunkModes draws block by block. Far:
	-- over the front left corner, far enough that every chunk is beyond
	-- FAR_STUDS, with the whole site in view.
	local function views(): (CFrame, CFrame)
		local centre = ORIGIN + Vector3.new(bp.sizeX, bp.sizeY, bp.sizeZ) * (STUDS / 2)
		local standing = table.create(index.chunkCount, 0)
		local reach = 0
		for c = 1, index.chunkCount do
			for i = index.slotStart[c], index.slotStart[c + 1] - 1 do
				local state = BuildSite.state(mirror, index.slotList[i])
				if state == State.PLACED or state == State.UNDOING then
					standing[c] += 1
				end
			end
			if index.slotStart[c + 1] > index.slotStart[c] then
				reach = math.max(reach, chunkDistance(c, centre))
			end
		end
		local best, nearView = -1, CFrame.new(centre)
		for edge = 1, 4 do
			for t = 0, if edge <= 2 then bp.sizeX else bp.sizeZ, 4 do
				for _, h in NEAR_HEIGHTS do
					local x, z, dx, dz = t, -2, 0, 1
					if edge == 2 then
						x, z, dx, dz = t, bp.sizeZ + 2, 0, -1
					elseif edge == 3 then
						x, z, dx, dz = -2, t, 1, 0
					elseif edge == 4 then
						x, z, dx, dz = bp.sizeX + 2, t, -1, 0
					end
					local eye = ORIGIN + Vector3.new(x, h, z) * STUDS
					local near = 0
					for c = 1, index.chunkCount do
						if standing[c] > 0 and chunkDistance(c, eye) < NEAR_STUDS then
							near += standing[c]
						end
					end
					if near > best then
						best = near
						nearView = CFrame.lookAt(eye, eye + Vector3.new(dx, -0.3, dz))
					end
				end
			end
		end
		-- Twice the site's radius fits it in a 60-degree cone, inside Roblox's 70-degree view.
		local radius = (Vector3.new(bp.sizeX, bp.sizeY, bp.sizeZ) * STUDS).Magnitude / 2
		local eye = centre + Vector3.new(-0.45, 0.55, -0.7).Unit * math.max(radius * 2, reach + FAR_STUDS + 10)
		return nearView, CFrame.lookAt(eye, centre)
	end

	-- Whether the snapshot is drawn, with no far merge or collision rebuild left.
	local function drawn(): boolean
		return backlogLeft() == 0 and next(redrawQueue) == nil and next(farDirty) == nil and next(collisionDirty) == nil
	end

	-- Closes the view in play with a row of the table. A view cut short by
	-- the next step's snapshot, which has cleared the site, gives what it
	-- last counted.
	local function record(run: { [string]: any }, cutShort: boolean?)
		local mean, p95 = frameSummary(run.samples)
		local counted = run.counted
		local near, far, collision
		if cutShort and counted then
			near, far, collision = counted[1], counted[2], counted[3]
		else
			near, far, collision = drawCounts()
		end
		table.insert(rows, {
			blocks = run.blocks,
			view = run.phase,
			near = near,
			far = far,
			collision = collision,
			fps = if mean > 0 then 1 / mean else 0,
			-- The 5th-percentile frame rate is the 95th-percentile frame's.
			lowFps = if p95 > 0 then 1 / p95 else 0,
			p95 = p95 * 1000,
		})
	end

	-- The graphics quality the player's settings ask for, as a LocalScript
	-- can read it: QualityLevel1 is the lowest.
	local function quality(): string
		local ok, level = pcall(function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel
		end)
		return if ok and typeof(level) == "EnumItem" then level.Name else "unknown"
	end

	-- The ladder is done: its table to the output and the screen, and the
	-- camera back.
	local function finish(run: { [string]: any })
		local viewport = workspace.CurrentCamera.ViewportSize
		local lines = {
			string.format(
				"Stress ladder: %d steps of %g s, viewport %d x %d, graphics quality %s",
				run.steps,
				run.hold,
				math.floor(viewport.X),
				math.floor(viewport.Y),
				quality()
			),
			string.format(
				"%7s  %-4s  %10s  %9s  %15s  %8s  %6s  %6s",
				"blocks",
				"view",
				"near parts",
				"far boxes",
				"collision boxes",
				"mean FPS",
				"5% FPS",
				"p95 ms"
			),
		}
		for _, row in rows do
			table.insert(
				lines,
				string.format(
					"%7d  %-4s  %10d  %9d  %15d  %8.1f  %6.1f  %6.1f",
					row.blocks,
					row.view,
					row.near,
					row.far,
					row.collision,
					row.fps,
					row.lowFps,
					row.p95
				)
			)
		end
		for _, line in lines do
			print(line)
		end
		showStressTable(lines)
		tour = nil
		giveCamera()
		setStressStatus("")
	end

	-- Called with each snapshot, once it's decoded and before its drawing
	-- is queued: a ladder step starts its tour from the near view, and a
	-- site that isn't one ends the tour.
	function stressSnapshot()
		local run = tour
		-- A step that ends before its tour does keeps what it timed.
		if run and (run.phase == "near" or run.phase == "far") then
			record(run, true)
		end
		local count = StressSite.parse(siteId)
		local step, steps = workspace:GetAttribute("StressStep"), workspace:GetAttribute("StressSteps")
		if count == nil or typeof(step) ~= "number" or typeof(steps) ~= "number" then
			if run then
				tour = nil
				giveCamera()
				setStressStatus("")
			end
			return
		end
		if step == 1 then
			table.clear(rows)
			showStressTable(nil)
		end
		takeCamera()
		local nearView, farView = views()
		workspace.CurrentCamera.CFrame = nearView
		tour = {
			blocks = count,
			step = step,
			steps = steps,
			near = nearView,
			far = farView,
			phase = "drawing",
			phaseAt = os.clock(),
			-- The server's hold, and each view's share of it, once drawn.
			hold = StressSite.STEP_SECONDS,
			view = StressSite.STEP_SECONDS * TOUR_SHARE / 2,
			samples = {},
			-- What the view last counted, and when it counts next.
			counted = nil,
			countAt = 0,
			shown = "",
		}
	end

	RunService.RenderStepped:Connect(function(dt)
		local run = tour
		if run == nil then
			return
		end
		local now = os.clock()
		if run.phase == "drawing" then
			if drawn() then
				-- The server's hold starts now, and so does the near view.
				run.hold = StressSite.stepSeconds(workspace:GetAttribute("StressStepSeconds"))
				run.view = run.hold * TOUR_SHARE / 2
				run.phase, run.phaseAt = "near", now
				StressRemote:FireServer(siteId)
			end
		elseif run.phase ~= "done" then
			local elapsed = now - run.phaseAt
			if elapsed >= math.min(SETTLE_SECONDS, run.view / 2) then
				table.insert(run.samples, dt)
				if now >= run.countAt then
					run.countAt = now + COUNT_SECONDS
					run.counted = { drawCounts() }
				end
			end
			if elapsed >= run.view then
				record(run)
				if run.phase == "near" then
					run.phase, run.phaseAt, run.samples, run.counted, run.countAt = "far", now, {}, nil, 0
				elseif run.step >= run.steps then
					finish(run)
					return
				else
					-- Until the server starts the next step.
					run.phase = "done"
				end
			end
		end
		workspace.CurrentCamera.CFrame = if run.phase == "near" or run.phase == "drawing" then run.near else run.far

		local left = math.max(0, math.ceil(run.view - (now - run.phaseAt)))
		local doing = if run.phase == "drawing"
			then "drawing"
			elseif run.phase == "done" then "waiting for the next step"
			else `{run.phase} view, {left} s left`
		if doing ~= run.shown then
			run.shown = doing
			setStressStatus(`{StressSite.name(run.blocks)}, step {run.step} of {run.steps}: {doing}`)
		end
	end)
end

-- State from the server -----------------------------------------------------

StateRemote.OnClientEvent:Connect(function(kind, buf, answers)
	if kind == "timelapse" then
		-- Every block drawn and every chunk near for the ending, so each block can rise on its own.
		drawBacklog(math.huge)
		for c in table.clone(chunkFar) do
			setFar(c, false)
		end
		for _, part in blocks do
			part.Parent = nil
		end
		timelapse = { order = Timelapse.decode(buf), started = os.clock(), shown = 0 }
		return
	elseif kind == "snapshot" then
		local current = workspace:GetAttribute("CurrentSite")
		if current and current ~= siteId then
			-- A new site: its blueprint, index, silhouette and sky.
			resetMirror()
			siteId = current
			bp = loadBlueprint(siteId)
			index = SiteIndex.build(bp, SiteConfig.CHUNK_CELLS)
			measureChunks()
			buildSilhouette()
			placeSkyGlow()
			say(`Next: the {siteName(siteId)}.`)
		end
		resetMirror()
		SiteCodec.decode(buf, function(s, p, r)
			BuildSite.setRemote(mirror, s, p, r)
		end)
		-- The stress tour places the camera first, since the drawing is queued from it.
		stressSnapshot()
		queueSnapshot()
		return
	end
	if buf then
		SiteCodec.decode(buf, function(s, p, r)
			Prediction.receive(pred, s, p, r)
		end)
	end
	for _, answer in answers or {} do
		if answer[2] then
			myPlaced += 1
		end
		Prediction.answer(pred, answer[1], answer[2])
	end
end)

ReadyRemote:FireServer()

-- Every frame ---------------------------------------------------------------

local arcClock, stuckFor = 0, 0

RunService.RenderStepped:Connect(function(dt)
	dropsThisFrame = 0
	stepDust()
	if timelapse then
		-- The ending: reveal blocks in the order they were placed, eased.
		local run = timelapse
		local elapsed = os.clock() - run.started
		local n = Timelapse.shown(elapsed, TIMELAPSE_SECONDS, #run.order)
		for i = run.shown + 1, n do
			local s = run.order[i]
			local part = blocks[s]
			if part then
				part.Parent = blockFolder
				dropIn(part, s)
			end
		end
		run.shown = n
		if elapsed >= TIMELAPSE_SECONDS then
			timelapse = nil
		end
	else
		for s in redrawQueue do
			redraw(s)
		end
		table.clear(redrawQueue)
		drawBacklog(SNAPSHOT_WORK_PER_FRAME)
		local merges = 0
		for c in farDirty do
			if merges >= MERGES_PER_FRAME then
				break
			end
			if chunkFar[c] then
				buildFar(c)
				merges += 1
			else
				farDirty[c] = nil
			end
		end
		local rebuilds = 0
		for c in collisionDirty do
			if rebuilds >= COLLISION_REBUILDS_PER_FRAME then
				break
			end
			if chunkFar[c] then
				collisionDirty[c] = nil
			else
				buildCollision(c)
				rebuilds += 1
			end
		end
	end

	local now = os.clock()
	for s, from in settingFrom do
		local part = blocks[s]
		if part then
			local p = math.clamp(from[1] + from[2] * (now - from[3]), 0, 1)
			part.Transparency = 0.75 - 0.55 * p
		end
	end

	local rx, ry, rz, root = rootCell()

	ghostClock += dt
	if ghostClock >= 0.1 and rx then
		ghostClock = 0
		refreshGhosts(rx, ry, rz)
	end

	local aimed = if holding or UserInputService.MouseEnabled then aimedSlot() else nil
	showAim(aimed)
	shadeGhosts(aimed, now)
	if holding then
		tryPlace(aimed)
	end

	local cooldown = player:GetAttribute("Cooldown") or 0.35
	drawHud(now, math.clamp((now - lastClick) / cooldown, 0, 1))

	-- A block that lands where the character stands moves them clear at once;
	-- a character wedged anywhere it can't stand for 2 seconds is moved too.
	if rx and root then
		local fx, fy, fz = math.floor(rx), math.floor(ry - 0.5), math.floor(rz)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local falling = humanoid and humanoid:GetState() == Enum.HumanoidStateType.Freefall
		local inside = standingAt(fx, fy, fz) or standingAt(fx, fy + 1, fz)
		if not inside and not falling and not Access.canStand(bp, mirror, fx, fy, fz, HEADROOM) then
			stuckFor += dt
		else
			stuckFor = 0
		end
		if inside or stuckFor > 2 then
			stuckFor = 0
			local x, y, z = Access.freeSurface(bp, mirror, rx, ry, rz, 6, HEADROOM)
			if x then
				moveCharacterTo(x, y :: number, z :: number)
			end
		end
		weatherPart.Position = root.Position + Vector3.new(0, 45, 0)
	end

	moveBoss(dt)

	arcClock += dt
	if arcClock >= 0.25 then
		arcClock = 0
		if timelapse == nil then
			updateChunkModes()
		end
		applyArc()
		refreshHud(now)
		Prediction.expire(pred, now, 4)
	end
end)
