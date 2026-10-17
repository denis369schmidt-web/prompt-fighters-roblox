--!strict
-- Small deterministic random generator (mulberry32). Same sequence on server, client and under Lune,
-- so a match replays exactly from its seed (tests, replays, anti-cheat checks).

export type Rng = {
	state: number,
	next: (self: Rng) -> number,
	range: (self: Rng, lo: number, hi: number) -> number,
	int: (self: Rng, lo: number, hi: number) -> number,
}

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number): Rng
	local self = setmetatable({ state = bit32.band(math.floor(seed), 0xFFFFFFFF) }, Rng)
	return (self :: any) :: Rng
end

-- Multiplies two 32-bit values modulo 2^32 without losing precision in doubles.
local function mul32(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	return bit32.band(aLo * b + bit32.lshift(bit32.band(aHi * b, 0xFFFF), 16), 0xFFFFFFFF)
end

-- Float in [0, 1).
function Rng.next(self: Rng): number
	self.state = bit32.band(self.state + 0x6D2B79F5, 0xFFFFFFFF)
	local t = self.state
	t = mul32(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, (t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % 2 ^ 32)
	return bit32.bxor(t, bit32.rshift(t, 14)) / 2 ^ 32
end

function Rng.range(self: Rng, lo: number, hi: number): number
	return lo + (hi - lo) * self:next()
end

-- Integer in [lo, hi] inclusive.
function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

return Rng
