--[[
	PlaceBuilder: builds a DataModel from a Rojo project file the way
	`rojo build` does, as Lune instances, so tests can run the place's scripts.

	It understands what default.project.json uses: services, $path folders of
	.luau files (.server.luau a Script, .client.luau a LocalScript, others
	ModuleScripts), and children with $className and $properties whose values
	take the type of the property's default.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance

local PlaceBuilder = {}

local function fromPath(path: string, name: string): any
	if fs.isDir(path) then
		local folder = Instance.new("Folder")
		folder.Name = name
		for _, entry in fs.readDir(path) do
			local childName = string.match(entry, "^(.-)%.server%.luau$")
				or string.match(entry, "^(.-)%.client%.luau$")
				or string.match(entry, "^(.-)%.luau$")
				or entry
			local child = fromPath(`{path}/{entry}`, childName)
			if child then
				child.Parent = folder
			end
		end
		return folder
	end
	local class = if string.match(path, "%.server%.luau$")
		then "Script"
		elseif string.match(path, "%.client%.luau$") then "LocalScript"
		elseif string.match(path, "%.luau$") then "ModuleScript"
		else nil
	if class == nil then
		return nil
	end
	local script = Instance.new(class)
	script.Name = name
	script.Source = fs.readFile(path)
	return script
end

local function convert(current: any, value: any): any
	local kind = typeof(current)
	if kind == "Vector3" then
		return roblox.Vector3.new(value[1], value[2], value[3])
	elseif kind == "Color3" then
		return roblox.Color3.new(value[1], value[2], value[3])
	elseif kind == "EnumItem" then
		local enumName = string.match(tostring(current), "^Enum%.([%w_]+)%.")
		return (roblox.Enum :: any)[enumName][value]
	end
	return value
end

local function fill(instance: any, node: { [string]: any })
	for key, value in node["$properties"] or {} do
		if key == "Position" then
			-- Position is derived from CFrame, which Lune stores.
			instance.CFrame = roblox.CFrame.new(value[1], value[2], value[3])
		else
			instance[key] = convert(instance[key], value)
		end
	end
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" then
			local made
			if child["$path"] then
				made = fromPath(child["$path"], key)
			else
				-- Rojo names some children by their class, like StarterPlayerScripts.
				local class = child["$className"]
					or (if key == "StarterPlayerScripts" or key == "StarterCharacterScripts" then key else "Folder")
				made = Instance.new(class)
			end
			made.Name = key
			fill(made, child)
			made.Parent = instance
		end
	end
end

function PlaceBuilder.build(projectPath: string): any
	local project = serde.decode("json", fs.readFile(projectPath))
	local game = Instance.new("DataModel")
	for serviceName, node in project.tree do
		if string.sub(serviceName, 1, 1) ~= "$" then
			fill(game:GetService(serviceName), node)
		end
	end
	return game
end

return PlaceBuilder
