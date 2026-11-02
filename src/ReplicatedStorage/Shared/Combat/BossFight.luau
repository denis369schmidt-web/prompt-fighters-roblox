--!strict
-- Boss-Raid: 1-4 heroes (players and bot helpers, all on team 1) against one giant boss, on top of a Simulation.
-- Deterministic, instance-free, tested under Lune; Combat/MatchRunner runs it when a match has a boss.
--
-- How it sits on the Simulation:
--   * The boss is represented in the Simulation by a stand-in fighter (team 2) with a big hurtbox (hurtW/hurtH).
--     Every hero attack, projectile and signature hits it through the normal combat code, and bots target it like
--     any opponent. After each tick the stand-in's percent is turned into boss HP and the stand-in is reset
--     (no knockback, no stun, no grabs): bosses are not launchable, they have an HP bar.
--   * The boss itself (movement, attack patterns from Data/Bosses, telegraphs, its projectiles) runs here.
--     Heroes have hit points in the raid (Fighters.health, 110-138); boss hits take HP and knock back a little.
--     A hero at 0 HP or out of the blast zone uses one life of the shared team pool and comes back after a short
--     timer; with the pool empty they are out. All heroes out, or the time limit, loses the raid.
--   * Phase 2 at 50 % HP: a transformation (the stone shell shatters, invulnerable for a moment, shockwave), then
--     the second pattern list. After ENRAGE_SECONDS the boss enrages (more damage, shorter gaps).
-- The Simulation runs with manualOutcome: this module sets sim.result (MVP hero on victory, -1 on defeat).
--
-- Every attack is telegraphed: a pattern's wind-up creates its zones (ground strips, circles, columns, beam lines,
-- wave fronts) that the client draws as warning decals; they go "live" when the wind-up ends.

local Arena = require(script.Parent.Arena)
local Input = require(script.Parent.Input)
local Items = require(script.Parent.Items)
local Simulation = require(script.Parent.Simulation)
local Bosses = require(script.Parent.Parent.Data.Bosses)
local Constants = require(script.Parent.Parent.Data.Constants)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local Rng = require(script.Parent.Parent.Util.Rng)

type Simulation = Simulation.Simulation
type Command = Input.Command

local STEP = 1 / Constants.TICK_RATE
local RAID = Bosses.RAID
local STAND_IN = "golem" -- fighter id of the boss stand-in (never drawn)
local STAND_IN_LIVES = 99
local HERO_BODY = 1.6
local SHOT_CAP = 40

export type Zone = {
	id: number,
	kind: string, -- rect | circle | column | beam | wave | aim | wind
	x1: number,
	x2: number,
	y1: number,
	y2: number,
	warn: number, -- seconds of warning left (0 = live)
	warnTotal: number,
	live: number, -- seconds live left
	dmg: number,
	push: number,
	source: string, -- pattern type (mercy and push)
	rehit: number?, -- seconds between hits while live (else once per hero)
	hit: { [number]: number },
	vx: number?, -- moving zones (waves)
	cx: number?, -- push origin
	follow: boolean?, -- charge: the zone is the boss body
	armed: boolean, -- waiting for its pattern to go live
}

export type Shot = {
	id: number,
	x: number,
	y: number,
	vx: number,
	vy: number,
	life: number,
	size: number,
	dmg: number,
	gravity: number,
	homing: number,
	freeze: number,
	explode: number,
	delay: number,
}

export type Hero = {
	index: number,
	hp: number,
	maxHp: number,
	down: number, -- respawn timer while down (0 = up)
	out: boolean,
	mercy: { [string]: number },
	evade: { [number]: boolean },
	damage: number,
	downs: number,
}

export type Fight = {
	sim: Simulation,
	bossId: string,
	def: { [string]: any },
	index: number, -- the stand-in fighter
	heroes: { Hero },
	hp: number,
	maxHp: number,
	phase: number,
	x: number,
	y: number,
	baseY: number,
	facing: number,
	width: number,
	height: number,
	speed: number,
	state: string, -- idle | windup | active | recover | transform | defeated | victory
	stateT: number,
	stateLen: number,
	pattern: string,
	patternType: string,
	lastPattern: string,
	target: number,
	lives: number,
	enraged: boolean,
	elapsed: number,
	rng: Rng.Rng,
	zones: { Zone },
	shots: { Shot },
	serial: number,
	emitLeft: number,
	emitT: number,
	aimX: number,
	moveTo: number?,
	moveSpeed: number,
	contact: { [number]: number },
	result: string?, -- "victory" | "defeat"
	reason: string?,
	patternsFired: { [string]: number },
	phaseReached: number,
	pending: { { [string]: any } },
}

local BossFight = {}
BossFight.__index = BossFight
BossFight.STAND_IN = STAND_IN

local function num(t: { [string]: any }, key: string, default: number): number
	local v = t[key]
	return if type(v) == "number" then v else default
end

local function sign(v: number): number
	return if v > 0 then 1 elseif v < 0 then -1 else 0
end

local function emit(self: Fight, event: { [string]: any })
	table.insert(self.pending, event)
end

local function stageClamp(self: Fight, x: number): number
	local limit = Arena.STAGE_RIGHT - self.width * 0.5 - 0.4
	return math.clamp(x, -limit, limit)
end

-- Hit points of a hero in the raid (SPEC 5.2: 110-138 by vitality).
function BossFight.heroHp(fighterId: string): number
	local def = Fighters.get(fighterId)
	return math.clamp(math.floor(def.health + 0.5), 100, 150)
end

export type Options = {
	heroes: number?, -- fighters 1..heroes are heroes (default: all fighters in the sim)
	lives: number?, -- shared lives pool (default floor(heroes * LIVES_PER_HERO))
	seed: number?,
	hpScale: number?, -- extra multiplier on boss HP (tests, difficulty)
}

