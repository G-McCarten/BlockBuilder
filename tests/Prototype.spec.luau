local roblox = require("@lune/roblox")

local Blueprint = require("../src/shared/Blueprint")
local BossConfig = require("../src/shared/BossConfig")
local FakeRoblox = require("./lib/FakeRoblox")
local SkillTuning = require("../src/shared/SkillTuning")
local PlaceBuilder = require("./lib/PlaceBuilder")
local Test = require("./lib/Test")
local Theme = require("../src/shared/Theme")

local Vector2, Vector3, CFrame, Ray, Enum = roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Ray, roblox.Enum
local STUDS = 3
local ORIGIN = Vector3.new(24, 0, 24)
-- A phone held sideways, in points.
local PHONE = Vector2.new(844, 390)
-- The first site, which the place starts with: its columns that hold a
-- block, and its ground slots.
local LODGE = Blueprint.load(require("../src/shared/Blueprints/WoodcuttersLodge") :: any)
local COLUMNS: { { number } } = {}
local GROUND: { number } = {}
do
	local seen = {}
	for s = 1, LODGE.count do
		local column = LODGE.x[s] + LODGE.z[s] * LODGE.sizeX
		if not seen[column] then
			seen[column] = true
			table.insert(COLUMNS, { LODGE.x[s], LODGE.z[s] })
		end
		if LODGE.y[s] == 0 then
			table.insert(GROUND, s)
		end
	end
end

-- The column a walk over the first site aims at on a frame: every column
-- once before any again, scattered over the site.
local function sweep(frame: number): (number, number)
	local column = COLUMNS[(frame * 7919) % #COLUMNS + 1]
	return column[1], column[2]
end

-- Boots the place with one player. device "phone" gives the client touch
-- and no mouse, on a phone-sized screen.
local function boot(attributes: { [string]: any }?, device: string?)
	local game = PlaceBuilder.build("default.project.json")
	for name, value in attributes or {} do
		game:GetService("Workspace"):SetAttribute(name, value)
	end
	local world = FakeRoblox.new(game)
	if device == "phone" then
		world.userInput.TouchEnabled = true
		world.userInput.MouseEnabled = false
		world.camera.ViewportSize = PHONE
	end
	world:runScripts("server")
	local player = world:addPlayer(1)
	world:runScripts("client")
	for _ = 1, 10 do
		world:step(1 / 60)
	end
	return world, player
end

local function steps(world, n: number)
	for _ = 1, n do
		world:step(1 / 60)
	end
end

local function errorsOf(world): string
	return table.concat(world.errors, "\n\n")
end

local function realOf(world, proxy)
	return world.reals[proxy]
end

local function embers(world, player): number
	local folder = realOf(world, player):FindFirstChild("leaderstats")
	local value = folder and folder:FindFirstChild("Embers")
	return if value then value.Value else -1
end

-- Blocks drawn one by one, near the camera.
local function blockCount(world): number
	local folder = world.realGame:GetService("Workspace"):FindFirstChild("SiteBlocks")
	return if folder then #folder:GetChildren() else -1
end

-- Merged boxes, far from the camera, and how many cells they cover.
local function farBoxes(world): (number, number)
	local folder = world.realGame:GetService("Workspace"):FindFirstChild("SiteFar")
	local cells = 0
	for _, part in folder:GetChildren() do
		local size = part.Size / STUDS
		cells += math.round(size.X * size.Y * size.Z)
	end
	return #folder:GetChildren(), cells
end

-- Every standing block drawn, near or far.
local function drawnCount(world): number
	local _, cells = farBoxes(world)
	return blockCount(world) + cells
end

local function hudOf(world, player)
	return realOf(world, player):FindFirstChild("PlayerGui"):FindFirstChild("SiteHud")
end

local function hudText(world, player, name: string): string
	return hudOf(world, player):FindFirstChild(name).Text
end

-- A GUI object's place on screen, in pixels, from its Position, Size and
-- AnchorPoint up to the ScreenGui, which fills the viewport: x, y, w, h.
local function rectOf(world, gui): (number, number, number, number)
	if gui:IsA("ScreenGui") then
		local size = world.camera.ViewportSize
		return 0, 0, size.X, size.Y
	end
	local px, py, pw, ph = rectOf(world, gui.Parent)
	local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
	local h = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
	local x = px + gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
	local y = py + gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * h
	return x, y, w, h
end

-- Where Roblox's TouchJump module puts the jump button on a screen this size.
local function jumpRect(screen): (number, number, number, number)
	local small = math.min(screen.X, screen.Y) <= 500
	local size = if small then 70 else 120
	local y = if small then screen.Y - size - 20 else screen.Y - size * 1.75
	return screen.X - (size * 1.5 - 10), y, size, size
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh): boolean
	return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- Whether a GUI object and everything above it in its ScreenGui are visible.
