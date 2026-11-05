--!strict
--[[
	News: Frostward's news items, newest first. A draft for the fork's
	NewsConfig, which the fork empties at the start and fills for launch.

	Each item: id (stable and never shown), date (shown as written: set the
	real date when it ships), title and body, a list of paragraphs.
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
		id = "launch",
		date = "Launch day",
		title = "The First Stone Is Laid",
		body = {
			"Welcome to Frostward! The long night is coming to the valley, and every hold needs raising before it falls.",
			"Lay bricks with your friends, send the Sled Train across the hold, and shoo the Rime when it creeps in. Finish a hold to earn Hearthstones, then warm an egg at the Kindling Hearth to meet your first hearthling.",
			"Come back each day for The Warm Welcome, visit the Sledyard when you're ready for a sled beast, and keep an eye on the sky for an Aurora Night.",
		},
	},
})
