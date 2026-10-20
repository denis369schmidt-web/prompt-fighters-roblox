--!strict
-- The fight itself: a deterministic, instance-free simulation ported from the Godot core (combat.gd).
-- The server runs one Simulation per match at 60 Hz and feeds it one Command per fighter per tick;
-- players and bots go through exactly the same path. Units: meters, seconds, x right, y up, feet at y.
--
-- Signature specials run in Combat/Signature, their projectiles in Combat/Projectiles.
-- Not ported yet (later phases): weapon items, hazards, mutators, bosses.

local Arena = require(script.Parent.Arena)
local Input = require(script.Parent.Input)
local Knockback = require(script.Parent.Knockback)
local Moveset = require(script.Parent.Moveset)
local Projectiles = require(script.Parent.Projectiles)
local Signature = require(script.Parent.Signature)
local Constants = require(script.Parent.Parent.Data.Constants)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local SignatureParams = require(script.Parent.Parent.Data.Generated.SignatureParams)
local Rng = require(script.Parent.Parent.Util.Rng)

type Command = Input.Command
type Ability = Moveset.Ability

local STEP = 1 / Constants.TICK_RATE
local MOVE = Constants.MOVEMENT
local COUNTDOWN = 2.4
local BODY_SEPARATION = 0.6
local BODY_PUSH_RATE = 0.9
local LANDING_LAG = 0.1
local PARRY_WINDOW = 0.12
local HITSTOP_FRAMES = 4
local ARMOR_SELF_LIMIT = 18
local LEDGE_ACT_DELAY = 0.1
local FINISH_TIME = 5.0
local FINISH_RANGE = 4.0
local FINISH_INPUT_WINDOW = 2.0
local HITBOX_BACK_REACH = 0.35
local BODY_HEIGHT = 1.6
local COMBO_MULT = { 1.0, 1.08, 1.18, 1.30, 1.45 }
local SMASH_OF = { ftilt = "fsmash", utilt = "usmash", dtilt = "dsmash", jab = "fsmash", dash_attack = "fsmash" }

export type Pending = {
	ability: Ability,
	key: string,
	special: boolean,
	stage: "windup" | "active" | "recovery",
	remaining: number,
	hitList: { [number]: boolean },
	rehitTimer: number,
}

export type FighterState = {
	index: number,
	team: number,
	fighterId: string,
	isBot: boolean,
	moves: { [string]: Ability },
	phys: { [string]: number },
	runSpeed: number,
	weight: number,
	stats: { vitality: number, power: number, defense: number, speed: number, technique: number },
	finisherCode: { string },

	x: number,
	y: number,
	vx: number,
	vy: number,
	walkV: number,
	grounded: boolean,
	facing: number,
	state: string,
	percent: number,
	lives: number,
	super: number,
	combo: number,
	comboTimer: number,
	hitstop: number,
	stun: number,
	intangible: number,
	invulnerable: number,
	airControlLock: number,
	dropThrough: number,
	lockTimer: number,

	blocking: boolean,
	shieldHp: number,
	parryTimer: number,
	parryUsed: boolean,
	airJumps: number,
	airDashUsed: boolean,
	airDodgeUsed: boolean,
	dodgeTimer: number,
	dodgeKind: string,
	dodgeDir: number,
	slide: number,

	ledge: number,
	ledgeTimer: number,
	ledgeGrabs: number,
	ledgeCooldown: number,

	chargeKey: string,
	chargeTime: number,
	runTime: number,
	hopFrames: number?,
	moving: boolean,
	crouching: boolean,

	cooldownStandard: number,
	cooldownSpecial: number,
	pending: Pending?,
	counter: number,
	rageTimer: number,
	armorTimer: number,

	-- signature specials (Combat/Signature)
	sigParams: { [string]: any }?,
	specialDamage: number,
	specialPush: number,
	specialHeld: boolean,
	freezeTimer: number,
	markedBy: number,
	markTimer: number,
	heat: number,
	bulwark: number,
	chainStage: number,
	chainTimer: number,
	turbo: number,
	turboHitT: number,
	eagle: number,
	eagleStrikeT: number,
	hoverT: number,
	slam: boolean,
	slamVx: number,
	slamDmg: number,
	dive: number,
	iai: number,
	volley: number,
	volleyT: number,
	hexT: number,
	hexMult: number,
	leashBy: number,
	leashT: number,
	leashLen: number,
	crown: string,
	sigCharge: number,
	trailLastX: number,

	grabTimer: number,
	grabTarget: number?,
	grabbedBy: number?,
	grabImmunity: number,

	inX: number,
	inY: number,
	prevShield: boolean,
	prevDown: boolean,
	prevAxis: number,
	tokens: { { key: string, time: number } },

	-- statistics for results and quests
	hits: number,
	kos: number,
	damageDealt: number,
	bestCombo: number,
	finishers: number,
	stocksLost: number,
}

export type Event = { [string]: any }

export type MatchConfig = {
	fighters: { string },
	bots: { boolean }?,
	teams: { number }?,
	arena: string?,
	stocks: number?,
	seed: number?,
	timeLimit: number?,
	countdown: number?,
	finishers: boolean?,
}

export type Simulation = {
	fighters: { FighterState },
	projectiles: { Projectiles.Projectile },
	projectileSerial: number,
	queued: { Contact },
	platforms: { Arena.Platform },
	arenaId: string,
	rng: Rng.Rng,
	events: { Event },
	elapsed: number,
	timeLeft: number,
	countdown: number,
	frame: number,
	suddenDeath: boolean,
	finishersEnabled: boolean,
	finishPhase: boolean,
	finishTimer: number,
	finishWinner: number,
	finishLoser: number,
	result: number?, -- nil while running; winner index, or -1 for a draw
	tick: (self: Simulation, commands: { Command }) -> (),
	nearestOpponent: (self: Simulation, index: number) -> number?,
	isAlly: (self: Simulation, a: number, b: number) -> boolean,
	snapshot: (self: Simulation) -> { FighterSnapshot },
}

local Sim = {}
Sim.__index = Sim
Sim.STEP = STEP
Sim.FINISH_TIME = FINISH_TIME

