--!strict
--[[
	Lore: Frostward's journal pages. A draft for the fork's LoreConfig, for
	its Journal and Notes to show.

	sites  the pages of each site, by SiteList id, in the order they're
	       found
	boss   the BOSS's story, in the order it's told: gently, because the
	       Rime isn't a villain, only a very old cold that doesn't know
	       better

	Each page: id (stable and never shown), title, from (who wrote it, or
	where it was found) and text.
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
	sites = {
		WoodcuttersLodge = {
			{
				id = "lodge_first_stone",
				title = "The First Stone",
				from = "The woodcutters' daybook",
				text = "We set the first stone where the pines thin out and the snow lies shallow. A lodge wants three things, the old woodcutter says: timber that remembers the tree, stone that remembers the hill, and thatch enough to keep them both dry.",
			},
			{
				id = "lodge_thatch",
				title = "Thatch Before Dark",
				from = "The woodcutters' daybook",
				text = "The thatch went up in a hurry, armful after armful, while the light went copper behind the hills. The hearthlings kept stealing tufts of it for their beds. We let them. There was plenty, and they'd earned it.",
			},
			{
				id = "lodge_chimney",
				title = "The Chimney Draws",
				from = "The woodcutters' daybook",
				text = "Tonight the chimney drew for the first time. The smoke went straight up into a sky full of stars, and far down the valley someone lit a lantern back at us. We aren't the only ones out here after all.",
			},
		},
		IceBridge = {
			{
				id = "bridge_river_sleeps",
				title = "The River Sleeps",
				from = "The bridge-keeper's notes",
				text = "The river froze in a single night, and the far bank was suddenly only a gorge away. A bridge of ice is the only kind the river forgives, the old folk say. It takes the bridge back in spring, gently, and we build it again next winter.",
			},
			{
				id = "bridge_knots",
				title = "A Knot for Everyone",
				from = "The bridge-keeper's notes",
				text = "Every rope in the rail is knotted by hand, one knot for each of us who'll cross. Mine has a little bell tied into it, so the hearthlings can find me in the fog.",
			},
			{
				id = "bridge_first_sled",
				title = "The First Sled Over",
				from = "The bridge-keeper's notes",
				text = "The first sled went over this morning, piled with firewood and pulled by two very proud sled beasts. The ice sang under the runners. Nobody fell in. Everybody cheered anyway.",
			},
		},
		Watchtower = {
			{
				id = "tower_seen",
				title = "Seen from Everywhere",
				from = "The watch log",
				text = "From the top you can see every hold in the valley, and on a clear night every hold can see you. That's what a watchtower is for, the builders say: not for watching out, but for being seen.",
			},
			{
				id = "tower_oil",
				title = "Lantern Oil",
				from = "The watch log",
				text = "The great lantern drinks a cup of oil a night. The hearthlings carry it up in thimbles, one stair at a time, and nobody has had the heart to show them the bucket.",
			},
			{
				id = "tower_night_four",
				title = "Night Four",
				from = "The watch log",
				text = "Snow. Quiet. Saw the Rime out on the far ice, sitting very still, looking at our light. It didn't come any closer. Left a mug of cocoa on the sill, in case.",
			},
		},
		GreatHall = {
			{
				id = "hall_room",
				title = "Room for Everyone",
				from = "The hall's guest book",
				text = "A hall big enough for the whole valley, the elders said, with a hearth at each end so nobody sits in the cold. We laughed. Then we started laying.",
			},
			{
				id = "hall_slate_glass",
				title = "Slate and Glass",
				from = "The hall's guest book",
				text = "The slate goes on like the scales of a fish, each one over the last. The glass came across the Ice Bridge wrapped in wool, every pane of it, and not one cracked.",
			},
			{
				id = "hall_last_brick",
				title = "The Last Brick",
				from = "The hall's guest book",
				text = "Every window is lit. The aurora opened over the roof as the last brick was laid, green and gold and slow, and the whole valley went quiet to watch. Then somebody found a fiddle, and nobody slept at all.",
			},
		},
	},

	boss = {
		{
			id = "rime_before",
			title = "Before the Holds",
			from = "As the old folk tell it",
			text = "Long before the first stone, the valley belonged to the snow. The Rime was its first frost, and for a hundred winters it had the place to itself: no smoke, no lanterns, no footprints but its own.",
		},
		{
			id = "rime_why",
			title = "Why It Comes",
			from = "As the old folk tell it",
			text = "The Rime doesn't hate our bricks. It remembers the valley bare, and every new wall is something it doesn't know. So it touches them, the way you'd run a hand along a wall in the dark, and the frost gets into the seams, and the bricks come loose.",
		},
		{
			id = "rime_stillness",
			title = "The Stillness",
			from = "As the old folk tell it",
			text = "Where the Rime rests, a stillness spreads, and no brick will set inside it. It isn't cruel. It's only very tired and very cold, and it has forgotten that anyone else might be busy.",
		},
		{
			id = "rime_marks_and_chains",
			title = "Marks and Chains",
			from = "As the old folk tell it",
			text = "On colder nights it leaves frost marks on the walls, little stars of ice that crack everything near them if they're left alone. When it's truly worried, it ties a hold down with chains of ice at the corners, as if to keep it from floating away.",
		},
		{
			id = "rime_shooing",
			title = "Shooing",
			from = "As the old folk tell it",
			text = "You can't fight the frost, the old folk say, but you can stand close and be warm at it. The Rime can't bear a warm heart near it for long. It drifts away, and comes back, and drifts away again.",
		},
		{
			id = "rime_rimelings",
			title = "Rimelings",
			from = "As the old folk tell it",
			text = "The little ones that tumble after it are rimelings, bits of the Rime that broke off in the wind. They're curious and clumsy, and most of them have never once been warm. One or two, they say, have found a hearth and stayed.",
		},
		{
			id = "rime_lights",
			title = "When the Lights Come On",
			from = "As the old folk tell it",
			text = "When a hall is nearly done, the Rime lets go of everything it holds and goes to sit at the edge of the light. Some say it's watching the aurora. Some say it's waiting to be asked in. Every spring there are frost ferns on the windows of every finished hall, and nobody in the valley has ever wiped them away.",
		},
	},
})