function BossFight.new(sim: Simulation, bossId: string, options: Options?): Fight
	local opts: Options = options or {}
	local def = Bosses.byId[bossId]
	assert(def, `unknown boss {bossId}`)
	local heroCount = opts.heroes or #sim.fighters
	local width, height, hover = Bosses.raidBody(bossId)
	local maxHp = math.floor(Bosses.scaledHp(bossId, heroCount) * RAID.HP_MULT * (opts.hpScale or 1) + 0.5)
	local index = sim:addFighter(STAND_IN, 2, STAND_IN_LIVES, true)
	local self = setmetatable({
		sim = sim,
		bossId = bossId,
		def = def,
		index = index,
		heroes = {},
		hp = maxHp,
		maxHp = maxHp,
		phase = 1,
		x = 0,
		y = hover,
		baseY = hover,
		facing = -1,
		width = width,
		height = height,
		speed = num(def, "speed", 2.2),
		state = "idle",
		stateT = 0,
		stateLen = 1.6,
		pattern = "",
		patternType = "",
		lastPattern = "",
		target = 1,
		lives = opts.lives or math.floor(heroCount * RAID.LIVES_PER_HERO),
		enraged = false,
		elapsed = 0,
		rng = Rng.new((opts.seed or 1) * 31 + 977),
		zones = {},
		shots = {},
		serial = 0,
		emitLeft = 0,
		emitT = 0,
		aimX = 0,
		moveTo = nil,
		moveSpeed = 0,
		contact = {},
		result = nil,
		reason = nil,
		patternsFired = {},
		phaseReached = 1,
		pending = {},
	}, BossFight)
	for i = 1, heroCount do
		local f = sim.fighters[i]
		f.team = 1
		local hp = BossFight.heroHp(f.fighterId)
		table.insert(self.heroes, {
			index = i,
			hp = hp,
			maxHp = hp,
			down = 0,
			out = false,
			mercy = {},
			evade = {},
			damage = 0,
			downs = 0,
		})
	end
	local standIn = sim.fighters[index]
	standIn.hurtW = width
	standIn.hurtH = height + hover
	standIn.x = 0
	standIn.facing = -1
	return (self :: any) :: Fight
end

function BossFight.heroOf(self: Fight, index: number): Hero?
	for _, h in self.heroes do
		if h.index == index then
			return h
		end
	end
	return nil
end

local function heroUp(self: Fight, h: Hero): boolean
	local f = self.sim.fighters[h.index]
	return not h.out and h.down <= 0 and f.state ~= "Defeated"
end

-- Keeps the stand-in where the boss is and undoes everything the combat code did to it.
local function placeStandIn(self: Fight)
	local f = self.sim.fighters[self.index]
	local dead = self.state == "defeated" or self.state == "victory"
	f.x = self.x
	f.y = if self.y > 1.5 then self.y else 0
	f.hurtH = self.height + (self.y - f.y)
	f.vx, f.vy, f.walkV = 0, 0, 0
	f.grounded = f.y <= 0
	f.facing = self.facing
	f.state = if dead then "Defeated" else "Ready"
	f.stun, f.hitstop, f.airControlLock = 0, 0, 0
	f.pending = nil
	f.blocking = false
	f.lives = if dead then 0 else STAND_IN_LIVES
	f.invulnerable = if self.state == "transform" then 1 else 0
	f.intangible = 0
	f.grabImmunity = 99
	f.grabbedBy = nil
	f.freezeTimer, f.markTimer, f.leashT, f.hexT = 0, 0, 0, 0
	f.ledge = 0
end

-- Before each Simulation tick: stand-in in place, hero stocks show the shared pool.
function BossFight.beforeTick(self: Fight)
	placeStandIn(self)
	for _, h in self.heroes do
		local f = self.sim.fighters[h.index]
		if not h.out and h.down <= 0 and f.state ~= "Defeated" then
			f.lives = self.lives + 1
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Heroes: damage, downs, respawns
--------------------------------------------------------------------------------------------------------------------

local function damageMult(self: Fight): number
	return (if self.phase >= 2 then RAID.PHASE_TWO_DAMAGE else 1) * (if self.enraged then RAID.ENRAGE_DAMAGE else 1)
end

local function takeDown(self: Fight, h: Hero, reason: string)
	local f = self.sim.fighters[h.index]
	h.downs += 1
	f.stocksLost += 1
	if self.lives > 0 then
		self.lives -= 1
		h.down = RAID.RESPAWN_SECONDS
	else
		h.out = true
	end
	f.state = "Defeated"
	f.pending = nil
	f.vx, f.vy = 0, 0
	f.lives = if h.out then 0 else self.lives + 1
	Items.release(self.sim, h.index)
	emit(self, {
		type = "hero_down",
		actor = h.index,
		lives = self.lives,
		out = h.out,
		reason = reason,
		x = f.x,
		y = f.y,
	})
end

local function respawn(self: Fight, h: Hero)
	local f = self.sim.fighters[h.index]
	local k = (h.index - 1) % #Arena.RESPAWN_X + 1
	f.x = Arena.RESPAWN_X[k]
	f.y = Arena.RESPAWN_Y
	f.vx, f.vy, f.walkV = 0, 0, 0
	f.grounded = false
	f.state = "Ready"
	f.stun = 0
	f.pending = nil
	f.percent = 0
	f.airJumps = f.phys.air_jumps
	f.airDashUsed = false
	f.invulnerable = RAID.RESPAWN_INVULNERABLE
	f.lives = self.lives + 1
	h.hp = h.maxHp
	h.down = 0
	table.clear(h.mercy)
	emit(self, { type = "respawn", actor = h.index })
end

