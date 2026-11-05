local BossConfig = require("../src/shared/BossConfig")
local Sim = require("../tools/sim/Sim")
local Sites = require("./lib/Sites")
local Test = require("./lib/Test")

Test.group("Sim")

Test.case("bots finish the TestHut solo, in co-op, and against every boss", function()
	local hut = Sites.hut()
	for _, name in { "none", "Normal", "Hard", "Nightmare" } do
		for _, players in { 1, 3 } do
			local r = Sim.run({
				blueprint = hut,
				players = players,
				seed = 7,
				boss = if name == "none" then nil else (BossConfig :: any)[name],
				maxMinutes = 60,
			})
			Test.check(r.finished, `{name}, {players} players: unfinished after {r.minutes} minutes`)
		end
	end
end)

Test.case("a party finishes faster than one player", function()
	local hut = Sites.hut()
	local solo = Sim.run({ blueprint = hut, players = 1, seed = 3 })
	local party = Sim.run({ blueprint = hut, players = 3, seed = 3 })
	Test.check(party.minutes < solo.minutes * 0.6, `solo {solo.minutes}, party of 3 {party.minutes}`)
end)

return nil
