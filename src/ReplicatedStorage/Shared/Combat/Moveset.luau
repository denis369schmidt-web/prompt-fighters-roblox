--!strict
-- Builds the runtime moveset of a fighter (combat.gd build_moveset + _apply_kit_moves).
-- Kit moves store damage and knockback as factors; here they become absolute numbers:
-- standard moves scale the fighter's base attack, uspecial/dspecial scale its base special.

local Fighters = require(script.Parent.Parent.Data.Fighters)
local Presets = require(script.Parent.Parent.Data.Generated.FighterPresets)

export type Ability = {
	key: string,
	name: string,
	damage: number,
	windup: number,
	active: number,
	recovery: number,
	range: number, -- forward reach (x max)
	xMin: number?,
	yMin: number?,
	yMax: number?,
	angle: number,
	push: number,
	hitstun: number,
	cooldown: number,
	freeAngle: boolean,
	special: boolean,
	aerial: boolean,
	allAround: boolean,
	back: boolean,
	noHit: boolean,
	rehit: number?,
	motionVx: number?,
	motionVy: number?,
	armor: number?,
	blink: number?,
	intangible: number?,
	armorSelf: number?,
	rageSelf: number?,
	counterTime: number?,
	superGain: number?,
	type: string?,
}

export type BaseAttacks = {
	standard: Ability,
	special: Ability,
	runSpeed: number,
}

local Moveset = {}

local AERIALS = { nair = true, fair = true, bair = true, uair = true, dair = true }
-- Special types (prompt specials) that hit on both sides.
local ALL_AROUND_TYPES = { radial = true, radial_blast = true, shockwave = true, ground_quake = true }

local function ability(key: string, name: string): Ability
	return {
		key = key,
		name = name,
		damage = 0,
		windup = 0.1,
		active = 0.12,
		recovery = 0.2,
		range = 1.5,
		angle = 35,
		push = 0.32,
		hitstun = 0.24,
		cooldown = 0,
		freeAngle = false,
		special = false,
		aerial = AERIALS[key] == true,
		allAround = false,
		back = false,
		noHit = false,
	}
end

-- Base standard attack and base special (prompt_interpreter.gd), from a fighter's stats and preset.
function Moveset.baseAttacks(fighterId: string): BaseAttacks
	local fighter = Fighters.get(fighterId)
	local preset = (Presets :: any)[fighterId]
	local power = fighter.stats.power

	local std = ability("jab", fighter.standardName)
	std.damage = 6 + power * 0.24
	std.range = preset.standard.range
	std.cooldown = preset.standard.cd
	std.windup = preset.standard.windup
	std.active = 0.08
	std.recovery = 0.14
	std.push = preset.standard.push
	std.angle = 28
	std.hitstun = 0.2

	local sp = ability("nspecial", fighter.specialName)
	sp.special = true
	sp.type = preset.special.type
	sp.damage = 16 + power * 0.32 + (preset.special.dmg_bonus or 0)
	sp.range = preset.special.range
	sp.cooldown = preset.special.cd
	sp.windup = preset.special.windup
	sp.active = 0.16
	sp.recovery = 0.28
	sp.push = preset.special.push
	sp.angle = preset.special.angle
	sp.hitstun = 0.38
	sp.allAround = ALL_AROUND_TYPES[preset.special.type] == true

	return { standard = std, special = sp, runSpeed = fighter.runSpeed }
end

local EXTRA_MAP: { [string]: string } = {
	all_around = "allAround",
	back = "back",
	no_hit = "noHit",
	rehit = "rehit",
	motion_vx = "motionVx",
	motion_vy = "motionVy",
	armor = "armor",
	blink = "blink",
	intangible = "intangible",
	armor_self = "armorSelf",
	rage_self = "rageSelf",
	counter_time = "counterTime",
	super_gain = "superGain",
	cooldown = "cooldown",
}

function Moveset.build(fighterId: string): { [string]: Ability }
	local fighter = Fighters.get(fighterId)
	local base = Moveset.baseAttacks(fighterId)
	local moves: { [string]: Ability } = {}

	moves.nspecial = base.special
	for key, def in fighter.moves do
		local isSpecial = key == "uspecial" or key == "dspecial"
		local baseAbility = if isSpecial then base.special else base.standard
		local a = ability(key, def.name)
		a.damage = baseAbility.damage * def.dmg
		a.push = baseAbility.push * def.kb
		a.windup = def.windup
		a.active = def.active
		a.recovery = def.recovery
		a.xMin = def.xMin
		a.range = def.xMax
		a.yMin = def.yMin
		a.yMax = def.yMax
		a.angle = def.angle
		a.freeAngle = def.extras.free_angle == true
		a.special = isSpecial
		if isSpecial then
			a.cooldown = if key == "uspecial" then 1.2 else 1.6
		elseif key == "jab" then
			a.cooldown = base.standard.cooldown * 0.5
		end
		for from, to in EXTRA_MAP do
			local value = def.extras[from]
			if value ~= nil then
				(a :: any)[to] = value
			end
		end
		moves[key] = a
	end
	return moves
end

return Moveset
