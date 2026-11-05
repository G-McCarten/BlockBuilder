--!strict
--[[
	Theme: every player-facing word of the current skin.

	Code stays in neutral names (Block, Site, RunCurrency, Boss...). Text a
	player reads comes from here or from the content configs, so a reskin
	touches only this module, the content configs and art.

	Current skin: Frostward.
]]

return table.freeze({
	GameName = "Frostward",
	Premise = "You are a hearthkeeper raising warm halls across a frozen valley before the long night falls.",

	Block = { one = "brick", many = "bricks" },
	PlaceVerb = { base = "lay", past = "laid", doing = "laying" },
	Site = { one = "hold", many = "holds" },

	RunCurrency = "Embers",
	MetaCurrency = "Hearthstones",
	PremiumCurrency = "Starglass",

	Pet = { one = "hearthling", many = "hearthlings" },
	PetRollPlace = "Kindling Hearth",
	Mount = { one = "sled beast", many = "sled beasts" },
	MountShop = "Sledyard",
	StartPad = "First Stone",

	Boss = { name = "the Rime", blurb = "A frost wraith that cracks exposed bricks loose." },
	-- What the boss leaves about the site.
	BossWorks = {
		marker = "frost mark",
		binding = "ice chain",
		minion = "rimeling",
		peace = "stillness",
		smother = "numbed",
	},
	Hoist = "hoist",
	Perfect = "Perfect!",
	ServerEvent = "Aurora Night",
	DailyReward = "The Warm Welcome",
	Ability = "Sled Train",
	PowerTool = "Forge Hammer",
})