local function shown(gui): boolean
	while not gui:IsA("ScreenGui") do
		if not gui.Visible then
			return false
		end
		gui = gui.Parent
	end
	return true
end

-- Every button in the HUD, shown or not.
local function hudButtons(world, player): { any }
	local list = {}
	for _, d in hudOf(world, player):GetDescendants() do
		if d:IsA("TextButton") then
			table.insert(list, d)
		end
	end
	return list
end

local function sitePlaced(world): number
	return world.realGame:GetService("Workspace"):GetAttribute("SitePlaced") or 0
end

local function capitalise(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- Stands the character in front of cell (x, y, z) and aims at it from above.
local function aimAt(world, player, x: number, y: number, z: number)
	local centre = ORIGIN + Vector3.new(x + 0.5, y + 0.5, z + 0.5) * STUDS
	local root = realOf(world, player.Character):FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(centre + Vector3.new(0, STUDS * 1.5, -STUDS * 1.5))
	local eye = centre + Vector3.new(0, 40, -10)
	world.aimRay = Ray.new(eye, (centre - eye).Unit)
end

-- Stands the character by column (x, z) and aims straight down at it, so
-- the column's top is in reach wherever it is on the site.
local function aimDown(world, player, x: number, z: number)
	local root = realOf(world, player.Character):FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(ORIGIN + Vector3.new(x + 0.5, 1.5, z - 1) * STUDS)
	world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
end

local function hold(world)
	world:input("began", { UserInputType = Enum.UserInputType.MouseButton1 })
end

local function release(world)
	world:input("ended", { UserInputType = Enum.UserInputType.MouseButton1 })
end

local function press(world, key)
	world:input("began", { KeyCode = key })
	world:input("ended", { KeyCode = key })
end

Test.group("Prototype")

Test.case("the server and client boot without errors and build their HUD", function()
	local world, player = boot()
	Test.equal(#world.errors, 0, errorsOf(world))
	Test.check(world.realGame:GetService("ReplicatedStorage"):FindFirstChild("SiteRemotes"), "remotes")
	Test.check(world.realGame:GetService("Workspace"):FindFirstChild("SiteProps"), "hoist pads")
	Test.equal(hudText(world, player, "Built"), "Woodcutter's Lodge: laid 0%", "the HUD shows the site and share laid")
	Test.equal(embers(world, player), 0, "an empty purse")
	local silhouette = world.realGame:GetService("Workspace"):FindFirstChild("SiteSilhouette")
	Test.check(silhouette and #silhouette:GetChildren() > 100, "the finished build's silhouette shows")
	for _ = 1, 20 do
		world:step(1 / 60)
	end
	Test.check(string.find(hudText(world, player, "Hint"), "Click a glowing ghost", 1, true) ~= nil, "the first hint")
end)

Test.case("hints name the buttons of the device in use", function()
	local phone, phonePlayer = boot(nil, "phone")
	for _ = 1, 20 do
		phone:step(1 / 60)
	end
	local words = hudText(phone, phonePlayer, "Hint")
	Test.check(string.find(words, "Tap a glowing ghost", 1, true) ~= nil, `on a phone: {words}`)
	local pad, padPlayer = boot()
	pad:input("began", { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonX })
	for _ = 1, 20 do
		pad:step(1 / 60)
	end
	words = hudText(pad, padPlayer, "Hint")
	Test.check(string.find(words, "press R2", 1, true) ~= nil, `on a gamepad: {words}`)
	Test.equal(#phone.errors + #pad.errors, 0, errorsOf(phone) .. errorsOf(pad))
end)

Test.case("the Site attribute starts any site, and its blocks lay", function()
	local world, player = boot({ Site = "GreatHall", Batch = 30, Cooldown = 0.1 })
	Test.equal(hudText(world, player, "Built"), "Great Hall: laid 0%", "the hall")
	hold(world)
	for frame = 1, 60 do
		local x, z = 3 + (frame * 7) % 60, 7 + (frame * 11) % 27
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		aimAt(world, player, x, 0, z)
		world:step(1 / 60)
	end
	release(world)
	Test.check(drawnCount(world) > 100, `laid {drawnCount(world)} in the hall`)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("holding the mouse over the plinth lays blocks, shown at once and paid", function()
	local world, player = boot()
	hold(world)
	-- A run's base cooldown is 0.75 s (SkillTuning), so stay 0.8 s on each cell.
	for x = 2, 26 do
		aimAt(world, player, x, 0, 4)
		for _ = 1, 48 do
			world:step(1 / 60)
		end
	end
	release(world)
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	Test.equal(#world.errors, 0, errorsOf(world))
	local blocks = drawnCount(world)
	Test.check(blocks >= 24, `the client shows {blocks} blocks`)
	Test.check(embers(world, player) >= blocks, `paid {embers(world, player)} for {blocks}`)
	Test.check(world.sounds >= 24, "a tick a placement")
end)

Test.case("a player buys a skill level with the number keys", function()
	local world, player = boot()
	-- A big batch for a while, to earn the price quickly.
	world.workspaceProxy:SetAttribute("Batch", 20)
	hold(world)
	for x = 2, 31 do
		aimAt(world, player, x, 0, 6)
		for _ = 1, 48 do
			world:step(1 / 60)
		end
	end
	release(world)
	world.workspaceProxy:SetAttribute("Batch", nil)
	world:step(1 / 60)
	local before = embers(world, player)
	local price = SkillTuning.price(SkillTuning.nodes[1], 0)
	Test.check(before >= price, `earned {before}, for a price of {price}`)
	press(world, Enum.KeyCode.One)
	for _ = 1, 5 do
		world:step(1 / 60)
	end
	Test.equal(realOf(world, player):GetAttribute("Level_batch"), 1, "one level of the first skill")
	Test.equal(embers(world, player), before - price, "its price paid")
	press(world, Enum.KeyCode.Q)
	world:step(1 / 60)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the Hard boss rises, binds the site and is drawn without errors", function()
	local world, player = boot({ Difficulty = "Hard", Batch = 60, Grasp = 60, Cooldown = 0.1 })
	hold(world)
	local bound = false
	for frame = 1, 3000 do
		local x, z = sweep(frame)
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		world:step(1 / 60)
		local boss = world.realGame:GetService("Workspace"):FindFirstChild("SiteBoss")
		-- The boss ball plus three bindings at least, once it binds the site.
		if boss and #boss:GetChildren() >= 4 then
			bound = true
			break
		end
	end
	release(world)
	Test.check(bound, `the boss and its bindings were drawn, built {hudText(world, player, "Built")}`)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("a hoist pad lifts the player to the working height", function()
	local world, player = boot({ Batch = 200, Grasp = 40, Cooldown = 0.05, Difficulty = "None" })
	hold(world)
	-- Over the ground slots, long enough to lay them all, so the work has
	-- left the ground.
	for frame = 1, 240 do
		local s = GROUND[(frame * 7919) % #GROUND + 1]
		aimDown(world, player, LODGE.x[s], LODGE.z[s])
		world:step(1 / 60)
	end
	release(world)
	local root = realOf(world, player.Character):FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 1, -1) * STUDS)
	local pivots = world.pivots or 0
	local pad = world.realGame:GetService("Workspace"):FindFirstChild("SiteProps"):FindFirstChild("HoistPad")
	world:touch(world:wrap(pad), world:wrap(root))
	world:step(1 / 60)
	Test.check((world.pivots or 0) > pivots, "lifted")
	Test.check(root.CFrame.Position.Y > ORIGIN.Y + STUDS * 2, `now at {root.CFrame.Position.Y} studs`)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("far chunks draw as merged boxes and come back near without losing a block", function()
	-- A small batch, so the blocks laid stay in a patch at the front corner.
	local world = boot({ Batch = 60, Grasp = 80, Cooldown = 0.05, Difficulty = "None" })
	hold(world)
	for frame = 1, 150 do
		local x, z = (frame * 7) % 31, (frame * 11) % 23
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		world:step(1 / 60)
	end
	release(world)
	-- Look from right above the patch: every chunk of it near.
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(48, 30, 36))
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	local standing = blockCount(world)
	Test.check(standing > 1000, `built {standing}`)
	Test.equal(select(1, farBoxes(world)), 0, "no merged boxes near")

	-- Far away: merged boxes, the same cells.
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 2000))
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	local boxes, cells = farBoxes(world)
	Test.equal(blockCount(world), 0, "no single blocks far away")
	Test.equal(cells, standing, "the boxes cover every standing block")
	Test.check(boxes < standing / 5, `{standing} blocks in {boxes} boxes`)

	-- Back near: single blocks again.
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(48, 30, 36))
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	Test.equal(blockCount(world), standing, "every block drawn singly again")
	Test.equal(select(1, farBoxes(world)), 0, "the boxes are gone")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the power tool swings for players who have it", function()
	local world, player = boot({ PowerTool = true, Difficulty = "None" })
	Test.equal(realOf(world, player):GetAttribute("HasTool"), true, "granted")
	-- Stand at the plinth's front edge, facing in.
	aimAt(world, player, 10, 0, 4)
	world.camera.CFrame = CFrame.lookAt(ORIGIN + Vector3.new(10, 3, 0) * STUDS, ORIGIN + Vector3.new(10, 1, 10) * STUDS)
	press(world, Enum.KeyCode.F)
	for _ = 1, 10 do
		world:step(1 / 60)
	end
	Test.check(drawnCount(world) > 5, `the swing laid {drawnCount(world)}`)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("with Sure Hand, a click at the sky lays the nearest block in reach", function()
	local world, player = boot({ Batch = 20, Difficulty = "None" })
	hold(world)
	for x = 2, 30, 2 do
		aimAt(world, player, x, 0, 8)
		for _ = 1, 48 do
			world:step(1 / 60)
		end
	end
	release(world)
	world.workspaceProxy:SetAttribute("Batch", nil)
	-- The number keys buy the nodes in SkillTuning's order.
	local digits = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	local key
	for i, node in SkillTuning.nodes do
		if node.id == "autoAim" then
			key = digits[i]
		end
	end
	Test.check(key ~= nil, "Sure Hand has a number key")
	press(world, (Enum.KeyCode :: any)[key])
	world:step(1 / 60)
	Test.equal(realOf(world, player):GetAttribute("Level_autoAim"), 1, "bought Sure Hand")
	local before = drawnCount(world)
	aimAt(world, player, 16, 0, 12)
	world.aimRay = Ray.new(ORIGIN + Vector3.new(16, 2, 12) * STUDS, Vector3.new(0, 1, 0))
	hold(world)
	for _ = 1, 50 do
		world:step(1 / 60)
	end
	release(world)
	Test.check(drawnCount(world) > before, `auto-aim laid {drawnCount(world) - before}`)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("bots work the site alongside players, sped up by TestSpeed", function()
	local world = boot({ BotPlayers = 3, TestSpeed = 5, Difficulty = "Hard" })
	local folder = world.realGame:GetService("Workspace"):FindFirstChild("SiteBots")
	Test.equal(#folder:GetChildren(), 3, "three bots drawn")
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 40))
	for _ = 1, 60 * 60 do
		world:step(1 / 60)
	end
	local drawn = drawnCount(world)
	-- Three bots lay a few hundred blocks a minute at real speed.
	Test.check(drawn > 1000, `in a minute at five times speed, bots laid {drawn}`)
	world.workspaceProxy:SetAttribute("BotPlayers", 1)
	world:step(1 / 60)
	Test.equal(#folder:GetChildren(), 1, "one bot after the change")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("pets work for their owner and are drawn", function()
	local world, player = boot({ Pets = 2, AbilityPets = 1, Difficulty = "None" })
	local folder = world.realGame:GetService("Workspace"):FindFirstChild("SitePets")
	aimAt(world, player, 10, 0, 6)
	local abilityUsed = false
	for _ = 1, 25 * 60 do
		world:step(1 / 60)
		if string.find(hudText(world, player, "Announce"), "around you", 1, true) then
			abilityUsed = true
		end
	end
	Test.equal(#folder:GetChildren(), 3, "three pets drawn")
	Test.check(abilityUsed, "the ability pet's timed ability fired")
	Test.check(embers(world, player) > 10, `the pets earned their owner {embers(world, player)}`)
	Test.check(drawnCount(world) > 10, `and laid {drawnCount(world)}`)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("near chunks collide through merged invisible boxes, not their blocks", function()
	local world = boot({ Batch = 400, Grasp = 80, Cooldown = 0.05, Difficulty = "None" })
	hold(world)
	for frame = 1, 60 do
		local x, z = (frame * 7) % 41, (frame * 11) % 28
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		world:step(1 / 60)
	end
	release(world)
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 40))
	for _ = 1, 60 do
		world:step(1 / 60)
	end
	local workspace = world.realGame:GetService("Workspace")
	local blocks = workspace:FindFirstChild("SiteBlocks"):GetChildren()
	local collision = workspace:FindFirstChild("SiteCollision"):GetChildren()
	for _, part in blocks do
		Test.check(not part.CanCollide, "a block part collides on its own")
	end
	local cells = 0
	for _, part in collision do
		Test.check(part.CanCollide and part.Transparency == 1, "collision boxes are solid and invisible")
		local size = part.Size / STUDS
		cells += math.round(size.X * size.Y * size.Z)
	end
	Test.equal(cells, #blocks, "the boxes cover exactly the standing blocks")
	Test.check(#collision < #blocks / 4, `{#blocks} blocks collide through {#collision} boxes`)

	-- Far away, the visual boxes collide and the near boxes go.
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 2000))
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	Test.equal(#workspace:FindFirstChild("SiteCollision"):GetChildren(), 0, "no near collision far away")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("a finished site is announced, then a fresh one replaces it", function()
	local world, player = boot()
	world.workspaceProxy:SetAttribute("Difficulty", "None")
	world.workspaceProxy:SetAttribute("Batch", 400)
	world.workspaceProxy:SetAttribute("Grasp", 80)
	world.workspaceProxy:SetAttribute("Cooldown", 0.05)
	hold(world)
	local finished = false
	for frame = 1, 6000 do
		-- Aim straight down at a different column each frame, over the whole site.
		local x, z = sweep(frame)
		aimDown(world, player, x, z)
		world:step(1 / 60)
		if string.find(hudText(world, player, "Built"), "laid 100%", 1, true) then
			finished = true
			break
		end
	end
	release(world)
	Test.check(finished, `the site was finished: {hudText(world, player, "Built")}`)
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	local summary = hudText(world, player, "Announce")
	Test.check(string.find(summary, "earned 100 Hearthstones", 1, true) ~= nil, `the payout, all of it solo: {summary}`)
	-- The ending: the blocks vanish and rise again over ten seconds.
	local count = LODGE.count
	Test.check(blockCount(world) < count, `the timelapse hides the build first, {blockCount(world)} showing`)
	for _ = 1, 5 * 60 do
		world:step(1 / 60)
	end
	local halfway = blockCount(world)
	Test.check(halfway > count / 6 and halfway < count * 5 / 6, `half way through, {halfway} of {count} showing`)
	for _ = 1, 6 * 60 do
		world:step(1 / 60)
	end
	Test.equal(drawnCount(world), count, "the whole build, risen again")
	for _ = 1, 20 * 60 do
		world:step(1 / 60)
	end
	Test.equal(drawnCount(world), 0, "a fresh site after the wait")
	Test.equal(embers(world, player), 0, "with an empty purse")
	Test.equal(world.realGame:GetService("Workspace"):GetAttribute("CurrentSite"), "IceBridge", "the next site")
	Test.equal(hudText(world, player, "Built"), "Ice Bridge: laid 0%", "the client loaded it")
	local sign = world.realGame:GetService("Workspace"):FindFirstChild("SiteProps"):FindFirstChild("SiteSign")
	local front = sign:FindFirstChild("Board"):FindFirstChild("Front")
	Test.equal(front:FindFirstChild("SiteName").Text, "Ice Bridge", "the sign names the next site")
	Test.equal(
		world.realGame:GetService("Workspace"):GetAttribute("CurrentDifficulty"),
		"None",
		"the next site reads the Difficulty set since"
	)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the hoist pads carry labels, a sign names the site, and the spawn faces it", function()
	local world = boot({ Site = "GreatHall" })
	local workspace = world.realGame:GetService("Workspace")
	local props = workspace:FindFirstChild("SiteProps")
	local pads = 0
	for _, pad in props:GetChildren() do
		if pad.Name == "HoistPad" then
			pads += 1
			local label = pad:FindFirstChild("Label")
			Test.check(label and label:IsA("BillboardGui") and label.Adornee == pad, "a label over each pad")
			Test.equal(label:FindFirstChild("Title").Text, `{capitalise(Theme.Hoist)} pad`, "named from Theme")
		end
	end
	Test.equal(pads, 2, "two pads")
	local board = props:FindFirstChild("SiteSign"):FindFirstChild("Board")
	for _, face in { "Front", "Back" } do
		Test.equal(board:FindFirstChild(face):FindFirstChild("SiteName").Text, "Great Hall", `the {face} names it`)
	end
	for _, part in props:FindFirstChild("SiteSign"):GetChildren() do
		Test.check(not part.CanCollide and not part.CanQuery, "the sign never stops a player or the camera")
	end
	Test.check(board.CFrame.Position.Z < ORIGIN.Z, "the sign stands before the site")
	local spawn = workspace:FindFirstChild("SpawnLocation")
	Test.check(spawn.CFrame.LookVector.Z > 0.99, `the spawn faces the site: {spawn.CFrame.LookVector}`)
	Test.equal(workspace:GetAttribute("CurrentDifficulty"), "Normal", "no Difficulty plays Normal")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case(
	"on a phone, buttons are thumb-sized, crew and tool sit by the jump button, the shop starts folded",
	function()
		local world, player = boot({ Difficulty = "None", PowerTool = true }, "phone")
		-- Shows the crew's button, as buying its skill would.
		player:SetAttribute("Level_crew", 1)
		steps(world, 20)
		local hud = hudOf(world, player)
		local function check(screen)
			local jx, jy, jw, jh = jumpRect(screen)
			for _, name in { "Crew", "Tool" } do
				local b = hud:FindFirstChild(name)
				local x, y, w, h = rectOf(world, b)
				Test.check(shown(b), `{name} shows`)
				Test.check(w >= 44 and h >= 44, `{name} is thumb-sized: {w} by {h}`)
				Test.check(x >= screen.X / 2 and y >= screen.Y / 2, `{name} is in the right thumb's corner: {x}, {y}`)
				Test.check(x + w <= screen.X and y + h <= screen.Y, `{name} is on screen`)
				Test.check(not overlaps(x, y, w, h, jx, jy, jw, jh), `{name} clears the jump button`)
				Test.check(not string.find(b.Text, "(", 1, true), `{name} shows no key on a phone: {b.Text}`)
			end
			local seen = {}
			for _, b in hudButtons(world, player) do
				if shown(b) then
					local x, y, w, h = rectOf(world, b)
					Test.check(w >= 44 and h >= 44, `{b.Name} is thumb-sized: {w} by {h}`)
					for _, other in seen do
						Test.check(not overlaps(x, y, w, h, rectOf(world, other)), `{b.Name} overlaps {other.Name}`)
					end
					table.insert(seen, b)
				end
			end
			Test.check(#seen >= 4, `{#seen} buttons show`)
		end
		check(PHONE)
		-- Taps between buttons land on something that takes input, not the site.
		local barX, barY, barW, barH = rectOf(world, hud:FindFirstChild("ToggleBar"))
		for _, name in { "ShopToggle", "SettingsToggle" } do
			local x, y, w, h = rectOf(world, hud:FindFirstChild(name))
			local inside = x >= barX and y >= barY and x + w <= barX + barW and y + h <= barY + barH
			Test.check(inside, `the bar spans {name}`)
		end
		for _, name in { "ToggleBar", "Shop", "Settings" } do
			Test.check(hud:FindFirstChild(name).Active, `{name} takes input`)
		end
		Test.check(not hud:FindFirstChild("Shop").Visible, "the shop starts folded")
		world:activate(world:wrap(hud:FindFirstChild("ShopToggle")), Enum.UserInputType.Touch)
		Test.check(hud:FindFirstChild("Shop").Visible, "its toggle opens it")
		local _, y, _, h = rectOf(world, hud:FindFirstChild("Shop"))
		Test.check(y + h <= PHONE.Y, "the open shop fits the screen, and scrolls")
		for _, b in hud:FindFirstChild("Shop"):GetChildren() do
			local _, _, bw, bh = rectOf(world, b)
			Test.check(bw >= 44 and bh >= 44, `the shop's {b.Name} is thumb-sized`)
		end
		-- Turned to a tablet: the bigger jump button, and the HUD follows.
		world.camera.ViewportSize = Vector2.new(1024, 768)
		steps(world, 20)
		check(world.camera.ViewportSize)
		Test.equal(#world.errors, 0, errorsOf(world))
	end
)

Test.case("with a mouse, the shop starts open and folds with its toggle", function()
	local world, player = boot()
	local hud = hudOf(world, player)
	local shop, toggle = hud:FindFirstChild("Shop"), hud:FindFirstChild("ShopToggle")
	Test.check(shop.Visible, "open")
	Test.equal(toggle.Text, "Hide shop", "offers to fold")
	world:activate(world:wrap(toggle))
	Test.check(not shop.Visible, "folded")
	Test.equal(toggle.Text, "Shop", "offers to open")
	world:activate(world:wrap(toggle))
	Test.check(shop.Visible, "open again")
	Test.equal(hudText(world, player, "Crew"), `{Theme.Ability} (Q)`, "keys show with a keyboard")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("a click or tap on any button never lays a block", function()
	for _, device in { "pc", "phone" } do
		local world, player = boot({ Difficulty = "None" }, device)
		local touch = device == "phone"
		local kind = if touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
		-- Shows the crew's and tool's buttons; the server grants neither, so
		-- their taps lay nothing themselves.
		player:SetAttribute("Level_crew", 1)
		player:SetAttribute("HasTool", true)
		steps(world, 20)
		aimAt(world, player, 10, 0, 4)
		local buttons = hudButtons(world, player)
		Test.check(#buttons >= 13, `{#buttons} buttons`)
		for _, b in buttons do
			world:activate(world:wrap(b), kind)
			steps(world, 3)
		end
		steps(world, 30)
		Test.equal(sitePlaced(world), 0, `{device}: no button laid a block`)
		Test.equal(drawnCount(world), 0, `{device}: none shows`)
		-- The same input, not taken by a button, lays one.
		world:input("began", { UserInputType = kind })
		steps(world, 10)
		Test.check(sitePlaced(world) >= 1, `{device}: a tap on the world lays`)
		Test.equal(#world.errors, 0, errorsOf(world))
	end
end)

Test.case("on a phone, a hold follows its own finger: the thumbstick neither moves nor ends it", function()
	local world, player = boot({ Difficulty = "None", Cooldown = 0.1 }, "phone")
	local finger = { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(600, 200, 0) }
	local thumb = { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(120, 300, 0) }
	aimAt(world, player, 2, 0, 4)
	world:input("began", finger)
	-- The thumbstick takes its touch, so the game sees it processed.
	world:input("began", thumb, true)
	local atLift = 0
	for x = 2, 20 do
		aimAt(world, player, x, 0, 4)
		thumb.Position = Vector3.new(120 + x, 300, 0)
		world:input("changed", thumb, true)
		steps(world, 12)
		Test.equal(world.screenPoint, Vector2.new(600, 200), "the hold aims where its finger is")
		if x == 8 then
			world:input("ended", thumb, true)
			atLift = sitePlaced(world)
		end
	end
	Test.check(atLift >= 5, `laid {atLift} before the thumb lifted`)
	Test.check(sitePlaced(world) >= atLift + 10, `and {sitePlaced(world) - atLift} after`)
	finger.Position = Vector3.new(640, 210, 0)
	world:input("changed", finger)
	steps(world, 1)
	Test.equal(world.screenPoint, Vector2.new(640, 210), "a moving finger moves its hold")
	world:input("ended", finger)
	steps(world, 2)
	local stopped = sitePlaced(world)
	for x = 2, 12 do
		aimAt(world, player, x, 0, 6)
		steps(world, 12)
	end
	Test.equal(sitePlaced(world), stopped, "lifting the finger ends the hold")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the settings turn sounds and hints off and set how far ghosts show, for the session", function()
	local world, player = boot({ Difficulty = "None" })
	local hud = hudOf(world, player)
	local panel = hud:FindFirstChild("Settings")
	local real = realOf(world, player)
	local function tap(gui)
		world:activate(world:wrap(gui))
		steps(world, 2)
	end
	steps(world, 20)
	Test.check(hudText(world, player, "Hint") ~= "", "a hint shows")
	tap(hud:FindFirstChild("SettingsToggle"))
	Test.check(panel.Visible and not hud:FindFirstChild("Shop").Visible, "the panel opens in the shop's place")

	tap(panel:FindFirstChild("Sounds"))
	Test.equal(panel:FindFirstChild("Sounds").Text, "Sounds: Off", "sounds off")
	Test.equal(real:GetAttribute("SettingSounds"), false, "kept on the player")
	tap(panel:FindFirstChild("Hints"))
	Test.equal(panel:FindFirstChild("Hints").Text, "Hints: Off", "hints off")
	Test.equal(hudText(world, player, "Hint"), "", "the hint showing goes")
	Test.equal(real:GetAttribute("SettingHints"), false, "kept on the player")
	hold(world)
	for x = 2, 10 do
		aimAt(world, player, x, 0, 4)
		steps(world, 48)
		Test.equal(hudText(world, player, "Hint"), "", "and no hint comes")
	end
	release(world)
	Test.check(sitePlaced(world) >= 8, `laid {sitePlaced(world)}`)
	Test.equal(world.sounds, 0, "in silence")

	local ghostFolder = world.realGame:GetService("Workspace"):FindFirstChild("SiteGhosts")
	local radius = panel:FindFirstChild("GhostRadius")
	aimAt(world, player, 20, 0, 12)
	steps(world, 10)
	local medium = #ghostFolder:GetChildren()
	Test.equal(radius.Text, "Ghost radius: Medium", "medium to start")
	tap(radius)
	local large = #ghostFolder:GetChildren()
	Test.equal(radius.Text, "Ghost radius: Large", "then large")
	tap(radius)
	local small = #ghostFolder:GetChildren()
	Test.equal(radius.Text, "Ghost radius: Small", "then small")
	Test.check(small < medium and medium < large, `ghosts: small {small}, medium {medium}, large {large}`)
	Test.equal(real:GetAttribute("SettingGhostRadius"), "Small", "kept on the player")
	tap(radius)
	Test.equal(real:GetAttribute("SettingGhostRadius"), "Medium", "and round to medium")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the aimed slot's ghost shows brighter than the other ghosts", function()
	local world, player = boot({ Difficulty = "None" })
	local ghostFolder = world.realGame:GetService("Workspace"):FindFirstChild("SiteGhosts")
	local function ghostAt(x: number, z: number)
		local centre = ORIGIN + Vector3.new(x + 0.5, 0.5, z + 0.5) * STUDS
		for _, ghost in ghostFolder:GetChildren() do
			if (ghost.CFrame.Position - centre).Magnitude < 0.01 then
				return ghost
			end
		end
		return nil
	end
	aimAt(world, player, 10, 0, 4)
	steps(world, 12)
	local aimed = ghostAt(10, 4)
	Test.check(aimed, "the aimed slot has a ghost")
	local others = 0
	for _, ghost in ghostFolder:GetChildren() do
		if ghost ~= aimed then
			others += 1
			Test.check(ghost.Transparency > aimed.Transparency + 0.2, "brighter than the rest")
		end
	end
	Test.check(others > 10, `{others} other ghosts`)
	aimAt(world, player, 14, 0, 4)
	steps(world, 12)
	Test.check(ghostAt(14, 4).Transparency < 0.6, "the newly aimed one lights")
	Test.check(aimed.Transparency > 0.6 or aimed.Parent == nil, "the old one dims")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("near placements land in a puff of dust, a few a frame, and far ones don't", function()
	local world, player = boot({ Difficulty = "None", Batch = 200, Grasp = 40, Cooldown = 0.05 })
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(10, 6, -4) * STUDS)
	hold(world)
	local most = 0
	for frame = 1, 40 do
		aimAt(world, player, 2 + frame % 20, 0, 4)
		local before = world.puffs
		world:step(1 / 60)
		most = math.max(most, world.puffs - before)
	end
	release(world)
	Test.check(world.puffs > 10, `{world.puffs} puffs`)
	Test.check(world.emits > world.puffs, "of a few particles each")
	Test.check(most <= 3, `at most three a frame, saw {most}`)

	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 2000))
	steps(world, 30)
	local puffs, placed = world.puffs, sitePlaced(world)
	hold(world)
	for frame = 1, 40 do
		aimAt(world, player, 2 + frame % 30, 0, 14)
		world:step(1 / 60)
	end
	release(world)
	steps(world, 5)
	Test.check(sitePlaced(world) > placed, "more laid")
	Test.equal(world.puffs, puffs, "but no dust far from the camera")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the boss wears its name and a faint ring of its shoo radius on the surface under it", function()
	local world, player = boot({ Difficulty = "Hard", Batch = 60, Grasp = 60, Cooldown = 0.1 })
	local folder = world.realGame:GetService("Workspace"):FindFirstChild("SiteBoss")
	hold(world)
	local boss
	for frame = 1, 3000 do
		local x, z = (frame * 7) % 41, (frame * 11) % 28
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		world:step(1 / 60)
		boss = folder:FindFirstChild("Boss")
		if boss then
			break
		end
	end
	release(world)
	Test.check(boss, `the boss rose, built {hudText(world, player, "Built")}`)
	steps(world, 30)
	local label = boss:FindFirstChild("NameLabel")
	Test.check(label and label:IsA("BillboardGui") and label.Adornee == boss, "a label over it")
	Test.equal(label:FindFirstChild("Name").Text, capitalise(Theme.Boss.name), "its name, from Theme")
	local anchor = boss:FindFirstChild("ShooRing")
	local ring = anchor:FindFirstChild("Ring")
	Test.equal(ring.Radius, BossConfig.Hard.shooRadius * STUDS, "the ring's radius is the shoo radius")
	Test.check(ring.Transparency >= 0.4 and ring.InnerRadius > ring.Radius - 1, "a faint, thin ring")
	Test.equal(ring.Adornee, anchor, "drawn on its anchor")
	local at, under = boss.CFrame.Position, anchor.CFrame.Position
	Test.check(math.abs(at.X - under.X) < 0.5 and math.abs(at.Z - under.Z) < 0.5, "the ring follows the boss")
	local surface = (under.Y - 0.08 - ORIGIN.Y) / STUDS
	Test.check(math.abs(surface - math.round(surface)) < 1e-3, `on a block's top or the ground, at {surface} cells`)
	Test.check(under.Y < at.Y + STUDS, "under the boss")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

return nil
