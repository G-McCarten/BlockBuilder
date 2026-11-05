--!strict
--[[
	BossConfig: the boss's tuning at each difficulty (see BossBrain).

	Harder difficulties add things for players to go and do: break markers
	and bindings, shoo the boss out of a peace circle, place stubborn slots by
	hand, dodge strikes. None makes a block tougher or a wait longer.

	Distances are in cells, times in seconds, shares of the site in 0..1.

	Balanced with the sim (tools/sim, docs/balance.md) so that on every site,
	solo, Normal adds a little to a run, Hard clearly more and Nightmare more
	again. What each lever does there:

	  - Undoing next to where players work costs them little: a click's
	    batch lays the gaps again. The boss bites a compact site only when it
	    undoes faster than that, so Normal already mends 4 blocks at a time.
	  - Markers and shoo trips cost a site where players work steadily, but
	    on a compact one the walk often lands them by fresh work. Markers come
	    every 90 seconds so the long sites don't pay for them twice.
	  - The stubborn band runs through every height, so where it lies along a
	    wall it takes much of the site. It comes late and narrow to keep that
	    from deciding a run.
	  - Minions reach 3 cells: at 4, on the smallest test site, they undo
	    about as fast as a fresh player lays and the run stalls.
	  - A peace circle comes at most once a minute. The boss works the spot
	    farthest from the players, so on the long Ice Bridge every circle was
	    a walk of 50 cells; one at every stop made Hard 65% slower there
	    than no boss, against 15 to 20% on the other sites.
]]

local Normal = {
	riseAt = 0.2,
	relentAt = 0.95,
	speed = 5,
	mendInterval = 2.5,
	mendCount = 4,
	mendRadius = 5,
	undoSpeed = 1.5,
	shooRadius = 3,
	shooedFor = 8,
	markers = { interval = 90, fuse = 20, radius = 4, breakRadius = 2.5, bounty = 25 },
}

local Hard = table.clone(Normal)
Hard.mendCount = 6
Hard.stubborn = { at = 0.6, width = 2 }
Hard.peace = { radius = 5, every = 60 }
Hard.binding = { at = 0.55, cap = 0.8, breakRadius = 2.5, bounty = 40 }

local Nightmare = table.clone(Hard)
Nightmare.minions = { count = 4, speed = 3, interval = 4, radius = 3 }
Nightmare.collapse = { at = { 0.4, 0.7 }, size = 8, budget = 120 }
Nightmare.strike = { interval = 12, radius = 4, smother = 3 }
Nightmare.finalStand = { shoos = 6 }

return table.freeze({
	Normal = table.freeze(Normal),
	Hard = table.freeze(Hard),
	Nightmare = table.freeze(Nightmare),
})