-- One boss hit on a hero: HP damage, a little knockback (none through a shield), a short mercy window.
local function hurt(self: Fight, h: Hero, base: number, source: string, fromX: number, push: number?, freeze: number?)
	if not heroUp(self, h) then
		return
	end
	local f = self.sim.fighters[h.index]
	if f.invulnerable > 0 or f.intangible > 0 or (h.mercy[source] or 0) > 0 then
		return
	end
	h.mercy[source] = RAID.HIT_MERCY
	local damage = base * damageMult(self)
	local blocked = f.blocking and f.grounded and f.stun <= 0
	local dir = if math.abs(f.x - fromX) > 0.05 then sign(f.x - fromX) else -self.facing
	if blocked then
		damage *= RAID.BLOCK_DAMAGE
		f.shieldHp = math.max(1, f.shieldHp - damage * 1.5)
		f.vx = dir * 2.5
	else
		local speed = push or RAID.PUSH[source] or 4
		if speed > 0 then
			f.vx = dir * speed
			f.vy = math.max(f.vy, speed * 0.55 + 2)
			f.grounded = false
			f.state = "HitStun"
			f.stun = math.clamp(speed * 0.04, 0.12, 0.45)
			f.airControlLock = f.stun * 0.5
			f.pending = nil
			f.blocking = false
			f.ledge = 0
			Items.dropCarried(self.sim, h.index)
		end
		f.hitstop = 3
		if freeze and freeze > 0 then
			f.freezeTimer = math.max(f.freezeTimer, freeze)
		end
	end
	h.hp = math.max(0, h.hp - damage)
	emit(self, {
		type = "hero_hit",
		target = h.index,
		damage = math.floor(damage * 10 + 0.5) / 10,
		hp = math.floor(h.hp + 0.5),
		source = source,
		blocked = blocked,
	})
	if h.hp <= 0 then
		takeDown(self, h, "hp")
	end
end

local function heroIn(self: Fight, h: Hero, x1: number, x2: number, y1: number, y2: number): boolean
	local f = self.sim.fighters[h.index]
	return f.x + 0.3 >= x1 and f.x - 0.3 <= x2 and f.y + HERO_BODY >= y1 and f.y <= y2
end

--------------------------------------------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------------------------------------------

local function newZone(self: Fight, kind: string, x1: number, x2: number, y1: number, y2: number, warn: number): Zone
	self.serial += 1
	local z: Zone = {
		id = self.serial,
		kind = kind,
		x1 = math.min(x1, x2),
		x2 = math.max(x1, x2),
		y1 = y1,
		y2 = y2,
		warn = warn,
		warnTotal = math.max(warn, 0.01),
		live = 0,
		dmg = 0,
		push = 0,
		source = self.patternType,
		hit = {},
		armed = true,
	}
	table.insert(self.zones, z)
	return z
end

local function centerY(self: Fight): number
	return self.y + self.height * 0.5
end

local function upHeroes(self: Fight): { Hero }
	local out = {}
	for _, h in self.heroes do
		if heroUp(self, h) then
			table.insert(out, h)
		end
	end
	return out
end

