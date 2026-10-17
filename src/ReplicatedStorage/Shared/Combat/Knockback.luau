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

-- Heavier vitality takes slightly less launch (combat.gd vitality_mult).
function Knockback.vitalityMult(vitality: number): number
	return math.clamp(1 - (vitality - 20) * 0.008, 0.85, 1.15)
end

return Knockback
