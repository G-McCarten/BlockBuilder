--!strict
--[[
	WorldArcConfig: Frostward's WORLD_ARC. As the hold rises, the blizzard
	thins, the light goes from late afternoon to night, the fog lifts, and an
	aurora opens over the finished hall.

	Each key is a share built and the look there (see WorldArc):

	  fogEnd      studs to full fog
	  fogColor    the fog, { r, g, b }
	  clockTime   hour of the day
	  brightness  Lighting brightness
	  density     Atmosphere density
	  snow        snowflakes a second around the player
	  aurora      0 to 1, how strongly the aurora shows
]]

return table.freeze({
	{
		at = 0,
		fogEnd = 220,
		fogColor = { 205, 214, 228 },
		clockTime = 15.5,
		brightness = 1.6,
		density = 0.42,
		snow = 140,
		aurora = 0,
	},
	{
		at = 0.5,
		fogEnd = 480,
		fogColor = { 150, 164, 192 },
		clockTime = 17.6,
		brightness = 1.2,
		density = 0.3,
		snow = 60,
		aurora = 0,
	},
	{
		at = 0.85,
		fogEnd = 900,
		fogColor = { 62, 72, 104 },
		clockTime = 19.5,
		brightness = 0.85,
		density = 0.22,
		snow = 14,
		aurora = 0.35,
	},
	{
		at = 1,
		fogEnd = 1600,
		fogColor = { 22, 30, 58 },
		clockTime = 21,
		brightness = 0.6,
		density = 0.15,
		snow = 0,
		aurora = 1,
	},
})
