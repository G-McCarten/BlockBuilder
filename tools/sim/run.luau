--[[
	Runs the sim and prints what it found. From the repo root:

	  lune run tools/sim/run                              a solo run of the first site, no boss
	  lune run tools/sim/run -- --boss Hard --seeds 20    20 seeded runs against the Hard boss
	  lune run tools/sim/run -- --coop                    solo against 2, 3 and 4 players
	  lune run tools/sim/run -- --site TestHut --tool --pets 1

	Options: --site <Name>, --players <n>, --boss Normal|Hard|Nightmare,
	--seeds <n>, --coop, --tool, --pets <n>, --max <minutes>, --share <party
	share of pay>, --bought.
]]

local process = require("@lune/process")

local Blueprint = require("../../src/shared/Blueprint")
local BossConfig = require("../../src/shared/BossConfig")
local Sim = require("./Sim")

local args = process.args
local function option(name: string): string?
	for i, a in args do
		if a == name then
			return args[i + 1] or ""
		end
	end
	return nil
end
local function flag(name: string): boolean
	return table.find(args, name) ~= nil
end

local siteName = option("--site") or "WoodcuttersLodge"
local bp = Blueprint.load(require(`../../src/shared/Blueprints/{siteName}`) :: any)
local bossName = option("--boss")
local boss = if bossName then (BossConfig :: any)[bossName] else nil
if bossName and boss == nil then
	print(`no boss tuning called {bossName}`)
	process.exit(2)
end
local seeds = tonumber(option("--seeds") or "1") or 1
local base = {
	blueprint = bp,
	boss = boss,
	tool = flag("--tool"),
	pets = tonumber(option("--pets") or "0"),
	maxMinutes = tonumber(option("--max") or "180"),
	partyShare = tonumber(option("--share") or ""),
}

local function summarise(label: string, players: number): number
	local total, worst, best, unfinished = 0, 0, math.huge, 0
	for seed = 1, seeds do
		local options = table.clone(base) :: any
		options.players = players
		options.seed = seed
		local r = Sim.run(options)
		if not r.finished then
			unfinished += 1
		end
		total += r.minutes
		worst = math.max(worst, r.minutes)
		best = math.min(best, r.minutes)
		if seeds == 1 then
			local marks = {}
			for _, minute in { 5, 10, 15, 20, 30, 45, 60 } do
				local p = r.percentAt[minute]
				if p then
					table.insert(marks, string.format("%d min %.0f%%", minute, p * 100))
				end
			end
			local events = {}
			for kind, n in r.events do
				table.insert(events, `{kind} {n}`)
			end
			table.sort(events)
			print(`  built by: {table.concat(marks, ", ")}`)
			print(`  clicks {r.clicks}, purchases {r.purchases}, events: {table.concat(events, ", ")}`)
			local causes = {}
			for cause, n in r.byCause do
				table.insert(causes, `{cause} {n}`)
			end
			table.sort(causes)
			print(`  blocks by cause: {table.concat(causes, ", ")}`)
			if flag("--bought") then
				print(`  bought: {table.concat(r.bought, " ")}`)
			end
		end
	end
	local mean = total / seeds
	print(
		string.format(
			"%s: %s players, %d run%s, mean %.1f min (%.1f to %.1f)%s",
			label,
			tostring(players),
			seeds,
			if seeds == 1 then "" else "s",
			mean,
			best,
			worst,
			if unfinished > 0 then `, {unfinished} unfinished` else ", all finished"
		)
	)
	return mean
end

local label = `{siteName}{if bossName then " vs " .. bossName else ""}`
if flag("--coop") then
	local solo = summarise(label, 1)
	for players = 2, 4 do
		local mean = summarise(label, players)
		print(string.format("  %d players take %.2f of the solo time", players, mean / solo))
	end
else
	summarise(label, tonumber(option("--players") or "1") or 1)
end
