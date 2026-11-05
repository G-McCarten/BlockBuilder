--[[
	FakeRoblox: runs a place's server Script and client LocalScript in Lune.

	Everything Lune models (instances, their properties checked against
	Roblox's API database, datatypes, enums) is real. Stand-ins cover the
	rest: players, the run loop, input, tweens, sounds, remotes, the camera,
	and the clock. Each script runs in its own environment with its own
	module cache, as server and client do in Roblox.

	Remote calls queue and are delivered between frames, as a network would.
	Errors raised in scripts or event handlers are collected in world.errors
	rather than stopping the run, as Roblox carries on after one.

	  local world = FakeRoblox.new(game)   a DataModel from PlaceBuilder
	  world:runScripts("server")           every Script in ServerScriptService
	  local player = world:addPlayer(1)    joins, with a character at the spawn
	  world:runScripts("client")           every LocalScript in StarterPlayerScripts
	  world:step(1 / 60)                   one frame: server tick, client frame
	  world:input("began", fields, true)   input, true if a button took it
	  world:activate(button)               a click or tap on a GUI button

	world.sounds counts sounds played, world.puffs ParticleEmitter bursts and
	world.emits the particles in them. Set world.userInput's TouchEnabled and
	MouseEnabled, and world.camera.ViewportSize, before the client runs to
	stand in for a phone.
]]

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local FakeRoblox = {}
FakeRoblox.__index = FakeRoblox

local SIGNALS = {
	Touched = true,
	Activated = true,
	OnServerEvent = true,
	OnClientEvent = true,
	AttributeChanged = true,
	Changed = true,
}

local function newSignal(world)
	local signal = { handlers = {} }
	function signal:Connect(fn)
		local entry = { fn = fn, connected = true }
		table.insert(self.handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				entry.connected = false
			end,
		}
	end
	function signal:Fire(...)
		for _, entry in table.clone(self.handlers) do
			if entry.connected then
				-- pcall, not xpcall with a traceback: Lune's traceback can fail on
				-- errors raised through instance metamethods.
				local ok, err = pcall(entry.fn, ...)
				if not ok then
					table.insert(world.errors, tostring(err))
				end
			end
		end
	end
	return signal
end

function FakeRoblox.new(game)
	local world = setmetatable({}, FakeRoblox)
	world.realGame = game
	world.time = 0
	world.errors = {}
	world.queue = {}
	world.proxies = {}
	world.reals = setmetatable({}, { __mode = "k" })
	world.extras = {}
	world.signals = {}
	world.modules = { server = {}, client = {} }
	world.sounds = 0
	world.puffs = 0
	world.emits = 0
	world.inputs = setmetatable({}, { __mode = "k" })
	world.created = {}
	world.aimRay = roblox.Ray.new(roblox.Vector3.new(0, 50, 0), roblox.Vector3.new(0, -1, 0))
	world.mouse = roblox.Vector2.new(400, 300)

	local meta = {}
	world.meta = meta
	meta.__index = function(proxy, key)
		return world:index(proxy, key)
	end
	meta.__newindex = function(proxy, key, value)
		world:newindex(proxy, key, value)
	end
	meta.__tostring = function(proxy)
		return tostring(world.reals[proxy])
	end

	world.players = {
		list = {},
		LocalPlayer = nil,
		PlayerAdded = newSignal(world),
		PlayerRemoving = newSignal(world),
	}
	function world.players:GetPlayers()
		return table.clone(self.list)
	end

	world.runService = {
		Heartbeat = newSignal(world),
		RenderStepped = newSignal(world),
	}

	world.userInput = {
		InputBegan = newSignal(world),
		InputChanged = newSignal(world),
		InputEnded = newSignal(world),
		MouseEnabled = true,
		TouchEnabled = false,
		GamepadEnabled = false,
	}
	function world.userInput:GetMouseLocation()
		return world.mouse
	end

	world.tweens = {}
	-- A tween lands on its goals at once and reports itself completed.
	function world.tweens.Create(_, instance, _info, goals)
		local tween = { Completed = newSignal(world) }
		tween.Play = function()
			for key, value in goals do
				instance[key] = value
			end
			tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
		end
		tween.Cancel = function() end
		return tween
	end

	world.camera = { CFrame = roblox.CFrame.new(), ViewportSize = roblox.Vector2.new(800, 600) }
	function world.camera:ViewportPointToRay()
		return world.aimRay
	end
	-- Every ray aims along world.aimRay; the screen point asked for is kept in world.screenPoint.
	function world.camera:ScreenPointToRay(x, y)
		world.screenPoint = roblox.Vector2.new(x, y)
		return world.aimRay
	end

	world.fakeServices = {
		Players = world.players,
		RunService = world.runService,
		UserInputService = world.userInput,
		TweenService = world.tweens,
	}

	world.gameProxy = world:wrap(game)
	world.workspaceProxy = world:wrap(game:GetService("Workspace"))
	world.extras[world.workspaceProxy] = { CurrentCamera = world.camera }
	return world
end

function FakeRoblox:wrap(value)
	if typeof(value) ~= "Instance" then
		return value
	end
	local proxy = self.proxies[value]
	if proxy == nil then
		proxy = setmetatable({}, self.meta)
		self.proxies[value] = proxy
		self.reals[proxy] = value
		self.signals[proxy] = {}
	end
	return proxy
end

function FakeRoblox:unwrap(value)
	if type(value) == "table" and self.reals[value] then
		return self.reals[value]
	end
	return value
end

function FakeRoblox:wrapAll(...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		local v = packed[i]
		if type(v) == "table" and getmetatable(v) == nil then
			-- Arrays of instances, like GetChildren's.
			local out = {}
			for k, item in v do
				out[k] = self:wrap(item)
			end
			packed[i] = out
		else
			packed[i] = self:wrap(v)
		end
	end
	return table.unpack(packed, 1, packed.n)
end

function FakeRoblox:unwrapAll(...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		packed[i] = self:unwrap(packed[i])
	end
	return table.unpack(packed, 1, packed.n)
end

-- Methods the stand-ins add or replace on instances.
local METHODS = {}

function METHODS.WaitForChild(world, proxy, name)
	local child = world.reals[proxy]:FindFirstChild(name)
	if child == nil then
		error(`WaitForChild would wait forever for {name} under {world.reals[proxy]:GetFullName()}`, 2)
	end
	return world:wrap(child)
end

function METHODS.GetService(world, proxy, name)
	return world.fakeServices[name] or world:wrap(world.reals[proxy]:GetService(name))
end

function METHODS.SetAttribute(world, proxy, name, value)
	local real = world.reals[proxy]
	real:SetAttribute(name, world:unwrap(value))
	-- Every world that sees the instance hears of it, as replication tells
	-- each client in Roblox. FakeGroup lists a group's worlds in peers.
	for _, peer in world.peers or { world } do
		local seen = peer.proxies[real]
		local signal = seen and peer.signals[seen].AttributeChanged
		if signal then
			signal:Fire(name)
		end
	end
end

function METHODS.FireServer(world, proxy, ...)
	table.insert(
		world.queue,
		{ remote = proxy, event = "OnServerEvent", args = table.pack(world.players.LocalPlayer, ...) }
	)
end

function METHODS.FireClient(world, proxy, player, ...)
	table.insert(
		world.queue,
		{ remote = proxy, event = "OnClientEvent", to = world:unwrap(player), args = table.pack(...) }
	)
end

function METHODS.FireAllClients(world, proxy, ...)
	table.insert(world.queue, { remote = proxy, event = "OnClientEvent", args = table.pack(...) })
end

function METHODS.Play(world)
	world.sounds += 1
end

-- Lune has no particles; a burst is counted. Roblox emits 16 when no count is given.
function METHODS.Emit(world, _proxy, count)
	world.puffs += 1
	world.emits += count or 16
end

function METHODS.Stop() end

function METHODS.PivotTo(world, proxy, cframe)
	local root = world.reals[proxy]:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = cframe
	end
	world.pivots = (world.pivots or 0) + 1
end

function METHODS.GetState()
	return roblox.Enum.HumanoidStateType.Running
end

function FakeRoblox:index(proxy, key)
	local real = self.reals[proxy]
	local extra = self.extras[proxy]
	if extra and extra[key] ~= nil then
		return extra[key]
	end
	if SIGNALS[key] then
		local signals = self.signals[proxy]
		local signal = signals[key]
		if signal == nil then
			signal = newSignal(self)
			signals[key] = signal
		end
		return signal
	end
	local method = METHODS[key]
	if method and (key ~= "GetService" or real.ClassName == "DataModel") then
		return function(_, ...)
			return method(self, proxy, ...)
		end
	end
	if key == "Position" and real:IsA("BasePart") then
		return real.CFrame.Position
	end
	-- Layout is Roblox's to compute; Lune has none. Guis sit at the top left,
	-- and a ScreenGui fills the camera's viewport.
	if key == "AbsolutePosition" and real:IsA("GuiBase2d") then
		return roblox.Vector2.new(0, 0)
	end
	if key == "AbsoluteSize" and real.ClassName == "ScreenGui" then
		return self.camera.ViewportSize
	end
	local value = real[key]
	if type(value) == "function" then
		return function(_, ...)
			return self:wrapAll(value(real, self:unwrapAll(...)))
		end
	end
	return self:wrap(value)
end

function FakeRoblox:newindex(proxy, key, value)
	local real = self.reals[proxy]
	local extra = self.extras[proxy]
	if extra and extra[key] ~= nil then
		extra[key] = value
		return
	end
	if key == "Position" and real:IsA("BasePart") then
		local cframe = real.CFrame
		real.CFrame = cframe + (value - cframe.Position)
		return
	end
	real[key] = self:unwrap(value)
end

function FakeRoblox:environment(script, side: string)
	local world = self
	-- A plain table: Lune copies an environment's own fields, not its metatable.
	local env = table.clone(self.globals)
	env.script = script
	env.require = function(target)
		return world:require(target, script, side)
	end
	return env
end

function FakeRoblox:require(target, from, side: string)
	if self.globals == nil then
		self:buildGlobals()
	end
	local module = target
	if type(target) == "string" then
		local name = string.match(target, "^%./(.+)$")
		assert(name, `only ./ requires are supported, got {target}`)
		module = from.Parent:FindFirstChild(name)
		assert(module, `require can't find {target} from {from.Name}`)
	end
	local cache = self.modules[side]
	local cached = cache[module]
	if cached then
		return cached.value
	end
	local real = self.reals[module]
	local fn = luau.load(real.Source, { debugName = real:GetFullName(), environment = self:environment(module, side) })
	local value = fn()
	cache[module] = { value = value }
	return value
end

function FakeRoblox:buildGlobals()
	local world = self
	local fakeOs = setmetatable({
		clock = function()
			return world.time
		end,
		time = function()
			return world.time
		end,
	}, { __index = os })
	self.globals = {
		game = self.gameProxy,
		workspace = self.workspaceProxy,
		Instance = {
			new = function(className)
				local made = roblox.Instance.new(className)
				-- What each side made, since clients share one real place here.
				table.insert(world.created, made)
				return world:wrap(made)
			end,
		},
		os = fakeOs,
		task = task,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		NumberSequence = roblox.NumberSequence,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		Ray = roblox.Ray,
		-- Lune has neither of these.
		TweenInfo = {
			new = function(time, style, direction)
				return { Time = time, EasingStyle = style, EasingDirection = direction }
			end,
		},
		Random = {
			new = function(seed: number?)
				local state = (seed or 12345) % 4294967296
				local function nextUnit()
					state = (state * 1664525 + 1013904223) % 4294967296
					return state / 4294967296
				end
				return {
					NextNumber = function(_, lo, hi)
						local u = nextUnit()
						return if lo then lo + u * (hi - lo) else u
					end,
					NextInteger = function(_, lo, hi)
						return lo + math.floor(nextUnit() * (hi - lo + 1))
					end,
				}
			end,
		},
	}
end

-- Runs every Script (server) or LocalScript (client) in its container.
function FakeRoblox:runScripts(side: string)
	if self.globals == nil then
		self:buildGlobals()
	end
	local container = if side == "server"
		then self.realGame:GetService("ServerScriptService")
		else self.realGame:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local class = if side == "server" then "Script" else "LocalScript"
	for _, d in container:GetDescendants() do
		if d.ClassName == class then
			local proxy = self:wrap(d)
			local fn = luau.load(d.Source, { debugName = d:GetFullName(), environment = self:environment(proxy, side) })
			local ok, err = pcall(fn)
			if not ok then
				table.insert(self.errors, `{d:GetFullName()}: {tostring(err)}`)
			end
		end
	end
end

-- Adds a player whose character stands at the spawn, and announces them.
function FakeRoblox:addPlayer(userId: number)
	local Instance = roblox.Instance
	local folder = Instance.new("Folder")
	folder.Name = `Player{userId}`
	local gui = Instance.new("Folder")
	gui.Name = "PlayerGui"
	gui.Parent = folder
	local model = Instance.new("Model")
	model.Name = `Character{userId}`
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(85, 3.5, 4)
	root.Parent = model
	Instance.new("Humanoid").Parent = model
	model.Parent = self.realGame:GetService("Workspace")
	local proxy = self:wrap(folder)
	self.extras[proxy] = { UserId = userId, Name = folder.Name, Character = self:wrap(model) }
	table.insert(self.players.list, proxy)
	self.players.LocalPlayer = self.players.LocalPlayer or proxy
	self.players.PlayerAdded:Fire(proxy)
	return proxy
end

function FakeRoblox:deliver()
	while #self.queue > 0 do
		local message = table.remove(self.queue, 1)
		local signal = self.signals[message.remote][message.event]
		if signal then
			signal:Fire(table.unpack(message.args, 1, message.args.n))
		end
	end
end

-- One frame: the server ticks, messages land, the client draws, messages land.
function FakeRoblox:step(dt: number)
	self.time += dt
	self.runService.Heartbeat:Fire(dt)
	self:deliver()
	self.runService.RenderStepped:Fire(dt)
	self:deliver()
end

-- Fires an input phase and returns its InputObject. Roblox keeps one object
-- for a touch from began to ended, so the same fields table gets the same
-- object here; move a touch by changing its Position and firing "changed".
-- processed is the gameProcessedEvent flag, true when a button took the input.
function FakeRoblox:input(phase: string, fields: { [string]: any }, processed: boolean?)
	local input = self.inputs[fields]
	if input == nil then
		input = {
			UserInputType = fields.UserInputType or roblox.Enum.UserInputType.None,
			-- Lune has no KeyCode.Unknown, which Roblox gives mouse input; F12 means nothing here either.
			KeyCode = fields.KeyCode or roblox.Enum.KeyCode.F12,
		}
		self.inputs[fields] = input
	end
	input.Position = fields.Position or roblox.Vector3.new(self.mouse.X, self.mouse.Y, 0)
	local signal = if phase == "began"
		then self.userInput.InputBegan
		elseif phase == "ended" then self.userInput.InputEnded
		else self.userInput.InputChanged
	signal:Fire(input, processed == true)
	return input
end

-- A click or tap on a GUI button (a proxy), as Roblox delivers it: the input
-- begins and ends marked processed, since the button took it, then the
-- button's Activated fires.
function FakeRoblox:activate(button, inputType)
	local fields = { UserInputType = inputType or roblox.Enum.UserInputType.MouseButton1 }
	local input = self:input("began", fields, true)
	self:input("ended", fields, true)
	local signal = self.signals[button] and self.signals[button].Activated
	if signal then
		signal:Fire(input, 1)
	end
end

function FakeRoblox:touch(part, hit)
	local signal = self.signals[part] and self.signals[part].Touched
	if signal then
		signal:Fire(hit)
	end
end

return FakeRoblox
