--[[
	ModelSource: reads a Studio model of grid-aligned parts into a Blueprint.Source.

	Build a site in Studio from parts sized in whole cells, BLOCK_STUDS on a
	side, and export it as .rbxm or .rbxmx to tools/blueprints/<Name>.
	docs/authoring.md walks through it. A part becomes one block for every
	cell it covers:

	  cell    the cells the part fills, shifted so the lowest sit at 0 on every
	          axis. The lowest layer rests on the ground.
	  kind    the part's Kind attribute, else the Kind of the nearest Model or
	          Folder around it that has one, else the part's name. The palette
	          lists the kinds in alphabetical order.
	  facing  the part's quarter turns about y: 0 faces -z, 1 faces -x, 2 faces
	          +z, 3 faces +x. Every cell of a part takes its facing.

	A part must be a whole number of cells along each axis, upright, turned
	only in quarter turns about y, with its faces on the grid, and no two parts
	may cover one cell. Anything else is refused with a message naming the part
	and where it is.

	Stages add extra ordering, such as roof after walls. Stage is a number
	attribute on a part, Model or Folder, and a part takes the nearest one the
	way it takes Kind. A stage orders what sits side by side in one group: the
	Model or Folder holding the instance the attribute is on, or the export's
	top level. In a group, every block of a stage waits for the top corners of
	the stage before it: of that stage's blocks on its highest layer, the ones
	with the least and greatest x + z and x - z, at most four. Only the order of
	the numbers counts, so 1.5 fits between 1 and 2. Blocks with no Stage in a
	group aren't ordered there. Groups nest: walls and roof can be stages of a
	house while the roof's own parts have stages within the roof.

	It's cheap in supports. A block waits through the block beneath it when
	that one is of its stage, so only a stage's lowest blocks and overhangs
	carry the four, and a stage waits only for the one before, which waits for
	the one before that. It can't make a cycle by itself: each of its supports
	points to an earlier stage of the same group, and the blocks of an inner
	group all share one stage in the groups outside it. A cycle can still come
	from a block resting, directly or through others, on a block of a later
	stage, such as walls marked after the roof they hold up. BlueprintValidator
	finds it, and explain names the parts behind the slots it reports.
]]

local roblox = require("@lune/roblox")

local Blueprint = require("../../src/shared/Blueprint")

local ModelSource = {}

local SPAN = Blueprint.SPAN
local EPSILON = 0.01
local AXES = { "x", "y", "z" }
-- Toward each corner of a layer: the least x + z, the greatest x - z, the
-- least x - z, the greatest x + z.
local CORNERS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

local function near(v: number, target: number): boolean
	return math.abs(v - target) <= EPSILON
end

-- Refusals are for whoever built the model, so they leave out this file's line.
local function refuse(message: string): never
	error(message, 0)
end

-- A number as Studio's Properties window shows it, to two places at most.
local function show(v: number): string
	local text = string.gsub(string.format("%.2f", v), "%.?0+$", "")
	return if text == "-0" then "0" else text
end

-- Where a part is, so a message finds it among parts that share a name.
local function where(part): string
	local p = part.CFrame.Position
	return `{part:GetFullName()} at ({show(p.X)}, {show(p.Y)}, {show(p.Z)})`
end

local function label(instance): string
	return if instance:IsA("BasePart") then where(instance) else instance:GetFullName()
end

local function attribute(instance, name: string, valueType: string): any
	local value = instance:GetAttribute(name)
	if value ~= nil and type(value) ~= valueType then
		refuse(`{label(instance)}: its {name} attribute is a {typeof(value)}; make it a {valueType}`)
	end
	return value
end

local function kindOf(instance): string?
	local kind = attribute(instance, "Kind", "string")
	return if kind == "" then nil else kind
end

local function stageOf(instance): number?
	local stage = attribute(instance, "Stage", "number")
	if stage ~= nil and (stage ~= stage or math.abs(stage) == math.huge) then
		refuse(`{label(instance)}: its Stage is {stage}; make it a finite number`)
	end
	return stage
end

-- The blocks, by slot, at a group's top corners.
local function corners(cells, top: { number }): { number }
	local picked = {}
	for _, d in CORNERS do
		local best, bestScore, bestAlong
		for _, i in top do
			local c = cells[i]
			local score, along = d[1] * c.x + d[2] * c.z, d[1] * c.x
			if best == nil or score > bestScore or (score == bestScore and along > bestAlong) then
				best, bestScore, bestAlong = i, score, along
			end
		end
		if not table.find(picked, best) then
			table.insert(picked, best)
		end
	end
	return picked
end

