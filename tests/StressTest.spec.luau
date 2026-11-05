--[[
	The prototype's stress test, under FakeRoblox: a StressTest site boots,
	lays all but its top layer and draws it, the readout shows what's drawn,
	and a ladder tours each step, moves on after StressStepSeconds and ends
	with its table. Frames here all take 1/60 s, so the times it prints say
	nothing of Studio's.
]]

local roblox = require("@lune/roblox")

local Blueprint = require("../src/shared/Blueprint")
local FakeRoblox = require("./lib/FakeRoblox")
local PlaceBuilder = require("./lib/PlaceBuilder")
local StressSite = require("../src/shared/StressSite")
local Test = require("./lib/Test")

local Vector3, CFrame, Ray, Enum = roblox.Vector3, roblox.CFrame, roblox.Ray, roblox.Enum
local STUDS = 3
local ORIGIN = Vector3.new(24, 0, 24)

-- Boots the place with one player, keeping what the scripts print.
local function boot(attributes: { [string]: any })
	local game = PlaceBuilder.build("default.project.json")
	for name, value in attributes do
		game:GetService("Workspace"):SetAttribute(name, value)
	end
	local world = FakeRoblox.new(game)
	world:buildGlobals()
	local printed = {}
	world.globals.print = function(...)
		table.insert(printed, table.concat(table.pack(...) :: any, " "))
	end
	world.printed = printed
	world:runScripts("server")
	local player = world:addPlayer(1)
	world:runScripts("client")
	world:step(1 / 60)
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

local function workspaceOf(world)
	return world.realGame:GetService("Workspace")
end

local function children(world, name: string): number
	local folder = workspaceOf(world):FindFirstChild(name)
	return if folder then #folder:GetChildren() else -1
end

-- Every standing block drawn: near ones one by one, far ones in merged boxes.
local function drawnCount(world): number
	local cells = 0
	for _, part in workspaceOf(world):FindFirstChild("SiteFar"):GetChildren() do
		local size = part.Size / STUDS
		cells += math.round(size.X * size.Y * size.Z)
	end
	return children(world, "SiteBlocks") + cells
end

local function stressGui(world, player)
	return world.reals[player]:FindFirstChild("PlayerGui"):FindFirstChild("SiteStress")
end

local function readoutText(world, player): string
	return stressGui(world, player):FindFirstChild("Readout").Text
end

local function press(world, key)
	world:input("began", { KeyCode = key })
	world:input("ended", { KeyCode = key })
end

-- The camera's place in the site's cells.
local function cameraCell(world): Vector3
	return (world.camera.CFrame.Position - ORIGIN) / STUDS
end

-- Steps until done() says so, up to limit frames. Returns the frames taken.
local function until_(world, limit: number, done: () -> boolean): number
	for frame = 1, limit do
		if done() then
			return frame - 1
		end
		world:step(1 / 60)
	end
	return limit
end

Test.group("StressTest")

