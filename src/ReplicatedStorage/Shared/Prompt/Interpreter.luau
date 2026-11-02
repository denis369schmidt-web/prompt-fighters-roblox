--!strict
-- Prompt fighters: turns a short description ("Eisgolem mit Hammer", "lava ninja", "Sternendrache") into a full
-- fighter definition, the same shape as a roster fighter (Data/Fighters) plus a Look (Data/Looks) for RigBuilder.
--
--   text --parse--> Traits (what was recognized + 9 seed bits) --build--> fighter, look, preset, signature
--
-- parse only looks for keywords (Prompt/Keywords) in the lower-cased text; the text is never executed, stored or
-- shown by this module. Everything else is derived from the Traits alone, so a 6-character code (Prompt/Code)
-- rebuilds the identical fighter on any machine: same text -> same traits -> same fighter.
-- Pure (no Instances, no services): runs on server, client and under Lune.

local Code = require(script.Parent.Code)
local GearData = require(script.Parent.Parent.Visual.GearData)
local PromptGear = require(script.Parent.Parent.Visual.PromptGear)
local Keywords = require(script.Parent.Keywords)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local Looks = require(script.Parent.Parent.Data.Looks)
local Presets = require(script.Parent.Parent.Data.Generated.FighterPresets)
local SignatureParams = require(script.Parent.Parent.Data.Generated.SignatureParams)
local Signatures = require(script.Parent.Parent.Data.Signatures)
local Rng = require(script.Parent.Parent.Util.Rng)
local Seed = require(script.Parent.Parent.Util.Seed)

export type Traits = Code.Traits

export type Summary = {
	id: string,
	code: string,
	name: string,
	title: string,
	element: string, -- element label (German)
	body: string, -- body name (German)
	weapon: string?,
	glow: string,
	primary: string,
	stats: Fighters.Stats,
	signature: string, -- signature move name
	signatureInfo: string, -- what the mechanic does
	archetype: string,
	recognized: { string }, -- canonical keywords that were understood (for the reveal)
}

export type Result = {
	id: string,
	code: string,
	traits: Traits,
	fighter: Fighters.Fighter,
	look: Looks.Look,
	preset: { [string]: any },
	signatureParams: { [string]: any },
	summary: Summary,
}

local Interpreter = {}

Interpreter.ID_PREFIX = "prompt_"
Interpreter.MAX_CHARS = 120
Interpreter.STAT_KEYS = { "vitality", "power", "defense", "speed", "technique" }
Interpreter.STAT_MIN = 8
Interpreter.STAT_MAX = 36
Interpreter.BUDGET = 100

local ELEMENTS = Keywords.ELEMENTS
local BODIES = Keywords.BODIES
local WEAPONS = Keywords.WEAPONS
local TEMPOS = Keywords.TEMPOS

local ELEMENT_BY_KEY: { [string]: number } = {}
for i, e in ELEMENTS do
	ELEMENT_BY_KEY[e.key] = i
end
local WEAPON_BY_KEY: { [string]: number } = {}
for i, w in WEAPONS do
	WEAPON_BY_KEY[w.key] = i
