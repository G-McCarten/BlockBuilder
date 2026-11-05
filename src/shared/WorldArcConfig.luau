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
	  weather     particles a second falling around the player: here, snow
	  skyGlow     0 to 1, how strongly the light in the sky shows: here, the aurora
]]

return table.freeze({
	{
		at = 0,
		fogEnd = 220,
		fogColor = { 205, 214, 228 },
		clockTime = 15.5,
		brightness = 1.6,
		density = 0.42,
		weather = 140,
		skyGlow = 0,
	},
	{
		at = 0.5,
		fogEnd = 480,
		fogColor = { 150, 164, 192 },
		clockTime = 17.6,
		brightness = 1.2,
		density = 0.3,
		weather = 60,
		skyGlow = 0,
	},
	{
		at = 0.85,
		fogEnd = 900,
		fogColor = { 62, 72, 104 },
		clockTime = 19.5,
		brightness = 0.85,
		density = 0.22,
		weather = 14,
		skyGlow = 0.35,
	},
	{
		at = 1,
		fogEnd = 1600,
		fogColor = { 22, 30, 58 },
		clockTime = 21,
		brightness = 0.6,
		density = 0.15,
		weather = 0,
		skyGlow = 1,
	},
})