Test.case("StressTest = 5000 lays all but the top layer and draws it, near and far", function()
	local world = boot({ StressTest = 5000, Site = "GreatHall" })
	local ws = workspaceOf(world)
	Test.equal(ws:GetAttribute("CurrentSite"), "Stress:5000", "the stress site, not the Site attribute's")
	Test.equal(ws:GetAttribute("CurrentDifficulty"), "None", "with the boss off")
	Test.equal(ws:GetAttribute("StressStep"), nil, "and no ladder")

	local bp = Blueprint.build(StressSite.source(5000))
	local below = 0
	for s = 1, bp.count do
		if bp.y[s] < bp.sizeY - 1 then
			below += 1
		end
	end
	steps(world, 60)
	Test.equal(ws:GetAttribute("SitePlaced"), below, "everything below the top layer is laid")
	Test.check(bp.count - below > 0, "and the top layer is left")
	Test.equal(drawnCount(world), below, "the client draws every block that stands")
	Test.check(math.abs(drawnCount(world) - 5000) <= 100, `about 5,000 drawn: {drawnCount(world)}`)
	-- The camera starts at the origin, near the site's front corner.
	Test.check(children(world, "SiteBlocks") > 0, "some near, one by one")
	Test.check(children(world, "SiteFar") > 0, "some far, merged")
	Test.equal(#ws:FindFirstChild("SiteBoss"):GetChildren(), 0, "no boss drawn")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("a stress site's top layer shows ghosts and lays", function()
	local world, player = boot({ StressTest = 5000, Grasp = 8, Cooldown = 0.1 })
	steps(world, 60)
	local ws = workspaceOf(world)
	local bp = Blueprint.build(StressSite.source(5000))
	local top = bp.sizeY - 1
	-- A top-layer slot resting on the layer below, so it's READY.
	local slot
	for s = 1, bp.count do
		if bp.y[s] == top and bp.physical[s] == Blueprint.Dir.BELOW then
			slot = s
			break
		end
	end
	Test.check(slot, "a top-layer slot to lay")
	local centre = ORIGIN + Vector3.new(bp.x[slot] + 0.5, top + 0.5, bp.z[slot] + 0.5) * STUDS
	local root = world.reals[player.Character]:FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(centre + Vector3.new(0, STUDS * 1.5, 0))
	steps(world, 12)
	Test.check(children(world, "SiteGhosts") > 0, `{children(world, "SiteGhosts")} ghosts on the top layer`)
	local placed = ws:GetAttribute("SitePlaced")
	world.aimRay = Ray.new(centre + Vector3.new(0, 40, 0), Vector3.new(0, -1, 0))
	world:input("began", { UserInputType = Enum.UserInputType.MouseButton1 })
	steps(world, 10)
	world:input("ended", { UserInputType = Enum.UserInputType.MouseButton1 })
	Test.check(ws:GetAttribute("SitePlaced") > placed, "work left: a click lays")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("the readout shows when StressTest is set, counts what's drawn, and F3 toggles it", function()
	local world, player = boot({ StressTest = 5000 })
	steps(world, 60)
	local gui = stressGui(world, player)
	Test.check(gui.Enabled, "shown")
	local text = readoutText(world, player)
	Test.check(string.find(text, "60.0 FPS", 1, true) ~= nil, `frames a second: {text}`)
	Test.check(string.find(text, "mean  16.7 ms  p95  16.7 ms", 1, true) ~= nil, `frame times: {text}`)
	Test.equal(tonumber(string.match(text, "near parts (%d+)")), children(world, "SiteBlocks"), "near parts")
	Test.equal(tonumber(string.match(text, "far boxes (%d+)")), children(world, "SiteFar"), "far boxes")
	Test.equal(
		tonumber(string.match(text, "collision boxes (%d+)")),
		children(world, "SiteCollision"),
		"collision boxes"
	)
	press(world, Enum.KeyCode.F3)
	Test.check(not gui.Enabled, "F3 hides it")
	press(world, Enum.KeyCode.F3)
	Test.check(gui.Enabled, "and shows it again")

	local plain, plainPlayer = boot({})
	local hidden = stressGui(plain, plainPlayer)
	Test.check(not hidden.Enabled, "hidden without StressTest")
	press(plain, Enum.KeyCode.F3)
	Test.check(hidden.Enabled, "until F3")
	steps(plain, 20)
	Test.check(string.find(readoutText(plain, plainPlayer), "near parts", 1, true) ~= nil, "on any site")
	Test.equal(#world.errors + #plain.errors, 0, errorsOf(world) .. errorsOf(plain))
end)

Test.case("the ladder tours each step near then far and moves on after StressStepSeconds", function()
	local world = boot({ StressTest = "Ladder", StressStepSeconds = 1 })
	local ws = workspaceOf(world)
	Test.equal(ws:GetAttribute("CurrentSite"), "Stress:5000", "the first step")
	Test.equal(ws:GetAttribute("StressStep"), 1, "step 1")
	Test.equal(ws:GetAttribute("StressSteps"), #StressSite.LADDER, "of the ladder's eight")
	Test.equal(world.camera.CameraType, Enum.CameraType.Scriptable, "the tour has the camera")

	local function tourStep(count: number)
		local bp = Blueprint.build(StressSite.source(count))
		local started = world.time
		local sawNear, sawFar, edge = 0, false, false
		local id = `Stress:{count}`
		local frames = until_(world, 600, function()
			if ws:GetAttribute("CurrentSite") ~= id then
				return true
			end
			local cell = cameraCell(world)
			local inside = cell.X >= 0 and cell.X <= bp.sizeX and cell.Z >= 0 and cell.Z <= bp.sizeZ
			if cell.Y < bp.sizeY and not inside then
				-- The near view, two cells out from an edge.
				edge = edge
					or (math.abs(cell.X + 2) < 0.01 or math.abs(cell.Z + 2) < 0.01)
					or (math.abs(cell.X - bp.sizeX - 2) < 0.01 or math.abs(cell.Z - bp.sizeZ - 2) < 0.01)
				sawNear = math.max(sawNear, children(world, "SiteBlocks"))
			elseif children(world, "SiteBlocks") == 0 and children(world, "SiteFar") > 0 then
				sawFar = true
			end
			return false
		end)
		Test.check(frames < 600, `step {count} moved on`)
		Test.check(edge, `step {count}: the near view stands at the site's edge`)
		Test.check(sawNear > 0, `step {count}: {sawNear} blocks drawn near`)
		Test.check(sawFar, `step {count}: every chunk far in the overview`)
		Test.check(world.time - started >= 1, `step {count} held its second: {world.time - started} s`)
	end
	tourStep(5000)
	Test.equal(ws:GetAttribute("CurrentSite"), "Stress:10000", "the second step")
	Test.equal(ws:GetAttribute("StressStep"), 2, "step 2")
	tourStep(10000)
	Test.equal(ws:GetAttribute("CurrentSite"), "Stress:15000", "the third step")
	Test.equal(ws:GetAttribute("StressStep"), 3, "step 3")
	Test.equal(world.camera.CameraType, Enum.CameraType.Scriptable, "still touring")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

Test.case("a ladder ends with its table printed and shown, and the camera given back", function()
	local world, player = boot({ StressTest = "1000, 2000", StressStepSeconds = 1 })
	-- The camera as the tour found it, after the first frame.
	Test.equal(world.camera.CameraType, Enum.CameraType.Scriptable, "toured")
	local results = stressGui(world, player):FindFirstChild("Results")
	local frames = until_(world, 600, function()
		return results.Visible
	end)
	Test.check(frames < 600, "the ladder finished")
	local printed = world.printed
	Test.equal(#printed, 2 + 4, `a header, then a row a view for each step:\n{table.concat(printed, "\n")}`)
	Test.check(string.find(printed[1], "2 steps of 1 s", 1, true) ~= nil, printed[1])
	Test.check(string.find(printed[1], "viewport 800 x 600", 1, true) ~= nil, printed[1])
	for _, name in { "blocks", "view", "near parts", "far boxes", "collision boxes", "mean FPS", "5% FPS", "p95 ms" } do
		Test.check(string.find(printed[2], name, 1, true) ~= nil, `a {name} column`)
	end
	local rows = {}
	for i = 3, #printed do
		local blocks, view, near, far, collision, fps, low, p95 =
			string.match(printed[i], "^%s*(%d+)%s+(%a+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d.]+)%s+([%d.]+)%s+([%d.]+)$")
		Test.check(blocks, `a row: {printed[i]}`)
		table.insert(rows, `{blocks} {view}`)
		if view == "near" then
			Test.check(tonumber(near) > 0 and tonumber(collision) > 0, `near: blocks and their collision: {printed[i]}`)
		else
			Test.check(tonumber(near) == 0 and tonumber(far) > 0, `far: only merged boxes: {printed[i]}`)
		end
		Test.equal(fps, "60.0", "mean FPS")
		Test.equal(low, "60.0", "5th-percentile FPS")
		Test.equal(p95, "16.7", "p95 frame ms")
	end
	Test.equal(table.concat(rows, ", "), "1000 near, 1000 far, 2000 near, 2000 far", "in order")
	Test.equal(results.Text, table.concat(printed, "\n"), "the table on screen too")
	Test.check(stressGui(world, player).Enabled, "showing")

	Test.equal(world.camera.CameraType, nil, "the camera's type given back")
	Test.equal(world.camera.CFrame, CFrame.new(), "and where it was")
	steps(world, 90)
	local ws = workspaceOf(world)
	Test.equal(ws:GetAttribute("StressStep"), nil, "the server's ladder is done")
	Test.equal(ws:GetAttribute("CurrentSite"), "Stress:2000", "its last site stays")
	Test.equal(world.camera.CFrame, CFrame.new(), "and the camera stays put")
	Test.equal(#world.errors, 0, errorsOf(world))
end)

return nil
