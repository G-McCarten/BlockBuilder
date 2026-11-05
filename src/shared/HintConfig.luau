--!strict
--[[
	HintConfig: the words of each hint (see Hints), built from Theme.
]]

local Theme = require("./Theme")

local function capitalise(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local works = Theme.BossWorks

return table.freeze({
	lay = `Click a glowing ghost to {Theme.PlaceVerb.base} a {Theme.Block.one}. Hold to keep going.`,
	buy = `You can afford a skill: press 1, or use the shop on the left.`,
	boss = `{capitalise(Theme.Boss.name)} is undoing your work. Walk up to it to shoo it away.`,
	marker = `Walk to the {works.marker} to break it before it bursts.`,
	bound = `{capitalise(works.binding)}s hold the {Theme.Site.one}: walk to each corner to break them.`,
	peace = `Nothing can be laid in {Theme.Boss.name}'s {works.peace}. Walk in and shoo it out.`,
	crew = `Press Q to send the {Theme.Ability} across the {Theme.Site.one}.`,
	hoist = `The work has climbed. Step on a blue {Theme.Hoist} pad to ride up.`,
})
