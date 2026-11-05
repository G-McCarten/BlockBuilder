--[[
	Ground rule 4: code speaks in neutral names, and theme words come from
	Theme and the content configs. And the Phase 6 proof: none of
	Unharvester's theme words reaches a player.
]]

local fs = require("@lune/fs")

local Test = require("./lib/Test")

-- Files whose job is the theme's words and content. An entry ending in "/"
-- is a folder of them.
local CONTENT = {
	["src/shared/Theme.luau"] = true,
	["src/shared/SkillTuning.luau"] = true,
	["src/shared/KindLooks.luau"] = true,
	["src/shared/SiteList.luau"] = true,
	["src/shared/WorldArcConfig.luau"] = true,
	["src/shared/BossConfig.luau"] = true,
	["src/shared/HintConfig.luau"] = true,
	["src/shared/content/"] = true,
}

local CURRENT = {
	"brick",
	"bricks",
	"ember",
	"embers",
	"hearthstone",
	"hearthstones",
	"starglass",
	"hearthling",
	"hearthlings",
	"rime",
	"frostward",
	"sled",
	"aurora",
	"blizzard",
}
local OLD = {
	"blight",
	"wither",
	"withered",
	"tithe",
	"tithes",
	"moontear",
	"moontears",
	"familiar",
	"familiars",
	"tender",
	"harvest",
	"scythe",
	"locust",
	"sowing",
	"cinderfall",
	"kindred",
	"crop",
	"crops",
}

local function files(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			files(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

local function hasWord(text: string, word: string): boolean
	return string.find(text, `%f[%w]{word}%f[%W]`) ~= nil
end

-- The text inside string literals, where player-facing words live.
local function strings(source: string): string
	local parts = {}
	for s in string.gmatch(source, '"([^"\n]*)"') do
		table.insert(parts, s)
	end
	for s in string.gmatch(source, "`([^`]*)`") do
		table.insert(parts, s)
	end
	return string.lower(table.concat(parts, " "))
end

Test.group("Words")

Test.case("code outside Theme and the content configs uses no Frostward words", function()
	for _, path in files("src", {}) do
		local isBlueprint = string.find(path, "/Blueprints/", 1, true) ~= nil
		local isContent = CONTENT[path] or CONTENT[string.match(path, "^.*/")]
		if not isContent and not isBlueprint then
			local text = string.lower(fs.readFile(path))
			for _, word in CURRENT do
				Test.check(not hasWord(text, word), `{path} says "{word}": take it from Theme or a content config`)
			end
		end
	end
end)

Test.case("no Unharvester theme word reaches a player", function()
	for _, path in files("src", {}) do
		local text = strings(fs.readFile(path))
		for _, word in OLD do
			Test.check(not hasWord(text, word), `{path} shows players "{word}"`)
		end
	end
end)

return nil
