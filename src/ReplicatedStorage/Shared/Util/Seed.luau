--!strict
-- Deterministic seeds. Same algorithm as prompt_interpreter.gd, so a prompt gives the same fighter as in Godot:
--   seed = 2166136261; for each lower-cased character: seed = ((seed ~ code) * 16777619) & 0x7fffffff
-- Luau numbers are doubles, so the multiply is split to stay exact modulo 2^31.

local Seed = {}

local MOD = 2 ^ 31

local function mulMod(a: number): number
	-- 16777619 = 2^24 + 403  ->  a * 2^24 mod 2^31 only depends on a mod 2^7.
	return ((a % 128) * 2 ^ 24 + a * 403) % MOD
end

-- Lower-cases ASCII plus German umlauts (Godot's to_lower covers all of Unicode; prompts are filtered first).
local UPPER_UMLAUTS = { ["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["ẞ"] = "ß" }

function Seed.lower(text: string): string
	return (
		string.lower(text):gsub("[\xC3\xE1][\x80-\xBF][\x80-\xBF]?", function(ch)
			return UPPER_UMLAUTS[ch] or ch
		end)
	)
end

function Seed.fromText(text: string): number
	local seed = 2166136261
	for _, code in utf8.codes(Seed.lower(text)) do
		seed = mulMod(bit32.bxor(seed, code))
	end
	return seed
end

-- Seed for a calendar day (daily challenge: same for everyone on that date).
function Seed.fromDate(year: number, month: number, day: number): number
	return Seed.fromText(string.format("%04d-%02d-%02d", year, month, day))
end

return Seed
