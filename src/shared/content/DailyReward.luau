--!strict
--[[
	DailyReward: The Warm Welcome (DAILY_REWARD), seven days of gifts for
	coming back. A draft for the fork's WatchConfig.

	The rewards are placeholders until Unharvester's WatchConfig numbers are
	ported.

	Each day, in order: day, label (a few words for the day's card) and
	reward, which is either currency (a Theme key, MetaCurrency or
	PremiumCurrency) and amount, or egg, an egg's id in PetRoster.
]]

-- Freezes a table and every table in it.
local function freeze(t: { [any]: any }): { [any]: any }
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freeze(v)
		end
	end
	return table.freeze(t)
end

return freeze({
	{ day = 1, label = "A Warm Mug", reward = { currency = "MetaCurrency", amount = 25 } },
	{ day = 2, label = "Dry Mittens", reward = { currency = "MetaCurrency", amount = 40 } },
	{ day = 3, label = "A Pocketful of Glints", reward = { currency = "PremiumCurrency", amount = 5 } },
	{ day = 4, label = "Fresh Kindling", reward = { currency = "MetaCurrency", amount = 60 } },
	{ day = 5, label = "Honey Biscuits", reward = { currency = "MetaCurrency", amount = 80 } },
	{ day = 6, label = "Starlight on the Snow", reward = { currency = "PremiumCurrency", amount = 10 } },
	{ day = 7, label = "A Gift by the Fire", reward = { egg = "pinecone_egg" } },
})
