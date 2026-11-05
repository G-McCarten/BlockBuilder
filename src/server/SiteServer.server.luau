--[[
	SiteServer: runs one graybox site in a plain place, to playtest the verb
	before the Unharvester fork. Open a new Baseplate place in Studio, serve
	this repo with Rojo, and press Play. SiteClient draws it.

	It builds a site from SiteList beside the spawn and runs it with
	SiteSession: the one named by the workspace's Site attribute, else the
	first. The site in play is in the workspace's CurrentSite attribute.
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
	  Cooldown, Grasp, Batch, SetTime, ChainChance, ChainRadius,
	  PerfectChance, CrewWidth, CrewCooldown
	               override that stat for everyone, read whenever one changes
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Blueprint = require(Shared:WaitForChild("Blueprint"))
local BossBrain = require(Shared:WaitForChild("BossBrain"))
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local BossConfig = require(Shared:WaitForChild("BossConfig"))
local SiteConfig = require(Shared:WaitForChild("SiteConfig"))
local SiteList = require(Shared:WaitForChild("SiteList"))
local SiteSession = require(Shared:WaitForChild("SiteSession"))
local SkillTuning = require(Shared:WaitForChild("SkillTuning"))
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
	pad.Parent = props
	pads[i] = pad
end
props.Parent = workspace

-- Loads site number n of SiteList and fits the ground and pads to it.
local function loadSite(n: number)
	siteNumber = n
	local entry = SiteList[n]
	bp = Blueprint.load(require(blueprints:WaitForChild(entry.id)))
	workspace:SetAttribute("CurrentSite", entry.id)
	pads[1].Position = ORIGIN + Vector3.new(-1.5 * STUDS, 0.2, -1.5 * STUDS)
	pads[2].Position = ORIGIN + Vector3.new((bp.sizeX + 1.5) * STUDS, 0.2, -1.5 * STUDS)
	if ground then
		ground.Size = Vector3.new(bp.sizeX * STUDS + 200, 2, bp.sizeZ * STUDS + 200)
		ground.Position = ORIGIN + Vector3.new(bp.sizeX * STUDS / 2, -1, bp.sizeZ * STUDS / 2)
	end
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

local function join(player: Player)
	-- A run starts from a bare tree and an empty purse.
	levels[player] = {}
	SiteSession.join(session, player.UserId, stats(player))
	pushStats(player)
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

local function start(n: number)
	loadSite(n)
	session = SiteSession.new(bp, nil, function()
		return random:NextNumber()
	end)
	local difficulty = workspace:GetAttribute("Difficulty")
	local tuning = if typeof(difficulty) == "string" then BossConfig[difficulty] else BossConfig.Normal
	if tuning then
		SiteSession.setBoss(session, tuning)
	end
	for _, player in Players:GetPlayers() do
		join(player)
	end
	syncBots()
end

start(chosenSite())

Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
	SiteSession.leave(session, player.UserId)
	answers[player] = nil
	levels[player] = nil
end)

workspace.AttributeChanged:Connect(function(name)
	if name == "BotPlayers" then
		syncBots()
		return
	end
	for _, player in Players:GetPlayers() do
		pushStats(player)
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

	-- This tick's delta, then the answers to this tick's clicks, in one message.
	local delta = SiteSession.takeDelta(session)
	for player, list in answers do
		if delta or #list > 0 then
			-- false, not nil, so the answers after it keep their place.
			StateRemote:FireClient(player, "delta", delta or false, list)
			answers[player] = {}
		end
	end

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
	end
	if resetAt and os.clock() >= resetAt then
		resetAt = nil
		start(siteNumber % #SiteList + 1)
		for _, player in Players:GetPlayers() do
			sendSnapshot(player)
		end
	end
end)
