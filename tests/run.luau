--[[
	Runs every test. From the repo root: lune run tests/run
]]

local process = require("@lune/process")
local Test = require("./lib/Test")

local started = os.clock()
require("./Blueprint.spec")
require("./BlueprintValidator.spec")
require("./BuildSite.spec")
require("./SiteCodec.spec")

local failed = Test.summary()
print(string.format("%.1f s", os.clock() - started))
process.exit(if failed > 0 then 1 else 0)
