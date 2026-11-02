--!strict
-- Prompt codes: 6 characters that rebuild a prompt fighter without its text, so players share codes instead of
-- unfiltered text. A code packs what the interpreter read from the prompt (element, body, second body, weapon,
-- tempo as indices into Prompt/Keywords) and 9 bits of the prompt's seed (Util/Seed) into 30 bits, scrambles
-- them with an invertible affine map (so similar prompts get unrelated-looking codes) and writes them in
-- Crockford base 32 (no I, L, O, U; those letters are read as 1, 1, 0 and V when typed).
-- Pure; the same on server, client and under Lune.

export type Traits = {
	element: number, -- 0 = none named, else Keywords.ELEMENTS index (1..31)
	body: number, -- 0 = none named, else Keywords.BODIES index (1..31)
	body2: number, -- second body ("Roboter Samurai"), 0 = none
	weapon: number, -- 0 = none named, else Keywords.WEAPONS index (1..15)
	tempo: number, -- 0 = none, else Keywords.TEMPOS index (1..3)
	variant: number, -- 0..511, from the prompt seed: colors, proportions, signature pick
}

local Code = {}

Code.LENGTH = 6
Code.ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
Code.VARIANTS = 512

local MOD = 2 ^ 30
local MUL = 0x2C9277 -- odd, so the map is invertible modulo 2^30
local ADD = 0x15A4E35

local DIGIT: { [string]: number } = {}
for i = 1, #Code.ALPHABET do
	DIGIT[string.sub(Code.ALPHABET, i, i)] = i - 1
end
-- Common misreadings.
DIGIT.O = 0
DIGIT.I = 1
DIGIT.L = 1
DIGIT.U = DIGIT.V

-- a * b mod 2^30 without losing precision (doubles are exact to 2^53): split b into 15-bit halves.
local function mulMod(a: number, b: number): number
	local hi, lo = b // 32768, b % 32768
	return ((a * hi) % MOD * 32768 + a * lo) % MOD
end

local INV = (function(): number
	-- Newton iteration for the inverse of an odd number modulo 2^30.
	local x = MUL
	for _ = 1, 6 do
		x = mulMod(x, (2 - mulMod(MUL, x)) % MOD)
	end
	return x
end)()
assert(mulMod(MUL, INV) == 1, "Code: multiplier has no inverse")

function Code.pack(t: Traits): number
	assert(t.element >= 0 and t.element < 32 and t.body >= 0 and t.body < 32 and t.body2 >= 0 and t.body2 < 32)
	assert(t.weapon >= 0 and t.weapon < 16 and t.tempo >= 0 and t.tempo < 4)
	assert(t.variant >= 0 and t.variant < Code.VARIANTS)
	return ((((t.element * 32 + t.body) * 32 + t.body2) * 16 + t.weapon) * 4 + t.tempo) * Code.VARIANTS + t.variant
end

function Code.unpack(n: number): Traits
	local variant = n % Code.VARIANTS
	n //= Code.VARIANTS
	local tempo = n % 4
	n //= 4
	local weapon = n % 16
	n //= 16
	local body2 = n % 32
	n //= 32
	local body = n % 32
	local element = n // 32
	return { element = element, body = body, body2 = body2, weapon = weapon, tempo = tempo, variant = variant }
end

function Code.encode(t: Traits): string
	local n = (mulMod(MUL, Code.pack(t)) + ADD) % MOD
	local chars = table.create(Code.LENGTH, "")
	for i = Code.LENGTH, 1, -1 do
		local d = n % 32
		chars[i] = string.sub(Code.ALPHABET, d + 1, d + 1)
		n //= 32
	end
	return table.concat(chars)
end

-- Cleans what a player typed: upper case, without spaces, dashes and "#". Returns nil unless 6 valid characters.
function Code.normalize(input: string): string?
	if #input > 32 then
		return nil
	end
	local cleaned = string.upper((string.gsub(input, "[%s%-_#]", "")))
	if #cleaned ~= Code.LENGTH then
		return nil
	end
	local out = table.create(Code.LENGTH, "")
	for i = 1, Code.LENGTH do
		local d = DIGIT[string.sub(cleaned, i, i)]
		if d == nil then
			return nil
		end
		out[i] = string.sub(Code.ALPHABET, d + 1, d + 1)
	end
	return table.concat(out)
end

-- The traits behind a code (not yet checked against the keyword lists; Interpreter.fromCode does that).
function Code.decode(input: string): Traits?
	local code = Code.normalize(input)
	if code == nil then
		return nil
	end
	local n = 0
	for i = 1, Code.LENGTH do
		n = n * 32 + DIGIT[string.sub(code, i, i)]
	end
	return Code.unpack(mulMod(INV, (n - ADD) % MOD))
end

return Code
