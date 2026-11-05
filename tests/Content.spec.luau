--[[
	The Phase 6 content drafts in src/shared/content: that each file is well
	formed and frozen, and that it names only what the game has. Goals may
	count only what SiteSession and BossBrain report for a player, read here
	from their source, and only real sites and difficulties.
]]

local fs = require("@lune/fs")

local BossConfig = require("../src/shared/BossConfig")
local SiteConfig = require("../src/shared/SiteConfig")
local SiteList = require("../src/shared/SiteList")
local SkillTuning = require("../src/shared/SkillTuning")
local Test = require("./lib/Test")
local Theme = require("../src/shared/Theme")

local Achievements = require("../src/shared/content/Achievements")
local DailyReward = require("../src/shared/content/DailyReward")
local Lore = require("../src/shared/content/Lore")
local Mounts = require("../src/shared/content/Mounts")
local News = require("../src/shared/content/News")
local PetRoster = require("../src/shared/content/PetRoster")
local Tasks = require("../src/shared/content/Tasks")

local FOLDER = "src/shared/content"
local CURRENCIES = { MetaCurrency = true, PremiumCurrency = true }
local BONUSES = { pay = true, speed = true, ability = true }
local GOALS = { Achievements = Achievements, Tasks = Tasks }
-- The longest a journal page may run, in characters.
local PAGE_LENGTH = 400

-- Every module in the content folder, by name.
local function contentFiles(): { [string]: any }
	local out = {}
	for _, entry in fs.readDir(FOLDER) do
		local name = string.match(entry, "^(.+)%.luau$")
		if name then
			out[name] = require(`../{FOLDER}/{name}`)
		end
	end
	return out
end

-- Calls visit with t and every table inside it, and each one's path.
local function walk(t: any, path: string, visit: (any, string) -> ())
	visit(t, path)
	for key, value in t do
		if type(value) == "table" then
			walk(value, `{path}.{key}`, visit)
		end
	end
end

local function checkText(value: any, label: string)
	Test.check(type(value) == "string" and value ~= "", `{label} is written`)
end

