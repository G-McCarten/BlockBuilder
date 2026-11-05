--[[
	SiteServer: runs one graybox site in a plain place, to playtest the verb
	before the Unharvester fork. Open a new Baseplate place in Studio, serve
	this repo with Rojo, and press Play. SiteClient draws it.

	It builds a site from SiteList beside the spawn and runs it with
	SiteSession: the one named by the workspace's Site attribute, else the
	first. The site in play is in the workspace's CurrentSite attribute, and
	its difficulty in CurrentDifficulty. A sign before the site names it, the
	hoist pads carry labels, and the spawn faces the site.
	Clicks arrive on SiteRemotes.Place. Each tick, the delta goes
	out on SiteRemotes.State with the answers to that tick's clicks after it,
	which is the order Prediction needs. The boss's view goes out on
	SiteRemotes.Boss, events on SiteRemotes.Event. A finished site sends its
	placement order for the ending's timelapse, and after RESET_SECONDS the
	next site in SiteList starts, as finishing one unlocks the next.

	Players start each site with a bare skill tree and an empty purse, earn
	run currency for every first placement, and buy skill levels from
	SkillTuning on SiteRemotes.Buy. The ABILITY unlocks with its node.

	Workspace attributes tune it while it runs:

	  Difficulty   None, Normal, Hard or Nightmare, read when a site starts
	  Site         a SiteList id to start at, read when the server starts
	  PowerTool    true gives everyone the POWER_TOOL, swung on
	               SiteRemotes.Tool, as its game pass will
	  BotPlayers   how many bots (BotBrain) work the site alongside players,
	               each drawn as a stand-in everyone can see
	  TestSpeed    1 to 5, how many times faster than real time the site runs
	  Pets         how many pets (SkillTuning.pet) each player brings, drawn
	               as stand-ins that ignore collision, read when they join
	  AbilityPets  how many pets with a timed ability (SkillTuning.abilityPet)
	               each player brings, read when they join
	  Cooldown, Grasp, Batch, SetTime, ChainChance, ChainRadius,
	  PerfectChance, CrewWidth, CrewCooldown
	               override that stat for everyone, read whenever one changes
	  StressTest   plays a generated site (StressSite) instead, for the
	               renderer's stress test, read when a site starts: a number
	               of blocks from 1,000 to 65,535, or "Ladder" to step
	               through StressSite.LADDER, or a list of sizes such as
	               "30000, 35000" to step through those. CurrentSite names it
	               Stress:<blocks>, and clients build the same blueprint from
	               that. Everything below its top layer is laid at once, and
	               the boss is off.
	  StressStepSeconds
	               how long each ladder step holds, 20 if unset, counted from
	               when a client says on SiteRemotes.Stress that it has drawn
	               the step. While a ladder runs, the server sets StressStep
	               and StressSteps to the step in play and how many there are.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Blueprint = require(Shared:WaitForChild("Blueprint"))
local BossBrain = require(Shared:WaitForChild("BossBrain"))
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local BossConfig = require(Shared:WaitForChild("BossConfig"))
local BuildSite = require(Shared:WaitForChild("BuildSite"))
local SiteConfig = require(Shared:WaitForChild("SiteConfig"))
local SiteList = require(Shared:WaitForChild("SiteList"))
local SiteSession = require(Shared:WaitForChild("SiteSession"))
local SkillTuning = require(Shared:WaitForChild("SkillTuning"))
local StressSite = require(Shared:WaitForChild("StressSite"))
local Theme = require(Shared:WaitForChild("Theme"))
local Timelapse = require(Shared:WaitForChild("Timelapse"))

local STUDS = SiteConfig.BLOCK_STUDS
local RESET_SECONDS = 30

-- The site sits beside the spawn, on the baseplate's top.
local function groundTop(): number
	local base = workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") then
		return base.Position.Y + base.Size.Y / 2
	end
	return 0
end
local ORIGIN = Vector3.new(24, groundTop(), 24)

local blueprints = Shared:WaitForChild("Blueprints")
local bp
local siteNumber = 1

local ground: BasePart? = nil
if not workspace:FindFirstChild("Baseplate") then
	local part = Instance.new("Part")
	part.Name = "SiteGround"
	part.Anchored = true
	part.Color = Color3.fromRGB(235, 240, 245)
	part.Material = Enum.Material.Snow
	part.Parent = workspace
	ground = part
end

-- Players arrive facing the site, and so its sign.
local spawnPad = workspace:FindFirstChild("SpawnLocation")
if spawnPad and spawnPad:IsA("BasePart") and spawnPad.Position.Z < ORIGIN.Z then
	local at = spawnPad.Position
	spawnPad.CFrame = CFrame.lookAt(at, Vector3.new(at.X, at.Y, ORIGIN.Z))
end

local function capitalise(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- A title and a line of help over a prop, the same size on screen at any distance.
local function hoverLabel(adornee: BasePart, title: string, detail: string, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(190, 52)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	billboard.Parent = adornee
	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.Size = UDim2.fromScale(1, 0.6)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 22
	heading.TextColor3 = Color3.fromRGB(235, 245, 255)
	heading.TextStrokeTransparency = 0.4
	heading.Text = title
	heading.Parent = billboard
	local line = Instance.new("TextLabel")
	line.Name = "Detail"
	line.Position = UDim2.fromScale(0, 0.6)
	line.Size = UDim2.fromScale(1, 0.4)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.Gotham
	line.TextSize = 15
	line.TextColor3 = Color3.fromRGB(210, 230, 250)
	line.TextStrokeTransparency = 0.5
	line.Text = detail
	line.Parent = billboard
end

-- Hoist pads at the front corners; SiteClient lifts whoever steps on one.
local props = Instance.new("Folder")
props.Name = "SiteProps"
local pads = {}
for i = 1, 2 do
	local pad = Instance.new("Part")
	pad.Name = "HoistPad"
	pad.Anchored = true
	pad.Size = Vector3.new(STUDS * 1.6, 0.4, STUDS * 1.6)
	pad.Color = Color3.fromRGB(120, 190, 255)
	pad.Material = Enum.Material.Neon
	hoverLabel(pad, `{capitalise(Theme.Hoist)} pad`, "Step on to ride up", 3)
	pad.Parent = props
	pads[i] = pad
end

-- A sign before the site's front, naming the site in play: a board on two
-- posts, high enough to walk under. None of it collides or stops the camera.
local SIGN_SIZE = Vector3.new(22, 4.5, 0.6)
local SIGN_HEIGHT = 9.5
local sign = Instance.new("Model")
sign.Name = "SiteSign"
local function signPart(name: string, size: Vector3, material: Enum.Material, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = sign
	return part
end
local board = signPart("Board", SIGN_SIZE, Enum.Material.WoodPlanks, Color3.fromRGB(110, 78, 52))
local postSize = Vector3.new(0.8, SIGN_HEIGHT + SIGN_SIZE.Y / 2, 0.8)
local signPosts = {
	signPart("Post", postSize, Enum.Material.Wood, Color3.fromRGB(86, 60, 40)),
	signPart("Post", postSize, Enum.Material.Wood, Color3.fromRGB(86, 60, 40)),
}
-- The name on both faces, so it reads from the spawn and from the site.
local signNames: { TextLabel } = {}
for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
	local surface = Instance.new("SurfaceGui")
	surface.Name = face.Name
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = board
	local text = Instance.new("TextLabel")
	text.Name = "SiteName"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 226, 160)
	text.Parent = surface
	table.insert(signNames, text)
end
sign.Parent = props
props.Parent = workspace

-- Fits the ground, pads and sign to bp, the site in play, which the sign names.
local function fitSite(name: string)
	pads[1].Position = ORIGIN + Vector3.new(-1.5 * STUDS, 0.2, -1.5 * STUDS)
	pads[2].Position = ORIGIN + Vector3.new((bp.sizeX + 1.5) * STUDS, 0.2, -1.5 * STUDS)
	-- In line with the spawn where the site is wide enough, else at its middle.
	local width = bp.sizeX * STUDS
	local left, right = ORIGIN.X + SIGN_SIZE.X / 2, ORIGIN.X + width - SIGN_SIZE.X / 2
	local along = if spawnPad then spawnPad.Position.X else ORIGIN.X + width / 2
	local x = if left <= right then math.clamp(along, left, right) else ORIGIN.X + width / 2
	local z = ORIGIN.Z - 2.5 * STUDS
	board.Position = Vector3.new(x, ORIGIN.Y + SIGN_HEIGHT, z)
	for i, post in signPosts do
		local side = if i == 1 then -1 else 1
		post.Position = Vector3.new(x + side * (SIGN_SIZE.X / 2 - 0.4), ORIGIN.Y + postSize.Y / 2, z)
	end
	for _, text in signNames do
		text.Text = name
	end
	if ground then
		ground.Size = Vector3.new(bp.sizeX * STUDS + 200, 2, bp.sizeZ * STUDS + 200)
		ground.Position = ORIGIN + Vector3.new(bp.sizeX * STUDS / 2, -1, bp.sizeZ * STUDS / 2)
	end
end

-- Loads site number n of SiteList.
local function loadSite(n: number)
	local entry = SiteList[n]
	bp = Blueprint.load(require(blueprints:WaitForChild(entry.id)))
	workspace:SetAttribute("CurrentSite", entry.id)
	fitSite(entry.name)
end

-- Builds the stress site of count blocks. Clients build the same blueprint
-- from the count in its id, so none crosses the network.
local function loadStress(count: number)
	bp = Blueprint.build(StressSite.source(count))
	workspace:SetAttribute("CurrentSite", StressSite.id(count))
	fitSite(StressSite.name(count))
end

local function chosenSite(): number
	local wanted = workspace:GetAttribute("Site")
	for i, entry in SiteList do
		if entry.id == wanted then
			return i
		end
	end
	return 1
end

-- Remotes, all made before the folder is published so clients find them.
local remotes = Instance.new("Folder")
remotes.Name = "SiteRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local PlaceRemote = remote("Place")
local ReadyRemote = remote("Ready")
local AbilityRemote = remote("Ability")
local BuyRemote = remote("Buy")
local ToolRemote = remote("Tool")
local StateRemote = remote("State")
local BossRemote = remote("Boss")
local EventRemote = remote("Event")
local StressRemote = remote("Stress")
workspace:SetAttribute("SiteOrigin", ORIGIN)
remotes.Parent = ReplicatedStorage

local botFolder = Instance.new("Folder")
botFolder.Name = "SiteBots"
botFolder.Parent = workspace
local bots: { { bot: any, part: BasePart } } = {}

local random = Random.new()
local session
local answers: { [Player]: { any } } = {}
local resetAt: number? = nil

local levels: { [Player]: { [string]: number } } = {}

-- Workspace attributes that override a stat, and the stat each sets.
local OVERRIDES = {
	Cooldown = "cooldown",
	Grasp = "grasp",
	Batch = "batch",
	SetTime = "setTime",
	ChainChance = "chainChance",
	ChainRadius = "chainRadius",
	PerfectChance = "perfectChance",
	CrewWidth = "crewWidth",
	CrewCooldown = "crewCooldown",
}

local function stats(player: Player)
	local s = SkillTuning.stats(levels[player] or {})
	for attribute, stat in OVERRIDES do
		local value = workspace:GetAttribute(attribute)
		if typeof(value) == "number" then
			s[stat] = value
		end
	end
	return s
end

-- The POWER_TOOL's stats, for players who have it.
local function toolFor(_player: Player)
	return if workspace:GetAttribute("PowerTool") == true then SkillTuning.tool else nil
end

local function pushStats(player: Player)
	local s = stats(player)
	local tool = toolFor(player)
	SiteSession.setStats(session, player.UserId, s, tool)
	player:SetAttribute("HasTool", tool ~= nil)
	player:SetAttribute("Cooldown", s.cooldown)
	player:SetAttribute("Grasp", s.grasp)
	for _, node in SkillTuning.nodes do
		player:SetAttribute(`Level_{node.id}`, (levels[player] or {})[node.id] or 0)
	end
end

local function currencyValue(player: Player): IntValue
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local value = folder:FindFirstChild(Theme.RunCurrency)
	if value == nil then
		value = Instance.new("IntValue")
		value.Name = Theme.RunCurrency
		value.Parent = folder
	end
	return value :: IntValue
end

local petFolder = Instance.new("Folder")
petFolder.Name = "SitePets"
petFolder.Parent = workspace
local petParts: { [number]: BasePart } = {}

local function join(player: Player)
	-- A run starts from a bare tree and an empty purse.
	levels[player] = {}
	SiteSession.join(session, player.UserId, stats(player))
	pushStats(player)
	for attribute, petStats in { Pets = SkillTuning.pet, AbilityPets = SkillTuning.abilityPet } do
		local count = workspace:GetAttribute(attribute)
		for _ = 1, if typeof(count) == "number" then math.clamp(math.floor(count), 0, 4) else 0 do
			SiteSession.addPet(session, player.UserId, petStats)
		end
	end
	answers[player] = {}
	currencyValue(player).Value = 0
end

-- Bots work the site with negative ids, so they never meet a real UserId.
local function syncBots()
	for _, entry in bots do
		SiteSession.leave(session, entry.bot.id)
		entry.part:Destroy()
	end
	table.clear(bots)
	local wanted = workspace:GetAttribute("BotPlayers")
	local count = if typeof(wanted) == "number" then math.clamp(math.floor(wanted), 0, 8) else 0
	for i = 1, count do
		local id = -i
		local bot = BotBrain.new(session, id, bp.sizeX * i / (count + 1), 1, -2)
		SiteSession.join(session, id, SkillTuning.stats(bot.levels), toolFor(nil :: any))
		local part = Instance.new("Part")
		part.Name = `Bot{i}`
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Size = Vector3.new(2, 5, 2)
		part.Color = Color3.fromRGB(255, 170, 90)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = botFolder
		table.insert(bots, { bot = bot, part = part })
	end
end

local function sendSnapshot(player: Player)
	StateRemote:FireClient(player, "snapshot", SiteSession.snapshot(session), {})
	BossRemote:FireClient(player, if session.boss then BossBrain.view(session.boss) else nil)
end

-- The stress test: the size of the stress site in play, nil for a SiteList
-- site; while a ladder runs, its sizes and the step in play; and when that
-- step's hold ends, once a client has drawn it.
local stressCount: number? = nil
local ladder: { number }? = nil
local ladderStep = 0
local holdUntil: number? = nil

-- Reads StressTest as a site starts: the stress site's size, or nil. A
-- ladder starts at its first step and keeps its place until it's done.
local function stressSize(): number?
	local sizes, isLadder = StressSite.plan(workspace:GetAttribute("StressTest"))
	if sizes == nil or not isLadder then
		ladder = nil
		return if sizes then sizes[1] else nil
	end
	if ladder == nil then
		ladder, ladderStep = sizes, 1
	end
	return (ladder :: { number })[ladderStep]
end

-- Lays everything below the stress site's top layer at once, paying no
-- one, and leaves it out of the next delta: the snapshot each player is
-- sent carries it.
local function layStress()
	local site = session.site
	local onPlaced = site.onPlaced
	site.onPlaced = nil
	for _, s in StressSite.layOrder(bp) do
		BuildSite.place(site, s, BuildSite.Cause.NONE, 0)
	end
	site.onPlaced = onPlaced
	SiteSession.takeDelta(session)
end

-- Starts site number n of SiteList, unless StressTest asks for a stress
-- site, which keeps n for when the stress test ends.
local function start(n: number)
	siteNumber = n
	resetAt, holdUntil = nil, nil
	stressCount = stressSize()
	if stressCount then
		loadStress(stressCount)
	else
		loadSite(n)
	end
	workspace:SetAttribute("StressStep", if ladder then ladderStep else nil)
	workspace:SetAttribute("StressSteps", if ladder then #ladder else nil)
	session = SiteSession.new(bp, nil, function()
		return random:NextNumber()
	end)
	-- A stress site plays without the boss.
	local difficulty = workspace:GetAttribute("Difficulty")
	local tuning = if stressCount
		then nil
		elseif typeof(difficulty) == "string" then BossConfig[difficulty]
		else BossConfig.Normal
	if tuning then
		SiteSession.setBoss(session, tuning)
	end
	-- Difficulty is read only here, so clients learn the one in play from this.
	workspace:SetAttribute(
		"CurrentDifficulty",
		if tuning == nil then "None" elseif typeof(difficulty) == "string" then difficulty else "Normal"
	)
	if stressCount then
		layStress()
	end
	for _, player in Players:GetPlayers() do
		join(player)
	end
	syncBots()
end

start(chosenSite())

-- A ladder step's hold is over: the next step starts, or the ladder is
-- done and its last site stays in play.
local function nextStep()
	local steps = ladder
	if steps and ladderStep < #steps then
		ladderStep += 1
		start(siteNumber)
		for _, player in Players:GetPlayers() do
			sendSnapshot(player)
		end
	else
		ladder = nil
		workspace:SetAttribute("StressStep", nil)
		workspace:SetAttribute("StressSteps", nil)
	end
end

Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
	SiteSession.leave(session, player.UserId)
	answers[player] = nil
	levels[player] = nil
end)

-- Only the attributes that change a stat push stats; SitePlaced changes every tick.
workspace.AttributeChanged:Connect(function(name)
	if name == "BotPlayers" then
		syncBots()
	elseif OVERRIDES[name] or name == "PowerTool" then
		for _, player in Players:GetPlayers() do
			pushStats(player)
		end
	end
end)

local function updatePosition(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local p = (root.Position - ORIGIN) / STUDS
		SiteSession.move(session, player.UserId, p.X, p.Y, p.Z)
	end
end

ReadyRemote.OnServerEvent:Connect(sendSnapshot)

-- A client has drawn the ladder step in play, named by its id: the step's
-- hold starts now. The first to say so starts it.
StressRemote.OnServerEvent:Connect(function(_player, id)
	if ladder and holdUntil == nil and id == workspace:GetAttribute("CurrentSite") then
		holdUntil = os.clock() + StressSite.stepSeconds(workspace:GetAttribute("StressStepSeconds"))
	end
end)

PlaceRemote.OnServerEvent:Connect(function(player, id, slot)
	local list = answers[player]
	if list == nil or typeof(id) ~= "number" or typeof(slot) ~= "number" then
		return
	end
	updatePosition(player)
	local ok = SiteSession.request(session, player.UserId, slot)
	table.insert(list, { id, ok })
end)

AbilityRemote.OnServerEvent:Connect(function(player)
	local mine = levels[player]
	if mine == nil or (mine[SkillTuning.abilityNode] or 0) < 1 then
		return
	end
	updatePosition(player)
	SiteSession.useAbility(session, player.UserId)
end)

ToolRemote.OnServerEvent:Connect(function(player, fx, fz)
	if typeof(fx) ~= "number" or typeof(fz) ~= "number" or fx ~= fx or fz ~= fz then
		return
	end
	updatePosition(player)
	SiteSession.useTool(session, player.UserId, fx, fz)
end)

BuyRemote.OnServerEvent:Connect(function(player, nodeId)
	local mine = levels[player]
	local worker = session.workers[player.UserId]
	if mine == nil or worker == nil or typeof(nodeId) ~= "string" then
		return
	end
	for _, node in SkillTuning.nodes do
		if node.id == nodeId then
			local level = mine[node.id] or 0
			local price = SkillTuning.price(node, level)
			if level < node.max and worker.purse >= price then
				worker.purse -= price
				mine[node.id] = level + 1
				pushStats(player)
			end
			return
		end
	end
end)

local bossClock = 0
-- Which pets this tick found, kept between ticks so no table is made per tick.
local alive: { [number]: boolean } = {}
RunService.Heartbeat:Connect(function(dt)
	local speed = workspace:GetAttribute("TestSpeed")
	dt = math.min(dt, 0.1) * (if typeof(speed) == "number" then math.clamp(speed, 1, 5) else 1)
	for _, player in Players:GetPlayers() do
		updatePosition(player)
	end
	local hasTool = workspace:GetAttribute("PowerTool") == true
	for _, entry in bots do
		local bot = entry.bot
		BotBrain.step(bot, session, SkillTuning, dt, hasTool)
		entry.part.Position = ORIGIN + Vector3.new(bot.x, bot.y, bot.z) * STUDS
	end
	SiteSession.step(session, dt)

	-- Pets' stand-ins follow them; a pet gone with its owner takes its part.
	table.clear(alive)
	for _, pet in session.pets do
		alive[pet.id] = true
		local part = petParts[pet.id]
		if part == nil then
			part = Instance.new("Part")
			part.Name = `Pet{pet.id}`
			part.Shape = Enum.PartType.Ball
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Size = Vector3.one * 1.6
			part.Color = Color3.fromRGB(255, 214, 140)
			part.Material = Enum.Material.Neon
			part.Parent = petFolder
			petParts[pet.id] = part
		end
		part.Position = ORIGIN + Vector3.new(pet.x, pet.y, pet.z) * STUDS
	end
	for id, part in petParts do
		if not alive[id] then
			part:Destroy()
			petParts[id] = nil
		end
	end

	-- This tick's delta, then the answers to this tick's clicks, in one message.
	local delta = SiteSession.takeDelta(session)
	for player, list in answers do
		if delta or #list > 0 then
			-- false, not nil, so the answers after it keep their place.
			StateRemote:FireClient(player, "delta", delta or false, list)
			answers[player] = {}
		end
	end

	-- For debugging in Studio, and for tests: how many blocks stand.
	workspace:SetAttribute("SitePlaced", session.site.placedCount)

	local events = SiteSession.takeEvents(session)
	if #events > 0 then
		EventRemote:FireAllClients(events)
	end

	for _, player in Players:GetPlayers() do
		local worker = session.workers[player.UserId]
		if worker then
			currencyValue(player).Value = math.floor(worker.purse)
		end
	end

	bossClock += dt
	if bossClock >= 0.2 then
		bossClock = 0
		BossRemote:FireAllClients(if session.boss then BossBrain.view(session.boss) else nil)
	end

	if session.finished and resetAt == nil then
		resetAt = os.clock() + RESET_SECONDS
		-- The ending: the build rises again, in the order it was placed.
		StateRemote:FireAllClients("timelapse", Timelapse.encode(Timelapse.order(session.site)), false)
		-- Each player's share of the site's payout, by blocks placed, and
		-- what they did; the meta would bank it and feed tasks from it.
		local shares = SiteSession.shares(session)
		local payout = if stressCount then 0 else SiteList[siteNumber].payout or 0
		for _, player in Players:GetPlayers() do
			local counts = SiteSession.counts(session, player.UserId)
			EventRemote:FireClient(player, {
				{
					kind = "payout",
					userId = player.UserId,
					amount = math.floor(payout * (shares[player.UserId] or 0) + 0.5),
					placed = counts.placed,
					shooed = counts.boss_shooed or 0,
				},
			})
		end
	end
	if resetAt and os.clock() >= resetAt then
		resetAt = nil
		-- A finished stress site plays again; otherwise the next site starts.
		start(if stressCount then siteNumber else siteNumber % #SiteList + 1)
		for _, player in Players:GetPlayers() do
			sendSnapshot(player)
		end
	end
	if holdUntil and os.clock() >= holdUntil then
		holdUntil = nil
		nextStep()
	end
end)
