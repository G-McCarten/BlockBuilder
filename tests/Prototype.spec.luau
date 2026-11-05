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

local function blockCount(world): number
	local folder = world.realGame:GetService("Workspace"):FindFirstChild("SiteBlocks")
	return if folder then #folder:GetChildren() else -1
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
	Test.equal(hudText(world, player, "Built"), "Laid 0%", "the HUD shows the share laid")
	Test.equal(embers(world, player), 0, "an empty purse")
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
	local blocks = blockCount(world)
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
		if hudText(world, player, "Built") == "Laid 100%" then
			finished = true
			break
		end
	end
	release(world)
	Test.check(finished, `the site was finished: {hudText(world, player, "Built")}`)
	Test.equal(blockCount(world), 5928, "every block drawn")
	for _ = 1, 30 do
		world:step(1 / 60)
	end
	Test.check(string.find(hudText(world, player, "Announce"), "stands", 1, true) ~= nil, "announced")
	for _ = 1, 31 * 60 do
		world:step(1 / 60)
	end
	Test.equal(blockCount(world), 0, "a fresh site after the wait")
	Test.equal(embers(world, player), 0, "with an empty purse")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

return nil
