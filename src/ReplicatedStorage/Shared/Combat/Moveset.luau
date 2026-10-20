--!strict
-- Builds the runtime moveset of a fighter (combat.gd build_moveset + _apply_kit_moves).
-- Kit moves store damage and knockback as factors; here they become absolute numbers:
-- standard moves scale the fighter's base attack, uspecial/dspecial scale its base special.

local Fighters = require(script.Parent.Parent.Data.Fighters)
local Presets = require(script.Parent.Parent.Data.Generated.FighterPresets)
local SignatureParams = require(script.Parent.Parent.Data.Generated.SignatureParams)

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
	-- signature specials (Combat/Signature)
	sig: { [string]: any }?,
	pullForce: number?,
	lifesteal: number?,
	sustainVx: number?,
	freeze: number?,
	unblockable: boolean?,
	koAt: number?,
	kbScale: number?,
	charge: boolean?,
	noHeat: boolean?,
	-- weapon items (Combat/Items)
	weapon: string?,
	spawnShot: string?,
	breaksWeapon: boolean?,
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

Moveset.blank = ability

-- Signature mechanics whose effect is a spawned object or a state change: the move itself does not hit.
local SPAWN_MECHS = {}
for _, mech in
	{
		"projectile",
		"meteor",
		"mine",
		"turret",
		"clone",
		"eruption",
		"rage",
		"mark",
		"javelin",
		"magma",
		"board",
		"cannon",
		"nova",
		"shadow_clone",
		"singularity",
		"star_seal",
		"ice_decoy",
		"turbo",
		"flame_wall",
		"eagle",
		"soul_weigh",
		"fox_orbit",
		"missile_salvo",
		"blizzard",
		"arrow_rain",
		"bramble",
		"root_snare",
		"hex",
		"bone_prison",
		"toxic_cloud",
		"flashbang",
		"orbital_strike",
		"revenant",
		"time_bomb",
		"phase_swap",
		"chain_leash",
		"anvil",
		"crescent",
		"lasso",
		"pack_hound",
		"anchor_chain",
	}
do
	SPAWN_MECHS[mech] = true
end

local function num(sig: { [string]: any }, key: string, default: number): number
	local v = sig[key]
	return if type(v) == "number" then v else default
end

local function box(b: Ability, xMin: number, range: number, yMin: number, yMax: number)
	b.xMin, b.range, b.yMin, b.yMax = xMin, range, yMin, yMax
end

-- One cut of the tri slash chain (stage 1-3): two low dashes keep the opponent close, the third launches.
function Moveset.triSlashCut(b: Ability, push: number, sig: { [string]: any }, stage: number)
	local last = stage >= 3
	box(b, -0.3, 1.6, -0.2, 2.0)
	b.active = 0.18
	b.recovery = if last then 0.34 else 0.14
	b.motionVx = num(sig, "speed", 11) * (if last then 0.55 else 1)
	b.angle = if last then 82 else 20
	b.push = push * (if last then 1.5 else 0.35)
	b.hitstun = if last then 0.4 else 0.5
end