local function checkLook(look: any, label: string)
	Test.check(type(look) == "table", `{label} has a look`)
	local color = look.color
	Test.check(type(color) == "table" and #color == 3, `{label}'s color is \{ r, g, b }`)
	for _, c in color do
		Test.check(type(c) == "number" and c >= 0 and c <= 255 and c == math.floor(c), `{label}'s color is in 0..255`)
	end
	checkText(look.shape, `{label}'s shape`)
end

-- A price or reward: a currency Theme names, and a positive whole amount.
local function checkAmount(value: any, label: string)
	Test.check(type(value) == "table", `{label} is given`)
	Test.check(
		CURRENCIES[value.currency] and Theme[value.currency] ~= nil,
		`{label} is in MetaCurrency or PremiumCurrency, not {value.currency}`
	)
	local amount = value.amount
	Test.check(
		type(amount) == "number" and amount > 0 and amount == math.floor(amount),
		`{label} is a positive whole amount`
	)
end

-- The kinds of event a source emits, and the ones among them that name a
-- userId: SiteSession.takeEvents counts those for the player.
local function emitted(path: string): ({ [string]: boolean }, { [string]: boolean })
	local source = fs.readFile(path)
	local all, counted = {}, {}
	local from = 1
	while true do
		local _, open = string.find(source, "emit%(", from)
		if open == nil then
			break
		end
		-- The call's arguments, up to its matching parenthesis.
		local depth, i = 1, open + 1
		while depth > 0 and i <= #source do
			local c = string.sub(source, i, i)
			if c == "(" then
				depth += 1
			elseif c == ")" then
				depth -= 1
			end
			i += 1
		end
		local args = string.sub(source, open + 1, i - 2)
		local kind = string.match(args, '^%s*session,%s*"([%w_]+)"') or string.match(args, 'kind%s*=%s*"([%w_]+)"')
		if kind then
			all[kind] = true
			if string.find(args, "userId", 1, true) then
				counted[kind] = true
			end
		end
		from = i
	end
	return all, counted
end

local rarityRank = {}
for i, rarity in PetRoster.rarities do
	rarityRank[rarity] = i
end
local petsById = {}
for _, pet in PetRoster.pets do
	petsById[pet.id] = pet
end
local eggsById = {}
for _, egg in PetRoster.eggs do
	eggsById[egg.id] = egg
end
local siteNames = {}
for _, site in SiteList do
	siteNames[site.id] = site.name
end

Test.group("Content")

Test.case("every content file is frozen all the way down", function()
	for name, module in contentFiles() do
		walk(module, name, function(t, path)
			Test.check(table.isfrozen(t), `{path} is frozen`)
		end)
	end
end)

Test.case("ids are unique within each content file", function()
	for name, module in contentFiles() do
		local seen = {}
		walk(module, name, function(t, path)
			local id = t.id
			if id ~= nil then
				Test.check(type(id) == "string" and id ~= "", `{path}'s id is a name`)
				Test.check(seen[id] == nil, `{name} uses the id {id} at {seen[id]} and {path}`)
				seen[id] = path
			end
		end)
	end
end)

Test.case("every rarity has a pet, and every pet a name, a blurb, a look and one bonus", function()
	Test.equal(PetRoster.rarities[#PetRoster.rarities], "Secret", "the rarest rarity")
	local count = {}
	for _, pet in PetRoster.pets do
		Test.check(rarityRank[pet.rarity] ~= nil, `{pet.id}'s rarity {pet.rarity} is one of the rarities`)
		count[pet.rarity] = (count[pet.rarity] or 0) + 1
		checkText(pet.name, `{pet.id}'s name`)
		checkText(pet.blurb, `{pet.id}'s blurb`)
		checkLook(pet.look, pet.id)
		Test.check(type(pet.bonus) == "table", `{pet.id} has a bonus`)
		local kinds = 0
		for kind, value in pet.bonus do
			kinds += 1
			Test.check(BONUSES[kind], `{pet.id}'s bonus is pay, speed or ability, not {kind}`)
			Test.check(type(value) == "number" and value > 0, `{pet.id}'s bonus is positive`)
		end
		Test.equal(kinds, 1, `{pet.id}'s bonus kinds`)
	end
	for _, rarity in PetRoster.rarities do
		Test.check((count[rarity] or 0) >= 1, `{rarity} has a pet`)
	end
end)

Test.case("each egg has a price, and odds that sum to 1 over real pets", function()
	Test.check(#PetRoster.eggs > 0, "there are eggs")
	for _, egg in PetRoster.eggs do
		checkText(egg.name, `{egg.id}'s name`)
		checkText(egg.blurb, `{egg.id}'s blurb`)
		checkLook(egg.look, egg.id)
		checkAmount(egg.price, `{egg.id}'s price`)
		Test.check(#egg.hatches > 0, `{egg.id} hatches something`)
		local sum, seen = 0, {}
		for _, hatch in egg.hatches do
			Test.check(petsById[hatch.pet] ~= nil, `{egg.id} hatches {hatch.pet}, which is no pet`)
			Test.check(not seen[hatch.pet], `{egg.id} lists {hatch.pet} once`)
			seen[hatch.pet] = true
			Test.check(type(hatch.odds) == "number" and hatch.odds > 0, `{egg.id}'s odds of {hatch.pet} are positive`)
			sum += hatch.odds
		end
		Test.check(math.abs(sum - 1) < 1e-9, `{egg.id}'s odds sum to 1, not {sum}`)
	end
end)

Test.case("in each egg, a rarer pet is never likelier than a commoner one", function()
	for _, egg in PetRoster.eggs do
		for _, a in egg.hatches do
			for _, b in egg.hatches do
				local pa, pb = petsById[a.pet], petsById[b.pet]
				if pa and pb and rarityRank[pa.rarity] < rarityRank[pb.rarity] then
					Test.check(a.odds >= b.odds, `{egg.id}: {b.pet} is rarer than {a.pet} but likelier`)
				end
			end
		end
	end
end)

Test.case("every pet hatches from an egg, and Secret pets come from nowhere else", function()
	local hatched = {}
	for _, egg in PetRoster.eggs do
		for _, hatch in egg.hatches do
			hatched[hatch.pet] = true
		end
	end
	local secret = {}
	for _, pet in PetRoster.pets do
		Test.check(hatched[pet.id], `{pet.id} hatches from an egg`)
		if pet.rarity == "Secret" then
			secret[pet.id] = true
		end
	end
	Test.check(next(secret) ~= nil, "there is a Secret pet")

	-- A Secret pet's id may stand only as its own id and in an egg's hatches.
	local function allowed(name: string, path: string, key: any): boolean
		if name ~= "PetRoster" then
			return false
		end
		return (key == "id" and string.match(path, "^PetRoster%.pets%.%d+$") ~= nil)
			or (key == "pet" and string.match(path, "^PetRoster%.eggs%.%d+%.hatches%.%d+$") ~= nil)
	end
	for name, module in contentFiles() do
		walk(module, name, function(t, path)
			for key, value in t do
				if type(value) == "string" and secret[value] then
					Test.check(allowed(name, path, key), `{path}.{key} hands out the Secret pet {value}`)
				end
			end
		end)
	end
end)

Test.case("goals count only what SiteSession and BossBrain report for a player", function()
	local sessionSource = fs.readFile("src/shared/SiteSession.luau")
	local sessionKinds, sessionCounted = emitted("src/shared/SiteSession.luau")
	local _, bossCounted = emitted("src/shared/BossBrain.luau")
	Test.check(next(sessionCounted) ~= nil, "the scan finds SiteSession's player events")
	Test.check(next(bossCounted) ~= nil, "the scan finds BossBrain's player events")
	Test.check(string.find(sessionSource, "counts%.placed%s*=") ~= nil, "SiteSession.counts reports placed")
	Test.check(sessionKinds.finished, "SiteSession emits finished")

	local counted = { placed = true }
	for kind in sessionCounted do
		counted[kind] = true
	end
	for kind in bossCounted do
		counted[kind] = true
	end
	for name, goals in GOALS do
		for _, entry in goals do
			local goal, label = entry.goal, `{name}.{entry.id}`
			Test.check(type(goal) == "table", `{label} has a goal`)
			if goal.stat ~= "finished" then
				Test.check(counted[goal.stat], `{label} counts {goal.stat}, which no player is counted for`)
				Test.check(
					goal.difficulty == nil and goal.site == nil,
					`{label}: only a finished goal names a difficulty or site`
				)
			end
		end
	end
end)

Test.case("goals name only real sites and difficulties", function()
	for name, goals in GOALS do
		for _, entry in goals do
			local goal, label = entry.goal, `{name}.{entry.id}`
			if goal.site ~= nil then
				Test.check(siteNames[goal.site] ~= nil, `{label}'s site {goal.site} is in SiteList`)
			end
			if goal.difficulty ~= nil then
				Test.check(
					BossConfig[goal.difficulty] ~= nil,
					`{label}'s difficulty {goal.difficulty} is in BossConfig`
				)
			end
		end
	end
end)

Test.case("every goal's blurb agrees with its target, and its reward is positive", function()
	for name, goals in GOALS do
		Test.check(#goals > 0, `{name} has goals`)
		for _, entry in goals do
			local goal, label = entry.goal, `{name}.{entry.id}`
			checkText(entry.name, `{label}'s name`)
			checkText(entry.blurb, `{label}'s blurb`)
			local target = goal.target
			Test.check(
				type(target) == "number" and target >= 1 and target == math.floor(target),
				`{label}'s target is a positive whole number`
			)
			-- Any number the blurb shows is the target.
			for digits in string.gmatch((string.gsub(entry.blurb, ",", "")), "%d+") do
				Test.equal(tonumber(digits), target, `{label}'s blurb says {digits}`)
			end
			if goal.site ~= nil and siteNames[goal.site] then
				Test.check(string.find(entry.blurb, siteNames[goal.site], 1, true), `{label}'s blurb names its site`)
			end
			if goal.difficulty ~= nil then
				Test.check(string.find(entry.blurb, goal.difficulty, 1, true), `{label}'s blurb names its difficulty`)
			end
			checkAmount(entry.reward, `{label}'s reward`)
		end
	end
end)

Test.case("every site has short journal pages, and the boss has its story", function()
	for _, site in SiteList do
		local pages = Lore.sites[site.id]
		Test.check(pages ~= nil and #pages >= 2, `{site.id} has journal pages`)
	end
	for id in Lore.sites do
		Test.check(siteNames[id] ~= nil, `Lore's {id} is a site in SiteList`)
	end
	Test.check(#Lore.boss >= 3, "the boss's story has pages")
	local function checkPage(page: any)
		checkText(page.title, `{page.id}'s title`)
		checkText(page.from, `{page.id}'s from`)
		checkText(page.text, `{page.id}'s text`)
		Test.check(#page.text <= PAGE_LENGTH, `{page.id} is short`)
	end
	for _, pages in Lore.sites do
		for _, page in pages do
			checkPage(page)
		end
	end
	for _, page in Lore.boss do
		checkPage(page)
	end
end)

Test.case("the daily reward has seven days, each with a gift", function()
	Test.equal(#DailyReward, 7, "days")
	for i, day in DailyReward do
		Test.equal(day.day, i, "day")
		checkText(day.label, `day {i}'s label`)
		local reward = day.reward
		Test.check(type(reward) == "table", `day {i} has a reward`)
		if reward.egg ~= nil then
			Test.check(eggsById[reward.egg] ~= nil, `day {i}'s egg {reward.egg} is in PetRoster`)
			Test.check(reward.currency == nil and reward.amount == nil, `day {i} gives an egg or currency, not both`)
		else
			checkAmount(reward, `day {i}'s reward`)
		end
	end
end)

Test.case("every mount has a name, a blurb, a look, a price and outruns walking", function()
	Test.check(#Mounts > 0, "there are mounts")
	-- Studs a second a player walks.
	local walking = SkillTuning.walkSpeed * SiteConfig.BLOCK_STUDS
	for _, mount in Mounts do
		checkText(mount.name, `{mount.id}'s name`)
		checkText(mount.blurb, `{mount.id}'s blurb`)
		checkLook(mount.look, mount.id)
		Test.check(type(mount.speed) == "number" and mount.speed > walking, `{mount.id} is faster than walking`)
		checkAmount(mount.price, `{mount.id}'s price`)
	end
end)

Test.case("the news has a launch item", function()
	local launch = nil
	for _, item in News do
		checkText(item.title, `{item.id}'s title`)
		checkText(item.date, `{item.id}'s date`)
		Test.check(type(item.body) == "table" and #item.body > 0, `{item.id} has a body`)
		for _, paragraph in item.body do
			checkText(paragraph, `{item.id}'s paragraph`)
		end
		if item.id == "launch" then
			launch = item
		end
	end
	Test.check(launch ~= nil, "there is a launch item")
end)

return nil
