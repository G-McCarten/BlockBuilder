--[[
	check: everything the repo can verify on its own, in one command. From the
	repo root:

	  lune run tools/check

	Runs StyLua's format check, every test, and the stamp check of every
	blueprint source, and exits non-zero if any of them fails.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local failures = {}

local function run(label: string, program: string, args: { string })
	local result = process.exec(program, args)
	if result.ok then
		print(`ok    {label}`)
	else
		print(`FAIL  {label}`)
		print(result.stdout)
		print(result.stderr)
		table.insert(failures, label)
	end
end

run("format", "stylua", { "--check", "src", "tools", "tests" })
run("tests", "lune", { "run", "tests/run" })
for _, entry in fs.readDir("tools/blueprints") do
	local name = string.match(entry, "^([%w_]+)%.luau$") or string.match(entry, "^([%w_]+)%.rbxmx?$")
	if name then
		run(`stamp {name}`, "lune", { "run", "tools/stamp_blueprint", name, "--check" })
	end
end

if #failures > 0 then
	print(`\n{#failures} failed: {table.concat(failures, ", ")}`)
	process.exit(1)
end
print("\nall checks passed")
