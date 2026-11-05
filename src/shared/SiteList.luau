--!strict
--[[
	SiteList: the sites in the order a player unlocks them, with what players
	call them. Each id names a stamped blueprint in shared/Blueprints.
	payout is the META_CURRENCY a finished site pays its party, split by
	blocks placed.
]]

return table.freeze({
	table.freeze({ id = "WoodcuttersLodge", name = "Woodcutter's Lodge", payout = 100 }),
	table.freeze({ id = "IceBridge", name = "Ice Bridge", payout = 140 }),
	table.freeze({ id = "Watchtower", name = "Watchtower", payout = 190 }),
	table.freeze({ id = "GreatHall", name = "Great Hall", payout = 260 }),
})
