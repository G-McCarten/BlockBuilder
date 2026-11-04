--[[
	A seeded random number generator, so every test run is repeatable.
	A 32-bit linear congruential generator, read from its high bits.
]]

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number): Rng
	return setmetatable({ state = seed % 4294967296 }, Rng)
end

-- A number in [0, 1).
function Rng.next(self: Rng): number
	self.state = (self.state * 1664525 + 1013904223) % 4294967296
	return self.state / 4294967296
end

-- An integer in [lo, hi].
function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng.range(self: Rng, lo: number, hi: number): number
	return lo + self:next() * (hi - lo)
end

return Rng
