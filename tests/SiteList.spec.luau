local fs = require("@lune/fs")

local Blueprint = require("../src/shared/Blueprint")
local KindLooks = require("../src/shared/KindLooks")
local SiteList = require("../src/shared/SiteList")
local Test = require("./lib/Test")

Test.group("SiteList")

Test.case("every site has a stamped blueprint, and every kind in it has a look", function()
	local seen = {}
	for i, site in SiteList do
		Test.check(not seen[site.id], `{site.id} is listed once`)
		seen[site.id] = true
		local path = `src/shared/Blueprints/{site.id}.luau`
		Test.check(fs.isFile(path), `{site.id} is stamped`)
		local bp = Blueprint.load(require(`../src/shared/Blueprints/{site.id}`) :: any)
		for _, kind in bp.palette do
			Test.check(KindLooks[kind] ~= nil, `{site.id}'s kind {kind} has a look`)
		end
		if i > 1 then
			local before = Blueprint.load(require(`../src/shared/Blueprints/{SiteList[i - 1].id}`) :: any)
			Test.check(bp.count > before.count, `{site.id} is bigger than the site before it`)
		end
	end
end)

return nil
