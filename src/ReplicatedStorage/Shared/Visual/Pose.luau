--!strict
-- Procedural animation: target joint angles for an R15 rig from what the snapshot says a fighter is doing.
-- Pure math (no Instances), so every state and move is covered by tests. The client (FighterView) samples this
-- every frame and drives the joints through springs, which adds a little overshoot and weight on top.
--
-- Moves are keyframed: each move kind has an anticipation pose (end of windup), a strike pose (active) and a
-- follow-through pose (recovery), plus optional curves for flips and spins. Time inside the stage
-- (`stageTime`, tracked by the client) runs them: ease into the wind-up, snap into the strike with an
-- overshoot, hold, follow through, settle back into the stance. Locomotion (stance, walk/run cycle, jumps,
-- landings), hit reactions, dodges and the rest are procedural layers in the same file.
--
-- Angle conventions (degrees per Motor6D, rotation in joint space; rig faces -Z):
--   Shoulder/Hip  +x swings the limb forward/up (90 = straight ahead, 180 = overhead), -x behind.
--                 +z lifts the right arm/leg outward (-z for the left side), y twists the limb.
--   Elbow +x bends, Knee -x bends. Wrist +x tips the hand (and a held blade) up, -x down.
--   Ankle +x lifts the toes, -x points them.
--   Waist/Neck/Root  +x tips the upper body back (chin up), -x hunches forward; +y turns the right
--                 shoulder forward (the body turns left), z tilts sideways.
-- Root channels: rootY studs added to the stand height (- = crouch), pitch + leans the whole body forward
-- (flips run through ±360), roll sways sideways, spin is extra yaw (spins run through ±360), lunge shifts the
-- body forward in studs (along facing).

export type Angles = { x: number, y: number, z: number }
-- Per-fighter animation personality: weight 0 (light, fast) .. 1 (heavy, slow, wide stance), bounce 0..1
-- (light fighters hop on the spot), seed spreads idle timing so two fighters never breathe in sync.
export type Style = { weight: number, bounce: number, seed: number }
export type PoseInput = {
	state: string,
	move: string, -- "" when no move is running
	stage: string, -- "windup" | "active" | "recovery" | ""
	grounded: boolean,
	blocking: boolean,
	speed: number, -- horizontal speed in m/s (absolute)
	vy: number, -- vertical speed in m/s
	phase: number, -- run cycle phase in radians (client advances it with distance)
	t: number, -- seconds, for idle breathing and wobbles
	-- Optional timing and context (the client tracks these; missing fields fall back to sensible defaults).
	stageTime: number?, -- seconds since the current move stage started
	stageLength: number?, -- expected length of the current stage in seconds
	stateTime: number?, -- seconds since `state` changed (dodge roll, throw, hit reaction)
	vx: number?, -- signed horizontal speed in m/s (world x)
	facing: number?, -- +1 / -1
	airTime: number?, -- seconds since leaving the ground
	landTime: number?, -- seconds since touching down
	landImpact: number?, -- 0..1 how hard the last landing was
	flipTime: number?, -- seconds since an air jump (front flip)
	turnTime: number?, -- seconds since the fighter turned around
	variant: number?, -- counts move starts: alternates jab hands and slash directions
	weapon: string?, -- weapon style in the right hand: "blade" | "polearm" | "heavy" | "gun" | ""
	style: Style?,
}
export type PoseOutput = {
	joints: { [string]: Angles },
	rootY: number, -- studs added to the standing height (negative = crouch)
	pitch: number, -- degrees, + leans forward
	roll: number, -- degrees, sideways sway
	spin: number, -- degrees of extra yaw (spinning aerials)
	lunge: number, -- studs the body shifts forward (along facing)
	snappy: boolean, -- true during strikes: the client eases faster so hits read crisp
	stiffness: number, -- spring frequency hint for the client (rad/s)
	damping: number, -- spring damping ratio hint (< 1 overshoots a little)
}

local Pose = {}

Pose.JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftWrist",
	"RightWrist",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
}

-- Which keyframed motion each move uses (see MOVES below).
Pose.MOTION_KIND = {
	jab = "jab",
	ftilt = "cross",
	dash_attack = "dash",
	fsmash = "smash",
	utilt = "upper",
	usmash = "launcher",
	uair = "scissor",
	uspecial = "rise",
	dtilt = "sweep",
	dsmash = "breaker",
	dair = "stomp",
	nair = "nair",
	fair = "fair",
	bair = "bair",
	nspecial = "cast",
	dspecial = "slam",
} :: { [string]: string }

-- Signature specials are sent with their mechanic as the move name (Simulation.snapshot).
local MECH_KIND: { [string]: string } = {
	anchor_chain = "throw",
	anvil = "launcher",
	arrow_rain = "summon",
	barrage = "barrage",
	bat_form = "dash",
	beam = "beam",
	blizzard = "summon",
	board = "dash",
	bone_prison = "summon",
	bramble = "slam",
	breath = "beam",
	bridge_dive = "launcher",
	bulwark = "counter",
	cannon = "launcher",
	chain_leash = "throw",
	charge_beam = "beam",
	clone = "cast",
	counter = "counter",
	crescent = "cast",
	crown_shift = "whirl",
	dash = "dash",
	eagle = "rise",
	eruption = "slam",
	flame_wall = "slam",
	flashbang = "throw",
	fox_orbit = "summon",
	fox_release = "cast",
	frost_roar = "beam",
	hex = "cast",
	iai = "iai",
	ice_decoy = "counter",
	javelin = "throw",
	lasso = "throw",
	leap_slam = "launcher",
	magma = "cast",
	mark = "cast",
	mark_strike = "smash",
	meltdown = "slam",
	meteor = "summon",
	mine = "slam",
	missile_salvo = "summon",
	nova = "summon",
	one_punch = "smash",
	orbital_strike = "summon",
	pack_hound = "summon",
	phase_swap = "cast",
	power = "smash",
	projectile = "cast",
	rage = "summon",
	reap = "whirl",
	rebirth = "summon",
	recall = "cast",
	revenant = "summon",
	root_snare = "slam",
	shadow_clone = "cast",
	singularity = "cast",
	sling_fist = "smash",
	soul_weigh = "cast",
	stampede = "dash",
	star_seal = "slam",
	sun_wheel = "whirl",
	teleport = "cast",
	time_bomb = "throw",
	toxic_cloud = "cast",
	trail_dash = "dash",
	tri_slash = "cross",
	tri_slash_2 = "cross",
	tri_slash_3 = "upper",
	turbo = "dash",
	turret = "cast",
	volley = "barrage",
	war_horn = "summon",
	whirl = "whirl",
}
for mech, kind in MECH_KIND do
	Pose.MOTION_KIND[mech] = kind
end

