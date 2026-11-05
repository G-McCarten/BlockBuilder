--[[
	FakeGroup: one server and several clients, as Studio's Local Server runs
	them, for testing what two real clients would do.

	Each side is its own FakeRoblox world over the same place, with its own
	view of the instances, signals, input, camera and module cache, as a
	server and its clients have in Roblox. The group carries remote calls
	between them each frame: a client's FireServer reaches the server with
	that client's player, FireClient reaches only that player's client, and
	FireAllClients reaches every client.

	  local group = FakeGroup.new(game)   a DataModel from PlaceBuilder
	  group:start()                       runs the server's Scripts
	  local client = group:addClient(1)   joins a player and runs their client
	  group:step(1 / 60)                  one frame everywhere
]]

local FakeRoblox = require("./FakeRoblox")

local FakeGroup = {}
FakeGroup.__index = FakeGroup

function FakeGroup.new(game)
	local group = setmetatable({}, FakeGroup)
	group.game = game
	group.server = FakeRoblox.new(game)
	-- Every world in the group, so an attribute set in one is heard in all.
	group.server.peers = { group.server }
	group.clients = {}
	return group
end

function FakeGroup:start()
	self.server:runScripts("server")
end

-- Joins player userId on the server and starts their client. Returns the
-- client's world, whose camera, aim and input are that player's.
function FakeGroup:addClient(userId: number)
	local serverPlayer = self.server:addPlayer(userId)
	local realPlayer = self.server.reals[serverPlayer]
	local realCharacter = self.server.reals[serverPlayer.Character]
	local client = FakeRoblox.new(self.game)
	client.peers = self.server.peers
	table.insert(client.peers, client)
	client.time = self.server.time
	local localPlayer = client:wrap(realPlayer)
	client.extras[localPlayer] = { UserId = userId, Name = realPlayer.Name, Character = client:wrap(realCharacter) }
	client.players.LocalPlayer = localPlayer
	client.players.list = { localPlayer }
	client.realPlayer = realPlayer
	table.insert(self.clients, client)
	client:runScripts("client")
	return client
end

-- Converts one world's values into another's: instances re-wrapped in the
-- receiving world's view, everything else as it is.
local function carry(from, to, args)
	local out = { n = args.n }
	for i = 1, args.n do
		out[i] = to:wrap(from:unwrap(args[i]))
	end
	return out
end

local function fire(world, realRemote, event: string, args)
	local proxy = world:wrap(realRemote)
	local signal = world.signals[proxy][event]
	if signal then
		signal:Fire(table.unpack(args, 1, args.n))
	end
end

-- Delivers every queued remote call to the side it's addressed to.
function FakeGroup:route()
	local moved = true
	while moved do
		moved = false
		for _, client in self.clients do
			while #client.queue > 0 do
				moved = true
				local message = table.remove(client.queue, 1)
				local realRemote = client:unwrap(message.remote)
				-- A client's call arrives with its own player first.
				local args = carry(client, self.server, message.args)
				args[1] = self.server:wrap(client.realPlayer)
				fire(self.server, realRemote, message.event, args)
			end
		end
		while #self.server.queue > 0 do
			moved = true
			local message = table.remove(self.server.queue, 1)
			local realRemote = self.server:unwrap(message.remote)
			for _, client in self.clients do
				if message.to == nil or message.to == client.realPlayer then
					fire(client, realRemote, message.event, carry(self.server, client, message.args))
				end
			end
		end
	end
end

-- One frame: the server ticks, calls land, every client draws, calls land.
function FakeGroup:step(dt: number)
	local server = self.server
	server.time += dt
	server.runService.Heartbeat:Fire(dt)
	self:route()
	for _, client in self.clients do
		client.time = server.time
		client.runService.RenderStepped:Fire(dt)
	end
	self:route()
end

-- Every error any side has raised.
function FakeGroup:errors(): { string }
	local all = table.clone(self.server.errors)
	for _, client in self.clients do
		for _, e in client.errors do
			table.insert(all, e)
		end
	end
	return all
end

return FakeGroup
