--!strict
-- Global combat and unit constants. Godot values are in meters; Roblox uses studs.

local Constants = {
	-- 1 m = 3.57 studs (1 stud = 0.28 m). Convert every Godot speed, range and hitbox with this.
	METER = 3.57,
	TICK_RATE = 60,
	MAX_PLAYERS = 4,
	DEFAULT_STOCKS = 3,
	MATCH_SECONDS = 99,
	MAX_PERCENT = 999,
	SUDDEN_DEATH_PERCENT = 150,
	RESPAWN_INVULNERABLE = 2.0,
	MAX_SUPER = 100,
	SUPER_GAIN = {
		standardAttacker = 6,
		specialAttacker = 12,
		standardTarget = 4,
		specialTarget = 8,
		passivePerSecond = 2.2,
		counterHit = 25,
	},
	FINISHER_MIN_PERCENT = 100,
	FINISHER_CODE_KEYS = { F = true, B = true, U = true, D = true, A = true, S = true },
	WEAPON_SPAWN_SECONDS = 8,
	GLOW_TRAIL_PERCENT = 120,
	-- Damage multiplier from the defense stat is clamped to this range.
	DEFENSE_MULT_MIN = 0.55,
	DEFENSE_MULT_MAX = 0.90,
	WEIGHT_MIN = 0.85,
	WEIGHT_MAX = 1.35,
	MOVESET = {
		"jab",
		"ftilt",
		"utilt",
		"dtilt",
		"fsmash",
		"usmash",
		"dsmash",
		"dash_attack",
		"nair",
		"fair",
		"bair",
		"uair",
		"dair",
		"uspecial",
		"dspecial",
	},
	-- Movement defaults (meters, seconds). Fighters override them in their kit physics.
	MOVEMENT = {
		groundAccel = 55,
		groundDecel = 42,
		runAfter = 0.3,
		coyoteTime = 0.1,
		airDash = { speed = 11.5, rise = 6.8, fall = -9 },
		shield = { max = 50, drainPerSecond = 11, regenPerSecond = 9, blockDamageMult = 1.3, breakStun = 2.2 },
		roll = { time = 0.34, speed = 7.2 },
		spotDodge = { time = 0.28 },
		airDodge = { time = 0.38, speed = 8 },
		dodgeIntangible = 0.24,
		ledge = { maxGrabsPerLife = 6, invulnerable = { 1.0, 0.6, 0.35, 0.15, 0, 0 }, maxHang = 5 },
		smash = { tapThreshold = 0.1, maxCharge = 1.0 },
		maxDI = 15,
	},
}

return Constants