-- Picks whom the next pattern aims at: mostly the closest hero, sometimes a random one.
local function pickTarget(self: Fight)
	local up = upHeroes(self)
	if #up == 0 then
		return
	end
	if self.rng:next() < 0.35 then
		self.target = up[self.rng:int(1, #up)].index
		return
	end
	local best, bestD = up[1].index, math.huge
	for _, h in up do
		local d = math.abs(self.sim.fighters[h.index].x - self.x)
		if d < bestD then
			best, bestD = h.index, d
		end
	end
	self.target = best
end

local function targetX(self: Fight): number
	local f = self.sim.fighters[self.target]
	return if f then f.x else 0
end

local function tempo(self: Fight): number
	return (if self.phase >= 2 then 0.85 else 1) * (if self.enraged then RAID.ENRAGE_TEMPO else 1)
end

local function patternList(self: Fight): { string }
	local lists = self.def.patterns
	return lists[math.min(self.phase, #lists)]
end

local function spawnShot(self: Fight, x: number, y: number, vx: number, vy: number, p: { [string]: any }, dmg: number)
	if #self.shots >= SHOT_CAP then
		return
	end
	local sim: any = self.sim
	sim.projectileSerial += 1
	local shot: Shot = {
		id = sim.projectileSerial,
		x = x,
		y = y,
		vx = vx,
		vy = vy,
		life = num(p, "life", 1.6),
		size = num(p, "size", 0.35) * 1.25,
		dmg = dmg,
		gravity = num(p, "gravity", 0),
		homing = num(p, "homing", 0),
		freeze = num(p, "freeze", 0),
		explode = num(p, "explode", 0),
		delay = 0,
	}
	table.insert(self.shots, shot)
	emit(self, {
		type = "projectile",
		actor = self.index,
		id = shot.id,
		shape = tostring(p.shape or "orb"),
		style = "shot",
		size = shot.size,
		color = p.color or self.def.color,
		boss = true,
	})
end

-- The wind-up: telegraph zones for the chosen pattern.
local function beginPattern(self: Fight)
	local list = patternList(self)
	local name = list[self.rng:int(1, #list)]
	if name == self.lastPattern and #list > 1 then
		name = list[(table.find(list, name) :: number) % #list + 1]
	end
	local p = Bosses.patterns[name]
	self.pattern = name
	self.patternType = p.type
	self.lastPattern = name
	pickTarget(self)
	local tx = targetX(self)
	self.facing = if tx >= self.x then 1 else -1
	self.aimX = tx
	local windup = (if p.type == "sweep" then num(p, "windup", RAID.WINDUP.sweep) else RAID.WINDUP[p.type] or 0.9)
		* tempo(self)
	self.state = "windup"
	self.stateT = windup
	self.stateLen = windup
	self.moveTo = nil
	local base = num(self.def, "dmg", 12)
	local function zone(kind: string, x1: number, x2: number, y1: number, y2: number): Zone
		local z = newZone(self, kind, x1, x2, y1, y2, windup)
		z.dmg = base * num(p, "dmg", 1)
		z.push = RAID.PUSH[p.type] or 5
		z.cx = self.x
		return z
	end
	local t = p.type
	if t == "emit" then
		local mode = p.emit
		if mode == "rain" then
			local half = 3.2 + num(p, "count", 10) * 0.05
			zone("rect", tx - half, tx + half, 0, 12).live = 0 -- warning only; the drops do the damage
			self.aimX = tx
		elseif mode == "aimed" then
			zone("aim", self.x, tx, centerY(self), self.sim.fighters[self.target].y + 0.9).live = 0
		elseif mode == "radial" then
			zone("circle", self.x - 4.5, self.x + 4.5, centerY(self) - 4.5, centerY(self) + 4.5).live = 0
		else
			zone("circle", self.x - 3, self.x + 3, centerY(self) - 3, centerY(self) + 3).live = 0
		end
	elseif t == "beam" then
		-- A low laser across the floor toward the target: jump or stand on a ledge.
		local fromX = self.x + self.facing * self.width * 0.5
		local toX = if self.facing > 0 then Arena.BLAST_RIGHT else Arena.BLAST_LEFT
		local z = zone("beam", fromX, toX, 0, 1.25)
		z.rehit = 0.3
	elseif t == "charge" then
		local ground = p.ground == true
		local dir = self.facing
		local endX = stageClamp(self, dir * 9)
		local y1 = if ground then 0 else self.y
		local z = zone("rect", self.x, endX, y1, y1 + (if ground then 1.8 else self.height * 0.7))
		z.follow = true
		self.moveTo = endX
		self.moveSpeed = num(p, "speed", 10)
	elseif t == "gale" then
		local dir = self.facing
		local z = zone("wind", self.x, if dir > 0 then Arena.STAGE_RIGHT + 2 else Arena.STAGE_LEFT - 2, 0, 6)
		z.dmg = 0
	elseif t == "ring" then
		zone("circle", self.x - 2.5, self.x + 2.5, 0, 1).dmg = 0
	elseif t == "dive" then
		local r = num(p, "radius", 4.5) * 0.75
		local z = zone("circle", tx - r, tx + r, 0, 2.4)
		z.cx = tx
		self.aimX = tx
	elseif t == "nova" then
		local r = num(p, "radius", 4.8)
		local cy = centerY(self)
		local z = zone("circle", self.x - r, self.x + r, cy - r, cy + r)
		z.cx = self.x
	elseif t == "pillars" then
		local count = if self.phase >= 2 then 5 else 4
		local spots: { number } = {}
		for _, h in upHeroes(self) do
			if #spots < count - 1 then
				table.insert(spots, self.sim.fighters[h.index].x)
			end
		end
		local guard = 0
		while #spots < count and guard < 40 do
			guard += 1
			local x = self.rng:range(Arena.STAGE_LEFT + 0.8, Arena.STAGE_RIGHT - 0.8)
			local ok = true
			for _, s in spots do
				if math.abs(s - x) < 2.4 then
					ok = false
				end
			end
			if ok then
				table.insert(spots, x)
			end
		end
		for _, x in spots do
			local z = zone("column", x - 0.8, x + 0.8, 0, 8)
			z.cx = x
		end
	elseif t == "slow" then
		local r = num(p, "radius", 7)
		local z = zone("circle", self.x - r, self.x + r, -1, 6)
		z.rehit = 0.5
		z.push = 0
	elseif t == "sweep" then
		local s = RAID.SCALE
		local near = self.x + self.facing * self.width * 0.3
		local far = self.x + self.facing * (self.width * 0.5 + num(p, "len", 5) * 0.85)
		zone("rect", near, far, self.y + num(p, "lo", -0.3) * s, self.y + num(p, "hi", 1.5) * s)
	end
	self.patternsFired[name] = (self.patternsFired[name] or 0) + 1
	emit(self, {
		type = "boss_windup",
		pattern = name,
		kind = t,
		time = windup,
		target = self.target,
	})
end

-- Wind-up over: the zones go live, emitters start, the boss moves.
local function activate(self: Fight)
	local p = Bosses.patterns[self.pattern]
	local t = p.type
	local live = 0.3
	if t == "emit" then
		self.emitLeft = num(p, "count", 8)
		self.emitT = 0
		live = self.emitLeft * num(p, "interval", 0.1) + 0.3
	elseif t == "beam" then
		live = 0.65
	elseif t == "charge" then
		live = 2.5
	elseif t == "gale" then
		live = num(p, "time", 1.6)
		self.emitLeft = num(p, "shots", 5)
		self.emitT = 0
	elseif t == "ring" then
		live = 2.2
		-- Two ground waves rolling outward from the boss's feet.
		for _, dir in { -1, 1 } do
			local z = newZone(self, "wave", self.x - 0.35, self.x + 0.35, 0, 0.9, 0)
			z.armed = false
			z.live = live
			z.dmg = num(self.def, "dmg", 12) * num(p, "dmg", 1)
			z.push = RAID.PUSH.ring
			z.vx = dir * num(p, "speed", 8)
			z.source = "ring"
			z.cx = self.x
		end
	elseif t == "dive" then
		live = 0.4
		self.x = stageClamp(self, self.aimX)
		self.y = self.baseY
		emit(self, { type = "boss_slam", x = self.x, radius = num(p, "radius", 4.5) * 0.75 })
	elseif t == "nova" then
		live = 0.3
		emit(self, { type = "boss_slam", x = self.x, radius = num(p, "radius", 4.8) })
	elseif t == "pillars" then
		live = 0.75
	elseif t == "slow" then
		live = num(p, "time", 2.6)
	elseif t == "sweep" then
		live = 0.28
	end
	for _, z in self.zones do
		if z.armed then
			z.armed = false
			z.warn = 0
			z.live = live
			if z.kind == "rect" and t == "emit" then
				z.dmg = 0 -- the rain strip stays visible while the drops (which do the damage) fall
			elseif z.kind == "aim" or (z.kind == "circle" and (t == "emit" or t == "ring")) then
				z.live = 0 -- telegraph-only zones end with the wind-up
			end
		end
	end
	self.state = "active"
	self.stateT = live
	self.stateLen = live
	emit(self, { type = "boss_attack", pattern = self.pattern, kind = t })
end

local function emitStep(self: Fight, dt: number)
	if self.emitLeft <= 0 then
		return
	end
	local p = Bosses.patterns[self.pattern]
	self.emitT -= dt
	if self.emitT > 0 then
		return
	end
	local base = num(self.def, "dmg", 12) * num(p, "dmg", 0.4)
	if p.type == "gale" then
		self.emitT = num(p, "time", 1.6) / math.max(1, num(p, "shots", 5))
		self.emitLeft -= 1
		local y = self.rng:range(0.4, 3.2)
		spawnShot(self, self.x + self.facing * self.width * 0.5, y, self.facing * 9, 0, p, base * 0.6)
		return
	end
	self.emitT = num(p, "interval", 0.1)
	self.emitLeft -= 1
	local mode = p.emit
	local cy = centerY(self) + self.height * 0.2
	local speed = num(p, "speed", 12)
	if mode == "aimed" then
		local f = self.sim.fighters[self.target]
		local tx, ty = f.x, f.y + 0.9
		local dx, dy = tx - self.x, ty - cy
		local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
		local spread = self.rng:range(-0.12, 0.12)
		local vx, vy = dx / len * speed, dy / len * speed
		vx, vy = vx - vy * spread, vy + vx * spread
		spawnShot(self, self.x + sign(dx) * self.width * 0.3, cy, vx, vy, p, base)
	elseif mode == "rain" then
		local half = 3.2 + num(p, "count", 10) * 0.05
		local x = self.aimX + self.rng:range(-half, half)
		spawnShot(self, x, 11.5, 0, -6, p, base)
		local drop = self.shots[#self.shots]
		if drop then
			drop.life = math.max(drop.life, 3) -- light drops (low gravity) still reach the floor
		end
	elseif mode == "radial" then
		local n = 7
		local offset = self.rng:range(0, 0.4)
		for k = 0, n - 1 do
			local a = math.rad(-15) + (k + offset) / (n - 1) * math.rad(210)
			spawnShot(self, self.x, cy, math.cos(a) * speed, math.sin(a) * speed, p, base)
		end
	else -- swarm
		local a = self.rng:range(0, math.pi * 2)
		spawnShot(
			self,
			self.x + math.cos(a) * self.width * 0.6,
			cy + math.sin(a) * 1.2,
			math.cos(a) * speed * 0.5,
			math.sin(a) * speed * 0.5,
			p,
			base
		)
	end
end

local function updateShots(self: Fight, dt: number)
	local keep = {}
	local up = upHeroes(self)
	for _, s in self.shots do
		s.life -= dt
		if s.homing > 0 then
			local best, bestD = nil, math.huge
			for _, h in up do
				local f = self.sim.fighters[h.index]
				local d = math.abs(f.x - s.x) + math.abs(f.y + 0.9 - s.y)
				if d < bestD then
					best, bestD = f, d
				end
			end
			if best then
				local dx, dy = best.x - s.x, best.y + 0.9 - s.y
				local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
				local speed = math.max(4, math.sqrt(s.vx * s.vx + s.vy * s.vy))
				s.vx += (dx / len * speed - s.vx) * math.min(1, s.homing * dt * 0.5)
				s.vy += (dy / len * speed - s.vy) * math.min(1, s.homing * dt * 0.5)
			end
		end
		s.vy -= s.gravity * dt
		s.x += s.vx * dt
		s.y += s.vy * dt
		local gone = s.life <= 0 or s.y < -0.2 or math.abs(s.x) > Arena.BLAST_RIGHT + 1
		if not gone then
			for _, h in up do
				local f = self.sim.fighters[h.index]
				if math.abs(f.x - s.x) <= s.size + 0.35 and s.y >= f.y - s.size and s.y <= f.y + HERO_BODY + s.size then
					hurt(self, h, s.dmg, "emit", s.x - s.vx * 0.05, nil, s.freeze)
					gone = true
					break
				end
			end
		end
		if gone then
			if s.explode > 0 then
				local r = s.explode
				emit(self, { type = "blast", actor = self.index, x = s.x, y = s.y, radius = r, color = self.def.color })
				for _, h in up do
					local f = self.sim.fighters[h.index]
					local dx, dy = f.x - s.x, f.y + 0.9 - s.y
					if math.sqrt(dx * dx + dy * dy) <= r + 0.4 then
						hurt(self, h, s.dmg, "blast", s.x)
					end
				end
			end
			emit(self, { type = "projectile_end", id = s.id })
		else
			table.insert(keep, s)
		end
	end
	self.shots = keep
end

local function updateZones(self: Fight, dt: number)
	local keep = {}
	for _, z in self.zones do
		if z.warn > 0 or z.armed then
			z.warn = math.max(0, z.warn - dt)
			table.insert(keep, z)
			continue
		end
		if z.live <= 0 then
			continue
		end
		z.live -= dt
		if z.vx then
			z.x1 += z.vx * dt
			z.x2 += z.vx * dt
			if z.x2 < Arena.STAGE_LEFT - 0.5 or z.x1 > Arena.STAGE_RIGHT + 0.5 then
				z.live = 0
			end
		end
		if z.follow then
			local half = self.width * 0.5
			z.x1, z.x2 = self.x - half, self.x + half
		end
		for _, h in self.heroes do
			if heroUp(self, h) then
				local f = self.sim.fighters[h.index]
				-- Zones hit as boxes; a ground wave only hits heroes on the floor (jump it).
				local inside = heroIn(self, h, z.x1, z.x2, z.y1, z.y2) and (z.kind ~= "wave" or f.y < 0.6)
				if inside then
					if z.source == "gale" then
						local p = Bosses.patterns[self.pattern]
						local force = num(p or {}, "force", 5)
						local away = sign(f.x - self.x)
						local slow = (p and p.slow) or 1
						f.x += away * force * dt * 0.75
						f.vx *= (1 - math.min(1, dt * 2 * slow))
					elseif z.source == "slow" then
						f.x -= f.vx * dt * 0.55
						f.vy = math.min(f.vy, 4)
						local last = z.hit[h.index]
						if last == nil or self.elapsed - last >= (z.rehit or 0.5) then
							z.hit[h.index] = self.elapsed
							hurt(self, h, z.dmg * 0.35, "slow", z.cx or self.x, 0)
						end
					elseif z.dmg > 0 then
						local last = z.hit[h.index]
						local again = z.rehit and last and self.elapsed - last >= z.rehit
						if last == nil or again then
							z.hit[h.index] = self.elapsed
							hurt(self, h, z.dmg, z.source, z.cx or self.x, z.push)
						end
					end
				end
			end
		end
		if z.live > 0 then
			table.insert(keep, z)
		end
	end
	self.zones = keep
end

-- Boss movement between patterns: drift toward the target, keep a little distance, hover and bob.
local function drift(self: Fight, dt: number)
	local tx = targetX(self)
	local want = tx - sign(tx - self.x) * (self.width * 0.5 + 2.2)
	if math.abs(tx - self.x) < self.width * 0.5 + 1.5 then
		want = self.x
	end
	local speed = self.speed * (if self.phase >= 2 then RAID.PHASE_TWO_SPEED else 1)
	local dx = want - self.x
	self.x = stageClamp(self, self.x + math.clamp(dx, -speed * dt, speed * dt))
	if math.abs(tx - self.x) > 0.3 then
		self.facing = if tx > self.x then 1 else -1
	end
	self.y = self.baseY
end

local function startTransform(self: Fight)
	self.phase = 2
	self.phaseReached = 2
	self.state = "transform"
	self.stateT = RAID.TRANSFORM_SECONDS
	self.stateLen = RAID.TRANSFORM_SECONDS
	for _, s in self.shots do
		emit(self, { type = "projectile_end", id = s.id })
	end
	table.clear(self.shots)
	table.clear(self.zones)
	self.moveTo = nil
	emit(self, { type = "boss_phase", phase = 2, x = self.x })
end

local function shatterWave(self: Fight)
	emit(self, { type = "boss_shatter", x = self.x, y = centerY(self) })
	for _, h in self.heroes do
		if heroUp(self, h) then
			local f = self.sim.fighters[h.index]
			local dir = if math.abs(f.x - self.x) > 0.05 then sign(f.x - self.x) else 1
			if math.abs(f.x - self.x) < 6 then
				f.vx = dir * 9
				f.vy = 6
				f.grounded = false
				f.state = "HitStun"
				f.stun = 0.25
				f.pending = nil
			end
		end
	end
end

local function finish(self: Fight, victory: boolean, reason: string)
	if self.result then
		return
	end
	self.result = if victory then "victory" else "defeat"
	self.reason = reason
	for _, s in self.shots do
		emit(self, { type = "projectile_end", id = s.id })
	end
	table.clear(self.shots)
	table.clear(self.zones)
	local sim = self.sim
	if victory then
		self.state = "defeated"
		local mvp, best = 1, -1
		for _, h in self.heroes do
			if h.damage > best then
				mvp, best = h.index, h.damage
			end
		end
		for _, h in self.heroes do
			if h.down > 0 and not h.out then
				respawn(self, h) -- everybody stands for the victory scene
			end
		end
		sim.result = mvp
		emit(self, { type = "boss_defeated", boss = self.bossId, mvp = mvp })
		emit(self, { type = "finish", winner = mvp, finisher = false, raid = true, victory = true })
	else
		self.state = "victory"
		sim.result = -1
		emit(self, { type = "raid_failed", boss = self.bossId, reason = reason })
		emit(self, { type = "finish", winner = -1, finisher = false, raid = true, victory = false, reason = reason })
	end
	placeStandIn(self)
end

-- After each Simulation tick: boss damage, boss AI, telegraphs, projectiles, downs, outcome.
function BossFight.afterTick(self: Fight)
	local sim = self.sim
	local events = sim.events
	local out: { { [string]: any } } = {}
	local standIn = sim.fighters[self.index]
	-- Hits on the stand-in become boss hits; everything else about the stand-in stays on the server.
	for _, e in events do
		if e.target == self.index then
			if e.type == "hit" then
				local h = BossFight.heroOf(self, e.actor)
				local dmg = (e.damage or 0) * RAID.DAMAGE_TAKEN
				if h then
					h.damage += dmg
				end
				table.insert(out, {
					type = "boss_hit",
					actor = e.actor,
					damage = math.floor(dmg * 10 + 0.5) / 10,
					special = e.special,
					combo = e.combo,
				})
			end
		elseif e.actor == self.index then
			if e.type == "projectile" or e.type == "projectile_end" or e.type == "blast" then
				table.insert(out, e)
			end
		elseif e.type == "ring_out" then
			-- Out of the blast zone: the Simulation respawned (or eliminated) the hero at once; the raid instead
			-- takes a life from the shared pool and brings them back after the respawn timer.
			local h = BossFight.heroOf(self, e.actor)
			if h and not h.out then
				local f = sim.fighters[h.index]
				if f.state == "Defeated" then
					h.out = true
					h.downs += 1
					table.insert(out, e)
					table.insert(out, {
						type = "hero_down",
						actor = h.index,
						lives = self.lives,
						out = true,
						reason = "ringout",
					})
				else
					f.lives += 1 -- takeDown counts the life
					f.stocksLost -= 1
					table.insert(out, e)
					takeDown(self, h, "ringout")
				end
			end
		elseif e.type == "respawn" then
			-- the raid respawns heroes itself
			continue
		else
			table.insert(out, e)
		end
	end
	table.clear(events)
	for _, e in out do
		table.insert(events, e)
	end

	if sim.countdown > 0 or self.result then
		placeStandIn(self)
		BossFight.flush(self)
		return
	end
	local dt = STEP
	self.elapsed += dt

	-- Damage from the heroes.
	if standIn.percent > 0 then
		if self.state ~= "transform" then
			self.hp = math.max(0, self.hp - standIn.percent * RAID.DAMAGE_TAKEN)
		end
		standIn.percent = 0
	end
	if self.hp <= 0 then
		finish(self, true, "boss")
		BossFight.flush(self)
		return
	end
	if self.phase == 1 and self.hp <= self.maxHp * Bosses.PHASE_TWO_AT then
		startTransform(self)
	end
	if not self.enraged and self.elapsed >= RAID.ENRAGE_SECONDS then
		self.enraged = true
		emit(self, { type = "boss_enrage" })
	end

	-- Boss state machine.
	self.stateT -= dt
	if self.state == "idle" then
		drift(self, dt)
		if self.stateT <= 0 and #upHeroes(self) > 0 then
			beginPattern(self)
		end
	elseif self.state == "windup" then
		if self.patternType == "dive" then
			-- Rise and hang over the target; the landing spot locks in for the last third.
			local u = 1 - self.stateT / math.max(0.01, self.stateLen)
			self.y = self.baseY + math.sin(math.min(1, u * 1.6) * math.pi * 0.5) * 6
			if u < 0.66 then
				local tx = targetX(self)
				self.aimX = tx
				for _, z in self.zones do
					local r = (z.x2 - z.x1) * 0.5
					z.x1, z.x2, z.cx = tx - r, tx + r, tx
				end
			end
		end
		if self.stateT <= 0 then
			activate(self)
		end
	elseif self.state == "active" then
		emitStep(self, dt)
		if self.moveTo then
			local target = self.moveTo :: number
			local step = self.moveSpeed * dt
			local dx = target - self.x
			self.x += math.clamp(dx, -step, step)
			if math.abs(target - self.x) < 0.05 then
				self.moveTo = nil
				self.stateT = math.min(self.stateT, 0.15)
			end
		end
		if self.stateT <= 0 then
			self.state = "recover"
			self.stateT = 0.45 * tempo(self)
			self.stateLen = self.stateT
			self.moveTo = nil
		end
	elseif self.state == "recover" then
		self.y = self.baseY
		if self.stateT <= 0 then
			local gap = RAID.GAP
			local len = self.rng:range(gap[1], gap[2]) * tempo(self) * (if self.phase >= 2 then 0.75 else 1)
			self.state = "idle"
			self.stateT = len
			self.stateLen = len
		end
	elseif self.state == "transform" then
		self.y = self.baseY + math.sin((1 - self.stateT / self.stateLen) * math.pi) * 1.2
		if self.stateT <= RAID.TRANSFORM_SECONDS * 0.45 and self.stateT + dt > RAID.TRANSFORM_SECONDS * 0.45 then
			shatterWave(self)
		end
		if self.stateT <= 0 then
			self.state = "idle"
			self.stateT = 0.6
			self.stateLen = 0.6
			self.y = self.baseY
			emit(self, { type = "boss_phase_ready", phase = 2 })
		end
	end

	updateZones(self, dt)
	updateShots(self, dt)

	-- Touching the boss's body hurts a little (no hiding inside it).
	for _, h in self.heroes do
		local mercy = h.mercy
		for k, v in mercy do
			if v - dt > 0 then
				mercy[k] = v - dt
			else
				mercy[k] = nil
			end
		end
		if heroUp(self, h) and self.state ~= "transform" then
			local f = sim.fighters[h.index]
			local inside = math.abs(f.x - self.x) < self.width * 0.35
				and f.y + HERO_BODY > self.y
				and f.y < self.y + self.height * 0.8
			if inside and self.patternType == "charge" and self.state == "active" then
				hurt(self, h, num(self.def, "dmg", 12), "charge", self.x)
			elseif inside then
				local t = (self.contact[h.index] or 0) + dt
				self.contact[h.index] = t
				if t > 0.6 then
					self.contact[h.index] = 0
					hurt(self, h, num(self.def, "dmg", 12) * 0.25, "contact", self.x)
				end
			else
				self.contact[h.index] = 0
			end
		end
	end

	-- Downs and respawns.
	local anyAlive = false
	for _, h in self.heroes do
		if h.down > 0 then
			h.down -= dt
			if h.down <= 0 then
				respawn(self, h)
			end
		end
		if not h.out then
			anyAlive = true
		end
	end
	if not anyAlive then
		finish(self, false, "wiped")
	elseif self.elapsed >= RAID.TIME_LIMIT then
		finish(self, false, "time")
	end
	sim.timeLeft = math.max(0, RAID.TIME_LIMIT - self.elapsed)
	placeStandIn(self)
	BossFight.flush(self)
end

-- Moves this tick's raid events into the Simulation's event list (MatchRunner reads them from there).
function BossFight.flush(self: Fight)
	for _, e in self.pending do
		table.insert(self.sim.events, e)
	end
	table.clear(self.pending)
end

-- Bot helpers step out of telegraphed zones shortly before they go live (and jump ground waves and low beams).
function BossFight.steer(self: Fight, index: number, cmd: Command, level: number): Command
	local found = BossFight.heroOf(self, index)
	if found == nil or not heroUp(self, found) then
		return cmd
	end
	local h = found :: Hero
	local f = self.sim.fighters[index]
	for _, z in self.zones do
		local soon = (z.warn > 0 and z.warn < 0.55) or (z.live > 0 and z.dmg > 0)
		if soon and z.kind ~= "aim" and z.kind ~= "wind" then
			local decided = h.evade[z.id]
			if decided == nil then
				decided = self.rng:next() < 0.35 + level * 0.07
				h.evade[z.id] = decided
			end
			if decided and heroIn(self, h, z.x1 - 0.4, z.x2 + 0.4, z.y1, z.y2) then
				local jumpIt = z.kind == "wave" or z.kind == "beam" or (z.y2 - z.y1) < 2.2
				if jumpIt then
					cmd.jump = f.grounded
					cmd.jumpHeld = true
				else
					local left, right = z.x1 - 0.8, z.x2 + 0.8
					local goLeft = math.abs(f.x - left) < math.abs(f.x - right)
					if left < Arena.STAGE_LEFT + 0.5 then
						goLeft = false
					elseif right > Arena.STAGE_RIGHT - 0.5 then
						goLeft = true
					end
					cmd.move = if goLeft then -1 else 1
					cmd.standard, cmd.special, cmd.grab, cmd.smash = false, false, false, false
					cmd.block = false
				end
				break
			end
		end
	end
	return cmd
end

--------------------------------------------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------------------------------------------

local STATE_CODE = { idle = 0, windup = 1, active = 2, recover = 3, transform = 4, defeated = 5, victory = 6 }
BossFight.STATE_CODE = STATE_CODE
local ZONE_CODE = { rect = 1, circle = 2, column = 3, beam = 4, wave = 5, aim = 6, wind = 7 }
BossFight.ZONE_CODE = ZONE_CODE
BossFight.MAX_ZONES = 8

local function r2(v: number): number
	return math.round(v * 100) / 100
end

-- Compact state for the client's boss HP bar, boss model and telegraphs (BossState remote, unreliable):
-- { hp, maxHp, phase, x, y, facing, state, pattern, progress, lives, timeLeft, enraged, heroes, zones }.
function BossFight.encode(self: Fight): { any }
	local heroes = {}
	for _, h in self.heroes do
		table.insert(heroes, math.floor(h.hp + 0.5))
		table.insert(heroes, h.maxHp)
		table.insert(heroes, if h.out then -1 else r2(math.max(0, h.down)))
	end
	local zones = {}
	local n = 0
	for _, z in self.zones do
		if n >= BossFight.MAX_ZONES then
			break
		end
		n += 1
		table.insert(zones, ZONE_CODE[z.kind] or 1)
		table.insert(zones, r2(z.x1))
		table.insert(zones, r2(z.x2))
		table.insert(zones, r2(z.y1))
		table.insert(zones, r2(z.y2))
		table.insert(zones, if z.warn > 0 then r2(1 - z.warn / z.warnTotal) else 2)
	end
	return {
		math.ceil(self.hp),
		self.maxHp,
		self.phase,
		r2(self.x),
		r2(self.y),
		self.facing,
		STATE_CODE[self.state] or 0,
		self.pattern,
		r2(math.clamp(1 - self.stateT / math.max(0.01, self.stateLen), 0, 1)),
		self.lives,
		r2(math.max(0, RAID.TIME_LIMIT - self.elapsed)),
		if self.enraged then 1 else 0,
		heroes,
		zones,
		self.bossId,
	}
end

export type NetZone = { kind: number, x1: number, x2: number, y1: number, y2: number, progress: number, live: boolean }
export type NetHero = { hp: number, maxHp: number, down: number, out: boolean }
export type NetBoss = {
	bossId: string,
	hp: number,
	maxHp: number,
	phase: number,
	x: number,
	y: number,
	facing: number,
	state: number,
	pattern: string,
	progress: number,
	lives: number,
	timeLeft: number,
	enraged: boolean,
	heroes: { NetHero },
	zones: { NetZone },
}

function BossFight.decode(a: { any }): NetBoss
	local heroes = {}
	local flat = a[13] or {}
	for k = 1, #flat - 2, 3 do
		table.insert(
			heroes,
			{ hp = flat[k], maxHp = flat[k + 1], down = math.max(0, flat[k + 2]), out = flat[k + 2] < 0 }
		)
	end
	local zones = {}
	local zf = a[14] or {}
	for k = 1, #zf - 5, 6 do
		table.insert(zones, {
			kind = zf[k],
			x1 = zf[k + 1],
			x2 = zf[k + 2],
			y1 = zf[k + 3],
			y2 = zf[k + 4],
			progress = math.min(1, zf[k + 5]),
			live = zf[k + 5] > 1.5,
		})
	end
	return {
		hp = a[1],
		maxHp = a[2],
		phase = a[3],
		x = a[4],
		y = a[5],
		facing = a[6],
		state = a[7],
		pattern = a[8],
		progress = a[9],
		lives = a[10],
		timeLeft = a[11],
		enraged = a[12] == 1,
		heroes = heroes,
		zones = zones,
		bossId = a[15],
	}
end

-- Boss projectiles for the Shots remote (id, x, y, size).
function BossFight.shotList(self: Fight): { Shot }
	return self.shots
end

-- Short raid summary for results and rewards.
function BossFight.summary(self: Fight): { [string]: any }
	return {
		boss = self.bossId,
		victory = self.result == "victory",
		reason = self.reason,
		phase = self.phaseReached,
		hp = math.ceil(self.hp),
		maxHp = self.maxHp,
		seconds = math.floor(self.elapsed),
		lives = self.lives,
	}
end

return BossFight
