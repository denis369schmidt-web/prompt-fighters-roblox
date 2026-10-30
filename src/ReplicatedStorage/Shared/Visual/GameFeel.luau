--!strict
-- Game-feel math for the client effects ("juice"): how strong a hit looks, how long the picture holds, camera
-- shake from trauma, springs for camera kicks and zoom punches, damage colors and combo words.
-- Pure and Instance-free so it runs under Lune; the client modules (Controllers/Juice, Effects, CameraController)
-- only turn these numbers into parts, tweens and camera moves. Never used by the server simulation.

local GameFeel = {}

-- Every tunable number of the hit/KO feel in one place.
GameFeel.TUNING = {
	-- Hit strength: 0..1 from damage and launch impulse (whichever is stronger).
	damageFull = 22, -- damage that counts as a full-strength hit
	impulseFull = 18, -- launch impulse (m/s) that counts as a full-strength hit
	mediumAt = 0.32, -- strength from which a hit is "medium"
	heavyAt = 0.62, -- strength from which a hit is "heavy"
	superBonus = 0.35, -- added strength for super hits

	-- Local hitstop (picture hold) in seconds; mirrors the server's hitstop frames, capped.
	holdMin = 0.05,
	holdMax = 0.12,
	holdFromTier = "medium", -- light hits rely on the server hitstop only

	-- Camera trauma: shake = trauma^2; trauma decays linearly per second.
	traumaDecay = 1.6,
	shakeTranslate = 1.4, -- studs at full trauma
	shakeRoll = 2.2, -- degrees at full trauma
	shakeFrequency = 18, -- noise samples per second
	traumaLight = 0.12,
	traumaMedium = 0.3,
	traumaHeavy = 0.55,
	traumaKo = 0.85,

	-- Springs (camera kick toward the hit direction, zoom punch, FOV pulse).
	springStiffness = 260,
	springDamping = 18,
	kickStuds = 1.1, -- kick at full strength
	zoomPunchHeavy = 0.12, -- fraction of the camera distance pulled in on heavy hits
	zoomPunchKo = 0.22,
	fovPulseSuper = 7, -- degrees added on a super

	-- Decisive KO (last stock): slow motion and a dolly toward the blast.
	koSlowScale = 0.25,
	koSlowSeconds = 0.9,
	koFocusSeconds = 1.4,

	-- Effect budget.
	maxDebris = 24,
	maxDamageNumbers = 10,
}

export type Tier = "light" | "medium" | "heavy"

export type Impact = {
	strength: number, -- 0..1
	tier: Tier,
	hold: number, -- seconds of local hitstop (0 for light hits)
	trauma: number,
}

local TIER_RANK: { [string]: number } = { light = 1, medium = 2, heavy = 3 }

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

-- Strength 0..1 of a hit from its damage, launch impulse and super flag.
function GameFeel.strength(damage: number, impulse: number?, superHit: boolean?): number
	local t = GameFeel.TUNING
	local s = math.max(damage / t.damageFull, (impulse or 0) / t.impulseFull)
	if superHit then
		s += t.superBonus
	end
	return clamp01(s)
end

function GameFeel.tier(strength: number): Tier
	local t = GameFeel.TUNING
	if strength >= t.heavyAt then
		return "heavy" :: Tier
	elseif strength >= t.mediumAt then
		return "medium" :: Tier
	end
	return "light" :: Tier
end

-- Local hold in seconds: the server's hitstop formula (frames at 60 Hz), clamped to holdMin..holdMax.
function GameFeel.holdSeconds(damage: number, special: boolean?): number
	local t = GameFeel.TUNING
	local frames = math.clamp(damage * 0.4 + (if special then 4 else 2), 3, 10)
	return math.clamp(frames / 60, t.holdMin, t.holdMax)
end

