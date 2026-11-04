--[[
	A minimal test harness. Test.case runs a case at once and records the result;
	tests/run.luau prints the summary.
]]

local Test = {}

local passed = 0
local failures: { string } = {}
local group = ""

function Test.group(name: string)
	group = name
end

function Test.case(name: string, fn: () -> ())
	local started = os.clock()
	local ok, err = xpcall(fn, debug.traceback)
	local ms = (os.clock() - started) * 1000
	local label = `{group}: {name}`
	if ok then
		passed += 1
		print(string.format("  ok    %s (%.0f ms)", label, ms))
	else
		table.insert(failures, `{label}\n{err}`)
		print(`  FAIL  {label}`)
	end
end

function Test.check(condition: any, message: string?)
	if not condition then
		error(message or "check failed", 2)
	end
end

function Test.equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

-- Prints the summary and returns how many cases failed.
function Test.summary(): number
	for _, failure in failures do
		print(`\n{failure}`)
	end
	print(`\n{passed} passed, {#failures} failed`)
	return #failures
end

return Test
