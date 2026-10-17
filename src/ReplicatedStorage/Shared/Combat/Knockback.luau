--!strict
-- Damage and launch math from the Godot core (combat.gd). Pure functions, units in meters and seconds.

local Constants = require(script.Parent.Parent.Data.Constants)

export type HitResult = {
	damage: number,
	percent: number,
	vx: number,
	vy: number,
	hitstun: number,
	airControlLock: number,
}

local Knockback = {}

function Knockback.defenseMult(defense: number): number
	return math.clamp(1 - defense * 0.01, Constants.DEFENSE_MULT_MIN, Constants.DEFENSE_MULT_MAX)
end

function Knockback.clampWeight(weight: number): number
	return math.clamp(weight, Constants.WEIGHT_MIN, Constants.WEIGHT_MAX)
end

function Knockback.launchScale(percent: number): number
	return 1 + percent * 0.009 + percent ^ 1.35 * 0.0017
end

function Knockback.hitstun(percent: number): number
	return math.clamp(0.30 + percent * 0.002, 0.18, 0.70)
end

-- Explosion/blast hits (item explosions in combat.gd). Spec section 4.4 describes this curve.
-- Applies one hit. `direction` is +1 (right) or -1 (left). `percent` is the target's percent before the hit.
function Knockback.compute(
	baseDamage: number,
	baseKnockback: number,
	percent: number,
	defense: number,
	weight: number,
	direction: number
): HitResult
	local damage = baseDamage * Knockback.defenseMult(defense)
	local newPercent = math.clamp(percent + damage, 0, Constants.MAX_PERCENT)
	local impulse = baseKnockback * 4.25 * Knockback.launchScale(newPercent) / Knockback.clampWeight(weight)
	local stun = Knockback.hitstun(newPercent)
	return {
		damage = damage,
		percent = newPercent,
		vx = direction * impulse * 0.85,
		vy = math.max(impulse * 0.5, 1.8),
		hitstun = stun,
		airControlLock = stun * 0.6,
	}
end

export type ThrowKind = "forward" | "back" | "up" | "down"

-- Throws: 15 base damage, own launch curve (combat.gd execute_throw). `facing` is the thrower's direction.
function Knockback.throw(
	kind: ThrowKind,
	percent: number,
	defense: number,
	weight: number,
	vitality: number,
	facing: number
): HitResult
	local damage = 15 * (1 - defense * 0.006)
	local newPercent = math.clamp(percent + damage, 0, Constants.MAX_PERCENT)
	local w = Knockback.clampWeight(weight)
	local launch = (1 + newPercent * 0.008 + newPercent ^ 1.38 * 0.0016) * Knockback.vitalityMult(vitality)
	local vx, vy
	if kind == "forward" then
		vx, vy = facing * 2.9 * launch / w, 2.0 * (1 + newPercent * 0.002)
	elseif kind == "back" then
		vx, vy = -facing * 3.2 * launch / w, 2.0 * (1 + newPercent * 0.002)
	elseif kind == "up" then
		vx, vy = facing * 0.5, 3.0 * launch / w
	else
		vx, vy = facing * 1.6 * launch / w, 1.4
	end
	local stun = math.clamp(0.32 + newPercent * 0.003, 0.25, 0.85)
	return { damage = damage, percent = newPercent, vx = vx, vy = vy, hitstun = stun, airControlLock = stun * 0.7 }
end

export type AttackLaunch = {
	vx: number,
	vy: number,
	impulse: number,
	hitstun: number,
	airControlLock: number,
	angle: number,
}

-- Launch of a melee or special hit (combat.gd contact resolution). `percent` is the target's percent
-- AFTER the damage was added. `superHit`: special with a full super meter. DI = held stick (diX, diY).
function Knockback.attack(
	damage: number,
	push: number,
	angle: number,
	freeAngle: boolean,
	hitstun: number,
	percent: number,
	weight: number,
	vitality: number,
	direction: number,
	isSpecial: boolean,
	superHit: boolean,
	targetGrounded: boolean,
	diX: number,
	diY: number,
	kbTakenMult: number?
): AttackLaunch
	local growth = percent * 0.024 + percent * damage * 0.0016
	local deg = angle
	if freeAngle then
		deg = math.clamp(deg, -85, 89)
		if deg < 0 and targetGrounded then
			deg = 30 -- a meteor on the ground pops the target up
		end
	else
		deg = math.clamp(deg, 15, 75)
	end
	local kind = if superHit then 1.35 elseif isSpecial then 1.15 else 1.0
	local w = math.clamp(weight, 0.82, 1.45)
	local impulse = (push * 4 + growth * 3.75) * kind / w
	impulse = math.clamp(impulse * (kbTakenMult or 1) * Knockback.vitalityMult(vitality), 0.9, 19)

	local rad = math.rad(deg)
	local lx, ly = direction * math.cos(rad), math.sin(rad)
	local diLen = math.sqrt(diX * diX + diY * diY)
	if diLen > 0.3 and impulse > 3 then
		-- Directional influence bends the launch by up to MAX_DI degrees.
		local dot = math.clamp((diX * -ly + diY * lx) / diLen, -1, 1)
		local turn = math.rad(Constants.MOVEMENT.maxDI) * dot
		local c, s = math.cos(turn), math.sin(turn)
		lx, ly = lx * c - ly * s, lx * s + ly * c
	end
	local stun = math.clamp(hitstun * (0.85 + percent * 0.005), 0.15, 0.85)
	return {
		vx = lx * impulse,
		vy = ly * impulse,
		impulse = impulse,
		hitstun = stun,
		airControlLock = stun * 0.65,
		angle = deg,
	}
end

-- Technique: clean hits deal more damage (15 is neutral, +1.2 % per point).
function Knockback.techniqueMult(technique: number): number
	return 1 + (technique - 15) * 0.012
end

-- Heavier vitality takes slightly less launch (combat.gd vitality_mult).
function Knockback.vitalityMult(vitality: number): number
	return math.clamp(1 - (vitality - 20) * 0.008, 0.85, 1.15)
end

return Knockback