local function newFighter(index: number, fighterId: string, team: number, stocks: number, isBot: boolean): FighterState
	local def = Fighters.get(fighterId)
	local phys: { [string]: number } = table.clone(def.phys :: any)
	local sig = (SignatureParams :: any)[fighterId]
	local baseSpecial = Moveset.baseAttacks(fighterId).special
	return {
		index = index,
		team = team,
		fighterId = fighterId,
		isBot = isBot,
		moves = Moveset.build(fighterId),
		phys = phys,
		runSpeed = def.runSpeed,
		weight = def.weight,
		stats = def.stats,
		finisherCode = def.finisher.code,

		x = Arena.SPAWN_X[(index - 1) % #Arena.SPAWN_X + 1],
		y = 0,
		vx = 0,
		vy = 0,
		walkV = 0,
		grounded = true,
		facing = Arena.SPAWN_FACING[(index - 1) % #Arena.SPAWN_FACING + 1],
		state = "Ready",
		percent = 0,
		lives = stocks,
		super = 0,
		combo = 0,
		comboTimer = 0,
		hitstop = 0,
		stun = 0,
		intangible = 0,
		invulnerable = 0,
		airControlLock = 0,
		dropThrough = 0,
		lockTimer = 0,

		blocking = false,
		shieldHp = MOVE.shield.max * (phys.shield or 1),
		parryTimer = 0,
		parryUsed = false,
		airJumps = phys.air_jumps,
		airDashUsed = false,
		airDodgeUsed = false,
		dodgeTimer = 0,
		dodgeKind = "",
		dodgeDir = 0,
		slide = 0,

		ledge = 0,
		ledgeTimer = 0,
		ledgeGrabs = 0,
		ledgeCooldown = 0,

		chargeKey = "",
		chargeTime = 0,
		runTime = 0,
		hopFrames = nil,
		moving = false,
		crouching = false,

		cooldownStandard = 0,
		cooldownSpecial = 0,
		pending = nil,
		counter = 0,
		rageTimer = 0,
		armorTimer = 0,

		sigParams = sig,
		specialDamage = baseSpecial.damage,
		specialPush = baseSpecial.push,
		specialHeld = false,
		freezeTimer = 0,
		markedBy = 0,
		markTimer = 0,
		heat = 0,
		bulwark = 0,
		chainStage = 0,
		chainTimer = 0,
		turbo = 0,
		turboHitT = 0,
		eagle = 0,
		eagleStrikeT = 0,
		hoverT = 0,
		slam = false,
		slamVx = 0,
		slamDmg = 0,
		dive = 0,
		iai = 0,
		volley = 0,
		volleyT = 0,
		hexT = 0,
		hexMult = 1,
		leashBy = 0,
		leashT = 0,
		leashLen = 0,
		crown = if sig and sig.mech == "crown_shift" then "frost" else "",
		sigCharge = 0,
		trailLastX = 0,

		grabTimer = 0,
		grabTarget = nil,
		grabbedBy = nil,
		grabImmunity = 0,

		inX = 0,
		inY = 0,
		prevShield = false,
		prevDown = false,
		prevAxis = 0,
		tokens = {},

		hits = 0,
		kos = 0,
		damageDealt = 0,
		bestCombo = 0,
		finishers = 0,
		stocksLost = 0,
	}
end

function Sim.new(config: MatchConfig): Simulation
	assert(#config.fighters >= 1 and #config.fighters <= Constants.MAX_PLAYERS, "1 to 4 fighters")
	local stocks = config.stocks or Constants.DEFAULT_STOCKS
	local arenaId = config.arena or "neon_alley"
	local self = setmetatable({
		fighters = {},
		projectiles = {},
		projectileSerial = 0,
		queued = {},
		platforms = Arena.platformsFor(arenaId),
		arenaId = arenaId,
		rng = Rng.new(config.seed or 7919),
		events = {},
		elapsed = 0,
		timeLeft = config.timeLimit or Constants.MATCH_SECONDS,
		countdown = config.countdown or COUNTDOWN,
		frame = 0,
		suddenDeath = false,
		finishersEnabled = config.finishers ~= false,
		finishPhase = false,
		finishTimer = 0,
		finishWinner = 0,
		finishLoser = 0,
		result = nil,
	}, Sim)
	for i, fighterId in config.fighters do
		local team = if config.teams then config.teams[i] else i
		local isBot = if config.bots then config.bots[i] == true else false
		table.insert(self.fighters, newFighter(i, fighterId, team, stocks, isBot))
	end
	return (self :: any) :: Simulation
end

local function moveToward(value: number, target: number, delta: number): number
	if value < target then
		return math.min(value + delta, target)
	end
	return math.max(value - delta, target)
end

local function sign(v: number): number
	return if v > 0 then 1 elseif v < 0 then -1 else 0
end

function Sim.isAlly(self: Simulation, a: number, b: number): boolean
	return a ~= b and self.fighters[a].team == self.fighters[b].team
end

function Sim.nearestOpponent(self: Simulation, index: number): number?
	local f = self.fighters[index]
	local best, bestDist = nil, math.huge
	for j, other in self.fighters do
		if j ~= index and not self:isAlly(index, j) and other.state ~= "Defeated" then
			local d = math.abs(other.x - f.x) + math.abs(other.y - f.y)
			if d < bestDist then
				best, bestDist = j, d
			end
		end
	end
	return best
end

local function emit(self: Simulation, event: Event)
	table.insert(self.events, event)
end

-- Reads one command and derives presses (edges) from what was held last tick.
type ReadInput = {
	axis: number,
	up: boolean,
	down: boolean,
	shield: boolean,
	jump: boolean,
	jumpHeld: boolean,
	standard: boolean,
	standardHeld: boolean,
	special: boolean,
	specialHeld: boolean,
	grab: boolean,
	smash: boolean,
	drop: boolean,
	shieldPressed: boolean,
	downPressed: boolean,
	sidePressed: number,
}

local function readInput(f: FighterState, cmd: Command): ReadInput
	local axis = math.clamp(cmd.move, -1, 1)
	local side = 0
	if math.abs(axis) > 0.6 and math.abs(f.prevAxis) <= 0.6 then
		side = sign(axis)
	end
	local inp: ReadInput = {
		axis = axis,
		up = cmd.up,
		down = cmd.down,
		shield = cmd.block,
		jump = cmd.jump,
		jumpHeld = cmd.jumpHeld,
		standard = cmd.standard,
		standardHeld = cmd.standardHeld,
		special = cmd.special,
		specialHeld = cmd.specialHeld,
		grab = cmd.grab,
		smash = cmd.smash,
		drop = cmd.drop,
		shieldPressed = cmd.block and not f.prevShield,
		downPressed = cmd.down and not f.prevDown,
		sidePressed = side,
	}
	f.prevShield, f.prevDown, f.prevAxis = cmd.block, cmd.down, axis
	f.inX = axis
	f.inY = (if cmd.up then 1 else 0) - (if cmd.down then 1 else 0)
	return inp
end

local function beginPending(self: Simulation, f: FighterState, a: Ability)
	f.walkV = 0
	f.state = "Attack"
	f.pending = {
		ability = a,
		key = a.key,
		special = a.special,
		stage = "windup",
		remaining = a.windup,
		hitList = {},
		rehitTimer = 0,
	}
	Signature.onBegin(f, a)
	emit(self, { type = "attack", actor = f.index, key = a.key, name = a.name, special = a.special })
end

-- Starts a move from the moveset. charge > 1 scales a charged smash.
local function startMove(self: Simulation, f: FighterState, key: string, charge: number?): boolean
	local base = f.moves[key]
	if not base then
		return false
	end
	if base.special then
		if f.cooldownSpecial > 0 then
			return false
		end
		f.cooldownSpecial = base.cooldown
	elseif key == "jab" then
		if f.cooldownStandard > 0 then
			return false
		end
		f.cooldownStandard = base.cooldown
	end
	local a = table.clone(base)
	local c = charge or 1
	if c > 1 then
		a.damage *= c
		a.push *= 1 + (c - 1) * 0.8
	end
	beginPending(self, f, a)
	return true
end

-- Second press of a two-stage signature (tri slash, mark strike, recall ...). True when one started.
local function startFollowup(self: Simulation, f: FighterState): boolean
	local found = Signature.followup(self, f.index)
	if found == nil then
		return false
	end
	local follow = found :: Ability
	f.cooldownSpecial = math.max(follow.cooldown, 0.4)
	beginPending(self, f, follow)
	return true
end

local function startDodge(self: Simulation, f: FighterState, kind: string, dir: number, dirY: number?)
	f.state = "Dodge"
	f.walkV = 0
	f.dodgeKind = kind
	f.dodgeDir = dir
	f.blocking = false
	if kind == "roll" then
		f.dodgeTimer = MOVE.roll.time
		f.intangible = MOVE.dodgeIntangible
	elseif kind == "spot" then
		f.dodgeTimer = MOVE.spotDodge.time
		f.intangible = MOVE.spotDodge.time * 0.8
	else
		f.dodgeTimer = MOVE.airDodge.time
		f.intangible = MOVE.dodgeIntangible + 0.04
		f.airDodgeUsed = true
		local vy = dirY or 0
		local len = math.sqrt(dir * dir + vy * vy)
		if len > 0.2 then
			f.vx = dir / len * MOVE.airDodge.speed
			f.vy = vy / len * MOVE.airDodge.speed
		else
			f.vx *= 0.3
			f.vy = math.max(f.vy, 0) * 0.3
		end
	end
	emit(self, { type = "dodge", actor = f.index, kind = kind })
end

local function shieldBreak(self: Simulation, f: FighterState)
	f.blocking = false
	f.shieldHp = 0
	f.state = "ShieldBreak"
	f.stun = MOVE.shield.breakStun
	f.pending = nil
	f.vy = 6
	f.grounded = false
	emit(self, { type = "shield_break", actor = f.index })
end

-- Universal recovery dash: special in the air, once per airtime.
local function airDash(self: Simulation, f: FighterState, axis: number, dive: boolean, rise: boolean): boolean
	if f.grounded or f.airDashUsed or f.state ~= "Ready" then
		return false
	end
	local dir = f.facing
	if math.abs(axis) > 0.25 then
		dir = sign(axis)
	elseif f.x < Arena.STAGE_LEFT or f.x > Arena.STAGE_RIGHT then
		dir = -sign(f.x)
	end
	f.facing = if dir > 0 then 1 else -1
	f.vx = dir * MOVE.airDash.speed
	local lift = math.sqrt(f.phys.gravity / 20)
	f.vy = if dive then MOVE.airDash.fall else math.max(f.vy, MOVE.airDash.rise * lift)
	if rise then
		f.vx = axis * MOVE.airDash.speed * 0.4
		f.vy = MOVE.airDash.speed * 0.95 * lift
	end
	f.airDashUsed = true
	f.airControlLock = 0
	emit(self, { type = "air_dash", actor = f.index, dive = dive })
	return true
end

local function initiateGrab(self: Simulation, f: FighterState)
	if f.state ~= "Ready" or f.grabImmunity > 0 then
		return
	end
	f.state = "Grab"
	f.grabTimer = 0.12
	f.lockTimer = 0.35
	emit(self, { type = "grab_attempt", actor = f.index })
end

local function executeThrow(self: Simulation, attacker: FighterState, kind: Knockback.ThrowKind)
	local targetIndex = attacker.grabTarget
	if not targetIndex then
		return
	end
	local target = self.fighters[targetIndex :: number]
	local hit = Knockback.throw(
		kind,
		target.percent,
		target.stats.defense,
		target.weight,
		target.stats.vitality,
		attacker.facing
	)
	target.percent = hit.percent
	target.vx, target.vy = hit.vx, hit.vy
	target.grounded = false
	target.dropThrough = 0.15
	target.stun = hit.hitstun
	target.airControlLock = hit.airControlLock
	target.state = "HitStun"
	target.grabbedBy = nil
	target.grabImmunity = 0.85
	attacker.state = "Throw"
	attacker.lockTimer = 0.28
	attacker.grabTarget = nil
	attacker.grabTimer = 0
	attacker.damageDealt += hit.damage
	emit(self, { type = "throw", actor = attacker.index, target = targetIndex, kind = kind, damage = hit.damage })
end

local function releaseGrab(self: Simulation, attacker: FighterState)
	local targetIndex = attacker.grabTarget
	if targetIndex then
		local target = self.fighters[targetIndex]
		target.state = "Ready"
		target.grabbedBy = nil
		target.grabImmunity = 0.65
		target.vx = -attacker.facing * 4.5
		target.vy = 2
	end
	attacker.state = "Ready"
	attacker.grabTarget = nil
	attacker.grabTimer = 0
	attacker.vx = attacker.facing * -2.5
	emit(self, { type = "grab_breakout", actor = attacker.index, target = targetIndex })
end

-- Standard button: jab, tilts (or a charged smash when held), dash attack, aerials.
local function chooseStandard(self: Simulation, f: FighterState, inp: ReadInput)
	local axis = inp.axis
	if not f.grounded then
		local key = "nair"
		if inp.up then
			key = "uair"
		elseif inp.down then
			key = "dair"
		elseif axis * f.facing > 0.3 then
			key = "fair"
		elseif axis * f.facing < -0.3 then
			key = "bair"
		end
		startMove(self, f, key)
		return
	end
	if math.abs(axis) > 0.3 then
		f.facing = sign(axis)
	end
	local key = "jab"
	if inp.up then
		key = "utilt"
	elseif inp.down then
		key = "dtilt"
	elseif math.abs(axis) > 0.3 then
		key = if f.runTime > MOVE.runAfter then "dash_attack" else "ftilt"
	end
	if inp.smash then
		startMove(self, f, SMASH_OF[key] or "fsmash", 1.3)
	elseif inp.standardHeld and (key == "ftilt" or key == "utilt" or key == "dtilt") then
		f.state = "Charge"
		f.chargeKey = key
		f.chargeTime = 0
		emit(self, { type = "charge", actor = f.index })
	else
		startMove(self, f, key)
	end
end

local function onLand(_self: Simulation, f: FighterState)
	f.walkV = 0
	f.airDodgeUsed = false
	f.ledgeGrabs = 0
	f.hopFrames = nil
	f.airJumps = f.phys.air_jumps
	f.airDashUsed = false
	local pending = f.pending
	if pending and pending.ability.aerial then
		f.pending = nil
		f.state = "Attack"
		f.lockTimer = LANDING_LAG
	end
	if f.state == "Dodge" and f.dodgeKind == "air" then
		f.state = "Ready"
		if math.abs(f.vx) > 2 then
			f.slide = 0.25
		end
	end
end

-- Grabs a stage ledge when falling past it. A newcomer pushes the current holder off.
local function tryLedgeGrab(self: Simulation, f: FighterState): boolean
	for _, side in { -1, 1 } do
		local edge = if side == -1 then Arena.STAGE_LEFT else Arena.STAGE_RIGHT
		local out = (f.x - edge) * side
		if out >= -0.2 and out <= 1.1 and f.y <= 0.05 and f.y >= -1.9 then
			for _, other in self.fighters do
				if other ~= f and other.state == "Ledge" and other.ledge == side then
					other.state = "Ready"
					other.ledge = 0
					other.intangible = 0
					other.vx = side * 2.5
					other.vy = 3
					other.ledgeCooldown = 0.6
					emit(self, { type = "ledge_trump", actor = f.index, target = other.index })
				end
			end
			f.state = "Ledge"
			f.ledge = side
			f.ledgeTimer = 0
			f.x = edge + side * 0.3
			f.y = Arena.LEDGE_HANG_Y
			f.vx, f.vy = 0, 0
			f.facing = -side
			f.airJumps = f.phys.air_jumps
			f.airDashUsed = false
			f.airDodgeUsed = false
			local table_ = MOVE.ledge.invulnerable
			f.intangible = table_[math.min(f.ledgeGrabs + 1, #table_)]
			f.ledgeGrabs += 1
			f.pending = nil
			emit(self, { type = "ledge_grab", actor = f.index, side = side, grabs = f.ledgeGrabs })
			return true
		end
	end
	return false
end

-- Ledge options: climb (towards stage / up), jump, attack, roll (shield), drop (down / away).
local function updateLedge(self: Simulation, f: FighterState, inp: ReadInput)
	f.ledgeTimer += STEP
	local side = f.ledge
	local edge = if side == -1 then Arena.STAGE_LEFT else Arena.STAGE_RIGHT
	local toward = -side
	if f.ledgeTimer < LEDGE_ACT_DELAY then
		return
	end
	local action = ""
	-- selene: allow(if_same_then_else)
	if f.ledgeTimer >= MOVE.ledge.maxHang then
		action = "drop"
	elseif inp.jump then
		action = "jump"
	elseif inp.standard or inp.special then
		action = "attack"
	elseif inp.shieldPressed then
		action = "roll"
	elseif inp.up or inp.axis * toward > 0.5 then
		action = "climb"
	elseif inp.down or inp.axis * toward < -0.5 then
		action = "drop"
	end
	if action == "" then
		return
	end
	f.ledge = 0
	f.state = "Ready"
	f.grounded = false
	if action == "drop" then
		f.ledgeCooldown = 0.45
		f.intangible = 0
	elseif action == "jump" then
		f.vy = f.phys.jump * 1.05
		f.vx = toward * 1.5
		f.ledgeCooldown = 0.3
		emit(self, { type = "jump", actor = f.index })
	else
		f.x = edge + toward * 0.45
		f.y = 0
		f.vy = 0
		f.grounded = true
		f.intangible = 0.25
		f.facing = toward
		if action == "attack" then
			startMove(self, f, "dtilt")
		elseif action == "roll" then
			startDodge(self, f, "roll", toward)
		end
		emit(self, { type = "ledge_climb", actor = f.index, action = action })
	end
end

local function recordFinishTokens(self: Simulation, f: FighterState, inp: ReadInput)
	local loser = self.fighters[self.finishLoser]
	local toward = if loser.x >= f.x then 1 else -1
	local function add(key: string)
		table.insert(f.tokens, { key = key, time = self.elapsed })
	end
	if inp.sidePressed ~= 0 then
		add(if inp.sidePressed == toward then "F" else "B")
	end
	if inp.jump then
		add("U")
	end
	if inp.downPressed then
		add("D")
	end
	if inp.standard then
		add("A")
	end
	if inp.special then
		add("S")
	end
	while #f.tokens > 8 do
		table.remove(f.tokens, 1)
	end
end

local function finishCodeEntered(self: Simulation, f: FighterState): boolean
	local code = f.finisherCode
	local n = #f.tokens
	if n < #code then
		return false
	end
	local first = f.tokens[n - #code + 1]
	if self.elapsed - first.time > FINISH_INPUT_WINDOW then
		return false
	end
	for k, key in code do
		if f.tokens[n - #code + k].key ~= key then
			return false
		end
	end
	return true
end

local function startFinishPhase(self: Simulation, winner: number, loser: number)
	self.finishPhase = true
	self.finishTimer = FINISH_TIME
	self.finishWinner = winner
	self.finishLoser = loser
	local w = self.fighters[winner]
	local l = self.fighters[loser]
	l.state = "Dazed"
	l.x = math.clamp(w.x + w.facing * 2.2, Arena.STAGE_LEFT + 1, Arena.STAGE_RIGHT - 1)
	l.y = 0
	l.vx, l.vy = 0, 0
	l.grounded = true
	l.facing = if w.x > l.x then 1 else -1
	l.intangible = FINISH_TIME + 1
	w.tokens = {}
	local def = Fighters.get(w.fighterId)
	emit(self, { type = "finish_him", actor = winner, target = loser, code = w.finisherCode, name = def.finisher.name })
end

local function endFinishPhase(self: Simulation, executed: boolean)
	self.finishPhase = false
	local w = self.fighters[self.finishWinner]
	local l = self.fighters[self.finishLoser]
	self.result = self.finishWinner
	l.state = "Defeated"
	w.state = "Ready"
	w.pending = nil
	if executed then
		w.finishers += 1
		local def = Fighters.get(w.fighterId)
		emit(self, {
			type = "finisher",
			actor = self.finishWinner,
			target = self.finishLoser,
			name = def.finisher.name,
			kind = def.finisher.kind,
		})
	end
	emit(self, { type = "finish", winner = self.result, finisher = executed })
end

local function armorHolds(t: FighterState, damage: number): boolean
	if t.armorTimer > 0 and damage < ARMOR_SELF_LIMIT then
		return true
	end
	local pending = t.pending
	if not pending or pending.stage == "recovery" then
		return false
	end
	return damage < ((pending :: Pending).ability.armor or 0)
end

-- Hitbox test: explicit move boxes (relative to the attacker's feet) against the target body (feet to +1.6 m).
local function touches(attacker: FighterState, target: FighterState, a: Ability): boolean
	local forward = (target.x - attacker.x) * attacker.facing
	if a.yMin and a.yMax then
		local xMin = a.xMin or -HITBOX_BACK_REACH
		if a.allAround then
			if math.abs(forward) > math.max(math.abs(xMin), a.range) then
				return false
			end
		elseif forward < xMin or forward > a.range then
			return false
		end
		local lo = attacker.y + a.yMin
		local hi = attacker.y + a.yMax
		return target.y <= hi and target.y + BODY_HEIGHT >= lo
	end
	if math.abs(target.y - attacker.y) > 1.5 then
		return false
	end
	if a.allAround then
		return math.abs(forward) <= a.range
	end
	return forward >= -HITBOX_BACK_REACH and forward <= a.range
end

local function respawnOrEliminate(self: Simulation, f: FighterState, index: number): boolean
	local koX, koY = f.x, f.y
	f.lives -= 1
	f.stocksLost += 1
	if f.grabTarget then
		local held = self.fighters[f.grabTarget]
		held.state = "Ready"
		held.grabbedBy = nil
		f.grabTarget = nil
	end
	if f.lives > 0 and not self.suddenDeath then
		f.percent = 0
		f.x = Arena.RESPAWN_X[(index - 1) % #Arena.RESPAWN_X + 1]
		f.y = Arena.RESPAWN_Y
		f.vx, f.vy = 0, 0
		f.grounded = false
		f.airJumps = f.phys.air_jumps
		f.airDashUsed = false
		f.invulnerable = Constants.RESPAWN_INVULNERABLE
		f.stun = 0
		f.pending = nil
		f.state = "Ready"
		Signature.reset(f)
		emit(self, { type = "ring_out", actor = index, lives = f.lives, x = koX, y = koY })
		emit(self, { type = "respawn", actor = index })
		return false
	end
	f.lives = 0
	f.percent = 0
	f.state = "Defeated"
	f.ledge = 0
	f.pending = nil
	Signature.reset(f)
	emit(self, { type = "ring_out", actor = index, lives = 0, x = koX, y = koY })
	emit(self, { type = "fighter_eliminated", actor = index })
	return true
end

local function lastHitter(self: Simulation, index: number): number?
	return (self :: any)._lastHitBy and (self :: any)._lastHitBy[index]
end

-- One fighter's movement and controls for this tick.
local function updateFighter(self: Simulation, i: number, f: FighterState, cmd: Command)
	local inp = readInput(f, cmd)
	if self.finishPhase and i == self.finishWinner then
		recordFinishTokens(self, f, inp)
		local loser = self.fighters[self.finishLoser]
		if finishCodeEntered(self, f) and math.abs(loser.x - f.x) <= FINISH_RANGE and math.abs(loser.y - f.y) < 3 then
			endFinishPhase(self, true)
			return
		end
		-- During the finisher window only movement and the code count.
		inp.standard, inp.special, inp.grab, inp.smash = false, false, false, false
	end

	if f.hitstop > 0 then
		f.hitstop -= 1
		return
	end
	f.specialHeld = inp.specialHeld
	if f.freezeTimer > 0 then
		-- Frozen in ice: no controls, and the hit stun lasts at least as long as the ice.
		f.freezeTimer = math.max(0, f.freezeTimer - STEP)
		f.walkV = 0
		inp.axis, inp.jump, inp.standard, inp.special, inp.grab, inp.smash = 0, false, false, false, false, false
		inp.shield, inp.shieldPressed, inp.sidePressed, inp.up, inp.down = false, false, 0, false, false
		cmd = Input.idle()
		if f.state == "HitStun" then
			f.stun = math.max(f.stun, f.freezeTimer)
		end
	end
	Signature.tick(self, i, f, STEP)

	-- Timers
	f.cooldownStandard = math.max(0, f.cooldownStandard - STEP)
	f.cooldownSpecial = math.max(0, f.cooldownSpecial - STEP)
	if f.stun > 0 then
		f.stun = math.max(0, f.stun - STEP)
		if f.stun <= 0 and (f.state == "HitStun" or f.state == "ShieldBreak") then
			f.state = "Ready"
		end
	end
	f.intangible = math.max(0, f.intangible - STEP)
	f.invulnerable = math.max(0, f.invulnerable - STEP)
	f.counter = math.max(0, f.counter - STEP)
	f.rageTimer = math.max(0, f.rageTimer - STEP)
	f.armorTimer = math.max(0, f.armorTimer - STEP)
	f.ledgeCooldown = math.max(0, f.ledgeCooldown - STEP)
	f.slide = math.max(0, f.slide - STEP)
	f.dropThrough = math.max(0, f.dropThrough - STEP)
	f.grabImmunity = math.max(0, f.grabImmunity - STEP)
	f.airControlLock = math.max(0, f.airControlLock - STEP)
	f.parryTimer = math.max(0, f.parryTimer - STEP)
	if f.comboTimer > 0 then
		f.comboTimer -= STEP
		if f.comboTimer <= 0 then
			if f.combo > 1 then
				emit(self, { type = "combo_end", actor = i, count = f.combo })
			end
			f.combo = 0
		end
	end
	f.super = math.min(Constants.MAX_SUPER, f.super + STEP * Constants.SUPER_GAIN.passivePerSecond)
	if f.blocking then
		f.shieldHp = math.max(0, f.shieldHp - MOVE.shield.drainPerSecond * STEP)
		if f.shieldHp <= 0 then
			shieldBreak(self, f)
		end
	else
		f.shieldHp = math.min(MOVE.shield.max * (f.phys.shield or 1), f.shieldHp + MOVE.shield.regenPerSecond * STEP)
	end
	if f.lockTimer > 0 then
		f.lockTimer = math.max(0, f.lockTimer - STEP)
		if f.lockTimer <= 0 and (f.state == "Throw" or (f.state == "Attack" and not f.pending)) then
			f.state = "Ready"
		end
	end

	if f.state == "Ledge" then
		updateLedge(self, f, inp)
		if f.state == "Ledge" then
			return
		end
	end

	if f.state == "Dodge" then
		f.dodgeTimer -= STEP
		if f.dodgeKind == "roll" then
			f.x += f.dodgeDir * MOVE.roll.speed * STEP
			if math.abs(f.y) < 0.01 then
				f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
			end
		end
		if f.dodgeTimer <= 0 then
			f.state = "Ready"
		end
	end

	if f.state == "Charge" then
		f.chargeTime += STEP
		if not inp.standardHeld or f.chargeTime >= MOVE.smash.maxCharge or not f.grounded then
			f.state = "Ready"
			if f.chargeTime < MOVE.smash.tapThreshold then
				startMove(self, f, f.chargeKey)
			else
				local ratio = math.min(f.chargeTime / MOVE.smash.maxCharge, 1)
				startMove(self, f, SMASH_OF[f.chargeKey] or "fsmash", 1 + 0.5 * ratio)
			end
		end
	end

	-- Facing: held direction decides on the ground; without input the fighter turns to the nearest opponent.
	if f.state == "Ready" then
		if f.grounded and math.abs(cmd.move) > 0.25 then
			f.facing = sign(cmd.move)
		elseif math.abs(cmd.move) <= 0.25 then
			local opp = self:nearestOpponent(i)
			if opp and math.abs(self.fighters[opp].x - f.x) > 0.05 then
				f.facing = if self.fighters[opp].x > f.x then 1 else -1
			end
		end
	end

	-- Launch velocity with friction
	local speedScale = (if f.rageTimer > 0 then 1.25 else 1) * Signature.speedScale(f)
	local friction = if f.grounded then (if f.slide > 0 then 8 else 26) else 6.5
	if math.abs(f.vx) > 0.05 then
		f.x += f.vx * STEP
		f.vx = moveToward(f.vx, 0, friction * STEP)
	end

	-- Grab execution and holding
	if f.state == "Grab" then
		f.grabTimer -= STEP
		if f.grabTimer <= 0 then
			local caught: number? = nil
			for ti, t in self.fighters do
				if
					ti ~= i
					and not self:isAlly(i, ti)
					and t.state ~= "Defeated"
					and t.invulnerable <= 0
					and t.grabImmunity <= 0
					and math.abs(t.x - f.x) <= 1.35
					and math.abs(t.y - f.y) <= 1.05
				then
					caught = ti
					break
				end
			end
			if caught then
				local t = self.fighters[caught]
				f.state = "Carrying"
				f.grabTarget = caught
				f.grabTimer = 1.3
				t.state = "Grabbed"
				t.grabbedBy = i
				t.stun = 1.3
				t.pending = nil
				t.vx, t.vy = 0, 0
				emit(self, { type = "grab_success", actor = i, target = caught })
			else
				f.state = "Ready"
				f.stun = 0.25
				emit(self, { type = "grab_miss", actor = i })
			end
		end
	elseif f.state == "Carrying" and f.grabTarget then
		local t = self.fighters[f.grabTarget]
		t.x = f.x + f.facing * 0.75
		t.y = f.y
		f.grabTimer -= STEP
		if f.grabTimer <= 0 then
			releaseGrab(self, f)
		elseif cmd.jump or cmd.special or cmd.up then
			executeThrow(self, f, "up")
		elseif cmd.down then
			executeThrow(self, f, "down")
		elseif math.abs(cmd.move) > 0.25 then
			executeThrow(self, f, if sign(cmd.move) == f.facing then "forward" else "back")
		elseif cmd.standard or cmd.grab then
			executeThrow(self, f, "forward")
		end
	end

	-- Controls
	if f.state == "Ready" and not f.pending then
		f.moving = false
		f.crouching = false
		local axis = inp.axis
		local wantDrop = (inp.shield and inp.jump) or inp.drop or (inp.downPressed and not inp.shield)
		if wantDrop and f.y > 0.2 and f.grounded then
			f.grounded = false
			f.y -= 0.14
			f.vy = -3.2
			f.dropThrough = 0.4
			f.blocking = false
			emit(self, { type = "drop_through", actor = i })
		elseif f.grounded and inp.shield and not inp.jump then
			if inp.sidePressed ~= 0 or (inp.shieldPressed and math.abs(axis) > 0.6) then
				startDodge(self, f, "roll", if inp.sidePressed ~= 0 then inp.sidePressed else sign(axis))
			elseif inp.downPressed or (inp.shieldPressed and inp.down) then
				startDodge(self, f, "spot", 0)
			elseif inp.grab then
				f.blocking = false
				initiateGrab(self, f)
			elseif f.shieldHp > 0 then
				f.blocking = true
				if inp.shieldPressed then
					f.parryTimer = PARRY_WINDOW
					f.parryUsed = false
				end
			end
		elseif not f.grounded and inp.shieldPressed and not f.airDodgeUsed then
			startDodge(self, f, "air", axis, (if inp.up then 1 else 0) - (if inp.down then 1 else 0))
		else
			f.blocking = false
			local upAttack = f.grounded and inp.up and (inp.standard or inp.special)
			if inp.jump and not upAttack then
				if f.grounded then
					f.vy = f.phys.jump
					f.y += 0.05
					f.grounded = false
					f.airJumps = f.phys.air_jumps
					f.airDashUsed = false
					f.hopFrames = 0
					f.walkV = 0
					emit(self, { type = "jump", actor = i })
				elseif f.airJumps > 0 and f.vy < 4.5 then
					f.airJumps -= 1
					f.vy = f.phys.jump * 0.95
					if f.x < Arena.STAGE_LEFT then
						f.vx = math.max(f.vx, 3.8)
					elseif f.x > Arena.STAGE_RIGHT then
						f.vx = math.min(f.vx, -3.8)
					end
					emit(self, { type = "double_jump", actor = i })
				end
			end

			if math.abs(axis) > 0.05 then
				if f.grounded then
					f.runTime += STEP
					local run = if f.runTime > MOVE.runAfter then f.phys.run else 1
					local target = axis * f.runSpeed * speedScale * run
					f.walkV = moveToward(f.walkV, target, MOVE.groundAccel * STEP)
					f.x += f.walkV * STEP
					f.moving = true
				elseif f.airControlLock <= 0 then
					f.x += axis * f.runSpeed * speedScale * f.phys.air * STEP
					f.moving = true
				end
				-- Walking stops at the stage edge; leaving it needs a jump or a launch.
				if f.grounded and math.abs(f.y) < 0.01 then
					f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
				end
			else
				f.runTime = 0
				f.crouching = f.grounded and inp.down
				if f.grounded and math.abs(f.walkV) > 0.01 then
					f.walkV = moveToward(f.walkV, 0, MOVE.groundDecel * STEP)
					f.x += f.walkV * STEP
					if math.abs(f.y) < 0.01 then
						f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
					end
				end
			end

			if inp.grab then
				initiateGrab(self, f)
			elseif inp.special and not f.grounded then
				-- Air special: up = steep recovery climb, down = dive, otherwise forward dash.
				local followed = not inp.up and not inp.down and startFollowup(self, f)
				if followed then
					f.blocking = false
				elseif inp.up and f.cooldownSpecial <= 0 and f.moves.uspecial then
					startMove(self, f, "uspecial")
				else
					airDash(self, f, axis, inp.down or inp.shield, inp.up)
				end
			elseif inp.special then
				if math.abs(axis) > 0.25 then
					f.facing = sign(axis)
				end
				if inp.up then
					startMove(self, f, "uspecial")
				elseif inp.down then
					startMove(self, f, "dspecial")
				elseif not startFollowup(self, f) then
					startMove(self, f, "nspecial")
				end
			elseif inp.standard or inp.smash then
				chooseStandard(self, f, inp)
			end
		end
	end

	-- Short hop: releasing jump within 5 frames cuts the rise.
	if not f.grounded and f.hopFrames then
		f.hopFrames += 1
		if not inp.jumpHeld and (f.hopFrames :: number) <= 5 and f.vy > 0 then
			f.vy *= 0.6
			f.hopFrames = nil
		elseif (f.hopFrames :: number) > 5 then
			f.hopFrames = nil
		end
	end
	-- Fast fall: tap down while falling.
	if not f.grounded and inp.downPressed and f.vy < 2 and f.state == "Ready" then
		f.vy = math.min(f.vy, -f.phys.fast_fall)
		emit(self, { type = "fast_fall", actor = i })
	end

	-- Vertical physics and landing (platforms are one-way from below).
	local prevY = f.y
	if not f.grounded and f.state ~= "Grabbed" then
		local lift = Signature.flight(f, inp.jump, inp.up or inp.jumpHeld, inp.down, STEP)
		f.vy -= f.phys.gravity * STEP * lift
		Signature.afterGravity(f, STEP)
		local nextY = f.y + f.vy * STEP
		local landed = false
		if f.vy <= 0 then
			if f.dropThrough <= 0 then
				for _, plat in self.platforms do
					if
						f.x >= plat.x1 - 0.2
						and f.x <= plat.x2 + 0.2
						and prevY >= plat.y - 0.15
						and nextY <= plat.y + 0.25
					then
						f.y = plat.y
						landed = true
						break
					end
				end
			end
			if
				not landed
				and f.x >= Arena.STAGE_LEFT - 0.25
				and f.x <= Arena.STAGE_RIGHT + 0.25
				and prevY >= -0.15
				and nextY <= 0.25
			then
				f.y = 0
				landed = true
			end
		end
		if landed then
			f.vy = 0
			f.grounded = true
			onLand(self, f)
			if Signature.onLand(self, i, f) then
				f.pending = nil
				f.state = "Attack"
				f.lockTimer = 0.3
			end
		else
			f.y = nextY
		end
	elseif f.grounded then
		local onGround = false
		local groundY = 0
		if f.dropThrough <= 0 then
			for _, plat in self.platforms do
				if f.x >= plat.x1 - 0.2 and f.x <= plat.x2 + 0.2 and math.abs(f.y - plat.y) < 0.35 then
					onGround, groundY = true, plat.y
					break
				end
			end
		end
		if
			not onGround
			and f.x >= Arena.STAGE_LEFT - 0.25
			and f.x <= Arena.STAGE_RIGHT + 0.25
			and math.abs(f.y) < 0.35
		then
			onGround, groundY = true, 0
		end
		if onGround then
			f.y = groundY
			f.vy = 0
		else
			f.grounded = false
		end
	end

	-- Nobody hangs inside the stage body.
	if f.y < -0.05 and f.y > -4.5 and f.x > Arena.STAGE_LEFT and f.x < Arena.STAGE_RIGHT then
		f.x = if f.x - Arena.STAGE_LEFT < Arena.STAGE_RIGHT - f.x
			then Arena.STAGE_LEFT - 0.01
			else Arena.STAGE_RIGHT + 0.01
		f.vx = 0
	end
	if
		not f.grounded
		and f.state == "Ready"
		and not f.pending
		and f.vy <= 0.5
		and f.ledgeCooldown <= 0
		and f.ledgeGrabs < MOVE.ledge.maxGrabsPerLife
	then
		tryLedgeGrab(self, f)
	end
end

-- Grounded fighters standing inside each other are eased apart.
local function resolveBodyPush(self: Simulation)
	local function canPush(f: FighterState): boolean
		return f.state ~= "Defeated"
			and f.state ~= "Grabbed"
			and f.state ~= "Dazed"
			and f.state ~= "Dodge"
			and f.grabTarget == nil
			and f.grounded
	end
	for i, a in self.fighters do
		if canPush(a) then
			for j = i + 1, #self.fighters do
				local b = self.fighters[j]
				if canPush(b) and math.abs(a.y - b.y) <= 0.5 then
					local dx = b.x - a.x
					local overlap = BODY_SEPARATION - math.abs(dx)
					if overlap > 0 then
						local dir = if math.abs(dx) > 0.0001 then sign(dx) else 1
						local shift = overlap * 0.5 * BODY_PUSH_RATE
						a.x -= dir * shift
						b.x += dir * shift
						for _, f in { a, b } do
							if math.abs(f.y) < 0.01 then
								f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
							end
						end
					end
				end
			end
		end
	end
end

type Contact = Projectiles.Contact

-- Hit test of a shadow clone's copied attack: the move box from the clone's position.
local function ghostTouches(x: number, y: number, facing: number, target: any, a: Ability): boolean
	return touches({ x = x, y = y, facing = facing } :: any, target, a)
end

-- Advances every running move (windup -> active -> recovery) and collects the hits of active frames.
local function advanceAttacks(self: Simulation): { Contact }
	local contacts: { Contact } = {}
	for i, f in self.fighters do
		local pending = f.pending
		if pending and f.hitstop <= 0 and f.state ~= "Defeated" then
			pending.remaining -= STEP
			local a = pending.ability
			Signature.holdCharge(f, pending, f.specialHeld, STEP)
			if pending.stage == "windup" and pending.remaining <= 0 then
				pending.stage = "active"
				pending.remaining = a.active
				Signature.onActiveStart(self, i, a)
				if a.blink then
					f.x += f.facing * a.blink
					if f.grounded and math.abs(f.y) < 0.01 then
						f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
					end
				end
				if a.intangible then
					f.intangible = math.max(f.intangible, a.intangible)
				end
				if a.armorSelf then
					f.armorTimer = math.max(f.armorTimer, a.armorSelf)
				end
				if a.rageSelf then
					f.rageTimer = math.max(f.rageTimer, a.rageSelf)
				end
				if a.counterTime then
					f.counter = a.counterTime
				end
				if a.superGain then
					f.super = math.min(Constants.MAX_SUPER, f.super + a.superGain)
				end
				if a.motionVx then
					f.vx = f.facing * a.motionVx
				end
				if a.motionVy then
					f.vy = a.motionVy
					f.grounded = false
				end
			end
			if pending.stage == "active" then
				Signature.whileActive(self, i, f, pending, contacts)
				if not a.noHit and not a.sig then
					Signature.echoStrike(self, i, a, ghostTouches, contacts)
				end
				if a.rehit then
					pending.rehitTimer += STEP
					if pending.rehitTimer >= a.rehit then
						pending.rehitTimer = 0
						pending.hitList = {}
					end
				end
				if not a.noHit then
					for ti, t in self.fighters do
						if
							ti ~= i
							and not self:isAlly(i, ti)
							and not pending.hitList[ti]
							and t.state ~= "Defeated"
							and t.state ~= "Dazed"
							and touches(f, t, a)
						then
							pending.hitList[ti] = true
							table.insert(contacts, { from = i, to = ti, ability = a, special = pending.special })
						end
					end
				end
				if pending.remaining <= 0 then
					pending.stage = "recovery"
					pending.remaining = a.recovery
				end
			end
			if pending.stage == "recovery" and pending.remaining <= 0 then
				f.pending = nil
				if f.state == "Attack" then
					f.state = "Ready"
				end
			end
		end
	end
	return contacts
end

-- Two attacks that hit each other in the same tick cancel out (clash).
local function resolveClashes(self: Simulation, contacts: { Contact }): { Contact }
	local clashed: { [number]: boolean } = {}
	for k, c in contacts do
		for m = k + 1, #contacts do
			local d = contacts[m]
			if c.from == d.to and c.to == d.from and not clashed[k] and not clashed[m] then
				clashed[k], clashed[m] = true, true
				local a, b = self.fighters[c.from], self.fighters[c.to]
				local dir = if b.x >= a.x then 1 else -1
				a.vx, b.vx = -dir * 3, dir * 3
				a.hitstop, b.hitstop = HITSTOP_FRAMES + 2, HITSTOP_FRAMES + 2
				a.pending, b.pending = nil, nil
				a.state, b.state = "Ready", "Ready"
				emit(
					self,
					{ type = "clash", actor = c.from, target = c.to, x = (a.x + b.x) / 2, y = (a.y + b.y) / 2 + 1 }
				)
			end
		end
	end
	local kept = {}
	for k, c in contacts do
		if not clashed[k] then
			table.insert(kept, c)
		end
	end
	return kept
end

local function resolveContacts(self: Simulation, contacts: { Contact })
	local lastHit = (self :: any)._lastHitBy
	local k = 0
	while k < #contacts do
		k += 1
		local contact = contacts[k]
		local attacker = self.fighters[contact.from]
		local target = self.fighters[contact.to]
		local a = contact.ability
		local isSpecial = contact.special
		local pushDir = contact.pushDir or attacker.facing
		if a.back then
			pushDir = -pushDir
		end
		if a.allAround and math.abs(target.x - attacker.x) > 0.01 then
			pushDir = sign(target.x - attacker.x)
		end

		if target.invulnerable > 0 or target.intangible > 0 then
			continue
		end
		if target.bulwark > 0 then
			-- Shield wall: hits from the front are stopped completely.
			local srcX = contact.srcX or attacker.x
			if math.abs(srcX - target.x) < 0.05 or sign(srcX - target.x) == target.facing then
				emit(self, { type = "bulwark_block", actor = contact.to, target = contact.from })
				if contact.srcX == nil then
					attacker.vx = sign(attacker.x - target.x) * 3.5
				end
				attacker.hitstop = 3
				continue
			end
		end
		if target.counter > 0 and not (contact :: any).isCounter then
			-- Counter stance: the attack is answered with a stronger strike.
			target.counter = 0
			local reply = table.clone(a)
			reply.name = "Konter"
			reply.damage = a.damage * 1.3 + 4
			local own = target.pending
			if own and own.ability.sig then
				reply.damage *= Projectiles.num(own.ability.sig :: any, "dmg", 1)
			end
			reply.push = a.push * 1.4 + 0.3
			reply.angle = 40
			reply.hitstun = 0.35
			reply.back = false
			reply.allAround = false
			emit(self, { type = "counter", actor = contact.to, target = contact.from })
			local counterContact: any = {
				from = contact.to,
				to = contact.from,
				ability = reply,
				special = true,
				pushDir = if math.abs(attacker.x - target.x) > 0.01 then sign(attacker.x - target.x) else target.facing,
				isCounter = true,
			}
			table.insert(contacts, counterContact)
			continue
		end

		local unblockable = a.unblockable == true
		local isParry = not unblockable
			and target.blocking
			and target.parryTimer > 0
			and not target.parryUsed
			and target.grounded
			and target.stun <= 0
		local isBlocked = not unblockable and not isParry and target.blocking and target.grounded and target.stun <= 0
		local comboMult = COMBO_MULT[math.min(attacker.combo, #COMBO_MULT - 1) + 1]
		local defense = Knockback.defenseMult(target.stats.defense)

		if isParry then
			target.parryUsed = true
			attacker.stun = 0.55
			attacker.state = "HitStun"
			attacker.pending = nil
			target.super = math.min(Constants.MAX_SUPER, target.super + Constants.SUPER_GAIN.counterHit)
			attacker.hitstop = HITSTOP_FRAMES * 2
			target.hitstop = HITSTOP_FRAMES
			emit(self, { type = "parry", actor = contact.to, target = contact.from })
		elseif isBlocked then
			target.shieldHp -= a.damage * MOVE.shield.blockDamageMult
			if target.shieldHp <= 0 then
				shieldBreak(self, target)
				attacker.hitstop = HITSTOP_FRAMES
				continue
			end
			local damage = a.damage * defense * 0.18
			target.percent = math.clamp(target.percent + damage, 0, Constants.MAX_PERCENT)
			target.vx = pushDir * a.push * 4
			target.stun = 0.08
			attacker.super = math.min(Constants.MAX_SUPER, attacker.super + 5)
			target.super = math.min(Constants.MAX_SUPER, target.super + 3)
			attacker.hitstop = HITSTOP_FRAMES
			target.hitstop = HITSTOP_FRAMES
			emit(self, { type = "block", actor = contact.from, target = contact.to, damage = damage })
		else
			local superHit = isSpecial and attacker.super >= Constants.MAX_SUPER
			if superHit then
				attacker.super = 0
				emit(self, { type = "super_used", actor = contact.from })
			end
			local rage = (if attacker.rageTimer > 0 then 1.35 else 1) * Signature.damageMult(attacker, target)
			local damage = a.damage
				* defense
				* comboMult
				* (if superHit then 1.7 else 1)
				* rage
				* Knockback.techniqueMult(attacker.stats.technique)
			target.percent = math.clamp(target.percent + damage, 0, Constants.MAX_PERCENT)
			attacker.hits += 1
			attacker.damageDealt += damage
			if lastHit then
				lastHit[contact.to] = contact.from
			end

			if armorHolds(target, damage) then
				-- Armor: damage counts, but the fighter keeps going.
				attacker.hitstop, target.hitstop = 3, 3
				attacker.combo += 1
				attacker.comboTimer = 2
				emit(self, {
					type = "hit",
					actor = contact.from,
					target = contact.to,
					damage = damage,
					special = isSpecial,
					armored = true,
					percent = target.percent,
				})
				continue
			end

			if target.state == "Grabbed" and target.grabbedBy then
				self.fighters[target.grabbedBy].grabTarget = nil
				target.grabbedBy = nil
			end

			local launch = Knockback.attack(
				damage,
				a.push,
				a.angle,
				a.freeAngle,
				a.hitstun,
				target.percent,
				target.weight,
				target.stats.vitality,
				pushDir,
				isSpecial,
				superHit,
				target.grounded,
				target.inX,
				target.inY
			)
			if a.kbScale then
				-- One punch: knockback grows with the target's percent; past the threshold it is a sure KO.
				local impulse = math.min(19, launch.impulse * (1 + target.percent / a.kbScale))
				if target.percent >= (a.koAt or 999) then
					impulse = 30
					emit(self, { type = "one_punch_ko", actor = contact.from, target = contact.to })
				end
				local scale = impulse / math.max(0.01, launch.impulse)
				launch.vx *= scale
				launch.vy *= scale
				launch.impulse = impulse
			end
			target.vx, target.vy = launch.vx, launch.vy
			target.grounded = false
			target.airDashUsed = false
			target.dropThrough = 0.12
			target.stun = launch.hitstun
			target.airControlLock = launch.airControlLock
			target.state = "HitStun"
			target.pending = nil
			target.blocking = false
			target.walkV = 0
			target.ledge = 0
			target.airDodgeUsed = false
			Signature.onHit(self, contact, damage)

			attacker.combo += 1
			attacker.bestCombo = math.max(attacker.bestCombo, attacker.combo)
			attacker.comboTimer = 2
			local gain = Constants.SUPER_GAIN
			attacker.super = math.min(
				Constants.MAX_SUPER,
				attacker.super + (if isSpecial then gain.specialAttacker else gain.standardAttacker)
			)
			target.super = math.min(
				Constants.MAX_SUPER,
				target.super + (if isSpecial then gain.specialTarget else gain.standardTarget)
			)
			local stop = math.round(math.clamp(damage * 0.4 + (if isSpecial then 4 else 2), 3, 10))
			attacker.hitstop, target.hitstop = stop, stop
			emit(self, {
				type = "hit",
				actor = contact.from,
				target = contact.to,
				damage = damage,
				special = isSpecial,
				superHit = superHit,
				impulse = launch.impulse,
				percent = target.percent,
				combo = attacker.combo,
			})
		end
	end
end

local function aliveTeams(self: Simulation): ({ number }, number)
	local alive, teams, count = {}, {}, 0
	for k, f in self.fighters do
		if f.state ~= "Defeated" and f.state ~= "Dazed" and f.lives > 0 then
			table.insert(alive, k)
			if not teams[f.team] then
				teams[f.team] = true
				count += 1
			end
		end
	end
	return alive, count
end

local function startSuddenDeath(self: Simulation, leaders: { number })
	self.suddenDeath = true
	local isLeader = {}
	for _, k in leaders do
		isLeader[k] = true
	end
	for k, f in self.fighters do
		if isLeader[k] then
			f.lives = 1
			f.percent = Constants.SUDDEN_DEATH_PERCENT
		elseif f.state ~= "Defeated" then
			f.state = "Defeated"
			f.lives = 0
		end
	end
	emit(self, { type = "sudden_death", fighters = leaders })
end

local function checkOutcome(self: Simulation, eliminatedNow: number?)
	if self.result ~= nil then
		return
	end
	local alive, teamCount = aliveTeams(self)
	if self.finishPhase then
		if self.finishTimer <= 0 then
			endFinishPhase(self, false)
		end
	elseif teamCount == 1 and #self.fighters > 1 and self.finishersEnabled and #alive == 1 and eliminatedNow then
		startFinishPhase(self, alive[1], eliminatedNow)
	elseif teamCount == 1 and #self.fighters > 1 then
		self.result = alive[1]
		emit(self, { type = "finish", winner = alive[1], finisher = false })
	elseif #alive == 0 then
		self.result = -1
		emit(self, { type = "finish", winner = -1, finisher = false })
	elseif self.timeLeft <= 0 and not self.suddenDeath then
		-- Time up: most stocks wins; a tie goes to Sudden Death at 150 %.
		local best = -1
		for _, k in alive do
			best = math.max(best, self.fighters[k].lives)
		end
		local leaders, leaderTeams, teams = {}, {}, 0
		for _, k in alive do
			local f = self.fighters[k]
			if f.lives == best then
				table.insert(leaders, k)
				if not leaderTeams[f.team] then
					leaderTeams[f.team] = true
					teams += 1
				end
			end
		end
		if teams > 1 then
			startSuddenDeath(self, leaders)
		else
			self.result = leaders[1]
			emit(self, { type = "finish", winner = leaders[1], finisher = false })
		end
	end
end

function Sim.tick(self: Simulation, commands: { Command })
	table.clear(self.events)
	if self.result ~= nil then
		return
	end
	self.frame += 1
	if self.countdown > 0 then
		self.countdown = math.max(0, self.countdown - STEP)
		if self.countdown <= 0 then
			emit(self, { type = "go" })
		end
		return
	end
	self.elapsed += STEP
	if not self.finishPhase and not self.suddenDeath then
		self.timeLeft = math.max(0, self.timeLeft - STEP)
	end
	if self.finishPhase then
		self.finishTimer -= STEP
	end
	if not (self :: any)._lastHitBy then
		(self :: any)._lastHitBy = {}
	end

	local eliminatedNow: number? = nil
	for i, f in self.fighters do
		if f.state ~= "Defeated" and f.state ~= "Dazed" then
			updateFighter(self, i, f, commands[i] or Input.idle())
			if self.result ~= nil then
				return -- finisher executed
			end
			if Arena.isOutOfBounds(f.x, f.y) and f.state ~= "Defeated" then
				local by = lastHitter(self, i)
				if by and by ~= i then
					self.fighters[by].kos += 1
				end
				if respawnOrEliminate(self, f, i) then
					eliminatedNow = i
				end
			end
		end
	end

	resolveBodyPush(self)
	local contacts = self.queued
	self.queued = {}
	for _, c in advanceAttacks(self) do
		table.insert(contacts, c)
	end
	Projectiles.update(self, STEP, contacts)
	Signature.stateContacts(self, contacts)
	contacts = resolveClashes(self, contacts)
	resolveContacts(self, contacts)
	checkOutcome(self, eliminatedNow)
end

-- Compact per-fighter state for the network and the renderer.
export type FighterSnapshot = {
	x: number,
	y: number,
	vx: number,
	vy: number,
	facing: number,
	state: string,
	move: string?,
	moveStage: string?,
	percent: number,
	lives: number,
	super: number,
	shield: number,
	blocking: boolean,
	invulnerable: boolean,
	grounded: boolean,
	combo: number,
	status: number, -- bit flags, see Sim.STATUS
}

-- Status flags for the renderer (ice, mark, eagle ...).
Sim.STATUS = {
	frozen = 1,
	marked = 2,
	eagle = 4,
	turbo = 8,
	rage = 16,
	armor = 32,
	bulwark = 64,
	hexed = 128,
	heatFull = 256,
	charging = 512,
	leashed = 1024,
}

local function statusOf(f: FighterState): number
	local S = Sim.STATUS
	local bits = 0
	local function set(on: boolean, bit: number)
		if on then
			bits += bit
		end
	end
	set(f.freezeTimer > 0, S.frozen)
	set(f.markTimer > 0, S.marked)
	set(f.eagle > 0, S.eagle)
	set(f.turbo > 0, S.turbo)
	set(f.rageTimer > 0, S.rage)
	set(f.armorTimer > 0, S.armor)
	set(f.bulwark > 0, S.bulwark)
	set(f.hexT > 0, S.hexed)
	set(f.heat >= Signature.HEAT_MAX, S.heatFull)
	set(f.pending ~= nil and (f.pending :: Pending).ability.charge == true and f.specialHeld, S.charging)
	set(f.leashT > 0, S.leashed)
	return bits
end

function Sim.snapshot(self: Simulation): { FighterSnapshot }
	local out = {}
	for _, f in self.fighters do
		local pending = f.pending
		table.insert(out, {
			x = f.x,
			y = f.y,
			vx = f.vx,
			vy = f.vy,
			facing = f.facing,
			state = f.state,
			move = if pending then (if pending.ability.sig then pending.ability.sig.mech else pending.key) else nil,
			moveStage = if pending then pending.stage else nil,
			percent = f.percent,
			lives = f.lives,
			super = f.super,
			shield = f.shieldHp,
			blocking = f.blocking,
			invulnerable = f.invulnerable > 0,
			grounded = f.grounded,
			combo = f.combo,
			status = statusOf(f),
		})
	end
	return out
end

return Sim
