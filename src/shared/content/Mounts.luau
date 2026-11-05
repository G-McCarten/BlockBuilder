--!strict
--[[
	Mounts: Frostward's sled beasts (MOUNT), sold at the Sledyard
	(MOUNT_SHOP). A draft for the fork's MountConfig.

	The speeds and prices are placeholders until Unharvester's MountConfig
	numbers are ported.

	Each mount, cheapest first:
	  id      stable and never shown
	  name, blurb
	  look    for the artist: color { r, g, b } in 0..255, and shape, a few
	          words about its build
	  speed   studs a second while riding. A player walks at 16.
	  price   currency (a Theme key, MetaCurrency or PremiumCurrency) and
	          amount
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
		id = "tussock_pony",
		name = "Tussock Pony",
		blurb = "Short, stout and as shaggy as a winter hedge. It will carry you anywhere, eventually.",
		look = { color = { 150, 112, 78 }, shape = "short stout pony, shaggy mane over its eyes, feathered hooves" },
		speed = 20,
		price = { currency = "MetaCurrency", amount = 100 },
	},
	{
		id = "drift_hound",
		name = "Drift Hound",
		blurb = "Long legs and a longer stride. It bounds over snowdrifts as if they weren't there.",
		look = { color = { 216, 212, 204 }, shape = "lean long-legged hound, thick ruff, plumed tail" },
		speed = 26,
		price = { currency = "MetaCurrency", amount = 350 },
	},
	{
		id = "toboggan_seal",
		name = "Toboggan Seal",
		blurb = "Climb on the toboggan and hold tight: it slides you along on its belly, and it loves a downhill.",
		look = { color = { 120, 128, 140 }, shape = "round grey seal pulling a small wooden toboggan" },
		speed = 30,
		price = { currency = "MetaCurrency", amount = 800 },
	},
	{
		id = "lantern_moose",
		name = "Lantern Moose",
		blurb = "A lantern swings from each antler, so the road ahead is always lit.",
		look = { color = { 96, 72, 56 }, shape = "tall moose, broad antlers with a lantern hung on each" },
		speed = 34,
		price = { currency = "MetaCurrency", amount = 1800 },
	},
	{
		id = "starhoof_elk",
		name = "Starhoof Elk",
		blurb = "Its hoofprints glitter for a moment after it passes, like a trail of fallen stars.",
		look = { color = { 222, 228, 246 }, shape = "pale slender elk, silver antlers, glittering hooves" },
		speed = 40,
		price = { currency = "PremiumCurrency", amount = 250 },
	},
})
