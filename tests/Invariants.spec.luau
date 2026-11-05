--[[
	The section 4.2 invariants that only the whole place can show: no player
	is trapped by a block (5), and the server makes no Instance per block (6).
	docs/invariants.md lists the tests for every invariant.
]]

local roblox = require("@lune/roblox")

local Blueprint = require("../src/shared/Blueprint")
local FakeGroup = require("./lib/FakeGroup")
local FakeRoblox = require("./lib/FakeRoblox")
local PlaceBuilder = require("./lib/PlaceBuilder")
local Test = require("./lib/Test")

local Vector3, CFrame, Ray, Enum = roblox.Vector3, roblox.CFrame, roblox.Ray, roblox.Enum
local STUDS = 3
local ORIGIN = Vector3.new(24, 0, 24)
local CLICK = { UserInputType = Enum.UserInputType.MouseButton1 }

local function boot(attributes: { [string]: any })
	local game = PlaceBuilder.build("default.project.json")
	for name, value in attributes do
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

local function rootOf(world, player)
	return world.reals[player.Character]:FindFirstChild("HumanoidRootPart")
end

-- The cell a character's feet are in. The root stands a cell above the feet.
local function feetCell(root): (number, number, number)
	local p = (root.CFrame.Position - ORIGIN) / STUDS
	return math.floor(p.X), math.floor(p.Y - 0.5), math.floor(p.Z)
end

local function placed(world): number
	return world.realGame:GetService("Workspace"):GetAttribute("SitePlaced") or -1
end

-- A ground slot of the first site that is READY from the start: it has no
-- supports, so laying it needs nothing else laid first.
local function readyGroundSlot(): (number, number)
	local bp = Blueprint.load(require("../src/shared/Blueprints/WoodcuttersLodge") :: any)
	for s = 1, bp.count do
		if bp.y[s] == 0 and bp.supportStart[s] == bp.supportStart[s + 1] and bp.x[s] > 4 and bp.z[s] > 4 then
			return bp.x[s], bp.z[s]
		end
	end
	error("the lodge has no free ground slot")
end

Test.group("Invariants")

Test.case("5: a block laid where a character stands moves them clear", function()
	local world, player = boot({ Difficulty = "None", SetTime = 0.2 })
	local x, z = readyGroundSlot()
	local root = rootOf(world, player)
	root.CFrame = CFrame.new(ORIGIN + Vector3.new(x + 0.5, 1, z + 0.5) * STUDS)
	Test.equal(select(2, feetCell(root)), 0, "the feet start in the slot's cell")
	world.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
	local pivots = world.pivots or 0
	world:input("began", CLICK)
	world:step(1 / 60)
	world:input("ended", CLICK)
	for _ = 1, 60 do
		world:step(1 / 60)
	end
	Test.equal(placed(world), 1, "the block was laid anyway")
	Test.check((world.pivots or 0) > pivots, "the character was moved")
	-- Only that block stands, so a free surface is the ground or its top.
	local fx, fy, fz = feetCell(root)
	local onGround = fy == 0 and not (fx == x and fz == z)
	local onTop = fy == 1 and fx == x and fz == z
	Test.check(onGround or onTop, `now at ({fx}, {fy}, {fz}), the block at ({x}, 0, {z})`)
	Test.equal(#world.errors, 0, table.concat(world.errors, "\n\n"))
end)

Test.case("5: a character wedged where it can't stand is moved after 2 seconds", function()
	local world, player = boot({ Difficulty = "None" })
	local x, z = readyGroundSlot()
	local root = rootOf(world, player)
	-- Feet four cells up with nothing beneath. The stand-in humanoid is never
	-- falling, so this is a character caught where it can't stand.
	root.CFrame = CFrame.new(ORIGIN + Vector3.new(x + 0.5, 5, z + 0.5) * STUDS)
	local pivots = world.pivots or 0
	for _ = 1, 90 do
		world:step(1 / 60)
	end
	Test.equal(world.pivots or 0, pivots, "left alone for 1.5 seconds")
	for _ = 1, 45 do
		world:step(1 / 60)
	end
	Test.check((world.pivots or 0) > pivots, "moved by 2.25 seconds")
	local fx, fy, fz = feetCell(root)
	Test.check(fy == 0 and math.abs(fx - x) <= 1 and math.abs(fz - z) <= 1, `now at ({fx}, {fy}, {fz})`)
	Test.equal(#world.errors, 0, table.concat(world.errors, "\n\n"))
end)

Test.case("6: the server makes no Instance per block", function()
	local game = PlaceBuilder.build("default.project.json")
	local workspace = game:GetService("Workspace")
	for name, value in { Difficulty = "None", Batch = 8, Cooldown = 0.05, Grasp = 40, SetTime = 0.2 } do
		workspace:SetAttribute(name, value)
	end
	local group = FakeGroup.new(game)
	group:start()
	local client = group:addClient(1)
	client.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 40))
	for _ = 1, 10 do
		group:step(1 / 60)
	end
	local before = #group.server.created
	local root = client.reals[client.players.LocalPlayer.Character]:FindFirstChild("HumanoidRootPart")
	client:input("began", CLICK)
	for frame = 1, 600 do
		local x, z = 2 + frame % 30, 4 + (frame // 30) % 20
		root.CFrame = CFrame.new(ORIGIN + Vector3.new(x + 0.5, 2, z - 1) * STUDS)
		client.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
		group:step(1 / 60)
	end
	client:input("ended", CLICK)
	for _ = 1, 60 do
		group:step(1 / 60)
	end
	local laid = workspace:GetAttribute("SitePlaced")
	Test.check(laid > 300, `laid {laid}`)
	local made = #group.server.created - before
	Test.equal(made, 0, `the server made {made} instances while {laid} blocks were laid`)
	Test.equal(#group:errors(), 0, table.concat(group:errors(), "\n\n"))
end)