-- Turns a special into a fighter's signature special (combat.gd signature_ability).
function Moveset.signatureAbility(a: Ability, sig: { [string]: any }): Ability
	local b = table.clone(a)
	local dmg = a.damage * num(sig, "dmg", 1)
	b.sig = sig
	b.damage = dmg
	b.type = nil
	b.allAround = false
	if sig.windup then
		b.windup = sig.windup
	end
	local mech = sig.mech
	if SPAWN_MECHS[mech] then
		b.noHit = true
		b.active = 0.1
	elseif mech == "tri_slash" then
		Moveset.triSlashCut(b, a.push, sig, 1)
	elseif mech == "sun_wheel" then
		local r = num(sig, "radius", 1.5)
		box(b, -r, r, -0.4, 2.2)
		b.allAround, b.active, b.rehit, b.angle = true, num(sig, "time", 0.55), 0.11, 55
		b.motionVx, b.motionVy, b.recovery = num(sig, "speed", 7.5), num(sig, "rise", 6.5), 0.24
		b.damage = dmg * 0.3
	elseif mech == "breath" then
		box(b, 0.4, num(sig, "length", 3.4), 0.3, 1.9)
		b.active, b.rehit, b.angle, b.recovery = num(sig, "time", 0.9), num(sig, "rehit", 0.12), 28, 0.26
		b.push = a.push * 0.45
	elseif mech == "rebirth" then
		local r = num(sig, "radius", 2.4)
		box(b, -r, r, -0.4, 2.6)
		b.allAround, b.active, b.angle, b.recovery = true, 0.16, 70, 0.3
		b.cooldown = num(sig, "cooldown", 10)
		b.push = a.push * 1.4
	elseif mech == "war_horn" then
		box(b, 0.2, num(sig, "length", 4.2), -0.3, 2.8)
		b.active, b.angle, b.recovery = 0.24, 32, 0.3
		b.push = a.push * 1.9
	elseif mech == "reap" then
		box(b, -0.2, num(sig, "length", 3.2), -0.3, 2.6)
		b.active, b.angle, b.recovery = 0.22, 40, 0.28
		b.pullForce, b.lifesteal = num(sig, "pull", 7), num(sig, "lifesteal", 0.5)
	elseif mech == "stampede" then
		box(b, -0.3, 1.5, -0.2, 1.9)
		b.active, b.angle, b.rehit, b.recovery = num(sig, "time", 0.9), 48, 0.3, 0.3
		b.sustainVx = num(sig, "speed", 8.5)
	elseif mech == "bat_form" then
		local r = num(sig, "radius", 1.3)
		local t = num(sig, "time", 1.0)
		box(b, -r, r, -0.4, 2.4)
		b.allAround, b.active, b.rehit, b.angle, b.recovery = true, t, 0.25, 45, 0.25
		b.sustainVx, b.intangible, b.lifesteal = num(sig, "speed", 6.5), t * 0.8, num(sig, "lifesteal", 0.6)
		b.damage = dmg * 0.4
	elseif mech == "sling_fist" then
		box(b, 0.3, num(sig, "length", 2.6), 0.7, 1.7)
		b.angle, b.active, b.recovery, b.charge = 36, 0.14, 0.42, true
	elseif mech == "iai" then
		b.noHit, b.active, b.recovery = true, num(sig, "time", 0.9), 0.3
	elseif mech == "volley" then
		b.noHit = true
		b.active = num(sig, "count", 6) * num(sig, "interval", 0.1) + 0.05
		b.recovery = 0.2
	elseif mech == "charge_beam" or mech == "beam" then
		local thick = num(sig, "thick", 0.8)
		box(b, 0.3, num(sig, "length", if mech == "beam" then 6 else 5), 1.2 - thick * 0.5, 1.2 + thick * 0.5)
		b.angle = 30
		b.active = if mech == "beam" then 0.28 else 0.3
		b.charge = mech == "charge_beam"
		if sig.freeze then
			b.freeze = sig.freeze
		end
	elseif mech == "leap_slam" or mech == "bridge_dive" then
		b.noHit, b.active, b.recovery = true, 1.6, 0.1
	elseif mech == "crown_shift" then
		local r = num(sig, "radius", 1.8)
		box(b, -r, r, -0.4, 2.6)
		b.allAround, b.active, b.angle, b.recovery, b.cooldown = true, 0.14, 55, 0.22, 1.2
	elseif mech == "frost_roar" then
		box(b, 0.2, num(sig, "length", 3.6), -0.3, 2.6)
		b.active, b.angle, b.recovery, b.freeze = 0.3, 35, 0.32, num(sig, "freeze", 0.8)
		b.push = a.push * 0.9
	elseif mech == "bulwark" then
		b.windup = num(sig, "time", 0.75)
		box(b, 0, 1.7, -0.2, 2.0)
		b.active, b.recovery, b.angle, b.push = 0.14, 0.3, 40, a.push * 1.8
	elseif mech == "counter" then
		b.noHit, b.active, b.recovery = true, 0.45, 0.25
	elseif mech == "dash" or mech == "trail_dash" then
		local multi = num(sig, "multi", 1)
		box(b, -0.3, 1.3, -0.2, 1.9)
		b.active, b.motionVx, b.angle = 0.3, num(sig, "speed", 12), 40
		if multi > 1 then
			b.rehit = 0.3 / multi
			b.damage = dmg / multi * 1.4
		end
	elseif mech == "teleport" then
		box(b, -0.4, 1.5, -0.3, 2.0)
		b.active, b.angle = 0.14, 45
	elseif mech == "whirl" then
		local r = num(sig, "radius", 2.5)
		box(b, -r, r, -0.4, 2.4)
		b.allAround, b.active, b.rehit, b.angle = true, num(sig, "time", 0.5), 0.18, 50
		b.damage = dmg * 0.45
		b.push = a.push * num(sig, "push_mult", 1)
		if num(sig, "pull", 0) > 0 then
			b.pullForce = sig.pull
		end
	elseif mech == "barrage" then
		local hits = num(sig, "hits", 5)
		box(b, -0.3, num(sig, "range", 2), -0.2, 2.0)
		b.active, b.rehit, b.angle, b.push = 0.08 * hits, 0.08, 30, 0.15
		b.damage = dmg / hits * 1.5
	elseif mech == "power" then
		box(b, -0.3, 1.8, -0.2, 2.0)
		b.active, b.recovery, b.angle, b.push = 0.12, 0.45, 38, a.push * 2.2
	elseif mech == "one_punch" then
		box(b, -0.3, 1.9, -0.2, 2.0)
		b.active, b.recovery, b.angle, b.push = 0.12, 0.6, 38, a.push * 1.6
		b.unblockable, b.koAt, b.kbScale = true, num(sig, "ko_at", 120), num(sig, "kb_scale", 70)
	end
	return b
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

	local sig = (SignatureParams :: any)[fighterId]
	moves.nspecial = if sig then Moveset.signatureAbility(base.special, sig) else base.special
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
		local useSig = def.extras.use_sig
		if isSpecial and type(useSig) == "table" then
			a = Moveset.signatureAbility(a, useSig :: any)
		end
		moves[key] = a
	end
	return moves
end

return Moveset
