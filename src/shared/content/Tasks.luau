--!strict
--[[
	Tasks: Frostward's short, repeatable goals, the pool the fork's
	TaskService hands out a few at a time and hands out again once claimed.
	A draft for the fork's TaskConfig.

	The targets and rewards are placeholders until Unharvester's TaskConfig
	numbers are ported.

	Each task has id, name, blurb, goal and reward, shaped as in
	Achievements. A task's progress counts from when it's handed out.

	Every task can be done at Normal, with one Common pet and no game pass.
	So none counts what only Hard and Nightmare bring (binding_broken,
	smother), what only a rarer pet does (pet_ability), or the swings of the
	POWER_TOOL (tool), which is a game pass.
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
	{
		id = "a_mornings_work",
		name = "A Morning's Work",
		blurb = "Lay 300 bricks.",
		goal = { stat = "placed", target = 300 },
		reward = { currency = "MetaCurrency", amount = 15 },
	},
	{
		id = "busy_mittens",
		name = "Busy Mittens",
		blurb = "Lay 1,500 bricks.",
		goal = { stat = "placed", target = 1500 },
		reward = { currency = "MetaCurrency", amount = 40 },
	},
	{
		id = "laid_true",
		name = "Laid True",
		blurb = "Lay 10 bricks with a Perfect!",
		goal = { stat = "perfect", target = 10 },
		reward = { currency = "MetaCurrency", amount = 20 },
	},
	{
		id = "ring_the_runners",
		name = "Ring the Runners",
		blurb = "Send the Sled Train across a hold 3 times.",
		goal = { stat = "ability", target = 3 },
		reward = { currency = "MetaCurrency", amount = 20 },
	},
	{
		id = "paws_to_work",
		name = "Paws to Work",
		blurb = "Have your hearthlings pitch in 30 times.",
		goal = { stat = "pet", target = 30 },
		reward = { currency = "MetaCurrency", amount = 20 },
	},
	{
		id = "off_you_go",
		name = "Off You Go",
		blurb = "Shoo the Rime away 3 times.",
		goal = { stat = "boss_shooed", target = 3 },
		reward = { currency = "MetaCurrency", amount = 25 },
	},
	{
		id = "thaw_the_marks",
		name = "Thaw the Marks",
		blurb = "Break 3 frost marks before they burst.",
		goal = { stat = "marker_broken", target = 3 },
		reward = { currency = "MetaCurrency", amount = 25 },
	},
	{
		id = "something_glinting",
		name = "Something Glinting",
		blurb = "Find Starglass while laying.",
		goal = { stat = "drop", target = 1 },
		reward = { currency = "MetaCurrency", amount = 20 },
	},
	{
		id = "lights_in_the_window",
		name = "Lights in the Window",
		blurb = "Finish a hold.",
		goal = { stat = "finished", target = 1 },
		reward = { currency = "MetaCurrency", amount = 50 },
	},
	{
		id = "hearth_to_hearth",
		name = "Hearth to Hearth",
		blurb = "Finish 2 holds.",
		goal = { stat = "finished", target = 2 },
		reward = { currency = "PremiumCurrency", amount = 3 },
	},
})