end
assert(#ELEMENTS < 32 and #BODIES < 32 and #WEAPONS < 16 and #TEMPOS < 4, "Keywords lists too long for the code")

---------------------------------------------------------------------------------------------------------------
-- Text -> traits

-- Folds umlauts and ß to ASCII (ä -> ae), so "baer" and "bär" match the same keyword.
local FOLD = { ["ä"] = "ae", ["ö"] = "oe", ["ü"] = "ue", ["ß"] = "ss" }
local function fold(text: string): string
	return (string.gsub(Seed.lower(text), "\xC3[\x84\x96\x9C\xA4\xB6\xBC\x9F]", function(ch)
		return FOLD[Seed.lower(ch)] or ch
	end))
end
Interpreter.fold = fold

type Entry = { word: string, kind: string, index: number }

-- Kind order breaks ties between equally long words (none share a word today).
local KIND_ORDER = { body = 1, weapon = 2, element = 3, tempo = 4 }
local ENTRIES: { Entry } = {}
local function addWords(kind: string, list: { any })
	for index, item in list do
		for _, word in item.words do
			table.insert(ENTRIES, { word = fold(word), kind = kind, index = index })
		end
	end
end
addWords("element", ELEMENTS)
addWords("body", BODIES)
addWords("weapon", WEAPONS)
addWords("tempo", TEMPOS)
table.sort(ENTRIES, function(a, b)
	if #a.word ~= #b.word then
		return #a.word > #b.word
	end
	if a.kind ~= b.kind then
		return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
	end
	if a.index ~= b.index then
		return a.index < b.index
	end
	return a.word < b.word
end)

export type Match = { kind: string, index: number, word: string }

-- Keywords in reading order. German compounds are split greedily ("sternendrache" = sternen + drache): a
-- keyword counts at the start of a word or right after another keyword; bodies and weapons also count at the
-- end of a word ("toasterritter"), so "meister" does not read as "eis" and "kreis" does not either.
function Interpreter.scan(text: string): { Match }
	local found: { Match } = {}
	local folded = fold(string.sub(text, 1, 512))
	for token in string.gmatch(folded, "[%a\128-\255]+") do
		local pos, chained = 1, true
		while pos <= #token do
			local hit: Entry? = nil
			for _, e in ENTRIES do
				local len = #e.word
				if string.sub(token, pos, pos + len - 1) == e.word then
					local atEnd = pos + len - 1 == #token
					if chained or (atEnd and (e.kind == "body" or e.kind == "weapon")) then
						hit = e
						break
					end
				end
			end
			if hit then
				table.insert(found, { kind = hit.kind, index = hit.index, word = hit.word })
				pos += #hit.word
				chained = true
			else
				pos += 1
				chained = false
			end
		end
	end
	return found
end

-- Normalized prompt text for the seed: trimmed, at most MAX_CHARS characters.
function Interpreter.clean(text: string): string
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	local len = utf8.len(trimmed)
	if len and len > Interpreter.MAX_CHARS then
		trimmed = string.sub(trimmed, 1, (utf8.offset(trimmed, Interpreter.MAX_CHARS + 1) :: number) - 1)
	end
	return trimmed
end

function Interpreter.parse(text: string): Traits
	local cleaned = Interpreter.clean(text)
	local traits: Traits = {
		element = 0,
		body = 0,
		body2 = 0,
		weapon = 0,
		tempo = 0,
		variant = Seed.fromText(if cleaned == "" then "Ausgeglichener Kämpfer" else cleaned) % Code.VARIANTS,
	}
	local bodies: { number } = {}
	for _, m in Interpreter.scan(cleaned) do
		if m.kind == "element" then
			if traits.element == 0 then
				traits.element = m.index -- the first element leads ("Lava Eis Golem" is a lava golem)
			end
		elseif m.kind == "body" then
			table.insert(bodies, m.index)
		elseif m.kind == "weapon" then
			traits.weapon = m.index -- the last weapon wins
		elseif m.kind == "tempo" then
			traits.tempo = m.index -- "langsam aber stark" ends strong
		end
	end
	-- The last body is the head noun ("Roboter Samurai" is a samurai), the one before it lends a trait.
	if #bodies > 0 then
		traits.body = bodies[#bodies]
		for k = #bodies - 1, 1, -1 do
			if bodies[k] ~= traits.body then
				traits.body2 = bodies[k]
				break
			end
		end
	end
	return traits
end

-- Traits from a code, or nil when the code is malformed or names entries that do not exist.
function Interpreter.traitsFromCode(input: string): Traits?
	local t = Code.decode(input)
	if t == nil then
		return nil
	end
	if t.element > #ELEMENTS or t.body > #BODIES or t.body2 > #BODIES or t.weapon > #WEAPONS or t.tempo > #TEMPOS then
		return nil
	end
	if t.body2 ~= 0 and (t.body == 0 or t.body2 == t.body) then
		return nil
	end
	return t
end

---------------------------------------------------------------------------------------------------------------
-- Colors (hex <-> HSV), pure

local function hexToRgb(hex: string): (number, number, number)
	return tonumber(string.sub(hex, 2, 3), 16) :: number / 255,
		tonumber(string.sub(hex, 4, 5), 16) :: number / 255,
		tonumber(string.sub(hex, 6, 7), 16) :: number / 255
end

local function rgbToHex(r: number, g: number, b: number): string
	local function c(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", c(r), c(g), c(b))
end

local function toHsv(r: number, g: number, b: number): (number, number, number)
	local maxV, minV = math.max(r, g, b), math.min(r, g, b)
	local d = maxV - minV
	local h = 0
	if d > 0 then
		if maxV == r then
			h = ((g - b) / d) % 6
		elseif maxV == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if maxV > 0 then d / maxV else 0, maxV
end

local function fromHsv(h: number, s: number, v: number): (number, number, number)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

-- Shifts hue (in turns), scales saturation and value.
local function vary(hex: string, dh: number, ds: number, dv: number): string
	local h, s, v = toHsv(hexToRgb(hex))
	local r, g, b = fromHsv((h + dh) % 1, math.clamp(s * ds, 0, 1), math.clamp(v * dv, 0, 1))
	return rgbToHex(r, g, b)
end

local function mix(a: string, b: string, t: number): string
	local ar, ag, ab = hexToRgb(a)
	local br, bg, bb = hexToRgb(b)
	return rgbToHex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end
Interpreter.mix = mix

---------------------------------------------------------------------------------------------------------------
-- Stats

-- Clamps every stat into [STAT_MIN, STAT_MAX] and moves points one at a time until they sum to BUDGET.
function Interpreter.normalize(values: { number }): { number }
	local out = table.create(#values, 0)
	local sum = 0
	for i, v in values do
		out[i] = math.clamp(math.floor(v + 0.5), Interpreter.STAT_MIN, Interpreter.STAT_MAX)
		sum += out[i]
	end
	while sum ~= Interpreter.BUDGET do
		local pick = 0
		for i, v in out do
			if sum > Interpreter.BUDGET then
				if v > Interpreter.STAT_MIN and (pick == 0 or v > out[pick]) then
					pick = i
				end
			elseif v < Interpreter.STAT_MAX and (pick == 0 or v < out[pick]) then
				pick = i
			end
		end
		local step = if sum > Interpreter.BUDGET then -1 else 1
		out[pick] += step
		sum += step
	end
	return out
end

---------------------------------------------------------------------------------------------------------------
-- Traits -> fighter

local function pick<T>(rng: Rng.Rng, list: { T }): T
	return list[rng:int(1, #list)]
end

local function lower(s: string): string
	return Seed.lower(s)
end

local function fullName(parts: { string }): string
	local name = table.concat(parts)
	if #parts >= 2 and (utf8.len(name) or #name) > 14 then
		name = parts[1] .. "-" .. table.concat(parts, "", 2)
	end
	return name
end

-- Part budget: the sculpted body and face take up to RIG_BASE parts (RIG_BASE_COVERED under a full helmet, which
-- hides the face), gear the rest of RigBuilder.PART_BUDGET.
local RIG_BASE, RIG_BASE_COVERED, RIG_BUDGET = 62, 46, 125
local COVERS_FACE = { knight_helm = true, dragon_helm = true, mech_head = true }
local function pieces(name: string): number
	local set = (GearData :: any)[name] or (PromptGear :: any)[name]
	return if set then #set else 0
end

-- Leaves optional gear off until the rig fits the part budget: the element accessory, the second body's trait,
-- extra weapon parts, then body gear from the end of its list (the first `keep` entries always stay).
local function fitBudget(gear: { string }, optional: { string }, keep: number)
	local function total(): number
		local n = RIG_BASE
		for _, g in gear do
			if COVERS_FACE[g] then
				n = RIG_BASE_COVERED
			end
		end
		for _, g in gear do
			n += pieces(g)
		end
		return n
	end
	for _, name in optional do
		if total() <= RIG_BUDGET then
			return
		end
		local at = table.find(gear, name)
		if at then
			table.remove(gear, at)
		end
	end
	local k = #gear
	while total() > RIG_BUDGET and k > keep do
		table.remove(gear, k)
		k -= 1
	end
end
Interpreter.RIG_BASE = RIG_BASE

local LIGHTER = { heavy = "medium", medium = "light", light = "light" }
local HEAVIER = { light = "medium", medium = "heavy", heavy = "heavy" }

function Interpreter.build(traits: Traits): Result
	local code = Code.encode(traits)
	local id = Interpreter.ID_PREFIX .. code
	local rng = Rng.new(Code.pack(traits) + 7919)

	-- Body first (it may imply the element), then element, weapon, tempo. Unnamed parts come from the seed.
	local explicitBody = traits.body ~= 0
	local bodyIndex = if explicitBody then traits.body else rng:int(1, #BODIES)
	local body = BODIES[bodyIndex]
	local body2 = if traits.body2 ~= 0 then BODIES[traits.body2] else nil

	local explicitElement = traits.element ~= 0
	local elementIndex = traits.element
	local implied = body.element or (if body2 then body2.element else nil)
	if elementIndex == 0 then
		elementIndex = if implied then ELEMENT_BY_KEY[implied] else rng:int(1, #ELEMENTS)
	end
	local element = ELEMENTS[elementIndex]

	local weaponIndex = if traits.weapon ~= 0 then traits.weapon else body.weapon
	local weapon = if weaponIndex then WEAPONS[weaponIndex] else nil
	local tempo = if traits.tempo ~= 0 then TEMPOS[traits.tempo] else nil

	-- Stats: the body's base, leaned by element, weapon and tempo, a little seed noise, budget 100.
	local values = table.clone(body.stats)
	for _, delta in { element.stats, if weapon then weapon.stats else nil, if tempo then tempo.stats else nil } do
		for k = 1, 5 do
			values[k] += delta[k]
		end
	end
	values = Interpreter.normalize(values)
	for _ = 1, 6 do
		local a, b = rng:int(1, 5), rng:int(1, 5)
		if a ~= b and values[a] > Interpreter.STAT_MIN and values[b] < Interpreter.STAT_MAX then
			values[a] -= 1
			values[b] += 1
		end
	end
	local stats: Fighters.Stats = {
		vitality = values[1],
		power = values[2],
		defense = values[3],
		speed = values[4],
		technique = values[5],
	}

	-- Moves, physics and finisher style from the body's kit fighter; weight and run speed follow the stats.
	local kit = Fighters.get(body.kit)
	local kitPreset = (Presets :: any)[body.kit]
	local bulk = (stats.vitality + stats.defense) - (kit.stats.vitality + kit.stats.defense)
	local weight = math.clamp(kit.weight * (1 + bulk * 0.004), 0.8, 1.5)
	local runSpeed = kit.runSpeed
		* (if tempo then tempo.run else 1)
		* math.clamp(1 + (stats.speed - kit.stats.speed) * 0.006, 0.85, 1.2)

	-- Signature: a mechanic that fits the element, in the element's color.
	local donor = pick(rng, element.signatures)
	local sig = table.clone((SignatureParams :: any)[donor]) :: { [string]: any }
	local mech = sig.mech :: string
	local specialName = element.sig .. lower(Keywords.SIGNATURE_NOUNS[mech] or "Schlag")

	-- Name and title from the recognized words (never from the raw text).
	local parts: { string } = {}
	if explicitElement then
		table.insert(parts, element.name)
	end
	if explicitBody then
		if body2 then
			table.insert(parts, body2.prefix)
		end
		table.insert(parts, body.name)
	elseif weapon and traits.weapon ~= 0 then
		if #parts == 0 then
			table.insert(parts, pick(rng, Keywords.SYLLABLES_START))
		end
		table.insert(parts, weapon.name)
	elseif #parts > 0 then
		table.insert(parts, pick(rng, Keywords.EPITHETS))
	else
		table.insert(parts, pick(rng, Keywords.SYLLABLES_START))
		table.insert(parts, pick(rng, Keywords.SYLLABLES_END))
	end
	local name = fullName(parts)
	local adjective = if explicitElement or implied
		then element.adjective
		elseif tempo then tempo.adjective
		else pick(rng, Keywords.ADJECTIVES)
	local title = `{adjective} {body.role}`

	-- Look: element palette with seed variation, body build and gear, weapon in hand.
	local dh, dv = rng:range(-0.025, 0.025), rng:range(0.9, 1.1)
	local primary = vary(element.primary, dh, rng:range(0.9, 1.1), dv)
	local secondary = vary(element.secondary, dh, 1, rng:range(0.9, 1.1))
	local glow = vary(element.glow, rng:range(-0.012, 0.012), 1, 1)
	sig.color = glow
	local accent = vary(element.accent, 0, 1, rng:range(0.92, 1.05))
	local hair = if rng:next() < 0.6 then element.hair else pick(rng, Keywords.HAIR_TONES)
	local skinKind = body.skin
	if skinKind == nil and body2 and (body2.skin == "metal" or body2.skin == "bone" or body2.skin == "pale") then
		skinKind = body2.skin -- "Roboter Samurai": a samurai with a metal body
	end
	local skin = pick(rng, Keywords.SKIN_TONES)
	local skinMaterial: string? = nil
	local materials: { [string]: string }? = nil
	if skinKind == "rock" then
		skin = mix(primary, "#B8B0A8", 0.35)
		skinMaterial = element.rock or "Slate"
		materials = { Slate = element.rock or "Slate" }
	elseif skinKind == "metal" then
		skin = mix("#A8B2BE", primary, 0.3)
		skinMaterial = "Metal"
	elseif skinKind == "bone" then
		skin = "#E8E4D8"
	elseif skinKind == "pale" then
		skin = mix("#E8DCE4", primary, 0.12)
	elseif skinKind == "fur" then
		skin = pick(rng, Keywords.FUR_TONES)
		hair = vary(skin, 0, 1, 0.8)
	elseif skinKind == "tint" then
		skin = mix(element.glow, "#3A2030", 0.5)
	end

	local build = body.build
	if tempo and tempo.build == "light" then
		build = LIGHTER[build]
	elseif tempo and tempo.build == "heavy" then
		build = HEAVIER[build]
	end
	local widthBuild = if build == body.build then 1 elseif build == LIGHTER[body.build] then 0.94 else 1.07
	local scale = {
		height = body.scale[1] * rng:range(0.97, 1.04),
		width = body.scale[2] * rng:range(0.97, 1.03) * widthBuild,
		depth = body.scale[3] * widthBuild,
		head = body.scale[4],
	}

	local gear = table.clone(body.gear)
	local optional: { string } = {}
	local used: { [string]: boolean } = {}
	for _, slot in body.slots do
		used[slot] = true
	end
	if weapon then
		if weapon.hands then
			local fists = table.find(gear, "magma_fists")
			if fists then
				table.remove(gear, fists)
			end
		end
		-- The weapon goes in front of the body gear, so the budget trims body gear before the weapon.
		for k, g in weapon.gear do
			if g == "knight_sword" and (element.key == "feuer" or element.key == "lava") then
				g = "flame_sword"
			end
			table.insert(gear, k, g)
			if k > 1 then
				table.insert(optional, g)
			end
		end
	end
	if body2 and body2.trait and not used[body2.traitSlot or ""] and table.find(gear, body2.trait) == nil then
		table.insert(gear, body2.trait)
		table.insert(optional, 1, body2.trait)
	end
	if explicitElement and element.extraGear and not used[element.extraSlot or ""] then
		table.insert(gear, element.extraGear)
		table.insert(optional, 1, element.extraGear)
	end
	fitBudget(gear, optional, if weapon then #weapon.gear + 2 else 2)

	local face = table.clone(body.face or { eyes = "sharp", brows = "angry", mouth = "smirk" }) :: Looks.Face
	local glowEyes = element.magic == true
		or (body.look ~= nil and body.look.glowEyes == true)
		or (body2 ~= nil and body2.skin == "metal")
	if glowEyes and face.eyes ~= "none" then
		face.eyes = "glow"
	elseif face.eyeColor == nil then
		face.eyeColor = vary(element.glow, 0, 1.1, 0.6)
	end

	local look: Looks.Look = {
		skin = skin,
		primary = primary,
		secondary = secondary,
		glow = glow,
		material = element.material or "Fabric",
		skinMaterial = skinMaterial,
		scale = scale,
		build = build,
		gear = gear,
		glowEyes = glowEyes,
		face = face,
		hair = hair,
		accent = accent,
		trim = glow,
		headOffset = body.headOffset,
		materials = materials,
	}
	for key, value in body.look or {} do
		if key ~= "glowEyes" then
			(look :: any)[key] = value
		end
	end

	local preset = {
		element = element.element,
		gear = gear,
		special = kitPreset.special,
		standard = kitPreset.standard,
		stats = stats,
		weight = weight,
	}

	local phys = table.clone(kit.phys)
	local finisher = table.clone(kit.finisher)
	finisher.name = `{element.name}-FINALE`

	local fighter: Fighters.Fighter = {
		id = id,
		name = name,
		archetype = body.archetype,
		elementLabel = element.label,
		signature = mech,
		unlock = { kind = "prompt" } :: any,
		element = element.element,
		weight = weight,
		runSpeed = runSpeed,
		stats = stats,
		health = 90 + stats.vitality * 1.6,
		phys = phys,
		standardName = kit.standardName,
		specialName = specialName,
		moves = kit.moves,
		signatureParams = sig,
		finisher = finisher,
		gear = gear,
	}
	;(fighter :: any).prompt = { code = code, title = title, kit = body.kit, donor = donor }

	local recognized: { string } = {}
	if explicitElement then
		table.insert(recognized, element.label)
	end
	if body2 then
		table.insert(recognized, BODIES[traits.body2].key)
	end
	if explicitBody then
		table.insert(recognized, body.key)
	end
	if traits.weapon ~= 0 then
		table.insert(recognized, WEAPONS[traits.weapon].key)
	end
	if tempo then
		table.insert(recognized, tempo.key)
	end

	return {
		id = id,
		code = code,
		traits = traits,
		fighter = fighter,
		look = look,
		preset = preset,
		signatureParams = sig,
		summary = {
			id = id,
			code = code,
			name = name,
			title = title,
			element = element.label,
			body = body.name,
			weapon = if weapon then weapon.name else nil,
			glow = glow,
			primary = primary,
			stats = stats,
			signature = specialName,
			signatureInfo = (Signatures.MECHANICS :: any)[mech] or "",
			archetype = body.archetype,
			recognized = recognized,
		},
	}
end

function Interpreter.fromText(text: string): Result
	return Interpreter.build(Interpreter.parse(text))
end

function Interpreter.fromCode(code: string): Result?
	local traits = Interpreter.traitsFromCode(code)
	return if traits then Interpreter.build(traits) else nil
end

-- The code inside a prompt fighter id ("prompt_7KQ2XM" -> "7KQ2XM"), or nil for other ids.
function Interpreter.codeOf(id: string): string?
	if string.sub(id, 1, #Interpreter.ID_PREFIX) ~= Interpreter.ID_PREFIX then
		return nil
	end
	local raw = string.sub(id, #Interpreter.ID_PREFIX + 1)
	local code = Code.normalize(raw)
	return if code == raw then code else nil
end

function Interpreter.isPromptId(id: string): boolean
	return Interpreter.codeOf(id) ~= nil
end

return Interpreter
