--[[
	Tuning: the run economy the sim plays with.

	A stand-in for the skill tree until Unharvester's UpgradeConfig arrives
	with the fork: the stat names follow section 5.1, the numbers are placed
	so a solo first run of the WoodcuttersLodge takes about 30 minutes. Swap
	in the real tree's nodes and prices, keeping this shape, and the sim
	measures that instead.

	Each node raises one stat per level. A node's price at level L (0 for
	the first purchase) is price * growth ^ L.
]]

local Tuning = {}

-- Cells a second a player walks: 16 studs a second at 3 studs a cell.
Tuning.walkSpeed = 16 / 3

-- Seconds a hoist pad takes to lift a player to the working height.
Tuning.hoistSeconds = 2

Tuning.base = table.freeze({
	cooldown = 0.75,
	grasp = 5,
	batch = 1,
	setTime = 3,
	chainChance = 0,
	chainRadius = 1.2,
	perfectChance = 0,
	perfectReward = 2.5,
	yield = 1,
	yieldMult = 1,
	crewWidth = 2,
	crewSpeed = 4,
	crewDuration = 6,
	crewCooldown = 45,
})

export type Node = {
	id: string,
	max: number,
	price: number,
	growth: number,
	apply: (stats: { [string]: number }, level: number) -> (),
}

Tuning.nodes = {
	{
		id = "batch",
		max = 5,
		price = 160,
		growth = 1.6,
		apply = function(stats, level)
			stats.batch += level
		end,
	},
	{
		id = "chain",
		max = 5,
		price = 190,
		growth = 1.6,
		apply = function(stats, level)
			stats.chainChance += 0.05 * level
			stats.chainRadius += 0.15 * level
		end,
	},
	{
		id = "setTime",
		max = 4,
		price = 130,
		growth = 1.5,
		apply = function(stats, level)
			stats.setTime *= 0.8 ^ level
		end,
	},
	{
		id = "perfect",
		max = 4,
		price = 150,
		growth = 1.5,
		apply = function(stats, level)
			stats.perfectChance += 0.05 * level
		end,
	},
	-- The ABILITY: the first level unlocks it, later ones widen and lengthen it.
	{
		id = "crew",
		max = 4,
		price = 320,
		growth = 1.7,
		apply = function(stats, level)
			if level >= 2 then
				stats.crewWidth += level - 1
				stats.crewDuration += 2 * (level - 1)
			end
		end,
	},
}

-- The node whose first level unlocks the ABILITY.
Tuning.abilityNode = "crew"

-- The POWER_TOOL, for runs that give players the pass.
Tuning.tool = table.freeze({
	radius = 4,
	halfAngle = math.rad(55),
	band = 2,
	setTime = 2,
	cooldown = 8,
})

-- A pet, for runs that give players one from the meta.
Tuning.pet = table.freeze({
	speed = 8,
	leash = 8,
	reach = 1.5,
	ring = 2.5,
	setTime = 2,
	rest = 2,
})

function Tuning.price(node: Node, level: number): number
	return math.floor(node.price * node.growth ^ level + 0.5)
end

-- The stats a player has with the given levels.
function Tuning.stats(levels: { [string]: number }): { [string]: number }
	local stats = table.clone(Tuning.base) :: any
	for _, node in Tuning.nodes do
		local level = levels[node.id] or 0
		if level > 0 then
			node.apply(stats, level)
		end
	end
	return stats
end

return Tuning