-- Coarse family of each move (punch, heavy, upper, low, stomp, spin, kick, backkick, blast) for effects that
-- only need the rough shape of a strike (FighterView's slash arcs).
local FAMILY: { [string]: string } = {
	jab = "punch",
	cross = "punch",
	dash = "punch",
	barrage = "punch",
	smash = "heavy",
	upper = "upper",
	launcher = "upper",
	rise = "upper",
	summon = "upper",
	sweep = "low",
	breaker = "low",
	iai = "low",
	counter = "low",
	stomp = "stomp",
	slam = "stomp",
	nair = "spin",
	whirl = "spin",
	fair = "kick",
	scissor = "kick",
	bair = "backkick",
	cast = "blast",
	beam = "blast",
	throw = "blast",
}
Pose.MOVE_KIND = {} :: { [string]: string }
for move, kind in Pose.MOTION_KIND do
	Pose.MOVE_KIND[move] = FAMILY[kind] or "punch"
end

-- Held weapons by id (rig gear and arena weapons) -> weapon style.
Pose.WEAPON_STYLE = {
	katana = "blade",
	flame_sword = "blade",
	ice_daggers = "blade",
	shadow_katana = "blade",
	sword_crescent = "blade",
	sword_frost = "blade",
	sword_hero = "blade",
	sword_plasma = "blade",
	flame_whip = "blade",
	glaive = "polearm",
	skull_staff = "polearm",
	soul_scythe = "polearm",
	dragon_lance = "polearm",
	sword_buster = "heavy",
	frost_axe = "heavy",
	thunder_hammer = "heavy",
	flail = "heavy",
	hammer = "heavy",
	battle_axe = "heavy",
	scythe = "polearm",
	magic_staff = "polearm",
	blaster = "gun",
	plasma_cannon = "gun",
	crystal_bow = "gun",
	boomerang = "gun",
} :: { [string]: string }

-- With a weapon in hand, body moves turn into weapon moves.
local WEAPON_KIND: { [string]: { [string]: string } } = {
	blade = {
		jab = "hslash",
		cross = "slash",
		smash = "chop",
		upper = "rising",
		sweep = "lowslash",
		dash = "thrust",
		nair = "spinslash",
		whirl = "spinslash",
		fair = "slash",
		barrage = "hslash",
	},
	polearm = {
		jab = "thrust",
		cross = "hslash",
		smash = "chop",
		upper = "rising",
		sweep = "lowslash",
		dash = "thrust",
		nair = "spinslash",
		whirl = "spinslash",
		fair = "slash",
	},
	heavy = {
		jab = "hslash",
		cross = "hslash",
		smash = "chop",
		upper = "rising",
		sweep = "lowslash",
		dash = "chop",
		nair = "spinslash",
		whirl = "spinslash",
	},
	gun = {
		jab = "aim",
		cross = "aim",
		smash = "aim",
		upper = "aim",
		sweep = "aim",
		dash = "aim",
		cast = "aim",
		beam = "aim",
	},
}

-- Fighters whose look calls for a clearly heavy or light way of moving (the rest follow their weight stat).
local STYLE_OVERRIDE: { [string]: { weight: number, bounce: number } } = {
	golem = { weight = 1, bounce = 0 },
	grimbolt = { weight = 0.8, bounce = 0 },
	cyborg_mech = { weight = 0.95, bounce = 0 },
	dragon = { weight = 0.85, bounce = 0 },
	steel_knight = { weight = 0.75, bounce = 0 },
	mutant_titan = { weight = 1, bounce = 0 },
	treant = { weight = 1, bounce = 0 },
	ninja = { weight = 0, bounce = 1 },
	zip = { weight = 0, bounce = 1 },
	lepora = { weight = 0, bounce = 0.9 },
	shira = { weight = 0.05, bounce = 0.8 },
	celestial_fox = { weight = 0.1, bounce = 0.7 },
}

-- Animation personality of a fighter from its id and weight stat (Fighters.weight, about 0.8 .. 1.5).
function Pose.style(fighterId: string, weightStat: number?, slot: number?): Style
	local w = math.clamp(((weightStat or 1) - 0.9) / 0.5, 0, 1)
	local bounce = math.clamp(1 - w * 2.5, 0, 1) * 0.5
	local override = STYLE_OVERRIDE[fighterId]
	if override then
		w, bounce = override.weight, override.bounce
	end
	local hash = 0
	for k = 1, #fighterId do
		hash = (hash * 31 + string.byte(fighterId, k)) % 1000
	end
	return { weight = w, bounce = bounce, seed = (hash + (slot or 0) * 137) % 1000 / 1000 * math.pi * 2 }
end

-- Weapon style from a list of gear names (RigBuilder looks) or an arena weapon id; "" when unarmed.
function Pose.weaponStyle(names: { string }): string
	for _, name in names do
		local style = Pose.WEAPON_STYLE[name]
		if style then
			return style
		end
	end
	return ""
end

--------------------------------------------------------------------------------------------------------------
-- Easing

local function clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end
local function lerp(a: number, b: number, w: number): number
	return a + (b - a) * w
end
local function smooth(e0: number, e1: number, v: number): number
	local u = clamp01((v - e0) / (e1 - e0))
	return u * u * (3 - 2 * u)
end

Pose.ease = {
	inQuad = function(u: number): number
		return u * u
	end,
	outQuad = function(u: number): number
		return 1 - (1 - u) * (1 - u)
	end,
	outCubic = function(u: number): number
		local v = 1 - u
		return 1 - v * v * v
	end,
	inOutQuad = function(u: number): number
		return if u < 0.5 then 2 * u * u else 1 - (-2 * u + 2) ^ 2 / 2
	end,
	inOutCubic = function(u: number): number
		return if u < 0.5 then 4 * u * u * u else 1 - (-2 * u + 2) ^ 3 / 2
	end,
	-- Overshoots past 1 and settles back: strikes snap past their mark.
	outBack = function(u: number, s: number?): number
		local c = s or 1.70158
		local v = u - 1
		return 1 + (c + 1) * v * v * v + c * v * v
	end,
}
local ease = Pose.ease

--------------------------------------------------------------------------------------------------------------
-- Pose building blocks

type Key = {
	j: { [string]: { number } },
	rootY: number?,
	pitch: number?,
	roll: number?,
	spin: number?,
	lunge: number?,
}
-- Curve over the whole move: progress g runs 0..1 through windup, 1..2 through active, 2..3 through
-- recovery; keys are { g, value } and segments ease out.
type Curve = { channel: string, keys: { { number } } }
type MoveDef = {
	wind: Key,
	hit: Key,
	follow: Key?,
	hold: Key?, -- pose the strike drifts into while the active stage lasts (beams, long spins)
	snap: number?, -- seconds from wind-up to strike
	overshoot: number?, -- easeOutBack strength of the strike
	charge: boolean?, -- trembles with power during the wind-up
	tremble: boolean?, -- trembles while active (beams)
	rapid: number?, -- alternates the strike with its mirror every `rapid` seconds (barrages)
	air: boolean?, -- aerial: built on the airborne pose
	alt: string?, -- move kind used on odd variants (1-2 combos, forehand/backhand)
	curves: { Curve }?,
}

local function a(x: number, y: number?, z: number?): Angles
	return { x = x, y = y or 0, z = z or 0 }
end

local function out(): PoseOutput
	local joints = {}
	for _, name in Pose.JOINTS do
		joints[name] = a(0)
	end
	return {
		joints = joints,
		rootY = 0,
		pitch = 0,
		roll = 0,
		spin = 0,
		lunge = 0,
		snappy = false,
		stiffness = 20,
		damping = 1,
	}
end

local function copy(p: PoseOutput): PoseOutput
	local c = out()
	for name, v in p.joints do
		c.joints[name] = a(v.x, v.y, v.z)
	end
	c.rootY, c.pitch, c.roll, c.spin, c.lunge = p.rootY, p.pitch, p.roll, p.spin, p.lunge
	c.snappy, c.stiffness, c.damping = p.snappy, p.stiffness, p.damping
	return c
end

local function set(p: PoseOutput, values: { [string]: { number } })
	for name, v in values do
		p.joints[name] = a(v[1], v[2], v[3])
	end
end

-- Adds angles on top (procedural offsets).
local function add(p: PoseOutput, values: { [string]: { number } }, w: number?)
	local k = w or 1
	for name, v in values do
		local j = p.joints[name]
		j.x += v[1] * k
		j.y += (v[2] or 0) * k
		j.z += (v[3] or 0) * k
	end
end

-- The base pose with a key laid over it (joints the key doesn't name keep the base).
local function over(base: PoseOutput, key: Key): PoseOutput
	local p = copy(base)
	set(p, key.j)
	p.rootY = key.rootY or p.rootY
	p.pitch = key.pitch or p.pitch
	p.roll = key.roll or p.roll
	p.spin = key.spin or p.spin
	p.lunge = key.lunge or p.lunge
	return p
end

-- Blends two full poses; w may leave 0..1 (overshoot).
local function mix(p: PoseOutput, q: PoseOutput, w: number): PoseOutput
	local r = copy(p)
	for name, v in r.joints do
		local b = q.joints[name]
		v.x, v.y, v.z = lerp(v.x, b.x, w), lerp(v.y, b.y, w), lerp(v.z, b.z, w)
	end
	r.rootY = lerp(p.rootY, q.rootY, w)
	r.pitch = lerp(p.pitch, q.pitch, w)
	r.roll = lerp(p.roll, q.roll, w)
	r.spin = lerp(p.spin, q.spin, w)
	r.lunge = lerp(p.lunge, q.lunge, w)
	return r
end

local MIRROR: { [string]: string } = {}
for _, name in Pose.JOINTS do
	if string.sub(name, 1, 4) == "Left" then
		MIRROR[name] = "Right" .. string.sub(name, 5)
	elseif string.sub(name, 1, 5) == "Right" then
		MIRROR[name] = "Left" .. string.sub(name, 6)
	else
		MIRROR[name] = name
	end
end

local function mirror(p: PoseOutput): PoseOutput
	local r = copy(p)
	for name, v in p.joints do
		r.joints[MIRROR[name]] = a(v.x, -v.y, -v.z)
	end
	r.roll, r.spin = -p.roll, -p.spin
	return r
end

--------------------------------------------------------------------------------------------------------------
-- Move keyframes (data). Base stance is right side forward (the side that faces the camera when facing right).

local function K(j: { [string]: { number } }, root: { [string]: number }?): Key
	local r: { [string]: number } = root or {}
	return { j = j, rootY = r.rootY, pitch = r.pitch, roll = r.roll, spin = r.spin, lunge = r.lunge }
end

local MOVES: { [string]: MoveDef } = {
	-- Quick lead jab; every second jab is the rear-hand cross of a 1-2.
	jab = {
		wind = K({
			RightShoulder = { 38, 0, 14 },
			RightElbow = { 125 },
			Waist = { -4, 14, 0 },
		}, { rootY = -0.3, lunge = -0.05 }),
		hit = K({
			RightShoulder = { 90, 0, -6 },
			RightElbow = { 3 },
			RightWrist = { -6 },
			LeftShoulder = { 50, 0, -18 },
			LeftElbow = { 118 },
			Waist = { -6, 30, 0 },
			Neck = { 4, -24, 0 },
			RightHip = { 26, 0, 6 },
			RightKnee = { -30 },
		}, { pitch = 7, lunge = 0.45, rootY = -0.3 }),
		follow = K({
			RightShoulder = { 72, 0, 0 },
			RightElbow = { 45 },
			Waist = { -5, 18, 0 },
		}, { lunge = 0.25 }),
		snap = 0.045,
		overshoot = 1.6,
		alt = "jab2",
	},
	jab2 = {
		wind = K({
			LeftShoulder = { 30, 0, -16 },
			LeftElbow = { 125 },
			Waist = { -2, 28, 0 },
		}, { rootY = -0.3 }),
		hit = K({
			LeftShoulder = { 92, 0, 10 },
			LeftElbow = { 2 },
			RightShoulder = { 55, 0, 18 },
			RightElbow = { 120 },
			Waist = { -8, -32, 0 },
			Root = { 0, -10, 0 },
			Neck = { 4, 28, 0 },
			LeftHip = { 20, 0, -6 },
			RightHip = { -10, 0, 6 },
			RightAnkle = { -25 },
		}, { pitch = 9, lunge = 0.55, rootY = -0.32 }),
		follow = K({
			LeftShoulder = { 70, 0, 0 },
			LeftElbow = { 50 },
			Waist = { -5, -18, 0 },
		}, { lunge = 0.3 }),
		snap = 0.05,
		overshoot = 1.6,
	},
	-- Rear straight with the whole body behind it: hips turn, back heel lifts, step in.
	cross = {
		wind = K({
			LeftShoulder = { 18, 0, -20 },
			LeftElbow = { 128 },
			RightShoulder = { 70, 0, 4 },
			RightElbow = { 80 },
			Waist = { -2, 38, 0 },
			Root = { 0, 12, 0 },
		}, { rootY = -0.42, pitch = -3, lunge = -0.12 }),
		hit = K({
			LeftShoulder = { 92, 0, 8 },
			LeftElbow = { 0 },
			LeftWrist = { -8 },
			RightShoulder = { 30, 0, 22 },
			RightElbow = { 112 },
			Waist = { -12, -46, 0 },
			Root = { 0, -18, 0 },
			Neck = { 6, 34, 0 },
			RightHip = { 38, 0, 6 },
			RightKnee = { -42 },
			LeftHip = { -26, 0, -6 },
			LeftKnee = { -10 },
			LeftAnkle = { -30 },
		}, { pitch = 13, lunge = 0.75, rootY = -0.42 }),
		follow = K({
			LeftShoulder = { 78, 0, 4 },
			LeftElbow = { 28 },
			Waist = { -8, -30, 0 },
		}, { pitch = 9, lunge = 0.55 }),
		snap = 0.06,
		overshoot = 1.8,
	},
	-- Forward smash: big wind back (twist away, crouch, lead hand aims), explosive lunge, long follow-through.
	smash = {
		wind = K({
			LeftShoulder = { -55, 0, -40 },
			LeftElbow = { 85 },
			RightShoulder = { 80, 0, 22 },
			RightElbow = { 25 },
			Waist = { 8, 58, 0 },
			Root = { 0, 22, 0 },
			Neck = { -4, -44, 0 },
			RightHip = { 42, 0, 10 },
			RightKnee = { -40 },
			LeftHip = { -8, 0, -12 },
			LeftKnee = { -60 },
		}, { rootY = -0.75, pitch = -9, lunge = -0.4 }),
		hit = K({
			LeftShoulder = { 96, 0, 6 },
			LeftElbow = { 0 },
			LeftWrist = { -10 },
			RightShoulder = { -35, 0, 34 },
			RightElbow = { 70 },
			Waist = { -20, -58, 0 },
			Root = { 0, -26, 0 },
			Neck = { 8, 46, 0 },
			RightHip = { 58, 0, 8 },
			RightKnee = { -58 },
			LeftHip = { -42, 0, -8 },
			LeftKnee = { -6 },
			LeftAnkle = { -38 },
		}, { pitch = 21, lunge = 1.15, rootY = -0.6 }),
		follow = K({
			LeftShoulder = { 82, 0, 0 },
			LeftElbow = { 18 },
			Waist = { -14, -42, 0 },
		}, { pitch = 15, lunge = 0.95 }),
		snap = 0.07,
		overshoot = 2.2,
		charge = true,
	},
	-- Uppercut: dip, then drive up off the toes.
	upper = {
		wind = K({
			RightShoulder = { -18, 0, 22 },
			RightElbow = { 112 },
			Waist = { -16, -24, 0 },
			LeftHip = { 38 },
			RightHip = { 30 },
			LeftKnee = { -55 },
			RightKnee = { -50 },
		}, { rootY = -0.75, pitch = 9 }),
		hit = K({
			RightShoulder = { 168, 0, -10 },
			RightElbow = { 38 },
			LeftShoulder = { 28, 0, -32 },
			LeftElbow = { 85 },
			Waist = { 16, 34, 0 },
			Neck = { 18, -10, 0 },
			RightHip = { 48 },
			RightKnee = { -75 },
			LeftHip = { -6 },
			LeftKnee = { -4 },
			LeftAnkle = { -40 },
		}, { rootY = 0.55, pitch = -8, lunge = 0.25 }),
		follow = K({
			RightShoulder = { 150, 0, -5 },
			RightElbow = { 55 },
		}, { rootY = 0.3 }),
		snap = 0.06,
		overshoot = 1.5,
	},
	-- Up smash: deep crouch, leap with both fists overhead and a full turn.
	launcher = {
		wind = K({
			LeftShoulder = { -30, 0, -25 },
			RightShoulder = { -30, 0, 25 },
			LeftElbow = { 60 },
			RightElbow = { 60 },
			Waist = { -24 },
			Neck = { 14 },
			LeftHip = { 70, 0, -10 },
			RightHip = { 70, 0, 10 },
			LeftKnee = { -105 },
			RightKnee = { -105 },
		}, { rootY = -1.25, pitch = 12 }),
		hit = K({
			LeftShoulder = { 172, 0, 10 },
			RightShoulder = { 172, 0, -10 },
			LeftElbow = { 8 },
			RightElbow = { 8 },
			Waist = { 14 },
			Neck = { 22 },
			RightHip = { 55 },
			RightKnee = { -85 },
			LeftHip = { -10 },
			LeftKnee = { -10 },
			LeftAnkle = { -45 },
			RightAnkle = { -30 },
		}, { rootY = 1.5, pitch = -6 }),
		follow = K({
			LeftShoulder = { 150, 0, -20 },
			RightShoulder = { 150, 0, 20 },
		}, { rootY = 0.8 }),
		snap = 0.08,
		overshoot = 1.4,
		charge = true,
		curves = { { channel = "spin", keys = { { 1, 0 }, { 2, 360 }, { 3, 360 } } } },
	},
	-- Down tilt: drop low and sweep the lead leg along the floor.
	sweep = {
		wind = K({
			LeftHip = { 85, 0, -18 },
			LeftKnee = { -125 },
			RightHip = { 30, 0, 35 },
			RightKnee = { -95 },
			Waist = { -24, -22, 0 },
			LeftShoulder = { 40, 0, -30 },
			RightShoulder = { 30, 0, 30 },
			RightElbow = { 40 },
		}, { rootY = -1.3, pitch = 12 }),
		hit = K({
			LeftHip = { 92, 0, -20 },
			LeftKnee = { -128 },
			RightHip = { 86, 0, 26 },
			RightKnee = { -4 },
			RightAnkle = { 25 },
			Waist = { -26, 32, 0 },
			Root = { 0, 34, 0 },
			LeftShoulder = { -25, 0, -50 },
			LeftElbow = { 20 },
			RightShoulder = { 55, 0, 45 },
			RightElbow = { 10 },
		}, { rootY = -1.45, pitch = 14, lunge = 0.35 }),
		follow = K({ Root = { 0, 42, 0 } }, { rootY = -1.3 }),
		snap = 0.05,
		overshoot = 1.5,
	},
	-- Down smash: drop into a breakdance spin with both legs out.
	breaker = {
		wind = K({
			LeftHip = { 95, 0, -20 },
			RightHip = { 95, 0, 20 },
			LeftKnee = { -130 },
			RightKnee = { -130 },
			Waist = { -30 },
			LeftShoulder = { 60, 0, -40 },
			RightShoulder = { 60, 0, 40 },
		}, { rootY = -1.5, pitch = 18 }),
		hit = K({
			LeftHip = { 75, 0, -55 },
			RightHip = { 75, 0, 55 },
			LeftKnee = { -5 },
			RightKnee = { -5 },
			LeftAnkle = { 20 },
			RightAnkle = { 20 },
			Waist = { -20 },
			LeftShoulder = { 20, 0, -35 },
			RightShoulder = { 20, 0, 35 },
		}, { rootY = -1.65, pitch = 10 }),
		snap = 0.06,
		charge = true,
		curves = { { channel = "spin", keys = { { 1, 0 }, { 2.4, 540 }, { 3, 720 } } } },
	},
	-- Dash attack: flying knee, arms swept back.
	dash = {
		wind = K({
			RightHip = { 40 },
			RightKnee = { -70 },
			LeftShoulder = { 40, 0, -20 },
			RightShoulder = { 40, 0, 20 },
			Waist = { 4 },
		}, { rootY = -0.5, pitch = -6 }),
		hit = K({
			RightHip = { 100 },
			RightKnee = { -115 },
			RightAnkle = { -30 },
			LeftHip = { -32 },
			LeftKnee = { -24 },
			LeftAnkle = { -40 },
			LeftShoulder = { -45, 0, -28 },
			RightShoulder = { -45, 0, 28 },
			LeftElbow = { 20 },
			RightElbow = { 20 },
			Waist = { -12 },
			Neck = { 22 },
		}, { rootY = 0.35, pitch = 26, lunge = 1.1 }),
		follow = K({ RightHip = { 70 }, RightKnee = { -80 } }, { pitch = 14, lunge = 0.7 }),
		snap = 0.06,
		overshoot = 1.5,
	},
	-- Neutral air: tuck, then burst out into a spinning star.
	nair = {
		wind = K({
			LeftHip = { 85 },
			RightHip = { 85 },
			LeftKnee = { -115 },
			RightKnee = { -115 },
			LeftShoulder = { 60, 0, 20 },
			RightShoulder = { 60, 0, -20 },
			LeftElbow = { 115 },
			RightElbow = { 115 },
			Waist = { -20 },
		}, { rootY = 0.2 }),
		hit = K({
			LeftShoulder = { 10, 0, -95 },
			RightShoulder = { 10, 0, 95 },
			LeftElbow = { 5 },
			RightElbow = { 5 },
			LeftHip = { 25, 0, -40 },
			RightHip = { 25, 0, 40 },
			LeftKnee = { -10 },
			RightKnee = { -10 },
			LeftAnkle = { -30 },
			RightAnkle = { -30 },
			Waist = { 6 },
		}),
		snap = 0.05,
		air = true,
		curves = { { channel = "spin", keys = { { 1, 0 }, { 2, 630 }, { 2.6, 720 } } } },
	},
	-- Forward air: front flip that ends in an axe kick.
	fair = {
		wind = K({
			LeftHip = { 80 },
			RightHip = { 80 },
			LeftKnee = { -110 },
			RightKnee = { -110 },
			LeftShoulder = { 150, 0, -20 },
			RightShoulder = { 150, 0, 20 },
			Waist = { -24 },
			Neck = { -10 },
		}),
		hit = K({
			RightHip = { 165 },
			RightKnee = { -4 },
			RightAnkle = { 30 },
			LeftHip = { -15 },
			LeftKnee = { -30 },
			LeftAnkle = { -40 },
			LeftShoulder = { 40, 0, -60 },
			RightShoulder = { 40, 0, 60 },
			Waist = { -12 },
		}),
		follow = K({ RightHip = { 70 }, RightKnee = { -40 } }),
		snap = 0.05,
		air = true,
		curves = { { channel = "pitch", keys = { { 0, 0 }, { 1, 70 }, { 2, 320 }, { 2.7, 360 } } } },
	},
	-- Back air: backflip with the legs whipping through behind.
	bair = {
		wind = K({
			LeftHip = { 70 },
			RightHip = { 70 },
			LeftKnee = { -110 },
			RightKnee = { -110 },
			Waist = { 14 },
			Neck = { 20 },
			LeftShoulder = { -40, 0, -40 },
			RightShoulder = { -40, 0, 40 },
		}),
		hit = K({
			RightHip = { -10 },
			RightKnee = { -2 },
			RightAnkle = { 20 },
			LeftHip = { 30 },
			LeftKnee = { -70 },
			Waist = { 18 },
			Neck = { 25 },
			LeftShoulder = { 60, 0, -70 },
			RightShoulder = { 60, 0, 70 },
		}),
		follow = K({ RightHip = { 30 }, RightKnee = { -50 } }),
		snap = 0.04,
		air = true,
		curves = { { channel = "pitch", keys = { { 0, 0 }, { 1, -50 }, { 2, -290 }, { 2.7, -360 } } } },
	},
	-- Up air: lean back into an overhead scissor kick.
	scissor = {
		wind = K({
			LeftHip = { 60 },
			RightHip = { 30 },
			LeftKnee = { -100 },
			RightKnee = { -60 },
			Waist = { -10 },
			LeftShoulder = { -30, 0, -40 },
			RightShoulder = { -30, 0, 40 },
		}),
		hit = K({
			RightHip = { 170 },
			RightKnee = { -3 },
			RightAnkle = { 30 },
			LeftHip = { -25 },
			LeftKnee = { -20 },
			Waist = { 22 },
			Neck = { 30 },
			LeftShoulder = { -40, 0, -55 },
			RightShoulder = { -40, 0, 55 },
		}, { pitch = -45 }),
		follow = K({ RightHip = { 110 }, RightKnee = { -30 } }, { pitch = -25 }),
		snap = 0.05,
		air = true,
	},
	-- Down air: knees to the chest, then both feet stamp down.
	stomp = {
		wind = K({
			LeftHip = { 105 },
			RightHip = { 105 },
			LeftKnee = { -135 },
			RightKnee = { -135 },
			LeftShoulder = { 160, 0, -15 },
			RightShoulder = { 160, 0, 15 },
			Waist = { -18 },
			Neck = { -20 },
		}, { rootY = 0.4 }),
		hit = K({
			LeftHip = { -4 },
			RightHip = { -4 },
			LeftKnee = { -2 },
			RightKnee = { -2 },
			LeftAnkle = { 20 },
			RightAnkle = { 20 },
			LeftShoulder = { 170, 0, -35 },
			RightShoulder = { 170, 0, 35 },
			LeftElbow = { 10 },
			RightElbow = { 10 },
			Waist = { 8 },
			Neck = { -25 },
		}, { rootY = -0.3 }),
		snap = 0.045,
		overshoot = 1.3,
		air = true,
	},
	-- Blast / projectile special: gather energy at the hip, thrust both palms out, recoil.
	cast = {
		wind = K({
			RightShoulder = { -35, 0, 18 },
			RightElbow = { 105 },
			LeftShoulder = { 25, 0, 40 },
			LeftElbow = { 115 },
			Waist = { -6, -42, 0 },
			Root = { 0, -14, 0 },
			Neck = { 0, 30, 0 },
		}, { rootY = -0.55, pitch = -4, lunge = -0.2 }),
		hit = K({
			LeftShoulder = { 88, 0, 12 },
			RightShoulder = { 88, 0, -12 },
			LeftElbow = { 4 },
			RightElbow = { 4 },
			LeftWrist = { 40 },
			RightWrist = { 40 },
			Waist = { -10, 8, 0 },
			RightHip = { 36 },
			RightKnee = { -42 },
			LeftHip = { -24 },
			LeftKnee = { -12 },
			LeftAnkle = { -25 },
		}, { pitch = 9, lunge = 0.45, rootY = -0.4 }),
		follow = K({
			LeftElbow = { 35 },
			RightElbow = { 35 },
			Waist = { 6, 0, 0 },
		}, { pitch = -5, lunge = 0.1 }),
		snap = 0.05,
		overshoot = 1.7,
		charge = true,
	},
	-- Beam: the cast held out while the beam runs, shaking with recoil.
	beam = {
		wind = K({
			RightShoulder = { -35, 0, 18 },
			RightElbow = { 105 },
			LeftShoulder = { 25, 0, 40 },
			LeftElbow = { 115 },
			Waist = { -6, -42, 0 },
		}, { rootY = -0.6, lunge = -0.25 }),
		hit = K({
			LeftShoulder = { 90, 0, 10 },
			RightShoulder = { 90, 0, -10 },
			LeftElbow = { 6 },
			RightElbow = { 6 },
			LeftWrist = { 45 },
			RightWrist = { 45 },
			Waist = { 4, 6, 0 },
			RightHip = { 40 },
			RightKnee = { -50 },
			LeftHip = { -30 },
			LeftKnee = { -20 },
		}, { pitch = -4, lunge = 0.2, rootY = -0.55 }),
		hold = K({ Waist = { 10, 6, 0 }, LeftElbow = { 14 }, RightElbow = { 14 } }, { pitch = -9, lunge = -0.1 }),
		snap = 0.06,
		charge = true,
		tremble = true,
	},
	-- Summon / sky special: arms crossed low, then thrown up into a wide V.
	summon = {
		wind = K({
			LeftShoulder = { 30, 0, 30 },
			RightShoulder = { 30, 0, -30 },
			LeftElbow = { 70 },
			RightElbow = { 70 },
			Waist = { -22 },
			Neck = { -20 },
			LeftHip = { 45 },
			RightHip = { 45 },
			LeftKnee = { -75 },
			RightKnee = { -75 },
		}, { rootY = -0.9, pitch = 10 }),
		hit = K({
			LeftShoulder = { 160, 0, -38 },
			RightShoulder = { 160, 0, 38 },
			LeftElbow = { 5 },
			RightElbow = { 5 },
			LeftWrist = { 30 },
			RightWrist = { 30 },
			Waist = { 16 },
			Neck = { 30 },
			LeftAnkle = { -30 },
			RightAnkle = { -30 },
		}, { rootY = 0.25, pitch = -6 }),
		hold = K({ Waist = { 20 }, Neck = { 34 } }, { rootY = 0.3 }),
		snap = 0.07,
		overshoot = 1.4,
		charge = true,
		tremble = true,
	},
	-- Up special: corkscrew uppercut.
	rise = {
		wind = K({
			RightShoulder = { -20, 0, 25 },
			RightElbow = { 115 },
			Waist = { -20, -35, 0 },
			LeftHip = { 55 },
			RightHip = { 45 },
			LeftKnee = { -85 },
			RightKnee = { -80 },
		}, { rootY = -0.9, pitch = 10 }),
		hit = K({
			RightShoulder = { 175, 0, -4 },
			RightElbow = { 6 },
			LeftShoulder = { 10, 0, -25 },
			LeftElbow = { 40 },
			Waist = { 10, 20, 0 },
			Neck = { 20 },
			RightHip = { 40 },
			RightKnee = { -80 },
			LeftHip = { -5 },
			LeftKnee = { -5 },
			LeftAnkle = { -45 },
		}, { rootY = 0.6, pitch = -5 }),
		snap = 0.06,
		curves = { { channel = "spin", keys = { { 1, 0 }, { 2, 720 }, { 3, 720 } } } },
	},
	-- Ground slam: hop up with both fists overhead, hammer them into the floor.
	slam = {
		wind = K({
			LeftShoulder = { 172, 0, 18 },
			RightShoulder = { 172, 0, -18 },
			LeftElbow = { 45 },
			RightElbow = { 45 },
			Waist = { 18 },
			Neck = { 10 },
			LeftHip = { 40 },
			RightHip = { 55 },
			LeftKnee = { -60 },
			RightKnee = { -90 },
		}, { rootY = 0.5, pitch = -10 }),
		hit = K({
			LeftShoulder = { 55, 0, 12 },
			RightShoulder = { 55, 0, -12 },
			LeftElbow = { 4 },
			RightElbow = { 4 },
			Waist = { -42 },
			Neck = { 30 },
			LeftHip = { 80, 0, -20 },
			RightHip = { 80, 0, 20 },
			LeftKnee = { -110 },
			RightKnee = { -110 },
		}, { rootY = -1.3, pitch = 24, lunge = 0.2 }),
		snap = 0.05,
		overshoot = 1.6,
		charge = true,
	},
	-- Throw special (javelin, lasso, bombs): overhand throw with a step.
	throw = {
		wind = K({
			RightShoulder = { 168, 0, 28 },
			RightElbow = { 105 },
			LeftShoulder = { 82, 0, -14 },
			LeftElbow = { 20 },
			Waist = { 12, -40, 0 },
			Root = { 0, -15, 0 },
			Neck = { -6, 34, 0 },
			LeftHip = { 25 },
			LeftKnee = { -45 },
		}, { pitch = -8, rootY = -0.35, lunge = -0.25 }),
		hit = K({
			RightShoulder = { 70, 0, -12 },
			RightElbow = { 6 },
			RightWrist = { -30 },
			LeftShoulder = { -25, 0, -30 },
			LeftElbow = { 50 },
			Waist = { -16, 44, 0 },
			Root = { 0, 15, 0 },
			Neck = { 4, -30, 0 },
			RightHip = { 35 },
			RightKnee = { -40 },
			LeftHip = { -25 },
			LeftAnkle = { -30 },
		}, { pitch = 15, lunge = 0.6, rootY = -0.35 }),
		follow = K({ RightShoulder = { 35, 0, -25 }, RightElbow = { 20 } }, { pitch = 10 }),
		snap = 0.06,
		overshoot = 1.6,
	},
	-- Counter stance: open guard, weight back, then a sharp parry flick.
	counter = {
		wind = K({
			RightShoulder = { 95, 0, -30 },
			LeftShoulder = { 70, 0, 30 },
			RightElbow = { 60 },
			LeftElbow = { 70 },
			RightWrist = { 40 },
			Waist = { 8, 20, 0 },
			LeftHip = { 20 },
			RightHip = { 45 },
			LeftKnee = { -70 },
			RightKnee = { -40 },
		}, { rootY = -0.6, pitch = -6, lunge = -0.2 }),
		hit = K({
			RightShoulder = { 120, 0, 40 },
			RightElbow = { 15 },
			RightWrist = { 50 },
			LeftShoulder = { 60, 0, -10 },
			LeftElbow = { 100 },
			Waist = { 4, -20, 0 },
			LeftHip = { 20 },
			RightHip = { 45 },
			LeftKnee = { -70 },
			RightKnee = { -40 },
		}, { rootY = -0.55, pitch = 2 }),
		snap = 0.05,
		overshoot = 1.8,
	},
	-- Iaido: crouched draw at the hip, then a flash cut across with a dash.
	iai = {
		wind = K({
			RightShoulder = { 30, 0, -48 },
			RightElbow = { 70 },
			RightWrist = { 10 },
			LeftShoulder = { 25, 0, 30 },
			LeftElbow = { 90 },
			Waist = { -18, -28, 0 },
			RightHip = { 60 },
			RightKnee = { -95 },
			LeftHip = { -15 },
			LeftKnee = { -100 },
		}, { rootY = -1.0, pitch = 14 }),
		hit = K({
			RightShoulder = { 88, 0, 72 },
			RightElbow = { 2 },
			RightWrist = { -10 },
			LeftShoulder = { 20, 0, -40 },
			LeftElbow = { 40 },
			Waist = { -16, 34, 0 },
			RightHip = { 70 },
			RightKnee = { -95 },
			LeftHip = { -25 },
			LeftKnee = { -30 },
			LeftAnkle = { -40 },
		}, { rootY = -1.05, pitch = 20, lunge = 1.3 }),
		snap = 0.04,
		overshoot = 1.3,
		charge = true,
	},
	-- Rapid alternating punches.
	barrage = {
		wind = K({
			RightShoulder = { 40, 0, 14 },
			RightElbow = { 120 },
			LeftShoulder = { 40, 0, -14 },
			LeftElbow = { 120 },
			Waist = { -8 },
		}, { rootY = -0.45, pitch = 4 }),
		hit = K({
			RightShoulder = { 92, 0, -4 },
			RightElbow = { 4 },
			LeftShoulder = { 45, 0, -12 },
			LeftElbow = { 115 },
			Waist = { -8, 26, 0 },
		}, { pitch = 9, lunge = 0.4, rootY = -0.45 }),
		snap = 0.03,
		rapid = 0.07,
	},
	-- Grounded spinning special (whirlwinds, scythes, sun wheel).
	whirl = {
		wind = K({
			LeftShoulder = { 70, 0, 30 },
			RightShoulder = { 70, 0, -30 },
			LeftElbow = { 90 },
			RightElbow = { 90 },
			Waist = { -10, -50, 0 },
		}, { rootY = -0.6 }),
		hit = K({
			LeftShoulder = { 15, 0, -95 },
			RightShoulder = { 15, 0, 95 },
			LeftElbow = { 4 },
			RightElbow = { 4 },
			Waist = { -6 },
			LeftHip = { 15, 0, -15 },
			RightHip = { 15, 0, 15 },
		}, { rootY = -0.3 }),
		snap = 0.05,
		curves = { { channel = "spin", keys = { { 1, 0 }, { 2, 1080 }, { 3, 1080 } } } },
	},

	-- Weapon moves (right hand; blades point along the hand's forward axis).
	-- Diagonal overhead slash: blade cocked over the shoulder, cut down and across.
	slash = {
		wind = K({
			RightShoulder = { 168, 0, 34 },
			RightElbow = { 75 },
			RightWrist = { 45 },
			LeftShoulder = { 60, 0, -22 },
			LeftElbow = { 85 },
			Waist = { 10, -30, 0 },
			Neck = { -4, 26, 0 },
		}, { rootY = -0.3, pitch = -6, lunge = -0.1 }),
		hit = K({
			RightShoulder = { 40, 0, -34 },
			RightElbow = { 8 },
			RightWrist = { -28 },
			LeftShoulder = { -28, 0, -36 },
			LeftElbow = { 40 },
			Waist = { -20, 42, 0 },
			Neck = { 6, -30, 0 },
			RightHip = { 40 },
			RightKnee = { -46 },
			LeftHip = { -25 },
			LeftKnee = { -10 },
			LeftAnkle = { -30 },
		}, { pitch = 15, lunge = 0.65, rootY = -0.45 }),
		follow = K({ RightShoulder = { 18, 0, -42 }, RightWrist = { -40 } }, { pitch = 11 }),
		snap = 0.06,
		overshoot = 1.4,
		alt = "slash2",
	},
	-- Rising backhand diagonal that answers the first slash.
	slash2 = {
		wind = K({
			RightShoulder = { 30, 0, -40 },
			RightElbow = { 40 },
			RightWrist = { -40 },
			Waist = { -12, 40, 0 },
		}, { rootY = -0.4, pitch = 8 }),
		hit = K({
			RightShoulder = { 150, 0, 50 },
			RightElbow = { 10 },
			RightWrist = { 20 },
			LeftShoulder = { 40, 0, -30 },
			LeftElbow = { 70 },
			Waist = { 8, -36, 0 },
			RightHip = { 30 },
			RightKnee = { -35 },
		}, { pitch = -4, lunge = 0.45, rootY = -0.2 }),
		snap = 0.06,
		overshoot = 1.4,
	},
	-- Horizontal sweep, forehand; every second one comes back as a backhand.
	hslash = {
		wind = K({
			RightShoulder = { 82, 0, 78 },
			RightElbow = { 45 },
			RightWrist = { 15 },
			LeftShoulder = { 55, 0, -15 },
			LeftElbow = { 90 },
			Waist = { 0, -45, 0 },
			Root = { 0, -15, 0 },
		}, { rootY = -0.35, lunge = -0.1 }),
		hit = K({
			RightShoulder = { 86, 0, -38 },
			RightElbow = { 6 },
			RightWrist = { -5 },
			LeftShoulder = { 20, 0, -45 },
			LeftElbow = { 50 },
			Waist = { -8, 50, 0 },
			Root = { 0, 15, 0 },
			RightHip = { 30 },
			RightKnee = { -38 },
		}, { pitch = 9, lunge = 0.45, rootY = -0.4 }),
		snap = 0.055,
		overshoot = 1.5,
		alt = "hslash2",
	},
	hslash2 = {
		wind = K({
			RightShoulder = { 82, 0, -48 },
			RightElbow = { 75 },
			RightWrist = { 10 },
			Waist = { 0, 42, 0 },
		}, { rootY = -0.35 }),
		hit = K({
			RightShoulder = { 86, 0, 72 },
			RightElbow = { 4 },
			RightWrist = { -5 },
			LeftShoulder = { 50, 0, -20 },
			LeftElbow = { 90 },
			Waist = { -6, -36, 0 },
			Root = { 0, -12, 0 },
		}, { pitch = 6, lunge = 0.4, rootY = -0.4 }),
		snap = 0.055,
		overshoot = 1.5,
	},
	-- Thrust: blade drawn back at the hip, driven straight ahead.
	thrust = {
		wind = K({
			RightShoulder = { 20, 0, 22 },
			RightElbow = { 105 },
			RightWrist = { -40 },
			LeftShoulder = { 75, 0, -10 },
			LeftElbow = { 30 },
			Waist = { 2, -34, 0 },
		}, { rootY = -0.45, lunge = -0.25 }),
		hit = K({
			RightShoulder = { 90, 0, -2 },
			RightElbow = { 0 },
			RightWrist = { -88 },
			LeftShoulder = { -30, 0, -30 },
			LeftElbow = { 30 },
			Waist = { -12, 40, 0 },
			RightHip = { 45 },
			RightKnee = { -50 },
			LeftHip = { -32 },
			LeftKnee = { -6 },
			LeftAnkle = { -35 },
		}, { pitch = 13, lunge = 1.0, rootY = -0.5 }),
		snap = 0.05,
		overshoot = 1.5,
	},
	-- Two-handed overhead chop (heavy weapons, weapon smashes).
	chop = {
		wind = K({
			RightShoulder = { 176, 0, -8 },
			LeftShoulder = { 176, 0, 14 },
			RightElbow = { 85 },
			LeftElbow = { 85 },
			RightWrist = { 35 },
			Waist = { 16 },
			Neck = { -8 },
			RightHip = { 20 },
		}, { rootY = -0.15, pitch = -12, lunge = -0.25 }),
		hit = K({
			RightShoulder = { 48, 0, -10 },
			LeftShoulder = { 48, 0, 14 },
			RightElbow = { 6 },
			LeftElbow = { 6 },
			RightWrist = { -40 },
			Waist = { -32 },
			Neck = { 22 },
			RightHip = { 50 },
			RightKnee = { -65 },
			LeftHip = { -22 },
			LeftKnee = { -15 },
		}, { rootY = -0.75, pitch = 22, lunge = 0.7 }),
		follow = K({ RightShoulder = { 30, 0, -10 }, LeftShoulder = { 30, 0, 14 } }, { pitch = 18 }),
		snap = 0.07,
		overshoot = 1.9,
		charge = true,
	},
	-- Rising slash: blade low behind, swept up overhead off the toes.
	rising = {
		wind = K({
			RightShoulder = { -15, 0, 25 },
			RightElbow = { 20 },
			RightWrist = { -45 },
			Waist = { -18, -25, 0 },
			LeftHip = { 45 },
			RightHip = { 35 },
			LeftKnee = { -70 },
			RightKnee = { -60 },
		}, { rootY = -0.8, pitch = 10 }),
		hit = K({
			RightShoulder = { 175, 0, 10 },
			RightElbow = { 8 },
			RightWrist = { 25 },
			LeftShoulder = { 20, 0, -40 },
			Waist = { 16, 25, 0 },
			Neck = { 22 },
			LeftAnkle = { -40 },
			RightHip = { 40 },
			RightKnee = { -70 },
		}, { rootY = 0.45, pitch = -8 }),
		snap = 0.06,
		overshoot = 1.4,
	},
	-- Low slash: drop to one knee and cut across at ankle height.
	lowslash = {
		wind = K({
			RightShoulder = { 45, 0, 70 },
			RightElbow = { 35 },
			RightWrist = { -45 },
			Waist = { -20, -35, 0 },
			RightHip = { 80 },
			RightKnee = { -95 },
			LeftHip = { -10 },
			LeftKnee = { -120 },
		}, { rootY = -1.25, pitch = 12 }),
		hit = K({
			RightShoulder = { 55, 0, -42 },
			RightElbow = { 4 },
			RightWrist = { -55 },
			LeftShoulder = { 20, 0, -50 },
			Waist = { -26, 45, 0 },
			RightHip = { 85 },
			RightKnee = { -95 },
			LeftHip = { -10 },
			LeftKnee = { -120 },
		}, { rootY = -1.3, pitch = 16, lunge = 0.3 }),
		snap = 0.05,
		overshoot = 1.4,
	},
	-- Spinning slash, blade held out.
	spinslash = {
		wind = K({
			RightShoulder = { 80, 0, -40 },
			RightElbow = { 70 },
			Waist = { -10, 45, 0 },
		}, { rootY = -0.4 }),
		hit = K({
			RightShoulder = { 88, 0, 85 },
			RightElbow = { 4 },
			RightWrist = { -10 },
			LeftShoulder = { 20, 0, -80 },
			Waist = { -6 },
		}, { rootY = -0.2 }),
		snap = 0.05,
		curves = { { channel = "spin", keys = { { 1, 0 }, { 2, 720 }, { 3, 720 } } } },
	},
	-- Gun: raise, aim down the arm, kick back on the shot.
	aim = {
		wind = K({
			RightShoulder = { 60, 0, 10 },
			RightElbow = { 40 },
			RightWrist = { -40 },
			LeftShoulder = { 50, 0, 25 },
			LeftElbow = { 70 },
			Waist = { -4, 25, 0 },
		}, { rootY = -0.3 }),
		hit = K({
			RightShoulder = { 90, 0, -4 },
			RightElbow = { 2 },
			RightWrist = { -88 },
			LeftShoulder = { 80, 0, 28 },
			LeftElbow = { 45 },
			Waist = { -4, 35, 0 },
			Neck = { 0, -30, 0 },
		}, { rootY = -0.3, pitch = 2 }),
		follow = K({
			RightShoulder = { 112, 0, -4 },
			RightElbow = { 28 },
			RightWrist = { -70 },
		}, { pitch = -6, lunge = -0.25 }),
		snap = 0.04,
	},
}
Pose.MOVES = MOVES

-- Move kind for a move name, with the held weapon applied and the 1-2 alternation.
function Pose.kindOf(move: string, weapon: string?, variant: number?): string?
	if move == "" then
		return nil
	end
	local kind = Pose.MOTION_KIND[move] or "jab"
	local byWeapon = if weapon and weapon ~= "" then WEAPON_KIND[weapon] else nil
	if byWeapon and byWeapon[kind] then
		kind = byWeapon[kind]
	end
	local def = MOVES[kind]
	if def and def.alt and (variant or 0) % 2 == 1 then
		kind = def.alt
	end
	return kind
end

--------------------------------------------------------------------------------------------------------------
-- Locomotion and stance

local DEFAULT_STYLE: Style = { weight = 0.4, bounce = 0.2, seed = 0 }

-- Fighting stance: right side leads, hands up, breathing, a slow weight shift and per-fighter rhythm.
local function stance(p: PoseOutput, input: PoseInput, s: Style)
	local t, w = input.t, s.weight
	local rate = lerp(2.4, 1.5, w)
	local breathe = math.sin(t * rate + s.seed)
	local shift = math.sin(t * 0.8 + s.seed * 1.7)
	local look = math.sin(t * 0.37 + s.seed * 2.3)
	-- Light fighters bounce on the balls of their feet like boxers.
	local hop = math.abs(math.sin(t * 4.6 + s.seed)) * s.bounce
	local wide = lerp(5, 13, w)
	local bend = lerp(24, 36, w) + hop * 10
	set(p, {
		Root = { 0, 8 + shift * 3, 0 },
		Waist = { -6 + breathe * 1.5, 10 - shift * 3, shift * 1.5 },
		Neck = { 7 - breathe, -14 + look * 7, 0 },
		RightShoulder = { 58, 0, 6 + breathe * 2 },
		RightElbow = { 98 },
		RightWrist = { -10 },
		LeftShoulder = { 42, 0, -14 - breathe * 2 },
		LeftElbow = { 118 },
		LeftWrist = { -10 },
		RightHip = { 20, 0, wide },
		RightKnee = { -bend },
		LeftHip = { -12, 0, -wide },
		LeftKnee = { -bend + 6 },
	})
	-- Heavy fighters breathe with the shoulders, rounded and low.
	add(p, {
		LeftShoulder = { 0, 0, -breathe * 3 * w },
		RightShoulder = { 0, 0, breathe * 3 * w },
		Waist = { -6 * w, 0, 0 },
	})
	p.rootY = -lerp(0.25, 0.5, w) + breathe * lerp(0.04, 0.08, w) + hop * 0.22
	p.roll = shift * 2
end

-- Walk-to-sprint cycle: contact and passing poses, arms against legs, hips and shoulders counter-twist,
-- head stays level, lean into the speed.
local function locomotion(p: PoseOutput, input: PoseInput, s: Style)
	local phase, speed, w = input.phase, input.speed, s.weight
	local k = smooth(1.2, 5, speed) -- 0 walk .. 1 sprint
	local sn, cs = math.sin(phase), math.cos(phase)
	local stride = lerp(26, 52, k) * lerp(1, 0.85, w)
	local flex = lerp(30, 95, k)
	local swingL = math.max(0, cs) -- left leg swinging forward
	local swingR = math.max(0, -cs)
	local arm = lerp(22, 62, k) * lerp(1, 0.8, w)
	local twist = lerp(5, 11, k)
	local lean = lerp(3, 15, k)
	set(p, {
		LeftHip = { stride * sn + lean * 0.4, 0, -lerp(3, 6, w) },
		RightHip = { -stride * sn + lean * 0.4, 0, lerp(3, 6, w) },
		LeftKnee = { -(lerp(6, 14, k) + flex * swingL ^ 1.4 + 12 * math.max(0, sn) * k) },
		RightKnee = { -(lerp(6, 14, k) + flex * swingR ^ 1.4 + 12 * math.max(0, -sn) * k) },
		-- Toes lift while the foot swings through, push off the ball of the foot behind.
		LeftAnkle = { 15 * swingL - 35 * math.max(0, -sn) * k },
		RightAnkle = { 15 * swingR - 35 * math.max(0, sn) * k },
		LeftShoulder = { -arm * sn + 8, 0, -lerp(6, 12, k) },
		RightShoulder = { arm * sn + 8, 0, lerp(6, 12, k) },
		LeftElbow = { lerp(22, 95, k) + 15 * math.max(0, -sn) },
		RightElbow = { lerp(22, 95, k) + 15 * math.max(0, sn) },
		LeftWrist = { -10 },
		RightWrist = { -10 },
		Root = { 0, -twist * sn, 0 },
		Waist = { -lerp(3, 12, k), 2 * twist * sn, 0 },
		Neck = { lerp(3, 14, k), -twist * sn, 0 },
	})
	-- Walk: body highest when passing over the planted foot; run: highest in the flight phase.
	local bob = lerp(-0.12, 0.32, k) * lerp(1, 1.25, w)
	p.rootY = bob * math.abs(sn) - lerp(0.0, 0.3, k) * lerp(1, 1.3, w)
	p.pitch = lean
	p.roll = sn * lerp(3, 2, k) * lerp(1, 1.6, w)
	-- Turning around: plant and skid for a moment.
	local turn = input.turnTime
	if turn and turn < 0.2 then
		local e = 1 - ease.outQuad(turn / 0.2)
		add(p, {
			Waist = { 14, 0, 0 },
			LeftShoulder = { 40, 0, -30 },
			RightShoulder = { 40, 0, 30 },
			RightHip = { 30 },
			RightKnee = { -30 },
		}, e)
		p.pitch -= 18 * e
		p.rootY -= 0.35 * e
	end
end

-- Airborne: take-off stretch, rising tuck, float at the peak, reach for the floor when falling; air jumps
-- turn into a front flip.
local function air(p: PoseOutput, input: PoseInput, s: Style)
	local vy, t = input.vy, input.t
	local airTime = input.airTime or 1
	local rising = smooth(0.5, 4, vy)
	local falling = smooth(-0.5, -6, vy)
	local float = math.max(0, 1 - rising - falling)
	local wave = math.sin(t * 7 + s.seed)
	-- Rising tuck (lead knee high).
	set(p, {
		RightHip = { 70 * rising + 20 * float + 8 * falling, 0, 6 },
		LeftHip = { 35 * rising + -8 * float - 10 * falling, 0, -6 },
		RightKnee = { -(95 * rising + 45 * float + 18 * falling) },
		LeftKnee = { -(70 * rising + 25 * float + 32 * falling) },
		RightAnkle = { -25 * rising - 15 * float + 10 * falling },
		LeftAnkle = { -35 * rising - 25 * float + 5 * falling },
		RightShoulder = {
			35 * rising + 30 * float + 70 * falling + wave * 6 * falling,
			0,
			20 + 45 * float + 55 * falling,
		},
		LeftShoulder = {
			20 * rising + 25 * float + 70 * falling - wave * 6 * falling,
			0,
			-(20 + 45 * float + 55 * falling),
		},
		RightElbow = { 70 * rising + 30 * float + 25 * falling },
		LeftElbow = { 80 * rising + 30 * float + 25 * falling },
		Waist = { -12 * rising - 4 * float + 6 * falling, 8, 0 },
		Neck = { 8 * rising - 12 * falling, -10, 0 },
	})
	p.pitch = 6 * rising - 4 * falling
	p.roll = wave * 2 * float
	-- Take-off: stretched out for the first instant.
	if airTime < 0.16 and vy > 0 then
		local e = 1 - ease.outQuad(airTime / 0.16)
		add(p, {
			RightHip = { -55, 0, 0 },
			LeftHip = { -30, 0, 0 },
			RightKnee = { 80, 0, 0 },
			LeftKnee = { 60, 0, 0 },
			RightAnkle = { -25 },
			LeftAnkle = { -15 },
			RightShoulder = { 110, 0, -10 },
			LeftShoulder = { 110, 0, 10 },
			Waist = { 18 },
			Neck = { 4 },
		}, e)
		p.rootY += 0.25 * e
	end
	-- Air jump: tuck tight and front flip.
	local flip = input.flipTime
	if flip and flip < 0.42 then
		local u = flip / 0.42
		local tuck = math.sin(math.pi * u)
		add(p, {
			RightHip = { 60, 0, 0 },
			LeftHip = { 80, 0, 0 },
			RightKnee = { -40 },
			LeftKnee = { -60 },
			RightShoulder = { 20, 0, -25 },
			LeftShoulder = { 30, 0, 25 },
			Waist = { -25 },
		}, tuck)
		p.pitch += 360 * ease.inOutQuad(u)
	end
end

-- Touch-down squash: knees give, body dips and recovers.
local function landing(p: PoseOutput, input: PoseInput)
	local land: number = input.landTime or 1
	if land >= 0.3 then
		return
	end
	local impact = math.clamp(input.landImpact or 0.5, 0, 1)
	local u = land / 0.3
	local d = (if u < 0.18 then ease.outQuad(u / 0.18) else 1 - ease.inOutQuad((u - 0.18) / 0.82)) * impact
	add(p, {
		LeftHip = { 40 },
		RightHip = { 40 },
		LeftKnee = { -70 },
		RightKnee = { -70 },
		Waist = { -16 },
		Neck = { 12 },
		LeftShoulder = { 10, 0, -25 },
		RightShoulder = { 10, 0, 25 },
	}, d)
	p.rootY -= 0.85 * d
	p.pitch += 8 * d
end

--------------------------------------------------------------------------------------------------------------
-- Moves on the timeline

local DEFAULT_LENGTH: { [string]: number } = { windup = 0.12, active = 0.12, recovery = 0.22 }

local function sampleCurve(c: Curve, g: number): number
	local keys = c.keys
	if g <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local k0, k1 = keys[i - 1], keys[i]
		if g <= k1[1] then
			local u = (g - k0[1]) / math.max(k1[1] - k0[1], 1e-3)
			return lerp(k0[2], k1[2], ease.outQuad(u))
		end
	end
	return keys[#keys][2]
end

local function tremble(p: PoseOutput, t: number, amount: number)
	local s1, s2 = math.sin(t * 61), math.sin(t * 47 + 1.3)
	add(p, {
		Waist = { s1 * 2.5, s2 * 2, 0 },
		RightShoulder = { s2 * 3, 0, s1 * 2 },
		LeftShoulder = { s1 * 3, 0, s2 * 2 },
		Neck = { s2 * 2, 0, 0 },
	}, amount)
	p.rootY += s1 * 0.05 * amount
	p.roll += s2 * 1.5 * amount
end

local function timeline(base: PoseOutput, def: MoveDef, input: PoseInput): PoseOutput
	local stage = input.stage
	local len = math.max(input.stageLength or DEFAULT_LENGTH[stage] or 0.12, 0.03)
	-- Without a clock, show the stage's signature pose: full wind-up, the strike, the start of the recovery.
	local st = input.stageTime or (if stage == "recovery" then 0 else len)
	local u = clamp01(st / len)
	local wind = over(base, def.wind)
	local hit = over(base, def.hit)
	local p: PoseOutput
	local g: number
	if stage == "windup" then
		g = u
		p = mix(base, wind, ease.outCubic(math.min(1, st / math.min(len, 0.1))))
		if def.charge then
			-- Long wind-ups keep sinking into the pose and shake with power.
			local build = clamp01((st - 0.08) / 0.5)
			tremble(p, input.t, build)
			p.rootY -= 0.12 * build
		end
	elseif stage == "active" then
		g = 1 + u
		local snap = def.snap or 0.06
		local rapid = def.rapid
		if rapid then
			local n = math.floor(st / rapid)
			local local_ = (st - n * rapid) / rapid
			local from = if n % 2 == 0 then mirror(hit) else hit
			local to = if n % 2 == 0 then hit else mirror(hit)
			p = mix(from, to, ease.outBack(clamp01(local_ / 0.5), 1.4))
			if n == 0 then
				p = mix(wind, hit, ease.outBack(clamp01(st / snap), 1.4))
			end
		else
			local e = ease.outBack(clamp01(st / snap), def.overshoot or 1.70158)
			p = mix(wind, hit, e)
			local hold = def.hold
			if hold and st > snap then
				p = mix(hit, over(base, hold), ease.inOutQuad(clamp01((st - snap) / math.max(len - snap, 0.05))))
			end
		end
		if def.tremble then
			tremble(p, input.t, 0.8)
		end
		p.snappy = true
	else
		g = 2 + u
		local from = if def.hold then over(base, def.hold) else hit
		local follow = if def.follow then over(from, def.follow) else mix(from, base, 0.25)
		if u < 0.35 then
			p = mix(from, follow, ease.outQuad(u / 0.35))
		else
			p = mix(follow, base, ease.inOutCubic((u - 0.35) / 0.65))
		end
	end
	if def.curves then
		for _, c in def.curves do
			local v = sampleCurve(c, g)
			if c.channel == "spin" then
				p.spin += v
			elseif c.channel == "pitch" then
				p.pitch += v
			end
		end
	end
	return p
end

--------------------------------------------------------------------------------------------------------------
-- Reactions and special states

local function hitStun(p: PoseOutput, input: PoseInput, s: Style)
	local st = input.stateTime or 0.2
	local vx, facing = input.vx or 0, input.facing or 1
	local launch = math.sqrt(vx * vx + input.vy * input.vy)
	local back = vx * facing <= 0 -- knocked backward (hit from the front)
	local dir = if back then 1 else -1
	-- Impact jolt: snaps hard for the first instant, then settles into the stagger.
	local jolt = 1 - ease.outQuad(clamp01(st / 0.16))
	local wob = math.sin(input.t * 17 + s.seed)
	set(p, {
		Waist = { dir * (16 + 16 * jolt), wob * 4, wob * 3 },
		Neck = { dir * (14 + 22 * jolt), -wob * 6, 0 },
		RightShoulder = { 40 + 30 * jolt + wob * 10, 0, 45 + 25 * jolt },
		LeftShoulder = { 30 + 30 * jolt - wob * 10, 0, -(50 + 25 * jolt) },
		RightElbow = { 35 },
		LeftElbow = { 45 },
		RightHip = { 30 + 15 * jolt, 0, 8 },
		LeftHip = { -10, 0, -8 },
		RightKnee = { -45 },
		LeftKnee = { -20 },
		RightAnkle = { -20 },
		LeftAnkle = { -30 },
	})
	if not back then
		add(p, { RightShoulder = { -80, 0, 0 }, LeftShoulder = { -70, 0, 0 } })
	end
	p.pitch = -dir * (12 + 14 * jolt)
	p.lunge = -dir * 0.25 * jolt
	p.rootY = -0.2
	-- Launched hard: curl up and tumble head over heels, faster the harder the hit.
	if not input.grounded then
		local tumble = smooth(9, 16, launch)
		if tumble > 0 then
			local spinRate = 300 + launch * 28
			local tucked = out()
			set(tucked, {
				Waist = { -30, 0, 0 },
				Neck = { -20 },
				RightHip = { 75, 0, 15 },
				LeftHip = { 55, 0, -15 },
				RightKnee = { -100 },
				LeftKnee = { -80 },
				RightShoulder = { 60 + wob * 25, 0, 70 },
				LeftShoulder = { 40 - wob * 25, 0, -70 },
				RightElbow = { 40 },
				LeftElbow = { 60 },
			})
			local blended = mix(p, tucked, tumble)
			p.joints = blended.joints
			p.pitch += -dir * st * spinRate * tumble
			p.roll += wob * 10 * tumble
		end
	end
	p.snappy = true
	p.stiffness = 42
	p.damping = 0.45
end

local function dodge(p: PoseOutput, input: PoseInput, s: Style)
	local st = input.stateTime or 0.15
	local vx, facing = input.vx or 0, input.facing or 1
	if not input.grounded then
		-- Air dodge: snap into a tuck and corkscrew.
		local u = clamp01(st / 0.38)
		air(p, input, s)
		add(p, {
			RightHip = { 60 },
			LeftHip = { 70 },
			RightKnee = { -60 },
			LeftKnee = { -70 },
			RightShoulder = { 30, 0, -40 },
			LeftShoulder = { 30, 0, 40 },
			Waist = { -20 },
		}, math.sin(math.pi * u))
		p.spin = 360 * ease.outCubic(u)
		p.stiffness, p.damping = 38, 0.8
		return
	end
	if math.abs(vx) > 1.5 then
		-- Roll: tight ball, one full turn in the direction of travel.
		local u = clamp01(st / 0.34)
		local dir = if vx * facing >= 0 then 1 else -1
		local ball = math.sin(math.pi * clamp01(u * 1.15))
		set(p, {
			Waist = { -40 * ball, 0, 0 },
			Neck = { -30 * ball },
			LeftHip = { 115 * ball + 20, 0, -8 },
			RightHip = { 115 * ball + 20, 0, 8 },
			LeftKnee = { -135 * ball - 20 },
			RightKnee = { -135 * ball - 20 },
			LeftShoulder = { 70, 0, 10 },
			RightShoulder = { 70, 0, -10 },
			LeftElbow = { 110 },
			RightElbow = { 110 },
			LeftAnkle = { -30 },
			RightAnkle = { -30 },
		})
		p.pitch = dir * 360 * ease.inOutQuad(u)
		p.rootY = -0.6 - 1.2 * ball
		p.stiffness, p.damping = 45, 0.85
	else
		-- Spot dodge: sway back and turn away toward the camera, light on the feet.
		local u = clamp01(st / 0.28)
		local e = math.sin(math.pi * u)
		stance(p, input, s)
		add(p, {
			Waist = { 22, -20, 0 },
			Neck = { -10, 15, 0 },
			LeftShoulder = { -30, 0, -30 },
			RightShoulder = { -30, 0, 30 },
			LeftHip = { 30 },
			LeftKnee = { -50 },
		}, e)
		p.spin = -40 * e
		p.pitch = -12 * e
		p.rootY -= 0.4 * e
		p.lunge = -0.35 * e
		p.stiffness, p.damping = 40, 0.85
	end
end

local function dazed(p: PoseOutput, input: PoseInput, s: Style)
	local t = input.t
	local c, sn = math.cos(t * 2.4 + s.seed), math.sin(t * 2.4 + s.seed)
	set(p, {
		Waist = { -18 + sn * 5, c * 6, c * 6 },
		Neck = { -10 + sn * 16, c * 10, c * 18 },
		LeftShoulder = { 8 + c * 12, 0, -10 },
		RightShoulder = { 8 - c * 12, 0, 10 },
		LeftElbow = { 20 },
		RightElbow = { 25 },
		LeftHip = { 20 + sn * 10, 0, -10 },
		RightHip = { 20 - sn * 10, 0, 10 },
		LeftKnee = { -35 - sn * 12 },
		RightKnee = { -35 + sn * 12 },
	})
	p.rootY = -0.45 + math.abs(sn) * 0.08
	p.roll = c * 10
	p.pitch = 6 + sn * 4
	p.stiffness, p.damping = 12, 1
end

local function ledge(p: PoseOutput, input: PoseInput, s: Style)
	local t = input.t
	local swing = math.sin(t * 2.2 + s.seed)
	set(p, {
		LeftShoulder = { 168, 0, -12 },
		RightShoulder = { 168, 0, 12 },
		LeftElbow = { 25 },
		RightElbow = { 25 },
		LeftWrist = { 30 },
		RightWrist = { 30 },
		Neck = { 22 },
		Waist = { 6 + swing * 3 },
		LeftHip = { 12 + swing * 12, 0, -4 },
		RightHip = { -4 - swing * 10, 0, 4 },
		LeftKnee = { -25 - math.max(0, swing) * 25 },
		RightKnee = { -15 - math.max(0, -swing) * 25 },
		LeftAnkle = { -40 },
		RightAnkle = { -40 },
	})
	p.pitch = swing * 4
	p.stiffness = 14
end

local function shield(p: PoseOutput, input: PoseInput, s: Style)
	local t = input.t
	local hold = math.sin(t * 3 + s.seed)
	set(p, {
		Root = { 0, 10, 0 },
		Waist = { -14, 0, 0 },
		Neck = { 14 },
		LeftShoulder = { 88, 0, 32 },
		RightShoulder = { 88, 0, -32 },
		LeftElbow = { 112 },
		RightElbow = { 112 },
		LeftWrist = { 20 },
		RightWrist = { 20 },
		RightHip = { 48, 0, 10 },
		LeftHip = { 22, 0, -10 },
		RightKnee = { -78 },
		LeftKnee = { -64 },
	})
	p.rootY = -0.7 + hold * 0.03
	p.pitch = 4
	p.stiffness = 30
end

local function grabbing(p: PoseOutput, input: PoseInput, s: Style)
	local st = input.stateTime or 0.2
	stance(p, input, s)
	if input.state == "Grab" then
		-- Lunge in with both hands.
		local e = ease.outBack(clamp01(st / 0.1), 1.5)
		local reach = out()
		set(reach, {
			LeftShoulder = { 88, 0, 12 },
			RightShoulder = { 88, 0, -12 },
			LeftElbow = { 15 },
			RightElbow = { 15 },
			Waist = { -16, 0, 0 },
			RightHip = { 35 },
			RightKnee = { -45 },
		})
		local r = mix(p, over(p, { j = {} }), 0)
		for name, v in reach.joints do
			if v.x ~= 0 or v.y ~= 0 or v.z ~= 0 then
				local b = r.joints[name]
				r.joints[name] = a(lerp(b.x, v.x, e), lerp(b.y, v.y, e), lerp(b.z, v.z, e))
			end
		end
		p.joints = r.joints
		p.pitch = 14 * e
		p.lunge = 0.5 * e
	elseif input.state == "Carrying" then
		set(p, {
			LeftShoulder = { 95, 0, 15 },
			RightShoulder = { 95, 0, -15 },
			LeftElbow = { 35 },
			RightElbow = { 35 },
			Waist = { 6, 0, 0 },
		})
		p.lunge = 0.2
	else
		-- Throw: heave from behind into a big forward release.
		local u = clamp01(st / 0.28)
		local e = if u < 0.3 then 0 else ease.outBack((u - 0.3) / 0.7, 1.6)
		local back = 1 - e
		set(p, {
			LeftShoulder = { lerp(-40, 120, e), 0, 10 },
			RightShoulder = { lerp(-40, 120, e), 0, -10 },
			LeftElbow = { 20 },
			RightElbow = { 20 },
			Waist = { lerp(18, -22, e), lerp(-30, 30, e), 0 },
			RightHip = { lerp(10, 45, e) },
			RightKnee = { lerp(-50, -40, e) },
			LeftHip = { lerp(-5, -25, e) },
		})
		p.pitch = lerp(-12, 18, e)
		p.lunge = 0.5 * e - 0.2 * back
	end
	p.snappy = true
	p.stiffness = 36
end

local function grabbed(p: PoseOutput, input: PoseInput, s: Style)
	local t = input.t
	local kick = math.sin(t * 11 + s.seed)
	set(p, {
		Waist = { 12, 0, kick * 4 },
		Neck = { 18, kick * 8, 0 },
		LeftShoulder = { 60 + kick * 30, 0, -60 },
		RightShoulder = { 60 - kick * 30, 0, 60 },
		LeftElbow = { 50 },
		RightElbow = { 50 },
		LeftHip = { 20 + kick * 25 },
		RightHip = { 20 - kick * 25 },
		LeftKnee = { -50 - kick * 20 },
		RightKnee = { -50 + kick * 20 },
		LeftAnkle = { -30 },
		RightAnkle = { -30 },
	})
	p.rootY = 0.2
	p.pitch = -10
	p.snappy = true
	p.stiffness = 30
	p.damping = 0.6
end

--------------------------------------------------------------------------------------------------------------
-- Finishing passes

-- Plants the feet flat on the floor (ankles cancel the leg chain and the body lean).
local function plantFeet(p: PoseOutput, amount: number)
	if amount <= 0 then
		return
	end
	local j = p.joints
	for _, side in { "Left", "Right" } do
		local ankle = j[side .. "Ankle"]
		local flat = p.pitch - j.Root.x - j[side .. "Hip"].x - j[side .. "Knee"].x
		ankle.x = lerp(ankle.x, math.clamp(flat, -50, 50), amount)
	end
end

local function finish(p: PoseOutput)
	for _, v in p.joints do
		v.x = math.clamp(v.x, -180, 180)
		v.y = math.clamp(v.y, -180, 180)
		v.z = math.clamp(v.z, -180, 180)
	end
	p.rootY = math.clamp(p.rootY, -2.5, 2.5)
end

function Pose.compute(input: PoseInput): PoseOutput
	local p = out()
	local state = input.state
	local s = input.style or DEFAULT_STYLE

	if state == "Defeated" then
		finish(p)
		return p
	elseif state == "Ledge" then
		ledge(p, input, s)
	elseif state == "HitStun" then
		hitStun(p, input, s)
	elseif state == "Grabbed" then
		grabbed(p, input, s)
	elseif state == "ShieldBreak" or state == "Dazed" then
		dazed(p, input, s)
	elseif state == "Grab" or state == "Carrying" or state == "Throw" then
		grabbing(p, input, s)
		plantFeet(p, 0.8)
	elseif state == "Charge" then
		-- Smash charge: hold the smash wind-up and shake harder the longer it charges.
		stance(p, input, s)
		local held = over(p, MOVES.smash.wind)
		p = held
		local build = clamp01((input.stateTime or 0.4) / 0.8)
		tremble(p, input.t, 0.4 + build)
		p.rootY -= 0.15 * build
		p.snappy = true
		p.stiffness = 34
		plantFeet(p, 0.9)
	elseif state == "Dodge" then
		dodge(p, input, s)
	elseif input.blocking then
		shield(p, input, s)
		plantFeet(p, 1)
	else
		local kind = Pose.kindOf(input.move, input.weapon, input.variant)
		local def = if kind then MOVES[kind] else nil
		local base = out()
		if def and def.air or not input.grounded then
			air(base, input, s)
		elseif input.speed > 0.6 and not def then
			locomotion(base, input, s)
		else
			stance(base, input, s)
		end
		if def and input.stage ~= "" then
			p = timeline(base, def, input)
			if input.stage == "recovery" then
				p.stiffness, p.damping = 28, 0.8
			else
				p.stiffness, p.damping = 44, 0.62
			end
			if input.grounded and not def.air then
				plantFeet(p, 0.85)
			end
		else
			p = base
			if state == "Attack" and input.grounded then
				-- Landing lag after an aerial: a heavy crouch.
				landing(p, { state = state, landTime = 0.05, landImpact = 1 } :: any)
			end
			if input.grounded then
				landing(p, input)
				plantFeet(p, if input.speed > 0.6 then 0.35 else 1)
				p.stiffness = if input.speed > 0.6 then 26 else 18
			else
				p.stiffness = 22
			end
		end
	end
	finish(p)
	return p
end

return Pose
