--[[
	Two clients and a server, as Studio's Local Server runs them: both lay
	blocks, sometimes racing for the same slots, and both end showing exactly
	what the server holds.
]]

local roblox = require("@lune/roblox")

local FakeGroup = require("./lib/FakeGroup")
local PlaceBuilder = require("./lib/PlaceBuilder")
local Test = require("./lib/Test")

local Vector3, CFrame, Ray, Enum = roblox.Vector3, roblox.CFrame, roblox.Ray, roblox.Enum
local STUDS = 3
local ORIGIN = Vector3.new(24, 0, 24)

-- What one client draws: its own blocks one by one, and its far boxes' cells.
local function drawn(client): number
	local count = 0
	for _, made in client.created do
		-- Lune refuses to read a destroyed instance; those are gone anyway.
		local ok, name = pcall(function()
			return made.Name
		end)
		if not ok then
			name = nil
		end
		if name == "SiteBlocks" then
			count += #made:GetChildren()
		elseif name == "SiteFar" then
			for _, part in made:GetChildren() do
				local size = part.Size / STUDS
				count += math.round(size.X * size.Y * size.Z)
			end
		end
	end
	return count
end

local function aim(client, x: number, z: number)
	local root = client.reals[client.players.LocalPlayer.Character]:FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(ORIGIN + Vector3.new(x + 0.5, 2, z - 1) * STUDS)
	client.aimRay = Ray.new(ORIGIN + Vector3.new(x + 0.5, 40, z + 0.5) * STUDS, Vector3.new(0, -1, 0))
end

Test.group("Clients")

Test.case("two clients lay blocks together and both end showing what the server holds", function()
	local game = PlaceBuilder.build("default.project.json")
	local workspace = game:GetService("Workspace")
	workspace:SetAttribute("Difficulty", "Hard")
	workspace:SetAttribute("Batch", 4)
	workspace:SetAttribute("Cooldown", 0.15)
	local group = FakeGroup.new(game)
	group:start()
	local a = group:addClient(1)
	local b = group:addClient(2)
	for _, client in { a, b } do
		client.camera.CFrame = CFrame.new(ORIGIN + Vector3.new(60, 30, 40))
		client:input("began", { UserInputType = Enum.UserInputType.MouseButton1 })
	end
	for frame = 1, 1800 do
		-- They work their own halves, and every so often the same cell.
		local shared = frame % 50 < 10
		local ax = if shared then 16 else 2 + (frame // 6) % 14
		local bx = if shared then 16 else 18 + (frame // 6) % 14
		local z = 4 + (frame // 90) % 20
		aim(a, ax, z)
		aim(b, bx, z)
		group:step(1 / 60)
	end
	for _, client in { a, b } do
		client:input("ended", { UserInputType = Enum.UserInputType.MouseButton1 })
	end
	for _ = 1, 120 do
		group:step(1 / 60)
	end
	local placed = workspace:GetAttribute("SitePlaced")
	Test.check(placed > 300, `the two laid {placed}`)
	Test.equal(drawn(a), placed, "the first client shows what the server holds")
	Test.equal(drawn(b), placed, "and so does the second")
	local errors = group:errors()
	Test.equal(#errors, 0, table.concat(errors, "\n\n"))
end)

return nil
