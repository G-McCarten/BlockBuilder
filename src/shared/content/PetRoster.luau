--!strict
--[[
	PetRoster: Frostward's hearthlings (PET) and the eggs warmed at the
	Kindling Hearth (PET_ROLL_PLACE). A draft for the fork's PetConfig and
	EggConfig (and the Index that lists every pet).

	EVERY NUMBER HERE IS A PLACEHOLDER: bonus values, egg prices and hatch
	chances all stand in until Unharvester's PetConfig and EggConfig numbers
	are ported. Section 5.2 keeps the same count per rarity and the same
	numbers as Unharvester's, so the balance carries over: port the numbers
	into these fields, then add or cut pets until each rarity's count
	matches.

	rarities  in order, commonest first. Secret is egg-only: a Secret pet
	          hatches from an egg and comes from nowhere else.
	pets      each pet:
	            id      stable and never shown
	            name, blurb
	            rarity  one of rarities
	            look    for the artist: color { r, g, b } in 0..255, and
	                    shape, a few words about its build
	            bonus   one kind and its value. The kinds are section 5.2's
	                    renames: pay (was blight), speed (still speed) and
	                    ability (was burst). Read a value as a share, 0.05
	                    for +5%, until PetConfig says what each kind scales.
	eggs      each egg: id, name, blurb, look, price (currency, a Theme
	          key, MetaCurrency or PremiumCurrency, and amount) and hatches,
	          the pets it can hatch with their chances, commonest first.
	          Each egg's chances sum to 1.
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
	rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" },

	pets = {
		-- Common
		{
			id = "thimble_vole",
			name = "Thimble Vole",
			blurb = "Wears a sewing thimble for a helmet and will not be talked out of it.",
			rarity = "Common",
			look = { color = { 150, 118, 92 }, shape = "round vole, thimble helmet, pink nose, tiny paws" },
			bonus = { pay = 0.02 },
		},
		{
			id = "pom_wren",
			name = "Pom Wren",
			blurb = "Fluffed up so round against the cold that it looks like a pom-pom with a beak.",
			rarity = "Common",
			look = { color = { 176, 124, 84 }, shape = "ball of feathers, tiny beak, stub of a tail" },
			bonus = { speed = 0.02 },
		},
		{
			id = "oatprickle",
			name = "Oatprickle",
			blurb = "A hedgehog with spines as soft as oat straw. It naps in mittens and has to be shaken out.",
			rarity = "Common",
			look = { color = { 214, 190, 140 }, shape = "small hedgehog, soft pale spines, curled up" },
			bonus = { pay = 0.02 },
		},
		{
			id = "kettle_newt",
			name = "Kettle Newt",
			blurb = "Basks on warm kettles and hums a little when the water's nearly ready.",
			rarity = "Common",
			look = { color = { 228, 132, 64 }, shape = "slim newt, long curled tail, spotted back, sleepy eyes" },
			bonus = { speed = 0.02 },
		},
		{
			id = "drift_lamb",
			name = "Drift Lamb",
			blurb = "So white that it disappears whenever it lies down in the snow, which is often.",
			rarity = "Common",
			look = { color = { 242, 244, 248 }, shape = "small lamb, curly fleece, dark face, knobbly legs" },
			bonus = { pay = 0.03 },
		},
		{
			id = "button_owlet",
			name = "Button Owlet",
			blurb = "Round and brown as a coat button, and nearly as quiet. It nods along as the bricks go up.",
			rarity = "Common",
			look = { color = { 124, 100, 80 }, shape = "stout round owlet, ear tufts, big eyes" },
			bonus = { ability = 0.02 },
		},
		{
			id = "mossbun",
			name = "Mossbun",
			blurb = "A rabbit with a coat like pine moss. It smells of the forest floor under the snow.",
			rarity = "Common",
			look = { color = { 72, 112, 80 }, shape = "plump rabbit, mossy green coat, long soft ears" },
			bonus = { speed = 0.03 },
		},

		-- Uncommon
		{
			id = "wickmoth",
			name = "Wickmoth",
			blurb = "Its feelers glow like two candle wicks, just bright enough to read by.",
			rarity = "Uncommon",
			look = { color = { 255, 196, 112 }, shape = "fuzzy moth, broad round wings, glowing feeler tips" },
			bonus = { pay = 0.04 },
		},
		{
			id = "quilt_stoat",
			name = "Quilt Stoat",
			blurb = "Its winter coat came in patchy, so it decided patchwork was the fashion.",
			rarity = "Uncommon",
			look = { color = { 204, 182, 156 }, shape = "long slinky stoat, patchwork coat, dark tail tip" },
			bonus = { speed = 0.04 },
		},
		{
			id = "cocoa_otter",
			name = "Cocoa Otter",
			blurb = "Floats on its back in the hot springs, holding a mug it found and will never give back.",
			rarity = "Uncommon",
			look = { color = { 110, 74, 52 }, shape = "sleek otter lying on its back, holding a tiny mug" },
			bonus = { pay = 0.05 },
		},
		{
			id = "spindle_hare",
			name = "Spindle Hare",
			blurb = "Winds loose yarn into balls with its long ears. Nobody knows where it finds the yarn.",
			rarity = "Uncommon",
			look = { color = { 230, 222, 210 }, shape = "tall slender hare, very long ears, a ball of yarn" },
			bonus = { ability = 0.04 },
		},
		{
			id = "conebeak",
			name = "Conebeak",
			blurb = "Pries pinecones open with its crossed beak and leaves the seeds for anyone hungry.",
			rarity = "Uncommon",
			look = { color = { 176, 84, 60 }, shape = "small finch, crossed beak, clutching a pinecone" },
			bonus = { speed = 0.05 },
		},
		{
			id = "juniper_fawn",
			name = "Juniper Fawn",
			blurb = "Speckled with spots the blue of juniper berries. It follows lanterns home.",
			rarity = "Uncommon",
			look = { color = { 176, 140, 104 }, shape = "spindly fawn, blue-grey speckles, big ears" },
			bonus = { pay = 0.05 },
		},

		-- Rare
		{
			id = "chimefox",
			name = "Chimefox",
			blurb = "A little bell grows at the tip of its tail, so you always hear it before you see it.",
			rarity = "Rare",
			look = { color = { 222, 128, 64 }, shape = "small fox, white chest, bushy tail ending in a bell" },
			bonus = { pay = 0.07 },
		},
		{
			id = "mantel_owl",
			name = "Mantel Owl",
			blurb = "Dozes all day on warm mantelpieces and keeps watch over the hearth all night.",
			rarity = "Rare",
			look = { color = { 150, 126, 98 }, shape = "broad round owl, folded wings, half-closed eyes" },
			bonus = { ability = 0.06 },
		},
		{
			id = "snowshoe_badger",
			name = "Snowshoe Badger",
			blurb = "Its feet are as wide as snowshoes, so it never sinks, and it never hurries.",
			rarity = "Rare",
			look = { color = { 120, 120, 128 }, shape = "low wide badger, white face stripe, huge flat feet" },
			bonus = { speed = 0.07 },
		},
		{
			id = "tallow_toad",
			name = "Tallow Toad",
			blurb = "Glows softly, like a candle stub. It sits in windows so travellers can find their way.",
			rarity = "Rare",
			look = { color = { 250, 214, 150 }, shape = "squat toad, waxy glowing skin, wide smile" },
			bonus = { ability = 0.07 },
		},
		{
			id = "bellows_pup",
			name = "Bellows Pup",
			blurb = "Puffs its cheeks at dying fires until they catch again, and is very proud of it.",
			rarity = "Rare",
			look = { color = { 196, 122, 76 }, shape = "round puppy, floppy ears, puffed-out cheeks" },
			bonus = { pay = 0.08 },
		},

		-- Epic
		{
			id = "northglow_lynx",
			name = "Northglow Lynx",
			blurb = "The tufts on its ears glow a faint green, like the sky on a clear, cold night.",
			rarity = "Epic",
			look = { color = { 200, 196, 186 }, shape = "big-pawed lynx, glowing green ear tufts, short tail" },
			bonus = { speed = 0.1 },
		},
		{
			id = "kettlecub",
			name = "Kettlecub",
			blurb = "A bear cub that steams gently when it's pleased, which is nearly always.",
			rarity = "Epic",
			look = { color = { 140, 96, 64 }, shape = "chubby bear cub, round belly, little puffs of steam" },
			bonus = { pay = 0.1 },
		},
		{
			id = "pineantler",
			name = "Pineantler",
			blurb = "A young elk whose antlers are living pine boughs. Birds nest in them every spring.",
			rarity = "Epic",
			look = { color = { 58, 104, 72 }, shape = "young elk, pine-bough antlers, shaggy neck" },
			bonus = { pay = 0.11 },
		},
		{
			id = "lanternshell",
			name = "Lanternshell",
			blurb = "A tortoise with a little lit window in its shell. Someone inside is always making tea.",
			rarity = "Epic",
			look = { color = { 255, 184, 92 }, shape = "tortoise, domed shell with one glowing window" },
			bonus = { ability = 0.1 },
		},

		-- Legendary
		{
			id = "hearthback",
			name = "Hearthback",
			blurb = "A great shaggy ox with a hearth on its back that never goes out. Wherever it lies down becomes home.",
			rarity = "Legendary",
			look = {
				color = { 104, 80, 64 },
				shape = "huge shaggy ox, low curled horns, a small stone hearth on its back",
			},
			bonus = { pay = 0.15 },
		},
		{
			id = "pinecrown_stag",
			name = "Pinecrown Stag",
			blurb = "Lanterns hang from its antlers like fruit from a bough, so it walks very carefully.",
			rarity = "Legendary",
			look = { color = { 120, 92, 68 }, shape = "tall stag, wide antlers hung with small lanterns" },
			bonus = { speed = 0.14 },
		},
		{
			id = "snowmantle_goose",
			name = "Snowmantle Goose",
			blurb = "Its wings spread as wide as a snowdrift. When it settles over a hold, the wind can't find a way in.",
			rarity = "Legendary",
			look = { color = { 246, 248, 252 }, shape = "big goose, wings like a cloak, dark beak" },
			bonus = { ability = 0.14 },
		},

		-- Mythic
		{
			id = "morrowmoth",
			name = "Morrowmoth",
			blurb = "Its wings show the colours of tomorrow's dawn. On the darkest nights, that's a comfort.",
			rarity = "Mythic",
			look = { color = { 244, 176, 128 }, shape = "large soft moth, wide wings shading from rose to gold" },
			bonus = { pay = 0.2 },
		},
		{
			id = "veil_crane",
			name = "Veil Crane",
			blurb = "Trails ribbons of aurora as it flies. Where they brush the snow, it glows until morning.",
			rarity = "Mythic",
			look = { color = { 96, 220, 180 }, shape = "tall crane, long legs, wings trailing ribbons of light" },
			bonus = { ability = 0.2 },
		},

		-- Secret: from eggs only.
		{
			id = "thawling",
			name = "Thawling",
			blurb = "A rimeling that sat too near a hearth one night and decided it liked being warm. It drips a little when it's happy.",
			rarity = "Secret",
			look = { color = { 200, 230, 248 }, shape = "small icy blob, stubby arms, a steady drip, shy smile" },
			bonus = { speed = 0.3 },
		},
		{
			id = "hundredwinter",
			name = "Hundredwinter",
			blurb = "A tiny, very old hearthling who has seen a hundred winters and remembers every one. It likes a warm corner and a long story.",
			rarity = "Secret",
			look = {
				color = { 214, 200, 176 },
				shape = "tiny round creature, frost-white whiskers to the ground, wrapped in a scarf",
			},
			bonus = { pay = 0.3 },
		},
	},

	eggs = {
		{
			id = "snowdrift_egg",
			name = "Snowdrift Egg",
			blurb = "Cold to the touch at first. Hold it near the hearth and it starts to hum.",
			look = { color = { 236, 242, 250 }, shape = "round egg, snow-white shell, frosty speckles" },
			price = { currency = "MetaCurrency", amount = 50 },
			hatches = {
				{ pet = "thimble_vole", odds = 0.22 },
				{ pet = "pom_wren", odds = 0.22 },
				{ pet = "drift_lamb", odds = 0.2 },
				{ pet = "mossbun", odds = 0.16 },
				{ pet = "quilt_stoat", odds = 0.08 },
				{ pet = "spindle_hare", odds = 0.07 },
				{ pet = "snowshoe_badger", odds = 0.05 },
			},
		},
		{
			id = "pinecone_egg",
			name = "Pinecone Egg",
			blurb = "Scaled like a pinecone and smelling of resin. Something inside is rustling.",
			look = { color = { 132, 96, 60 }, shape = "tall egg, overlapping brown scales like a pinecone" },
			price = { currency = "MetaCurrency", amount = 200 },
			hatches = {
				{ pet = "oatprickle", odds = 0.22 },
				{ pet = "kettle_newt", odds = 0.2 },
				{ pet = "button_owlet", odds = 0.18 },
				{ pet = "wickmoth", odds = 0.12 },
				{ pet = "conebeak", odds = 0.11 },
				{ pet = "chimefox", odds = 0.07 },
				{ pet = "bellows_pup", odds = 0.06 },
				{ pet = "kettlecub", odds = 0.0395 },
				{ pet = "thawling", odds = 0.0005 },
			},
		},
		{
			id = "lantern_egg",
			name = "Lantern Egg",
			blurb = "Glows from the inside, faintly, like a lantern turned down low.",
			look = { color = { 255, 196, 112 }, shape = "egg with a warm amber glow, a little wire handle on top" },
			price = { currency = "MetaCurrency", amount = 750 },
			hatches = {
				{ pet = "cocoa_otter", odds = 0.22 },
				{ pet = "juniper_fawn", odds = 0.2 },
				{ pet = "mantel_owl", odds = 0.16 },
				{ pet = "tallow_toad", odds = 0.14 },
				{ pet = "northglow_lynx", odds = 0.1 },
				{ pet = "pineantler", odds = 0.09 },
				{ pet = "hearthback", odds = 0.045 },
				{ pet = "pinecrown_stag", odds = 0.035 },
				{ pet = "morrowmoth", odds = 0.0098 },
				{ pet = "hundredwinter", odds = 0.0002 },
			},
		},
		{
			id = "starglass_egg",
			name = "Starglass Egg",
			blurb = "A shell of starglass, clear as a frosty night, with something bright asleep inside.",
			look = { color = { 196, 214, 255 }, shape = "clear glassy egg, tiny points of starlight inside" },
			price = { currency = "PremiumCurrency", amount = 150 },
			hatches = {
				{ pet = "pineantler", odds = 0.36 },
				{ pet = "lanternshell", odds = 0.32 },
				{ pet = "pinecrown_stag", odds = 0.14 },
				{ pet = "snowmantle_goose", odds = 0.12 },
				{ pet = "morrowmoth", odds = 0.035 },
				{ pet = "veil_crane", odds = 0.024 },
				{ pet = "thawling", odds = 0.0006 },
				{ pet = "hundredwinter", odds = 0.0004 },
			},
		},
	},
})
