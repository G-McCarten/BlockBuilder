--!strict
--[[
	Prediction: shows a player's own clicks at once, before the server answers.

	The client keeps a mirror of the site, a BuildSite fed through setRemote.
	On a click, predict() places the aimed slot in the mirror straight away, so
	its block shows and the slot above it opens for the next click. The
	request goes to the server with an id.

	  predict   places the aimed slot in the mirror now, remembering how it was
	  receive   applies a slot's state from the server. A placed state
	            confirms a prediction at once. Anything else waits while the
	            slot is predicted and unanswered, so the block doesn't flicker
	            out before the server has seen the click.
	  answer    the server's answer to a request. A yes keeps the prediction
	            until the server's state arrives. A no rolls it back.
	  expire    rolls back predictions left unanswered too long

	Rolling a slot back restores the server's latest word on it, or how it was
	before the click, and first rolls back the predictions resting on it, so
	nothing predicted is left floating.

	Ordering. The server must send each tick's answers after that tick's
	states, in one message or on one ordered channel, and the client applies
	the states before the answers. Then the latest state held for a slot when
	its answer arrives is never older than the click.
]]

local BuildSite = require("./BuildSite")

local Prediction = {}

type Site = BuildSite.Site

export type Pending = {
	id: number,
	at: number,
	before: { number },
	truth: { number }?,
	answered: boolean,
}

export type Prediction = {
	mirror: Site,
	pending: { [number]: Pending },
	slotOf: { [number]: number },
	count: number,
	-- Called with each slot whose state in the mirror this changes, so a
	-- renderer knows what to redraw.
	onChange: ((slot: number) -> ())?,
}

function Prediction.new(mirror: Site): Prediction
	return { mirror = mirror, pending = {}, slotOf = {}, count = 0, onChange = nil }
end

function Prediction.isPredicted(pred: Prediction, slot: number): boolean
	return pred.pending[slot] ~= nil
end

-- Sets a slot's state in the mirror and reports the change.
local function set(pred: Prediction, slot: number, progress: number, rate: number)
	BuildSite.setRemote(pred.mirror, slot, progress, rate)
	local onChange = pred.onChange
	if onChange then
		onChange(slot)
	end
end

-- Places slot in the mirror for request id, if the mirror says a click
-- could place it. Returns whether it did.
function Prediction.predict(pred: Prediction, slot: number, id: number, now: number): boolean
	local mirror = pred.mirror
	if pred.pending[slot] or not BuildSite.canPlace(mirror, slot, BuildSite.Cause.HAND) then
		return false
	end
	pred.pending[slot] = {
		id = id,
		at = now,
		before = { mirror.progress[slot], mirror.rate[slot] },
		truth = nil,
		answered = false,
	}
	pred.slotOf[id] = slot
	pred.count += 1
	set(pred, slot, 1, 0)
	return true
end

local function clear(pred: Prediction, slot: number)
	local p = pred.pending[slot]
	if p then
		pred.pending[slot] = nil
		pred.slotOf[p.id] = nil
		pred.count -= 1
	end
end

local function rollback(pred: Prediction, slot: number)
	local p = pred.pending[slot]
	if p == nil then
		return
	end
	-- Predictions resting on this one go first.
	local bp = pred.mirror.blueprint
	for i = bp.dependentStart[slot], bp.dependentStart[slot + 1] - 1 do
		rollback(pred, bp.dependentList[i])
	end
	clear(pred, slot)
	local state = p.truth or p.before
	set(pred, slot, state[1], state[2])
end

-- Applies the server's state for slot.
function Prediction.receive(pred: Prediction, slot: number, progress: number, rate: number)
	local p = pred.pending[slot]
	if p then
		-- A placed state confirms the click. Anything else waits for the
		-- answer, unless the answer was yes and the server has moved on since:
		-- then its word stands.
		local placed = rate == 0 and progress >= 1
		if not placed and not p.answered then
			p.truth = { progress, rate }
			return
		end
		clear(pred, slot)
	end
	set(pred, slot, progress, rate)
end

-- The server's answer to request id.
function Prediction.answer(pred: Prediction, id: number, ok: boolean)
	local slot = pred.slotOf[id]
	if slot == nil then
		return
	end
	local p = pred.pending[slot] :: Pending
	if ok then
		p.answered = true
		-- The server's placed state may already have come and gone.
		if p.truth then
			local truth = p.truth :: { number }
			clear(pred, slot)
			set(pred, slot, truth[1], truth[2])
		end
	else
		rollback(pred, slot)
	end
end

-- Rolls back predictions older than timeout seconds that the server hasn't
-- answered, and drops answered ones it never followed up.
function Prediction.expire(pred: Prediction, now: number, timeout: number)
	local stale = {}
	for slot, p in pred.pending do
		if now - p.at > timeout then
			table.insert(stale, slot)
		end
	end
	for _, slot in stale do
		local p = pred.pending[slot]
		if p then
			if p.answered then
				clear(pred, slot)
			else
				rollback(pred, slot)
			end
		end
	end
end

return Prediction
