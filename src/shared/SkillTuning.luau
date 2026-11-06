--[[
	SkillTuning: the run's skill tree and base stats, as the sim and the
	prototype play them.

	A stand-in for the skill tree until Unharvester's UpgradeConfig arrives
	with the fork. The stat names follow section 5.1; the numbers are placed
	so a solo first run of the WoodcuttersLodge takes about 30 minutes in the
	sim. Swap in the real tree's nodes and prices, keeping this shape, and
	the sim measures that instead.

	Each node raises its stats with each level. A node's price at level L (0
	for the first purchase) is price * growth ^ L.
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
	-- What players see.
	name: string,
	blurb: string,
	-- Changes only how the client plays, so the sim's bots, which aim
	-- perfectly, don't buy it.
	clientOnly: boolean?,
	max: number,
	price: number,
	growth: number,
	apply: (stats: { [string]: number }, level: number) -> (),
}

Tuning.nodes = {
	{
		id = "batch",
		name = "Armful",
		blurb = "Lay one more brick with every click.",
		max = 5,
		price = 192,
		growth = 1.6,
		apply = function(stats, level)
			stats.batch += level
		end,
	},
	{
		id = "chain",
		name = "Mortar Run",
		blurb = "A laid brick may set the bricks around it going.",
		max = 5,
		price = 228,
		growth = 1.6,
		apply = function(stats, level)
			stats.chainChance += 0.05 * level
			stats.chainRadius += 0.15 * level
		end,
	},
	{
		id = "setTime",
		name = "Quick Set",
		blurb = "Bricks set by themselves sooner.",
		max = 4,
		price = 156,
		growth = 1.5,
		apply = function(stats, level)
			stats.setTime *= 0.8 ^ level
		end,
	},
	{
		id = "perfect",
		name = "True Eye",
		blurb = "More bricks land perfect, for extra Embers.",
		max = 4,
		price = 180,
		growth = 1.5,
		apply = function(stats, level)
			stats.perfectChance += 0.05 * level
		end,
	},
	-- The ABILITY: the first level unlocks it, later ones widen and lengthen it.
	{
		id = "crew",
		name = "Sled Train",
		blurb = "Unlock, then widen and lengthen, the crew's sweep.",
		max = 4,
		price = 384,
		growth = 1.7,
		apply = function(stats, level)
			if level >= 2 then
				stats.crewWidth += level - 1
				stats.crewDuration += 2 * (level - 1)
			end
		end,
	},
	-- Auto-aim: a click with nothing under the cursor lays the nearest READY
	-- slot in reach. It changes only how the client aims.
	{
		id = "autoAim",
		name = "Sure Hand",
		blurb = "Click anywhere to lay the nearest brick in reach.",
		max = 1,
		price = 240,
		growth = 1,
		clientOnly = true,
		apply = function(stats, level)
			stats.autoAim = level
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

-- A rarer pet with a timed ability, as Unharvester's Cinderfall pets have.
Tuning.abilityPet = table.freeze({
	speed = 8,
	leash = 8,
	reach = 1.5,
	ring = 2.5,
	setTime = 2,
	rest = 2,
	ability = table.freeze({ interval = 20, radius = 3 }),
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