-- Reads parts from the given instances and their descendants. Besides the
-- Source's fields, the result has from, the part each block came from, and
-- stages, a line for each group with stages.
function ModelSource.fromInstances(roots: { any }, name: string, blockStuds: number)
	-- Each part with the kind it takes and its stages: a { scope, stage } for
	-- each group that orders it, outermost first. A scope is one group.
	local parts = {}
	local scopes = {}
	local function newScope(scopeName: string)
		local scope = { name = scopeName, values = {}, groups = {} }
		table.insert(scopes, scope)
		return scope
	end
	local function visit(instance, scope, kind: string?, stages)
		local isPart = instance:IsA("BasePart")
		if isPart or instance:IsA("Model") or instance:IsA("Folder") then
			local stage = stageOf(instance)
			local staged = stages
			if stage ~= nil then
				staged = table.clone(stages)
				table.insert(staged, { scope = scope, stage = stage })
			end
			local own = kindOf(instance)
			if not isPart then
				local inner = newScope(instance:GetFullName())
				for _, child in instance:GetChildren() do
					visit(child, inner, own or kind, staged)
				end
				return
			end
			table.insert(parts, { part = instance, kind = own or kind or instance.Name, stages = staged })
		end
		-- A part's children, like anything else's, inherit from the group
		-- around it, never from the part.
		for _, child in instance:GetChildren() do
			visit(child, scope, kind, stages)
		end
	end
	local top = newScope("the top level")
	for _, root in roots do
		visit(root, top, nil, {})
	end
	if #parts == 0 then
		refuse(`{name}: the model has no parts`)
	end

	-- Each part's lowest cell and size in cells, checked before any cell is
	-- listed, so one huge part can't run the tool out of memory.
	local total, biggest = 0, nil
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local lowPart, highPart = {}, {}
	for _, info in parts do
		local part = info.part
		local here = where(part)
		info.where = here
		local cf = part.CFrame
		local up = cf.UpVector
		if not (near(up.X, 0) and near(up.Z, 0) and up.Y > 0) then
			refuse(`{here}: isn't upright; parts may only turn about y`)
		end
		local look = cf.LookVector
		local angle = math.atan2(-look.X, -look.Z)
		local turn = angle / (math.pi / 2)
		if not near(turn, math.round(turn)) then
			refuse(`{here}: is turned {show(math.deg(angle))} degrees, not a whole quarter turn`)
		end
		info.facing = math.round(turn) % 4

		-- A quarter turn lays the part's x along the world's z.
		local size = part.Size
		local extent = { size.X, size.Y, size.Z }
		if info.facing % 2 == 1 then
			extent[1], extent[3] = extent[3], extent[1]
		end
		local count = {}
		for axis = 1, 3 do
			local n = extent[axis] / blockStuds
			count[axis] = math.round(n)
			if not near(n, count[axis]) or count[axis] < 1 then
				refuse(
					`{here}: size ({show(size.X)}, {show(size.Y)}, {show(size.Z)}) isn't a whole number `
						.. `of {blockStuds}-stud cells on every axis`
				)
			end
		end
		local p = cf.Position
		local centre = { p.X, p.Y, p.Z }
		local first = {}
		for axis = 1, 3 do
			local corner = (centre[axis] - extent[axis] / 2) / blockStuds
			first[axis] = math.round(corner)
			if not near(corner, first[axis]) then
				local off = show(math.abs(corner - first[axis]) * blockStuds)
				refuse(
					`{here}: is off the {blockStuds}-stud grid along {AXES[axis]}, `
						.. `by {off} stud{if off == "1" then "" else "s"}`
				)
			end
		end
		info.first, info.count = first, count

		info.cells = count[1] * count[2] * count[3]
		total += info.cells
		if biggest == nil or info.cells > biggest.cells then
			biggest = info
		end
		for axis = 1, 3 do
			if first[axis] < low[axis] then
				low[axis], lowPart[axis] = first[axis], here
			end
			local last = first[axis] + count[axis] - 1
			if last > high[axis] then
				high[axis], highPart[axis] = last, here
			end
		end
	end
	for axis = 1, 3 do
		local across = high[axis] - low[axis] + 1
		if across > SPAN then
			refuse(
				`the model spans {across} cells along {AXES[axis]}, more than the {SPAN} a site can hold, `
					.. `from {lowPart[axis]} to {highPart[axis]}`
			)
		end
	end
	if total > Blueprint.MAX_SLOTS then
		refuse(
			`the model's parts cover {total} cells, more than the {Blueprint.MAX_SLOTS} blocks a site can hold; `
				.. `the biggest, {biggest.where}, covers {biggest.cells}`
		)
	end

	-- One cell for each cell of each part, shifted so the lowest sit at 0.
	local cells = table.create(total)
	local taken: { [number]: number } = {}
	for index, info in parts do
		local f, n = info.first, info.count
		for y = f[2], f[2] + n[2] - 1 do
			for z = f[3], f[3] + n[3] - 1 do
				for x = f[1], f[1] + n[1] - 1 do
					local cx, cy, cz = x - low[1], y - low[2], z - low[3]
					local k = Blueprint.key(cx, cy, cz)
					local other = taken[k]
					if other ~= nil then
						local at = `({show((x + 0.5) * blockStuds)}, {show((y + 0.5) * blockStuds)}, `
							.. `{show((z + 0.5) * blockStuds)})`
						refuse(`{parts[other].where} and {info.where} both cover the cell centred at {at}`)
					end
					taken[k] = index
					table.insert(cells, { x = cx, y = cy, z = cz, part = index, order = (cy * SPAN + cz) * SPAN + cx })
				end
			end
		end
	end

	-- Lowest layer first, so slot order doesn't depend on the model's.
	table.sort(cells, function(a, b)
		return a.order < b.order
	end)

	local kinds: { [string]: boolean } = {}
	local slotAt: { [number]: number } = {}
	local blocks = table.create(#cells)
	local from = table.create(#cells)
	for i, c in cells do
		local info = parts[c.part]
		kinds[info.kind] = true
		slotAt[Blueprint.key(c.x, c.y, c.z)] = i
		blocks[i] = { x = c.x, y = c.y, z = c.z, kind = info.kind, facing = info.facing }
		from[i] = info.where
	end
	local palette = {}
	for kind in kinds do
		table.insert(palette, kind)
	end
	table.sort(palette)

	-- Each group's stages: their blocks, and the blocks on their highest layer.
	-- Slots run lowest layer first, so a stage's highest layer comes last.
	for i, c in cells do
		for _, entry in parts[c.part].stages do
			local scope, stage = entry.scope, entry.stage
			local group = scope.groups[stage]
			if group == nil then
				group = { members = {}, topY = c.y, top = {} }
				scope.groups[stage] = group
				table.insert(scope.values, stage)
			end
			table.insert(group.members, i)
			if c.y > group.topY then
				group.topY, group.top = c.y, {}
			end
			table.insert(group.top, i)
		end
	end
	local function stageIn(slot: number, scope): number?
		for _, entry in parts[cells[slot].part].stages do
			if entry.scope == scope then
				return entry.stage
			end
		end
		return nil
	end

	local after: { [number]: { number } } = {}
	local summary = {}
	for _, scope in scopes do
		if #scope.values > 0 then
			table.sort(scope.values)
			local counts = {}
			for v, stage in scope.values do
				local group = scope.groups[stage]
				local n = #group.members
				table.insert(counts, `{show(stage)} ({n} block{if n == 1 then "" else "s"})`)
				if v > 1 then
					local wanted = corners(cells, scope.groups[scope.values[v - 1]].top)
					for _, i in group.members do
						local c = cells[i]
						local beneath = if c.y > 0 then slotAt[Blueprint.key(c.x, c.y - 1, c.z)] else nil
						-- Resting on a block of its own stage, it already waits through that one.
						if beneath == nil or stageIn(beneath, scope) ~= stage then
							local list = after[i]
							if list == nil then
								list = {}
								after[i] = list
							end
							table.move(wanted, 1, #wanted, #list + 1, list)
						end
					end
				end
			end
			table.insert(summary, `{scope.name}: {table.concat(counts, ", ")}`)
		end
	end
	-- In slot order, however many groups added to the list.
	for i, list in after do
		table.sort(list)
		blocks[i].after = list
	end

	return { name = name, palette = palette, blocks = blocks, from = from, stages = summary }
end

-- Reads a .rbxm or .rbxmx file's contents.
function ModelSource.fromContents(contents: string, name: string, blockStuds: number)
	return ModelSource.fromInstances(roblox.deserializeModel(contents), name, blockStuds)
end

-- Lines naming the parts behind the slots a BlueprintValidator message
-- reports, for a source read from a model. A source from a script has none.
function ModelSource.explain(source, message: string): { string }
	local from = source.from
	local lines = {}
	if from == nil then
		return lines
	end
	local slot = string.match(message, "^slot (%d+) ")
	if slot and from[tonumber(slot) :: number] then
		table.insert(lines, `from {from[tonumber(slot) :: number]}`)
	end
	local cycle = string.match(message, "^supports form a cycle.-including ([%d, ]+)$")
	if cycle then
		for s in string.gmatch(cycle, "%d+") do
			if from[tonumber(s) :: number] then
				table.insert(lines, `slot {s} from {from[tonumber(s) :: number]}`)
			end
		end
		table.insert(
			lines,
			"in a model, a cycle means a block rests, directly or through others, on one of a later Stage"
		)
	end
	return lines
end

return ModelSource
