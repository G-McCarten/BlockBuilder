--[[
	Runs the sim and prints what it found. From the repo root:

	  lune run tools/sim/run                              a solo run of the first site, no boss
	  lune run tools/sim/run -- --boss Hard --seeds 20    20 seeded runs against the Hard boss
	  lune run tools/sim/run -- --coop                    solo against 2, 3 and 4 players
	  lune run tools/sim/run -- --site TestHut --tool --pets 1
	  lune run tools/sim/run -- --site all --boss all --seeds 5    every site at every difficulty
	  lune run tools/sim/run -- --seeds 10 --report       every table below, over 10 runs

	Options: --site <Name>|all, --players <n>, --boss Normal|Hard|Nightmare|all
	(all is no boss and then each difficulty), --seeds <n>, --seed <first
	seed>, --coop, --tool, --pets <n>, --max <minutes>, --share <party share
	of pay>, --buy cheapest|value (how bots choose skills), --bought.

	Tables, averaged over the seeds (with one seed, that run's own), by
	minute every --every <n> minutes (default 5):

	  --clicks   blocks per click: the median a click placed itself, and with
	             the chains it set off
	  --skills   the minute each skill level was bought
	  --purse    run currency held and earned
	  --undo     blocks the boss undid
	  --pay      what each player's share of the site's payout pays per
	             minute played; with --coop, against the solo rate
	  --report   all of them

	With more than one site or difficulty, it ends with a table of them all.
]]

local process = require("@lune/process")

local Blueprint = require("../../src/shared/Blueprint")
local BossConfig = require("../../src/shared/BossConfig")
local SiteList = require("../../src/shared/SiteList")
local Sim = require("./Sim")
local Tuning = require("./Tuning")

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

local siteOption = option("--site") or "WoodcuttersLodge"
local siteNames = {}
if siteOption == "all" then
	for _, entry in SiteList do
		table.insert(siteNames, entry.id)
	end
else
	table.insert(siteNames, siteOption)
end

local bossOption = option("--boss")
local bossNames: { string } = {}
if bossOption == "all" then
	bossNames = { "none", "Normal", "Hard", "Nightmare" }
else
	table.insert(bossNames, bossOption or "none")
end
for _, name in bossNames do
	if name ~= "none" and (BossConfig :: any)[name] == nil then
		print(`no boss tuning called {name}`)
		process.exit(2)
	end
end

local buying = option("--buy") or "cheapest"
if buying ~= "cheapest" and buying ~= "value" then
	print(`no way of buying called {buying}: cheapest or value`)
	process.exit(2)
end

local seeds = tonumber(option("--seeds") or "1") or 1
local firstSeed = tonumber(option("--seed") or "1") or 1
local every = math.max(1, tonumber(option("--every") or "5") or 5)
local report = flag("--report")
local show = {
	clicks = report or flag("--clicks"),
	skills = report or flag("--skills"),
	purse = report or flag("--purse"),
	undo = report or flag("--undo"),
	pay = report or flag("--pay"),
}

local base = {
	tool = flag("--tool"),
	pets = tonumber(option("--pets") or "0"),
	maxMinutes = tonumber(option("--max") or "180"),
	partyShare = tonumber(option("--share") or ""),
	buying = buying,
}

local function percent(share: number): string
	return string.format("%.0f%%", share * 100)
end

-- The minutes a by-minute table shows: the first, every `every`, and the last.
local function shownMinutes(count: number): { number }
	local minutes = {}
	for m = 1, count do
		if m == 1 or m % every == 0 or m == count then
			table.insert(minutes, m)
		end
	end
	return minutes
end

-- What a single run did, as the sim has always printed it.
local function printRun(r: Sim.Result)
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

local function printClicks(s: Sim.Summary)
	print("\n| minute | runs | built | blocks per click | with chains |")
	print("|---|---|---|---|---|")
	local peak, peakAt = 0, 0
	for m, row in s.byMinute do
		if row.perClick > peak then
			peak, peakAt = row.perClick, m
		end
	end
	for _, m in shownMinutes(#s.byMinute) do
		local row = s.byMinute[m]
		print(
			string.format(
				"| %d | %d | %s | %.1f | %.1f |",
				m,
				row.runs,
				percent(row.built),
				row.perClick,
				row.withChains
			)
		)
	end
	print(string.format("\nA click places at most %.1f blocks itself, first at minute %d.", peak, peakAt))
end

local function printSkills(s: Sim.Summary)
	local most = 0
	for _, node in Tuning.nodes do
		if not node.clientOnly then
			most = math.max(most, node.max)
		end
	end
	local head, rule = { "| skill |" }, { "|---|" }
	for level = 1, most do
		table.insert(head, ` level {level} |`)
		table.insert(rule, "---|")
	end
	print(`\n{table.concat(head)}`)
	print(table.concat(rule))
	for _, node in Tuning.nodes do
		if not node.clientOnly then
			local cells = { `| {node.id} |` }
			local levels = s.boughtAt[node.id] or {}
			for level = 1, most do
				local cell = levels[level]
				if level > node.max then
					table.insert(cells, " |")
				elseif cell == nil then
					table.insert(cells, " not bought |")
				elseif cell.share < 0.995 then
					table.insert(cells, string.format(" %.1f (%s) |", cell.minute, percent(cell.share)))
				else
					table.insert(cells, string.format(" %.1f |", cell.minute))
				end
			end
			print(table.concat(cells))
		end
	end
	print("\nThe mean minute each level was bought; a share is how many players bought it, where not all did.")
end

local function printPurse(s: Sim.Summary)
	print("\n| minute | held | earned |")
	print("|---|---|---|")
	for _, m in shownMinutes(#s.byMinute) do
		local row = s.byMinute[m]
		print(string.format("| %d | %.0f | %.0f |", m, row.purse, row.earned))
	end
end

local function printUndo(s: Sim.Summary)
	print("\n| minute | runs | built | undone per minute |")
	print("|---|---|---|---|")
	local peak, peakAt = 0, 0
	for m, row in s.byMinute do
		if row.undone > peak then
			peak, peakAt = row.undone, m
		end
	end
	for _, m in shownMinutes(#s.byMinute) do
		local row = s.byMinute[m]
		print(string.format("| %d | %d | %s | %.0f |", m, row.runs, percent(row.built), row.undone))
	end
	local by = s.undoneBy
	print(
		string.format(
			"\nUndone per run: %.0f (nearest %.0f, markers %.0f, collapses %.0f), %.1f a minute, at most %.0f in minute %d.",
			s.undone,
			by.nearest or 0,
			by.marker or 0,
			by.collapse or 0,
			s.undoneRate,
			peak,
			peakAt
		)
	)
end

local function line(label: string, players: number, s: Sim.Summary): string
	return string.format(
		"%s: %d players, %d run%s, mean %.1f min (%.1f to %.1f)%s",
		label,
		players,
		s.runs,
		if s.runs == 1 then "" else "s",
		s.mean,
		s.best,
		s.worst,
		if s.unfinished > 0 then `, {s.unfinished} unfinished` else ", all finished"
	)
end

local function summarise(bp: any, bossName: string, players: number): Sim.Summary
	local results = {}
	for seed = firstSeed, firstSeed + seeds - 1 do
		local options = table.clone(base) :: any
		options.blueprint = bp
		options.boss = if bossName == "none" then nil else (BossConfig :: any)[bossName]
		options.players = players
		options.seed = seed
		local r = Sim.run(options)
		if seeds == 1 then
			printRun(r)
		end
		table.insert(results, r)
	end
	local s = Sim.summarise(results)
	local label = `{bp.name}{if bossName ~= "none" then " vs " .. bossName else ""}`
	print(line(label, players, s))
	if show.clicks then
		printClicks(s)
	end
	if show.skills then
		printSkills(s)
	end
	if show.purse then
		printPurse(s)
	end
	if show.undo then
		printUndo(s)
	end
	if show.pay and not flag("--coop") then
		print(string.format("\nEach player's share of the payout pays %.2f a minute played.", s.pay))
	end
	return s
end

local function printCoop(solo: Sim.Summary, parties: { [number]: Sim.Summary })
	print("\n| players | time | of the solo time | payout a minute, each | of the solo rate |")
	print("|---|---|---|---|---|")
	print(string.format("| 1 | %.1f min | 1.00 | %.2f | 1.00 |", solo.mean, solo.pay))
	for players = 2, 4 do
		local s = parties[players]
		print(
			string.format(
				"| %d | %.1f min | %.2f | %.2f (%.2f to %.2f) | %.2f |",
				players,
				s.mean,
				s.mean / solo.mean,
				s.pay,
				s.payLow,
				s.payHigh,
				if solo.pay > 0 then s.pay / solo.pay else 0
			)
		)
	end
end

-- grid[site][boss]: each summary, for the closing table.
local grid: { [string]: { [string]: Sim.Summary } } = {}
for _, siteName in siteNames do
	local bp = Blueprint.load(require(`../../src/shared/Blueprints/{siteName}`) :: any)
	grid[siteName] = {}
	for _, bossName in bossNames do
		if flag("--coop") then
			local solo = summarise(bp, bossName, 1)
			local parties = {}
			for players = 2, 4 do
				parties[players] = summarise(bp, bossName, players)
				print(
					string.format("  %d players take %.2f of the solo time", players, parties[players].mean / solo.mean)
				)
			end
			if show.pay then
				printCoop(solo, parties)
			end
			grid[siteName][bossName] = solo
		else
			grid[siteName][bossName] = summarise(bp, bossName, tonumber(option("--players") or "1") or 1)
		end
	end
end

if #siteNames > 1 or #bossNames > 1 then
	local head, rule = { "| site |" }, { "|---|" }
	for _, bossName in bossNames do
		table.insert(head, ` {bossName} |`)
		table.insert(rule, "---|")
	end
	print(`\n{table.concat(head)}`)
	print(table.concat(rule))
	for _, siteName in siteNames do
		local cells = { `| {siteName} |` }
		local none = grid[siteName].none
		for _, bossName in bossNames do
			local s = grid[siteName][bossName]
			local cell = string.format("%.1f (%.1f to %.1f)", s.mean, s.best, s.worst)
			if none and bossName ~= "none" then
				cell ..= string.format(", %+.0f%%", (s.mean / none.mean - 1) * 100)
			end
			if s.unfinished > 0 then
				cell ..= `, {s.unfinished} unfinished`
			end
			table.insert(cells, ` {cell} |`)
		end
		print(table.concat(cells))
	end
	print(`\nMinutes, mean (fastest to slowest) over {seeds} seeded run{if seeds == 1 then "" else "s"} each.`)
end
