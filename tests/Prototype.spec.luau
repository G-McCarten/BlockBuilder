local roblox = require("@lune/roblox")

local FakeRoblox = require("./lib/FakeRoblox")
local PlaceBuilder = require("./lib/PlaceBuilder")
local Test = require("./lib/Test")

local Vector3, CFrame, Ray, Enum = roblox.Vector3, roblox.CFrame, roblox.Ray, roblox.Enum
local STUDS = 3
local ORIGIN = Vector3.new(24, 0, 24)

local function boot(attributes: { [string]: any }?)
	local game = PlaceBuilder.build("default.project.json")
	for name, value in attributes or {} do
		game:GetService("Workspace"):SetAttribute(name, value)
	end
	local world = FakeRoblox.new(game)
	world:runScripts("server")
	local player = world:addPlayer(1)
	world:runScripts("client")
	for _ = 1, 10 do
		world:step(1 / 60)
	end
	return world, player
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

local function hudText(world, player, name: string): string
	local hud = realOf(world, player):FindFirstChild("PlayerGui"):FindFirstChild("SiteHud")
	return hud:FindFirstChild(name).Text
end

-- Stands the character in front of cell (x, y, z) and aims at it from above.
local function aimAt(world, player, x: number, y: number, z: number)
	local centre = ORIGIN + Vector3.new(x + 0.5, y + 0.5, z + 0.5) * STUDS
	local root = realOf(world, player.Character):FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(centre + Vector3.new(0, STUDS * 1.5, -STUDS * 1.5))
	local eye = centre + Vector3.new(0, 40, -10)
	world.aimRay = Ray.new(eye, (centre - eye).Unit)
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
	world.workspaceProxy:SetAttribute("Batch", 12)
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
	Test.check(before >= 160, `earned {before}`)
	press(world, Enum.KeyCode.One)
	for _ = 1, 5 do
		world:step(1 / 60)
	end
	Test.equal(realOf(world, player):GetAttribute("Level_batch"), 1, "one level of the first skill")
	Test.equal(embers(world, player), before - 160, "its price paid")
	press(world, Enum.KeyCode.Q)
	world:step(1 / 60)
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the Hard boss rises, binds the site and is drawn without errors", function()
	local world, player = boot({ Difficulty = "Hard", Batch = 60, Grasp = 60, Cooldown = 0.1 })
	hold(world)
	local bound = false
	for frame = 1, 3000 do
		local x, z = (frame * 7) % 41, (frame * 11) % 28
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
	for frame = 1, 120 do
		local x, z = (frame * 7) % 41, (frame * 11) % 28
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
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
	local world = boot({ Batch = 400, Grasp = 80, Cooldown = 0.05, Difficulty = "None" })
	hold(world)
	for frame = 1, 90 do
		local x, z = (frame * 7) % 41, (frame * 11) % 28
		world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		world:step(1 / 60)
	end
	release(world)
	-- Look from right above the site: every chunk near.
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 40))
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	local standing = blockCount(world)
	Test.check(standing > 2000, `built {standing}`)
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
	world.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 40))
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
	press(world, Enum.KeyCode.Six)
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
	Test.check(drawn > 1500, `in a minute at five times speed, bots laid {drawn}`)
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
	for frame = 1, 4000 do
		-- Aim straight down at a different column each frame, over the whole site.
		local x, z = (frame * 7) % 41, (frame * 11) % 28
		local top = ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS
		world.aimRay = Ray.new(top, Vector3.new(0, -1, 0))
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
	Test.check(blockCount(world) < 5928, `the timelapse hides the build first, {blockCount(world)} showing`)
	for _ = 1, 5 * 60 do
		world:step(1 / 60)
	end
	local halfway = blockCount(world)
	Test.check(halfway > 1000 and halfway < 5000, `half way through, {halfway} showing`)
	for _ = 1, 6 * 60 do
		world:step(1 / 60)
	end
	Test.equal(drawnCount(world), 5928, "the whole build, risen again")
	for _ = 1, 20 * 60 do
		world:step(1 / 60)
	end
	Test.equal(drawnCount(world), 0, "a fresh site after the wait")
	Test.equal(embers(world, player), 0, "with an empty purse")
	Test.equal(world.realGame:GetService("Workspace"):GetAttribute("CurrentSite"), "IceBridge", "the next site")
	Test.equal(hudText(world, player, "Built"), "Ice Bridge: laid 0%", "the client loaded it")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

return nil
