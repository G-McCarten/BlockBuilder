--!strict
--[[
	Achievements: Frostward's long-term goals. A draft for the fork's
	AchievementConfig.

	The targets and rewards are placeholders until Unharvester's
	AchievementConfig numbers are ported.

	Each achievement:
	  id      stable and never shown
	  name, blurb
	          the blurb says what to do. Any number in it is the target.
	  goal    stat, what counts, added up over every site the player works,
	          and target, how many:
	            placed     blocks the player placed for the first time
	            perfect, ability, pet, pet_ability, drop, boss_shooed,
	            marker_broken, binding_broken, smother
	                       events the player caused, by kind, as
	                       SiteSession.counts counts them
	            finished   sites finished with the player on them. With
	                       difficulty (a BossConfig key) or site (a SiteList
	                       id), only finishes at that difficulty or of that
	                       site count.
	  reward  currency (a Theme key, MetaCurrency or PremiumCurrency) and
	          amount

	No goal counts tool, the POWER_TOOL's swings. The POWER_TOOL is a game
	pass, so a goal on it would shut out everyone without the pass.
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
	-- Laying
	{
		id = "first_course",
		name = "First Course",
		blurb = "Lay 1,000 bricks.",
		goal = { stat = "placed", target = 1000 },
		reward = { currency = "MetaCurrency", amount = 50 },
	},
	{
		id = "mortar_on_your_mittens",
		name = "Mortar on Your Mittens",
		blurb = "Lay 25,000 bricks.",
		goal = { stat = "placed", target = 25000 },
		reward = { currency = "MetaCurrency", amount = 200 },
	},
	{
		id = "valley_mason",
		name = "Valley Mason",
		blurb = "Lay 250,000 bricks.",
		goal = { stat = "placed", target = 250000 },
		reward = { currency = "PremiumCurrency", amount = 25 },
	},
	{
		id = "million_bricks",
		name = "Keeper of a Million Bricks",
		blurb = "Lay 1,000,000 bricks.",
		goal = { stat = "placed", target = 1000000 },
		reward = { currency = "PremiumCurrency", amount = 50 },
	},
	{
		id = "true_line",
		name = "True Line",
		blurb = "Lay 100 bricks with a Perfect!",
		goal = { stat = "perfect", target = 100 },
		reward = { currency = "MetaCurrency", amount = 75 },
	},
	{
		id = "plumb_perfect",
		name = "Plumb Perfect",
		blurb = "Lay 2,500 bricks with a Perfect!",
		goal = { stat = "perfect", target = 2500 },
		reward = { currency = "MetaCurrency", amount = 300 },
	},

	-- The Sled Train and the hearthlings
	{
		id = "bells_on_the_runners",
		name = "Bells on the Runners",
		blurb = "Send the Sled Train across a hold 25 times.",
		goal = { stat = "ability", target = 25 },
		reward = { currency = "MetaCurrency", amount = 75 },
	},
	{
		id = "sled_train_driver",
		name = "Driver of the Sled Train",
		blurb = "Send the Sled Train across a hold 500 times.",
		goal = { stat = "ability", target = 500 },
		reward = { currency = "PremiumCurrency", amount = 15 },
	},
	{
		id = "many_small_paws",
		name = "Many Small Paws",
		blurb = "Have your hearthlings pitch in 250 times.",
		goal = { stat = "pet", target = 250 },
		reward = { currency = "MetaCurrency", amount = 100 },
	},
	{
		id = "hearthling_crew",
		name = "A Crew of Hearthlings",
		blurb = "Have your hearthlings pitch in 5,000 times.",
		goal = { stat = "pet", target = 5000 },
		reward = { currency = "MetaCurrency", amount = 400 },
	},
	{
		id = "gift_of_warmth",
		name = "A Gift of Warmth",
		blurb = "Have a hearthling lay every brick around you at once, 50 times.",
		goal = { stat = "pet_ability", target = 50 },
		reward = { currency = "MetaCurrency", amount = 150 },
	},
	{
		id = "warmth_all_around",
		name = "Warmth All Around",
		blurb = "Have a hearthling lay every brick around you at once, 1,000 times.",
		goal = { stat = "pet_ability", target = 1000 },
		reward = { currency = "PremiumCurrency", amount = 15 },
	},
	{
		id = "glint_in_the_snow",
		name = "A Glint in the Snow",
		blurb = "Find Starglass while laying, 10 times.",
		goal = { stat = "drop", target = 10 },
		reward = { currency = "MetaCurrency", amount = 75 },
	},
	{
		id = "starglass_gatherer",
		name = "Starglass Gatherer",
		blurb = "Find Starglass while laying, 250 times.",
		goal = { stat = "drop", target = 250 },
		reward = { currency = "PremiumCurrency", amount = 25 },
	},

	-- The Rime
	{
		id = "shoo_rime_shoo",
		name = "Shoo, Rime, Shoo",
		blurb = "Shoo the Rime away 10 times.",
		goal = { stat = "boss_shooed", target = 10 },
		reward = { currency = "MetaCurrency", amount = 75 },
	},
	{
		id = "not_in_my_hold",
		name = "Not in My Hold",
		blurb = "Shoo the Rime away 250 times.",
		goal = { stat = "boss_shooed", target = 250 },
		reward = { currency = "MetaCurrency", amount = 400 },
	},
	{
		id = "mark_breaker",
		name = "Mark Breaker",
		blurb = "Break 25 frost marks before they burst.",
		goal = { stat = "marker_broken", target = 25 },
		reward = { currency = "MetaCurrency", amount = 100 },
	},
	{
		id = "nothing_bursts_here",
		name = "Nothing Bursts Here",
		blurb = "Break 500 frost marks before they burst.",
		goal = { stat = "marker_broken", target = 500 },
		reward = { currency = "MetaCurrency", amount = 500 },
	},
	{
		id = "chain_snapper",
		name = "Chain Snapper",
		blurb = "Break 10 ice chains.",
		goal = { stat = "binding_broken", target = 10 },
		reward = { currency = "MetaCurrency", amount = 150 },
	},
	{
		id = "valley_unchained",
		name = "The Valley Unchained",
		blurb = "Break 150 ice chains.",
		goal = { stat = "binding_broken", target = 150 },
		reward = { currency = "PremiumCurrency", amount = 20 },
	},
	{
		id = "cold_hands_warm_heart",
		name = "Cold Hands, Warm Heart",
		blurb = "Get numbed by the Rime 25 times, and keep on laying.",
		goal = { stat = "smother", target = 25 },
		reward = { currency = "MetaCurrency", amount = 100 },
	},

	-- Holds finished
	{
		id = "warm_at_last",
		name = "Warm at Last",
		blurb = "Finish a hold.",
		goal = { stat = "finished", target = 1 },
		reward = { currency = "MetaCurrency", amount = 50 },
	},
	{
		id = "ten_warm_halls",
		name = "Ten Warm Halls",
		blurb = "Finish 10 holds.",
		goal = { stat = "finished", target = 10 },
		reward = { currency = "MetaCurrency", amount = 250 },
	},
	{
		id = "keeper_of_the_valley",
		name = "Keeper of the Valley",
		blurb = "Finish 50 holds.",
		goal = { stat = "finished", target = 50 },
		reward = { currency = "PremiumCurrency", amount = 25 },
	},
	{
		id = "every_window_lit",
		name = "Every Window Lit",
		blurb = "Finish 200 holds.",
		goal = { stat = "finished", target = 200 },
		reward = { currency = "PremiumCurrency", amount = 50 },
	},
	{
		id = "kept_warm",
		name = "Kept Warm",
		blurb = "Finish a hold on Normal.",
		goal = { stat = "finished", target = 1, difficulty = "Normal" },
		reward = { currency = "MetaCurrency", amount = 75 },
	},
	{
		id = "colder_still",
		name = "Colder Still",
		blurb = "Finish a hold on Hard.",
		goal = { stat = "finished", target = 1, difficulty = "Hard" },
		reward = { currency = "MetaCurrency", amount = 150 },
	},
	{
		id = "coldest_of_all",
		name = "Coldest of All",
		blurb = "Finish a hold on Nightmare.",
		goal = { stat = "finished", target = 1, difficulty = "Nightmare" },
		reward = { currency = "PremiumCurrency", amount = 10 },
	},
	{
		id = "the_hearth_holds",
		name = "The Hearth Holds",
		blurb = "Finish 25 holds on Nightmare.",
		goal = { stat = "finished", target = 25, difficulty = "Nightmare" },
		reward = { currency = "PremiumCurrency", amount = 40 },
	},
	{
		id = "smoke_from_the_chimney",
		name = "Smoke from the Chimney",
		blurb = "Finish the Woodcutter's Lodge.",
		goal = { stat = "finished", target = 1, site = "WoodcuttersLodge" },
		reward = { currency = "MetaCurrency", amount = 50 },
	},
	{
		id = "safe_across",
		name = "Safe Across",
		blurb = "Finish the Ice Bridge.",
		goal = { stat = "finished", target = 1, site = "IceBridge" },
		reward = { currency = "MetaCurrency", amount = 75 },
	},
	{
		id = "light_on_the_ridge",
		name = "A Light on the Ridge",
		blurb = "Finish the Watchtower.",
		goal = { stat = "finished", target = 1, site = "Watchtower" },
		reward = { currency = "MetaCurrency", amount = 100 },
	},
	{
		id = "the_hall_is_warm",
		name = "The Hall Is Warm",
		blurb = "Finish the Great Hall.",
		goal = { stat = "finished", target = 1, site = "GreatHall" },
		reward = { currency = "MetaCurrency", amount = 150 },
	},
	{
		id = "warmest_hall_coldest_night",
		name = "Warmest Hall, Coldest Night",
		blurb = "Finish the Great Hall on Nightmare.",
		goal = { stat = "finished", target = 1, site = "GreatHall", difficulty = "Nightmare" },
		reward = { currency = "PremiumCurrency", amount = 25 },
	},
})
