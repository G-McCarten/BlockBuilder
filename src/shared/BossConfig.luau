--!strict
--[[
	BossConfig: the boss's tuning at each difficulty (see BossBrain).

	Harder difficulties add things for players to go and do: break markers
	and bindings, shoo the boss out of a peace circle, place stubborn slots by
	hand, dodge strikes. None makes a block tougher or a wait longer.

	Distances are in cells, times in seconds, shares of the site in 0..1.
]]

local Normal = {
	riseAt = 0.15,
	relentAt = 0.95,
	speed = 5,
	mendInterval = 2.5,
	mendCount = 2,
	mendRadius = 4,
	undoSpeed = 1.5,
	shooRadius = 3,
	shooedFor = 8,
	markers = { interval = 45, fuse = 20, radius = 4, breakRadius = 2.5, bounty = 25 },
}

local Hard = table.clone(Normal)
Hard.mendCount = 3
Hard.stubborn = { at = 0.3, width = 3 }
Hard.peace = { radius = 5 }
Hard.binding = { at = 0.55, cap = 0.8, breakRadius = 2.5, bounty = 40 }

local Nightmare = table.clone(Hard)
Nightmare.minions = { count = 3, speed = 3, interval = 4, radius = 3 }
Nightmare.collapse = { at = { 0.4, 0.7 }, size = 8, budget = 120 }
Nightmare.strike = { interval = 12, radius = 4, smother = 3 }
Nightmare.finalStand = { shoos = 3 }

return table.freeze({
	Normal = table.freeze(Normal),
	Hard = table.freeze(Hard),
	Nightmare = table.freeze(Nightmare),
})
