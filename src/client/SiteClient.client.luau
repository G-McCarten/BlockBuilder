--[[
	SiteClient: draws the graybox site and handles the click, to playtest the
	verb before the Unharvester fork. SiteServer runs the site.

	The client keeps a mirror of the site, fed by SiteRemotes.State, with
	Prediction placing the player's own clicks at once. Blocks are pooled
	Parts that drop in near the camera. READY slots near the player pulse as
	ghosts, and the slot the player would place is outlined. The world follows
	WorldArcConfig as the site rises.

	Controls: click or tap to place, hold to keep placing. Q, the gamepad's X
	or the on-screen button calls the crew (the ABILITY) once its skill is
	bought. The gamepad's R2 places at the screen centre. Keys 1 to 5, or the
	shop's buttons, buy skill levels. Step on a hoist pad to ride up to the
	working height.
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
local BossConfig = require(Shared:WaitForChild("BossConfig"))
local BuildSite = require(Shared:WaitForChild("BuildSite"))
local Prediction = require(Shared:WaitForChild("Prediction"))
local SiteCodec = require(Shared:WaitForChild("SiteCodec"))
local SiteConfig = require(Shared:WaitForChild("SiteConfig"))
local SiteIndex = require(Shared:WaitForChild("SiteIndex"))
local SiteRay = require(Shared:WaitForChild("SiteRay"))
local SkillTuning = require(Shared:WaitForChild("SkillTuning"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldArc = require(Shared:WaitForChild("WorldArc"))
local WorldArcConfig = require(Shared:WaitForChild("WorldArcConfig"))

local remotes = ReplicatedStorage:WaitForChild("SiteRemotes")
local PlaceRemote = remotes:WaitForChild("Place")
local ReadyRemote = remotes:WaitForChild("Ready")
local AbilityRemote = remotes:WaitForChild("Ability")
local BuyRemote = remotes:WaitForChild("Buy")
local StateRemote = remotes:WaitForChild("State")
local BossRemote = remotes:WaitForChild("Boss")
local EventRemote = remotes:WaitForChild("Event")

while workspace:GetAttribute("SiteOrigin") == nil do
	task.wait()
end
local ORIGIN: Vector3 = workspace:GetAttribute("SiteOrigin")
local STUDS = SiteConfig.BLOCK_STUDS
local HEADROOM = SiteConfig.HEADROOM_CELLS
local State = BuildSite.State

local bp = Blueprint.load(require(Shared:WaitForChild("Blueprints"):WaitForChild("WoodcuttersLodge")))
local index = SiteIndex.build(bp, SiteConfig.CHUNK_CELLS)
local found = {}

-- Looks ---------------------------------------------------------------------

local KIND_LOOK = {
	stone = { Color3.fromRGB(150, 152, 160), Enum.Material.Slate },
	timber = { Color3.fromRGB(140, 98, 62), Enum.Material.WoodPlanks },
	thatch = { Color3.fromRGB(198, 172, 108), Enum.Material.Fabric },
}
local FALLBACK_LOOK = { Color3.fromRGB(180, 180, 190), Enum.Material.SmoothPlastic }
local GHOST_COLOR = Color3.fromRGB(170, 215, 255)
local GHOST_RADIUS = 14
local DROP_DISTANCE = 70
local MAX_DROPS_PER_FRAME = 24

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

local function dropIn(part: BasePart, s: number)
	local final = cellCFrame(s)
	local camera = workspace.CurrentCamera
	if dropsThisFrame >= MAX_DROPS_PER_FRAME or (camera.CFrame.Position - final.Position).Magnitude > DROP_DISTANCE then
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

local function redraw(s: number)
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
		part.CanCollide = standing
		if setting then
			settingFrom[s] = { mirror.progress[s], mirror.rate[s], os.clock() }
			part.Transparency = 0.7
			part.CFrame = cellCFrame(s)
		else
			settingFrom[s] = nil
			part.Transparency = if state == State.UNDOING then 0.4 else 0
			if fresh then
				dropIn(part, s)
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

-- Ghosts and aim ------------------------------------------------------------

local ghostFolder = Instance.new("Folder")
ghostFolder.Name = "SiteGhosts"
ghostFolder.Parent = workspace
local ghosts: { [number]: BasePart } = {}
local ghostPool: { BasePart } = {}

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

local function clearAll()
	for s, part in blocks do
		givePart(part)
		blocks[s] = nil
	end
	for s, part in ghosts do
		part.Parent = nil
		table.insert(ghostPool, part)
		ghosts[s] = nil
	end
	table.clear(settingFrom)
	table.clear(redrawQueue)
end

local function resetMirror()
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
local function playTick()
	local now = os.clock()
	chainCount = if now - lastTickAt < 0.6 then math.min(chainCount + 1, 16) else 0
	lastTickAt = now
	local sound = ticks[tickNext]
	tickNext = tickNext % #ticks + 1
	sound.PlaybackSpeed = 1 + 0.035 * chainCount
	sound:Play()
end

-- HUD -----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "SiteHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(240, 245, 255)
	l.TextStrokeTransparency = 0.5
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.Text = ""
	l.Parent = gui
	return l
end

local builtLabel = label("Built", UDim2.fromOffset(300, 26), UDim2.new(0.5, 0, 0, 8), 20)
local announce = label("Announce", UDim2.fromOffset(640, 30), UDim2.new(0.5, 0, 0, 40), 22)
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

local crewButton = Instance.new("TextButton")
crewButton.Name = "Crew"
crewButton.AnchorPoint = Vector2.new(1, 1)
crewButton.Position = UDim2.new(1, -16, 1, -140)
crewButton.Size = UDim2.fromOffset(150, 44)
crewButton.BackgroundColor3 = Color3.fromRGB(46, 70, 110)
crewButton.TextColor3 = Color3.fromRGB(240, 245, 255)
crewButton.Font = Enum.Font.GothamBold
crewButton.TextSize = 18
crewButton.Text = `{Theme.Ability} (Q)`
crewButton.Parent = gui
crewButton.Activated:Connect(function()
	AbilityRemote:FireServer()
end)

-- The skill shop: one button a node, with its level and next price.
local shop = Instance.new("Frame")
shop.Name = "Shop"
shop.AnchorPoint = Vector2.new(0, 0.5)
shop.Position = UDim2.new(0, 12, 0.5, 0)
shop.Size = UDim2.fromOffset(250, #SkillTuning.nodes * 52)
shop.BackgroundTransparency = 1
shop.Parent = gui
local shopButtons: { TextButton } = {}
for i, node in SkillTuning.nodes do
	local button = Instance.new("TextButton")
	button.Name = node.id
	button.Position = UDim2.fromOffset(0, (i - 1) * 52)
	button.Size = UDim2.fromOffset(250, 46)
	button.BackgroundColor3 = Color3.fromRGB(34, 44, 66)
	button.BackgroundTransparency = 0.15
	button.TextColor3 = Color3.fromRGB(235, 240, 250)
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Font = Enum.Font.Gotham
	button.TextSize = 14
	button.TextWrapped = true
	button.Parent = shop
	button.Activated:Connect(function()
		BuyRemote:FireServer(node.id)
	end)
	shopButtons[i] = button
end

local function purse(): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild(Theme.RunCurrency)
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function refreshShop()
	local have = purse()
	for i, node in SkillTuning.nodes do
		local level = player:GetAttribute(`Level_{node.id}`) or 0
		local button = shopButtons[i]
		if level >= node.max then
			button.Text = `  {i}  {node.name}  (max)\n      {node.blurb}`
			button.BackgroundColor3 = Color3.fromRGB(34, 44, 66)
		else
			local price = SkillTuning.price(node, level)
			button.Text = `  {i}  {node.name}  {level}/{node.max}   {price} {Theme.RunCurrency}\n      {node.blurb}`
			button.BackgroundColor3 = if have >= price then Color3.fromRGB(52, 92, 66) else Color3.fromRGB(34, 44, 66)
		end
	end
	crewButton.Visible = (player:GetAttribute(`Level_{SkillTuning.abilityNode}`) or 0) >= 1
end

local function say(text: string)
	announce.Text = text
	announceUntil = os.clock() + 3.5
end

local function capitalise(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- Clicking ------------------------------------------------------------------

local holding = false
local holdPoint: Vector2? = nil
local lastClick = -math.huge
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

local function aimedSlot(): number?
	local rx, ry, rz = rootCell()
	if rx == nil then
		return nil
	end
	local ray = aimRay()
	local ox, oy, oz = toCells(ray.Origin)
	local d = ray.Direction.Unit
	local grasp = player:GetAttribute("Grasp") or SiteConfig.BASE_GRASP_CELLS
	return (SiteRay.cast(bp, mirror, ox, oy, oz, d.X, d.Y, d.Z, 120, rx, ry, rz, grasp))
end

local function tryPlace()
	local now = os.clock()
	local cooldown = player:GetAttribute("Cooldown") or 0.35
	if now - lastClick < cooldown then
		return
	end
	local slot = aimedSlot()
	if slot == nil then
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
	if processed then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		holding, holdPoint = true, nil
		tryPlace()
	elseif kind == Enum.UserInputType.Touch then
		holding, holdPoint = true, Vector2.new(input.Position.X, input.Position.Y)
		tryPlace()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
		AbilityRemote:FireServer()
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
	if holding and input.UserInputType == Enum.UserInputType.Touch then
		holdPoint = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if
		kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
	then
		holding, holdPoint = false, nil
	end
end)

-- Hoist pads ----------------------------------------------------------------

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

-- The world arc -------------------------------------------------------------

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere == nil then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

local snowPart = Instance.new("Part")
snowPart.Name = "Snowfall"
snowPart.Anchored = true
snowPart.CanCollide = false
snowPart.CanQuery = false
snowPart.CanTouch = false
snowPart.Transparency = 1
snowPart.Size = Vector3.new(160, 1, 160)
snowPart.Parent = workspace
local snow = Instance.new("ParticleEmitter")
snow.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
snow.LightEmission = 0.3
snow.Size = NumberSequence.new(0.18)
snow.Lifetime = NumberRange.new(5, 7)
snow.Speed = NumberRange.new(4, 7)
snow.SpreadAngle = Vector2.new(25, 25)
snow.Acceleration = Vector3.new(1.5, -1, 0)
snow.EmissionDirection = Enum.NormalId.Bottom
snow.Rate = 0
snow.Parent = snowPart

local aurora = Instance.new("Part")
aurora.Name = "Aurora"
aurora.Anchored = true
aurora.CanCollide = false
aurora.CanQuery = false
aurora.CanTouch = false
aurora.CastShadow = false
aurora.Material = Enum.Material.Neon
aurora.Size = Vector3.new(600, 30, 2)
aurora.CFrame = CFrame.new(ORIGIN + Vector3.new(bp.sizeX * STUDS / 2, 260, bp.sizeZ * STUDS + 220))
	* CFrame.Angles(math.rad(-20), 0, 0)
aurora.Transparency = 1
aurora.Parent = workspace

local look = {}
local function applyArc()
	WorldArc.at(WorldArcConfig, mirror.placedCount / mirror.count, look)
	Lighting.FogEnd = look.fogEnd
	Lighting.FogColor = Color3.fromRGB(look.fogColor[1], look.fogColor[2], look.fogColor[3])
	Lighting.ClockTime = look.clockTime
	Lighting.Brightness = look.brightness
	-- With an Atmosphere present, it, not Lighting's fog, colours the distance.
	atmosphere.Density = look.density
	atmosphere.Color = Lighting.FogColor
	snow.Rate = look.snow
	aurora.Transparency = 1 - 0.65 * look.aurora
end

-- The boss ------------------------------------------------------------------

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

BossRemote.OnClientEvent:Connect(function(view)
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
		local difficulty = workspace:GetAttribute("Difficulty")
		local tuning = BossConfig[if typeof(difficulty) == "string" then difficulty else "Normal"]
		local radius = if tuning and tuning.peace then tuning.peace.radius else 5
		peaceDisc.Size = Vector3.new(0.4, radius * 2 * STUDS, radius * 2 * STUDS)
		peaceDisc.CFrame = CFrame.new(cellPoint(view.peace[1], 0, view.peace[2]) + Vector3.new(0, 0.3, 0))
			* CFrame.Angles(0, 0, math.pi / 2)
		peaceDisc.Parent = bossFolder
	else
		peaceDisc.Parent = nil
	end
end)

-- Events --------------------------------------------------------------------

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
		elseif kind == "perfect" and e.userId == me then
			playTick()
		elseif kind == "finished" then
			say(`The {Theme.Site.one} stands! A new one starts soon.`)
		end
	end
end)

-- State from the server -----------------------------------------------------

StateRemote.OnClientEvent:Connect(function(kind, buf, answers)
	if kind == "snapshot" then
		resetMirror()
		SiteCodec.decode(buf, function(s, p, r)
			BuildSite.setRemote(mirror, s, p, r)
			markRedraw(s)
		end)
		return
	end
	if buf then
		SiteCodec.decode(buf, function(s, p, r)
			Prediction.receive(pred, s, p, r)
		end)
	end
	for _, answer in answers or {} do
		Prediction.answer(pred, answer[1], answer[2])
	end
end)

ReadyRemote:FireServer()

-- Every frame ---------------------------------------------------------------

local ghostClock, arcClock, stuckFor = 0, 0, 0

RunService.RenderStepped:Connect(function(dt)
	dropsThisFrame = 0
	for s in redrawQueue do
		redraw(s)
	end
	table.clear(redrawQueue)

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
		local n = SiteIndex.within(index, rx, ry, rz, GHOST_RADIUS, function(s)
			return BuildSite.state(mirror, s) == State.READY
		end, found)
		local want = {}
		for i = 1, n do
			want[found[i]] = true
		end
		for s, part in ghosts do
			if not want[s] then
				part.Parent = nil
				table.insert(ghostPool, part)
				ghosts[s] = nil
			end
		end
		for s in want do
			if ghosts[s] == nil then
				local part = ghostPart()
				part.CFrame = cellCFrame(s)
				part.Parent = ghostFolder
				ghosts[s] = part
			end
		end
	end
	local pulse = 0.8 + 0.08 * math.sin(now * 5)
	for _, part in ghosts do
		part.Transparency = pulse
	end

	local aimed = if holding or UserInputService.MouseEnabled then aimedSlot() else nil
	if aimed then
		aimPart.CFrame = cellCFrame(aimed)
		aimBox.Visible = true
	else
		aimBox.Visible = false
	end
	if holding then
		tryPlace()
	end

	local cooldown = player:GetAttribute("Cooldown") or 0.35
	cooldownFill.Size = UDim2.fromScale(math.clamp((now - lastClick) / cooldown, 0, 1), 1)
	builtLabel.Text =
		string.format("%s %d%%", capitalise(Theme.PlaceVerb.past), math.floor(100 * mirror.placedCount / mirror.count))
	if now > announceUntil then
		announce.Text = ""
	end

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
		snowPart.Position = root.Position + Vector3.new(0, 45, 0)
	end

	if bossTarget then
		bossPart.Position = bossPart.Position:Lerp(bossTarget, math.min(1, dt * 6))
	end

	arcClock += dt
	if arcClock >= 0.25 then
		arcClock = 0
		applyArc()
		refreshShop()
		Prediction.expire(pred, now, 4)
	end
end)
