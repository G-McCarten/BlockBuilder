--!strict
--[[
	Hints: what to tell a new player next, one at a time, each once.

	pick(context, shown) gives the first hint, in order of urgency, whose
	moment has come and that hasn't been shown yet, or nil. HintConfig words
	each one, and words(config, id, device) picks a hint's words for the
	device the player is using.
]]

local Hints = {}

export type Context = {
	-- Blocks this player has laid.
	placed: number,
	purse: number,
	-- The cheapest skill level on offer.
	cheapest: number,
	-- Skill levels bought.
	bought: number,
	workingLayer: number,
	bossRisen: boolean,
	markers: number,
	bound: boolean,
	peace: boolean,
	crewUnlocked: boolean,
}

local ORDER: { { id: string, when: (Context) -> boolean } } = {
	{
		id = "lay",
		when = function(c)
			return c.placed == 0
		end,
	},
	{
		id = "bound",
		when = function(c)
			return c.bound
		end,
	},
	{
		id = "peace",
		when = function(c)
			return c.peace
		end,
	},
	{
		id = "marker",
		when = function(c)
			return c.markers > 0
		end,
	},
	{
		id = "boss",
		when = function(c)
			return c.bossRisen
		end,
	},
	{
		id = "buy",
		when = function(c)
			return c.bought == 0 and c.purse >= c.cheapest
		end,
	},
	{
		id = "crew",
		when = function(c)
			return c.crewUnlocked
		end,
	},
	{
		id = "hoist",
		when = function(c)
			return c.workingLayer >= 3
		end,
	},
}

Hints.ORDER = ORDER

function Hints.pick(context: Context, shown: { [string]: boolean }): string?
	for _, hint in ORDER do
		if not shown[hint.id] and hint.when(context) then
			return hint.id
		end
	end
	return nil
end

export type Device = "mouse" | "touch" | "gamepad"

-- The words for hint id on a device. A hint that names no button has one
-- string for every device; one that does has words for each.
function Hints.words(config: { [string]: any }, id: string, device: Device): string
	local words = config[id]
	if type(words) == "table" then
		return words[device] or words.mouse
	end
	return words
end

return Hints
