--!strict
--[[
	KindLooks: how each kind of block looks in graybox, by the kind names the
	sites' blueprints use. color is { r, g, b } in 0..255; material names an
	Enum.Material.
]]

return table.freeze({
	stone = table.freeze({ color = { 150, 152, 160 }, material = "Slate" }),
	timber = table.freeze({ color = { 140, 98, 62 }, material = "WoodPlanks" }),
	thatch = table.freeze({ color = { 198, 172, 108 }, material = "Fabric" }),
	ice = table.freeze({ color = { 176, 216, 240 }, material = "Ice" }),
	rope = table.freeze({ color = { 168, 138, 92 }, material = "Fabric" }),
	lantern = table.freeze({ color = { 255, 196, 112 }, material = "Neon" }),
	slate = table.freeze({ color = { 84, 92, 108 }, material = "Slate" }),
	glass = table.freeze({ color = { 196, 226, 255 }, material = "Glass" }),
})