-- Everything the client needs to know about one hit event.
function GameFeel.impact(damage: number, impulse: number?, superHit: boolean?, special: boolean?): Impact
	local t = GameFeel.TUNING
	local strength = GameFeel.strength(damage, impulse, superHit)
	local tier: Tier = GameFeel.tier(strength)
	local hold = if TIER_RANK[tier] >= TIER_RANK[t.holdFromTier]
		then GameFeel.holdSeconds(damage, special or superHit)
		else 0
	local trauma = if tier == "heavy"
		then t.traumaHeavy + (strength - t.heavyAt) * 0.5
		elseif tier == "medium" then t.traumaMedium
		else t.traumaLight
	return { strength = strength, tier = tier, hold = hold, trauma = clamp01(trauma) }
end

-- Trauma only grows up to 1 when added.
function GameFeel.addTrauma(current: number, amount: number): number
	return clamp01(current + amount)
end

function GameFeel.decayTrauma(current: number, dt: number): number
	return math.max(0, current - GameFeel.TUNING.traumaDecay * dt)
end

-- Smooth noise shake for a trauma value at time t: x, y offset (studs) and roll (degrees).
-- scale is the accessibility multiplier (0 = no shake, 1 = full).
function GameFeel.shake(trauma: number, t: number, scale: number): (number, number, number)
	local tu = GameFeel.TUNING
	local amount = clamp01(trauma) ^ 2 * math.max(0, scale)
	if amount <= 0 then
		return 0, 0, 0
	end
	local s = t * tu.shakeFrequency
	local x = math.noise(s, 0.5, 11.3) * 2
	local y = math.noise(s, 3.7, 29.1) * 2
	local r = math.noise(s, 7.9, 47.7) * 2
	return x * tu.shakeTranslate * amount, y * tu.shakeTranslate * amount, r * tu.shakeRoll * amount
end

-- One step of a damped spring toward 0 (semi-implicit Euler, sub-stepped so long frames stay stable).
function GameFeel.spring(value: number, velocity: number, dt: number): (number, number)
	local tu = GameFeel.TUNING
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		velocity += (-tu.springStiffness * value - tu.springDamping * velocity) * h
		value += velocity * h
	end
	if math.abs(value) < 1e-4 and math.abs(velocity) < 1e-3 then
		return 0, 0
	end
	return value, velocity
end

-- Damage number color as r, g, b (0..1): white for chip damage, then yellow, orange and deep red.
function GameFeel.damageColor(damage: number): (number, number, number)
	local stops = {
		{ 0, 1, 1, 1 },
		{ 6, 1, 0.95, 0.55 },
		{ 12, 1, 0.62, 0.18 },
		{ 20, 1, 0.22, 0.16 },
		{ 30, 0.85, 0.05, 0.25 },
	}
	if damage <= stops[1][1] then
		return stops[1][2], stops[1][3], stops[1][4]
	end
	for k = 2, #stops do
		local a, b = stops[k - 1], stops[k]
		if damage <= b[1] then
			local f = (damage - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f
		end
	end
	local last = stops[#stops]
	return last[2], last[3], last[4]
end

-- Size multiplier of a damage number (pops bigger for big hits).
function GameFeel.damageScale(damage: number): number
	return 0.8 + clamp01(damage / 25) * 0.9
end

-- Combo counter text, or nil below two hits.
function GameFeel.comboText(count: number): string?
	if count < 2 then
		return nil
	end
	return `{math.floor(count)} HIT COMBO`
end

-- Unit direction (x, y) from a KO point back toward the stage center, used to aim the KO beam.
function GameFeel.koDirection(x: number, y: number, centerY: number?): (number, number)
	local dx, dy = -x, (centerY or 2) - y
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1e-3 then
		return 0, 1
	end
	return dx / length, dy / length
end

-- Time scale for a slow-motion window: eases from `scale` back to 1 over the last 40 % of the window.
-- elapsed and duration in seconds; returns 1 outside the window.
function GameFeel.slowScale(elapsed: number, duration: number, scale: number): number
	if duration <= 0 or elapsed >= duration or elapsed < 0 then
		return 1
	end
	local f = elapsed / duration
	if f < 0.6 then
		return scale
	end
	local k = (f - 0.6) / 0.4
	return scale + (1 - scale) * (k * k * (3 - 2 * k))
end

return GameFeel
