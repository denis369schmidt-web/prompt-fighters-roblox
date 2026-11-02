--!strict
-- Computer players. A bot only produces Commands, exactly like a player's controller, so it can never do anything
-- a player can't (SPEC 4.6: same inputs, same simulation).
--
-- Each bot has a personality from its fighter's archetype (rushdown, zoner, grappler, defensive, allround) and a
-- skill set from its level 1..9 (Bot.skill): reaction time, mistakes, shield/dodge reactions, combo follow-ups,
-- edge guarding, recovery quality, signature use. Low levels are slow and sloppy so new players win; level 9
-- reacts in a few frames, punishes whiffs and guards the ledge.
--
-- Decisions: a bot "thinks" every reaction window (Bot.reactionFrames + a random part) and holds movement/shield
-- in between; buttons are only pressed on think frames. Two things run every frame on top of that:
--   * threat watch: when an opponent starts an attack in range, the bot may schedule a defensive reaction
--     (shield, spot dodge, roll, jump) after its reaction delay, like a human seeing the wind-up;
--   * urgent states (off stage, on the ledge, holding someone) think on a short fixed cadence.
-- Everything random goes through the brain's seeded Rng, so a match replays exactly from its seed.
--
-- Bots also pick varied targets (a crowd penalty stops three bots from ganging up on one player), pick up items,
-- and taunt after a KO when nobody is close (brain:takeEmotes() -> "emote" events for the client).

local Arena = require(script.Parent.Arena)
local Input = require(script.Parent.Input)
local Moveset = require(script.Parent.Moveset)
local Signature = require(script.Parent.Signature)
local Simulation = require(script.Parent.Simulation)
local Constants = require(script.Parent.Parent.Data.Constants)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local Rng = require(script.Parent.Parent.Util.Rng)

type Command = Input.Command
type Simulation = Simulation.Simulation
type FighterState = Simulation.FighterState

type Plan = {
	move: number?,
	up: boolean?,
	down: boolean?,
	jump: boolean?,
	shortHop: boolean?,
	standard: boolean?,
	special: boolean?,
	block: boolean?,
	grab: boolean?,
	smash: boolean?,
}

export type Style = "rushdown" | "zoner" | "grappler" | "defensive" | "allround"

export type Personality = {
	style: Style,
	aggression: number, -- 0..1: how eagerly it walks in and attacks
	range: number, -- preferred distance as a multiple of its standard reach (zoner: of its special reach)
	shield: number, -- multiplier on defensive reactions
	grab: number, -- share of grabs among close-range options
	aerial: number, -- how often it jumps in with aerials
	special: number, -- how often it uses its signature special when in range
	punish: number, -- multiplier on whiff punishes
	items: number, -- interest in items
	taunt: number, -- chance to taunt after a KO
}

export type Skill = {
	reaction: number, -- frames between decisions
	jitter: number, -- extra random frames 0..jitter
	mistake: number, -- chance a decision is botched
	defend: number, -- chance to react to an attack it sees coming
	dodge: number, -- share of reactions that are dodges/rolls instead of shield
	punish: number, -- chance to punish an opponent's whiffed move
	combo: number, -- chance to follow up a landed hit
	edgeguard: number, -- chance to guard the ledge against a recovering opponent
	signature: number, -- SPEC: signature use 0.3 + level * 0.12
	finisher: number, -- SPEC: finisher chance 0.35 + level * 0.07
	recovery: number, -- 0..1 how cleverly it spends jumps and specials coming back
	approach: number, -- stick strength when walking in (low levels dawdle)
	kill: number, -- percent from which it goes for smash attacks
}

type Memory = {
	t: number,
	plan: Plan,
	skill: Skill,
	personality: Personality,
	standardRange: number,
	specialRange: number,
	ideal: number,
	target: number?,
	targetTimer: number,
	seen: { [number]: any },
	reactAt: number?,
	reactTo: number,
	hits: number,
	chain: number,
	comboUntil: number,
	dive: number,
	ledgeWait: number?,
	lastState: string,
	kos: number,
	tauntUntil: number,
	emoteT: number,
	itemFocus: number,
	finDo: boolean?,
	finStep: number,
	finFrame: number,
}

export type Emote = { type: string, actor: number, kind: string }

export type Brain = {
	level: number,
	levels: { [number]: number },
	gentle: { [number]: boolean },
	rng: Rng.Rng,
	memory: { [number]: Memory },
	emotes: { Emote },
	command: (self: Brain, sim: Simulation, index: number) -> Command,
	setLevel: (self: Brain, index: number, level: number) -> (),
	setGentle: (self: Brain, index: number, gentle: boolean) -> (),
	levelOf: (self: Brain, index: number) -> number,
	takeEmotes: (self: Brain) -> { Emote },
	emoting: (self: Brain, index: number) -> boolean,
	targetOf: (self: Brain, index: number) -> number?,
}

local Bot = {}
Bot.__index = Bot

Bot.MIN_LEVEL = 1
Bot.MAX_LEVEL = 9
-- Frames a taunt lasts (the bot stands still and is open to a hit, like a player taunting).
Bot.TAUNT_FRAMES = 70

local STAGE_LEFT, STAGE_RIGHT = Arena.STAGE_LEFT, Arena.STAGE_RIGHT

local function clampLevel(level: number): number
	return math.clamp(math.floor(level), Bot.MIN_LEVEL, Bot.MAX_LEVEL)
end

-- Reaction delay in frames before the next decision (without the random part).
function Bot.reactionFrames(level: number): number
	return 22 - clampLevel(level) * 2
end

-- Bot level for a player's progress (SPEC 8.2: bot level by player level): the first match is level 1, the next
-- few level 2, then it climbs with wins and player level up to 8.
function Bot.levelFor(matches: number, wins: number, playerLevel: number): number
	if matches <= 0 then
		return 1
	elseif matches < 3 then
		return 2
	end
	return math.clamp(2 + wins // 3 + (playerLevel - 1) // 5, 2, 8)
end

-- Per-slot levels around a base so the bots of one match differ a little (one weaker, one stronger).
local LINEUP_OFFSET = { 0, -1, 1, 0 }
function Bot.lineup(base: number, count: number): { number }
	local out = {}
	for i = 1, count do
		out[i] = clampLevel(base + LINEUP_OFFSET[(i - 1) % #LINEUP_OFFSET + 1])
	end
	return out
end

function Bot.skill(level: number): Skill
	local l = clampLevel(level)
	local k = (l - 1) / 8
	return {
		reaction = Bot.reactionFrames(l),
		jitter = 3 + math.round((1 - k) * 5),
		mistake = 0.3 - k * 0.28,
		defend = 0.04 + k * 0.74,
		dodge = k * 0.5,
		punish = 0.08 + k * 0.8,
		combo = 0.12 + k * 0.83,
		edgeguard = if l >= 4 then (l - 3) * 0.14 else 0,
		signature = math.min(1, 0.3 + l * 0.12),
		finisher = math.min(1, 0.35 + l * 0.07),
		recovery = k,
		approach = 0.6 + k * 0.4,
		kill = 125 - l * 5,
	}
end

local STYLES: { [Style]: Personality } = {
	rushdown = {
		style = "rushdown",
		aggression = 0.95,
		range = 0.7,
		shield = 0.7,
		grab = 0.18,
		aerial = 0.5,
		special = 0.25,
		punish = 1,
		items = 0.25,
		taunt = 0.55,
	},
	zoner = {
		style = "zoner",
		aggression = 0.35,
		range = 0.75,
		shield = 1,
		grab = 0.1,
		aerial = 0.2,
		special = 0.75,
		punish = 0.8,
		items = 0.55,
		taunt = 0.4,
	},
	grappler = {
		style = "grappler",
		aggression = 0.65,
		range = 0.55,
		shield = 1.1,
		grab = 0.5,
		aerial = 0.18,
		special = 0.3,
		punish = 1,
		items = 0.45,
		taunt = 0.45,
	},
	defensive = {
		style = "defensive",
		aggression = 0.4,
		range = 1.2,
		shield = 1.35,
		grab = 0.22,
		aerial = 0.2,
		special = 0.35,
		punish = 1.4,
		items = 0.2,
		taunt = 0.25,
	},
	allround = {
		style = "allround",
		aggression = 0.7,
		range = 0.9,
		shield = 1,
		grab = 0.22,
		aerial = 0.32,
		special = 0.4,
		punish = 1,
		items = 0.35,
		taunt = 0.35,
	},
}
Bot.STYLES = STYLES

-- Archetype words (Data/Roster, German) -> style. First match wins.
local STYLE_WORDS: { { style: Style, words: { string } } } = {
	{ style = "grappler", words = { "grappler", "kerker", "ketten", "koloss", "schwergewicht", "schmied", "bestie" } },
	{ style = "defensive", words = { "verteidiger", "konter", "punisher", "duellant" } },
	{
		style = "zoner",
		words = {
			"zoner",
			"artillerie",
			"schütz",
			"beschwör",
			"fluch",
			"fallen",
			"tüftler",
			"taktiker",
			"kontrolle",
		},
	},
	{ style = "rushdown", words = { "rushdown", "speedster", "assassin", "brawler", "krallen", "luftjäger" } },
}

function Bot.styleOf(fighterId: string): Style
	local def = Fighters.byId[fighterId]
	local archetype = if def then string.lower(def.archetype) else ""
	for _, entry in STYLE_WORDS do
		for _, word in entry.words do
			if string.find(archetype, word, 1, true) then
				return entry.style
			end
		end
	end
	return "allround"
end

function Bot.personalityFor(fighterId: string): Personality
	return table.clone(STYLES[Bot.styleOf(fighterId)])
end

function Bot.new(level: number, seed: number?): Brain
	local self = setmetatable({
		level = clampLevel(level),
		levels = {},
		gentle = {},
		rng = Rng.new(seed or 4242),
		memory = {},
		emotes = {},
	}, Bot)
	return (self :: any) :: Brain
end

-- Per-slot level (a match can mix levels); defaults to the brain's level.
function Bot.setLevel(self: Brain, index: number, level: number)
	self.levels[index] = clampLevel(level)
	self.memory[index] = nil
end

function Bot.levelOf(self: Brain, index: number): number
	return self.levels[index] or self.level
end

-- Gentle bots (a new player's first match): slow, never smash or edge-guard a human, rarely shield.
function Bot.setGentle(self: Brain, index: number, gentle: boolean)
	self.gentle[index] = gentle
	self.memory[index] = nil
end

function Bot.takeEmotes(self: Brain): { Emote }
	local out = self.emotes
	if #out > 0 then
		self.emotes = {}
	end
	return out
end

function Bot.emoting(self: Brain, index: number): boolean
	local mem = self.memory[index]
	return mem ~= nil and mem.emoteT > 0
end

function Bot.targetOf(self: Brain, index: number): number?
	local mem = self.memory[index]
	return if mem then mem.target else nil
end

-- Bots never "hold" jump between presses, so every jump they press is a full jump (unless a short hop is planned).
local function idle(): Command
	local c = Input.idle()
	c.jumpHeld = true
	return c
end

local function sign(v: number): number
	return if v > 0 then 1 elseif v < 0 then -1 else 0
end

local function offstage(f: FighterState): boolean
	return f.x < STAGE_LEFT or f.x > STAGE_RIGHT or (f.y < -0.3 and not f.grounded)
end

-- How far a fighter's neutral special reaches: shots by speed and flight time, aimed signatures (rain,
-- meteor, storm) from afar, melee signatures by their hitbox.
local function signatureRange(a: Moveset.Ability): number
	if a.sig == nil or not a.noHit then
		return a.range
	end
	local sig = a.sig :: { [string]: any }
	local speed = tonumber(sig.speed) or 0
	local gravity = tonumber(sig.gravity) or 0
	if speed > 0 and gravity > 0 then
		local rise = tonumber(sig.rise) or 0
		return math.clamp(speed * (2 * math.max(rise, 1) / gravity) + 0.5, 1.5, 8)
	elseif speed > 0 and sig.life then
		return math.clamp(speed * (tonumber(sig.life) or 1) * 0.8, 1.5, 8)
	end
	return 5
end
Bot.signatureRange = signatureRange

local function memoryFor(self: Brain, sim: Simulation, index: number): Memory
	local mem = self.memory[index]
	if not mem then
		local f = sim.fighters[index]
		local base = Moveset.baseAttacks(f.fighterId)
		local personality = Bot.personalityFor(f.fighterId)
		local level = self:levelOf(index)
		local skill = Bot.skill(level)
		if self.gentle[index] then
			skill.defend = 0.02
			skill.dodge = 0
			skill.punish = 0.05
			skill.combo = 0.1
			skill.edgeguard = 0
			skill.mistake = math.max(skill.mistake, 0.3)
			skill.reaction += 4
		end
		local reach = math.max(base.standard.range, (f.moves.ftilt and f.moves.ftilt.range) or 0)
		local specialRange = signatureRange(f.moves.nspecial)
		local ideal = if personality.style == "zoner"
			then math.max(3, specialRange * personality.range)
			else math.max(0.9, reach * personality.range)
		mem = {
			t = 0,
			plan = {},
			skill = skill,
			personality = personality,
			standardRange = reach,
			specialRange = specialRange,
			ideal = ideal,
			target = nil,
			targetTimer = 0,
			seen = {},
			reactAt = nil,
			reactTo = 0,
			hits = f.hits,
			chain = 0,
			comboUntil = 0,
			dive = 0,
			ledgeWait = nil,
			lastState = f.state,
			kos = f.kos,
			tauntUntil = 0,
			emoteT = 0,
			itemFocus = 0,
			finDo = nil,
			finStep = 1,
			finFrame = 0,
		}
		self.memory[index] = mem
	end
	return mem :: Memory
end

local function alive(f: FighterState): boolean
	return f.state ~= "Defeated" and f.state ~= "Dazed" and f.lives > 0
end

-- Picks whom to fight. Close, damaged and vengeful targets score well; targets other bots already chase score
-- worse (more so for humans), so three bots don't gang up on one player.
local function pickTarget(self: Brain, sim: Simulation, index: number, mem: Memory): number?
	local f = sim.fighters[index]
	local current = mem.target
	if current and (not alive(sim.fighters[current]) or sim:isAlly(index, current)) then
		current = nil
	end
	mem.targetTimer -= 1
	if current and mem.targetTimer > 0 then
		return current
	end
	local lastHitBy = (sim :: any)._lastHitBy and (sim :: any)._lastHitBy[index]
	local best, bestScore = nil, math.huge
	for j, o in sim.fighters do
		if j ~= index and not sim:isAlly(index, j) and alive(o) then
			local crowd = 0
			for k, other in self.memory do
				if k ~= index and other.target == j and sim.fighters[k] and alive(sim.fighters[k]) then
					crowd += 1
				end
			end
			local score = math.abs(o.x - f.x) + math.abs(o.y - f.y) * 0.7
			score -= o.percent * 0.025
			score += crowd * (if o.isBot then 3 else 5.5)
			if lastHitBy == j then
				score -= 2.5
			end
			if o.invulnerable > 0 then
				score += 4
			end
			if j == current then
				score -= 1.5
			end
			if self.gentle[index] and not o.isBot then
				score += 3 + crowd * 6 -- a new player faces one soft bot at a time
			end
			score += self.rng:next() * 2.5
			if score < bestScore then
				best, bestScore = j, score
			end
		end
	end
	mem.target = best
	mem.targetTimer = 80 + self.rng:int(0, 120)
	return best
end

-- Holds a human-like reaction ready when an opponent starts an attack that can reach this fighter.
local function watchThreats(self: Brain, sim: Simulation, index: number, mem: Memory)
	local f = sim.fighters[index]
	for j, o in sim.fighters do
		if j ~= index and not sim:isAlly(index, j) then
			local pending = o.pending
			if pending and pending ~= mem.seen[j] and pending.stage == "windup" then
				mem.seen[j] = pending
				local a = pending.ability
				local reach = (if a.noHit then signatureRange(a) else a.range) + 0.7
				local forward = (f.x - o.x) * o.facing
				local inFront = a.allAround or a.noHit or forward > -0.6
				if
					inFront
					and math.abs(f.x - o.x) < reach
					and math.abs(f.y - o.y) < 2
					and self.rng:next() < mem.skill.defend * mem.personality.shield
				then
					local delay = mem.skill.reaction // 2 + self.rng:int(0, mem.skill.jitter)
					mem.reactAt = sim.frame + delay
					mem.reactTo = j
				end
			elseif pending == nil then
				mem.seen[j] = nil
			end
		end
	end
end

-- The reaction itself: shield, spot dodge, roll away or jump out. Returns the plan and how long to hold it.
local function defendPlan(self: Brain, sim: Simulation, index: number, mem: Memory): (Plan?, number)
	local f = sim.fighters[index]
	local o = sim.fighters[mem.reactTo]
	local pending = o and o.pending
	if not pending or pending.stage == "recovery" or f.state ~= "Ready" then
		return nil, 0
	end
	local away = if f.x >= o.x then 1 else -1
	local p: Plan = {}
	if not f.grounded then
		if not f.airDodgeUsed and self.rng:next() < 0.6 then
			p.block = true
			p.move = away
			return p, 6
		end
		return nil, 0
	end
	local r = self.rng:next()
	local nearEdge = math.abs(f.x + away * 2) > STAGE_RIGHT
	if r < mem.skill.dodge then
		if r < mem.skill.dodge * 0.45 then
			p.block = true
			p.down = true -- spot dodge
			return p, 8
		elseif not nearEdge then
			p.block = true
			p.move = away -- roll away
			return p, 6
		end
		p.jump = true
		p.move = -away
		return p, 8
	end
	if f.shieldHp > 12 then
		p.block = true
		return p, 10 + self.rng:int(0, 10)
	end
	p.jump = true
	p.move = away
	return p, 8
end

-- A botched decision: stand there, attack the air, jump for nothing or walk the wrong way.
local function flub(self: Brain, dir: number): Plan
	local r = self.rng:next()
	local p: Plan = {}
	if r < 0.35 then
		return p
	elseif r < 0.6 then
		p.standard = true
		p.move = if self.rng:next() < 0.5 then -dir else 0
	elseif r < 0.8 then
		p.jump = true
	else
		p.move = -dir * 0.6
	end
	return p
end

local function ledgePlan(self: Brain, sim: Simulation, index: number, mem: Memory): Plan
	local f = sim.fighters[index]
	local p: Plan = {}
	if mem.ledgeWait == nil then
		local base = 0.15 + (1 - mem.skill.recovery) * 0.5
		mem.ledgeWait = base + self.rng:next() * (0.2 + mem.skill.recovery * 0.9)
	end
	if f.ledgeTimer < (mem.ledgeWait :: number) and f.ledgeTimer < Constants.MOVEMENT.ledge.maxHang - 0.5 then
		return p
	end
	local toward = -f.ledge
	local edge = if f.ledge < 0 then STAGE_LEFT else STAGE_RIGHT
	local guarded = false
	for j, o in sim.fighters do
		if j ~= index and not sim:isAlly(index, j) and alive(o) and o.grounded then
			if math.abs(o.x - edge) < 2.4 and math.abs(o.y) < 0.5 then
				guarded = true
			end
		end
	end
	local r = self.rng:next()
	if guarded and mem.skill.recovery > 0.4 then
		if r < 0.4 then
			p.block = true -- roll past
		elseif r < 0.75 then
			p.jump = true
		else
			p.standard = true
		end
	elseif r < 0.5 then
		p.move = toward
	elseif r < 0.72 then
		p.jump = true
	elseif r < 0.87 then
		p.block = true
	else
		p.standard = true
	end
	return p
end

-- Holding someone: throw them toward the near edge, or up into a juggle at low percent.
local function throwPlan(self: Brain, sim: Simulation, index: number, mem: Memory): Plan
	local f = sim.fighters[index]
	local p: Plan = {}
	local held = f.grabTarget
	local percent = if held then sim.fighters[held].percent else 0
	local edgeSide = if f.x >= 0 then 1 else -1
	local r = self.rng:next()
	if percent < 70 and r < 0.35 + mem.personality.grab * 0.5 then
		p.up = true
	elseif r < 0.2 then
		p.down = true
	else
		p.move = edgeSide -- forward or back throw, whichever points at the close edge
	end
	return p
end

local function recoveryPlan(_self: Brain, sim: Simulation, index: number, mem: Memory): Plan
	local f = sim.fighters[index]
	local p: Plan = {}
	local side = if f.x < 0 then -1 else 1
	local out = (f.x - side * STAGE_RIGHT) * side
	p.move = -side
	if f.state ~= "Ready" or f.pending then
		return p -- in hit stun: hold toward the stage (drift / DI)
	end
	-- Edge guard dive: hit the recovering opponent, then come back.
	local target = mem.target
	if mem.dive > 0 and target then
		local o = sim.fighters[target]
		local dx, dy = o.x - f.x, o.y - f.y
		if math.abs(dx) < mem.standardRange + 0.5 and math.abs(dy) < 1.8 then
			mem.dive = 0
			p.standard = true
			if dy < -0.6 then
				p.down = true
			else
				p.move = sign(dx)
			end
			return p
		end
		if f.y > -0.5 and out < 3.5 then
			p.move = sign(dx)
			return p
		end
		mem.dive = 0
	end
	if f.vy > 2 then
		return p
	end
	local smart = mem.skill.recovery
	local high = f.y > 1.2
	if f.airJumps > 0 and (f.y < 0.4 or (out > 4 and not high) or (smart < 0.3 and f.y < 1.5)) then
		p.jump = true
	elseif not f.airDashUsed and out > 1.6 and f.y > -0.8 then
		p.special = true -- forward air dash toward the stage
	elseif f.y < -0.15 and ((f.cooldownSpecial <= 0 and f.moves.uspecial ~= nil) or not f.airDashUsed) then
		p.special = true
		p.up = true -- up special, or the rising dash when it isn't ready
	elseif not f.airDodgeUsed and out < 2.6 and f.y < -0.4 and smart > 0.25 then
		p.block = true
		p.up = true
	end
	return p
end

-- Walks to a nearby item and picks it up; throws a carried item at the target.
local function itemPlan(self: Brain, sim: Simulation, index: number, mem: Memory, o: FighterState): Plan?
	local f = sim.fighters[index]
	local p: Plan = {}
	if f.carriedItem ~= 0 then
		local dx, dy = o.x - f.x, o.y - f.y
		if math.abs(dy) < 1.6 and math.abs(dx) < 9 and math.abs(dx) > 0.6 then
			p.move = sign(dx)
			p.standard = true
		else
			p.move = sign(dx)
		end
		return p
	end
	if f.weapon or not f.grounded or not sim.itemsEnabled then
		return nil
	end
	if mem.itemFocus <= 0 then
		if self.rng:next() > mem.personality.items * 0.5 then
			return nil
		end
		mem.itemFocus = 120
	end
	local best, bestD = nil, 6.5
	for _, item in sim.items do
		if (item.state == "resting" or item.state == "free") and math.abs(item.y - f.y) < 1 then
			local d = math.abs(item.x - f.x)
			if d < bestD then
				best, bestD = item, d
			end
		end
	end
	if best == nil then
		mem.itemFocus = 0
		return nil
	end
	local item = best :: any
	if bestD < 1.1 then
		if item.power and not item.explosive then
			p.move = sign(item.x - f.x) * 0.5 -- touch is enough
		else
			p.grab = true
		end
		mem.itemFocus = 0
	else
		p.move = sign(item.x - f.x)
	end
	return p
end

local function think(self: Brain, sim: Simulation, index: number, mem: Memory): Plan
	local rng = self.rng
	local f = sim.fighters[index]
	local skill = mem.skill
	local pers = mem.personality
	local lvl = self:levelOf(index)
	local gentle = self.gentle[index] == true
	local p: Plan = {}

	if f.state == "Ledge" then
		return ledgePlan(self, sim, index, mem)
	end
	mem.ledgeWait = nil
	if f.state == "Carrying" then
		return throwPlan(self, sim, index, mem)
	end
	if offstage(f) then
		return recoveryPlan(self, sim, index, mem)
	end

	local found = pickTarget(self, sim, index, mem)
	if found == nil then
		return p
	end
	local oIndex = found :: number
	local o = sim.fighters[oIndex]
	local soft = gentle and not o.isBot -- pull punches against a new player
	local dx = o.x - f.x
	local adx = math.abs(dx)
	local dy = o.y - f.y
	local dir = if adx > 0.05 then sign(dx) else f.facing
	local reach = mem.standardRange
	local inReach = adx <= reach * 0.95 and math.abs(dy) < 1.3

	-- Taunt after a KO, when nobody is close.
	if mem.tauntUntil > sim.frame and f.grounded and f.state == "Ready" and adx > 4.5 then
		mem.tauntUntil = 0
		mem.emoteT = Bot.TAUNT_FRAMES
		table.insert(self.emotes, { type = "emote", actor = index, kind = "taunt" })
		return p
	end

	-- Combo state: a hit that just landed opens a short follow-up window.
	if f.hits > mem.hits then
		mem.chain += 1
		mem.comboUntil = sim.frame + 45
	elseif sim.frame > mem.comboUntil then
		mem.chain = 0
	end
	mem.hits = f.hits

	if rng:next() < skill.mistake then
		return flub(self, dir)
	end
	if soft and rng:next() < 0.45 then
		-- Hesitate against a new player: give them room to land their hits.
		p.move = if rng:next() < 0.5 then 0 else -dir * 0.5
		return p
	end

	local items = itemPlan(self, sim, index, mem, o)
	if items and adx > 2.5 then
		return items
	end
	mem.itemFocus = math.max(0, mem.itemFocus - skill.reaction)

	-- Whiff punish: the opponent is stuck in the end lag of a move right in front of us.
	local oPending = o.pending
	if
		oPending
		and oPending.stage == "recovery"
		and adx < reach + 0.4
		and math.abs(dy) < 1.2
		and f.grounded
		and rng:next() < skill.punish * pers.punish
	then
		if o.percent > skill.kill and not soft then
			p.smash = true
			p.standard = true
			p.move = dir
		elseif f.weapon == nil and adx < 1.3 and rng:next() < 0.5 then
			p.grab = true
		else
			p.standard = true
			p.move = dir
		end
		return p
	end

	-- Combo follow-ups (jab -> jab -> ftilt, utilt -> uair, aerial chases).
	if mem.chain > 0 and o.state == "HitStun" and rng:next() < skill.combo then
		if dy > 0.8 and adx < 1.8 then
			p.standard = true
			p.up = true
			if f.grounded and dy > 2 then
				p.standard = nil
				p.up = nil
				p.jump = true
				p.move = dir
			end
		elseif dy > 2 and adx < 4 then
			p.move = dir
			p.jump = f.grounded or (f.airJumps > 0 and f.vy < 1)
		elseif adx <= reach + 0.2 and math.abs(dy) < 1.3 then
			p.standard = true
			if not f.grounded then
				p.move = dir
				p.down = dy < -0.8
			elseif mem.chain >= 3 and o.percent > skill.kill * 0.8 and not soft then
				p.smash = true
				p.move = dir
			elseif mem.chain == 1 then
				p.down = rng:next() < 0.3
			else
				p.move = dir -- ftilt finisher of the string
			end
		else
			p.move = dir
		end
		return p
	end

	-- Edge guard: wait at the ledge for a recovering opponent, hit them on the way back, dive at high levels.
	if not soft and f.grounded and o.state ~= "Ledge" and offstage(o) and rng:next() < skill.edgeguard then
		local side = if o.x < 0 then -1 else 1
		local standX = side * (STAGE_RIGHT - 0.7)
		local out = (o.x - f.x) * side
		if math.abs(f.x - standX) > 0.6 then
			p.move = sign(standX - f.x)
			return p
		end
		if out < reach + 0.5 and o.y > -1.6 and o.y < 1.8 then
			p.standard = true
			p.move = side
			p.smash = lvl >= 6
			p.down = o.y < -0.6
			return p
		end
		if lvl >= 7 and f.airJumps > 0 and out < 3.2 and o.y > -1 and o.y < 2.5 and rng:next() < 0.5 then
			p.jump = true
			p.move = side
			mem.dive = 40
			return p
		end
		return p
	end

	-- Ledge trap: stand back from the edge and hit the get-up.
	if not soft and o.state == "Ledge" and lvl >= 4 and f.grounded then
		local side = o.ledge
		local standX = side * (STAGE_RIGHT - 1.7)
		if math.abs(f.x - standX) > 0.5 then
			p.move = sign(standX - f.x)
		end
		return p
	end

	-- Vertical play: platforms above and below.
	if not f.grounded then
		if adx < reach + 0.5 and math.abs(dy) < 2.2 then
			p.standard = true
			if dy > 0.9 then
				p.up = true
			elseif dy < -0.9 then
				p.down = true
			else
				p.move = dir
			end
		else
			p.move = dir
			-- Fast fall toward a target below.
			if dy < -1 and f.vy < 1 and lvl >= 5 and rng:next() < 0.5 then
				p.down = true
			end
		end
		return p
	end
	if dy > 1.2 and adx < 1.4 then
		p.standard = true
		p.up = true
		if o.percent > skill.kill and lvl >= 4 and not soft then
			p.smash = true
		end
		return p
	end
	if dy > 1.2 then
		p.move = dir
		p.jump = adx < 3 and rng:next() < 0.6
		return p
	end
	if dy < -1 and f.y > 0.3 then
		p.down = true
		return p
	end

	-- Two-stage signatures: follow up (next cut, strike the mark, recall the spear ...).
	if f.state == "Ready" and Signature.followup(sim, index) and rng:next() < 0.1 + lvl * 0.04 then
		p.special = true
		p.move = dir
		return p
	end

	-- Signature special at a good moment: in its range, more likely with a full super bar or a kill percent.
	if f.cooldownSpecial <= 0 and adx <= mem.specialRange and math.abs(dy) < 1.4 then
		local chance = pers.special * skill.signature * 0.6
		if f.super >= Constants.MAX_SUPER then
			chance += 0.35 * skill.signature
		end
		if o.percent > skill.kill then
			chance += 0.15
		end
		if o.state == "HitStun" or o.state == "ShieldBreak" then
			chance += 0.2
		end
		if soft then
			chance *= 0.4
		end
		if rng:next() < chance then
			p.special = true
			p.move = dir
			return p
		end
	end

	if inReach then
		local r = rng:next()
		if o.percent > skill.kill and r < 0.25 + lvl * 0.05 and not soft then
			p.smash = true
			p.standard = true
			p.move = dir
		elseif f.weapon == nil and ((o.blocking and r < 0.3 + lvl * 0.06) or (r < pers.grab * 0.6 and adx < 1.3)) then
			p.grab = true -- shields get grabbed; grapplers grab a lot
		elseif r < 0.35 then
			p.standard = true -- jab (a follow-up turns it into a string)
		elseif r < 0.58 then
			p.standard = true
			p.move = dir
		elseif r < 0.72 then
			p.standard = true
			p.down = true
		elseif r < 0.8 and f.cooldownSpecial <= 0 and f.moves.dspecial then
			p.special = true
			p.down = true
		elseif r < 0.87 + (1 - pers.aggression) * 0.1 then
			-- Back off a step (spacing), or shield and wait.
			if pers.style == "defensive" or pers.style == "zoner" then
				p.move = -dir
			else
				p.block = rng:next() < 0.4
			end
		else
			p.jump = true
			p.shortHop = true
			p.move = dir
		end
		return p
	end

	-- Neutral spacing by style.
	local ideal = mem.ideal
	local nearEdge = math.abs(f.x) > STAGE_RIGHT - 1.6
	if adx < ideal - 0.7 and (pers.style == "zoner" or pers.style == "defensive") then
		if nearEdge and f.x * dir < 0 then
			p.jump = true -- cornered: jump over
			p.move = dir
		else
			p.move = -dir
		end
		return p
	end
	if adx > reach and adx < reach + 2.6 and math.abs(dy) < 1 then
		local r = rng:next()
		if r < pers.aerial * pers.aggression then
			p.jump = true
			p.shortHop = rng:next() < 0.6
			p.move = dir
			return p
		end
		if pers.style == "rushdown" and r < 0.7 and f.runTime > 0.3 then
			p.standard = true -- dash attack
			p.move = dir
			return p
		end
		if pers.style == "defensive" and r < 0.55 then
			p.move = if rng:next() < 0.5 then 0 else dir * 0.4 -- wait for a whiff
			return p
		end
	end
	if adx > ideal then
		local speed = if adx > 3 then 1 else skill.approach
		p.move = dir * speed * (0.55 + pers.aggression * 0.45)
	else
		p.move = 0
	end
	if adx > 1.6 and adx < 3.5 and rng:next() < 0.05 + lvl * 0.015 then
		p.jump = true
	end
	return p
end

-- The winner types its finisher code; the chance to even try grows with the level.
local function finisher(self: Brain, sim: Simulation, index: number, c: Command, mem: Memory): Command
	local f = sim.fighters[index]
	local loser = sim.fighters[sim.finishLoser]
	local toward = if loser.x >= f.x then 1 else -1
	if mem.finDo == nil then
		mem.finDo = self.rng:next() < mem.skill.finisher
		mem.finStep = 1
		mem.finFrame = 0
	end
	if not mem.finDo then
		return c
	end
	if math.abs(loser.x - f.x) > 2.6 then
		c.move = toward
		return c
	end
	mem.finFrame += 1
	if mem.finFrame % 8 ~= 0 then
		return c
	end
	local key = f.finisherCode[mem.finStep]
	if key == nil then
		return c
	end
	if key == "F" then
		c.move = toward
	elseif key == "B" then
		c.move = -toward * 0.7
	elseif key == "U" then
		c.jump = true
	elseif key == "D" then
		c.down = true
	elseif key == "A" then
		c.standard = true
	elseif key == "S" then
		c.special = true
	end
	mem.finStep += 1
	return c
end

local function apply(c: Command, plan: Plan, heldOnly: boolean)
	if plan.move ~= nil then
		c.move = plan.move
	end
	if plan.block ~= nil then
		c.block = plan.block
	end
	if plan.up ~= nil then
		c.up = plan.up
	end
	if plan.down ~= nil then
		c.down = plan.down
	end
	if plan.shortHop then
		c.jumpHeld = false
	end
	if heldOnly then
		return
	end
	c.jump = plan.jump == true
	c.standard = plan.standard == true
	c.standardHeld = false
	c.special = plan.special == true
	c.grab = plan.grab == true
	c.smash = plan.smash == true
end

function Bot.command(self: Brain, sim: Simulation, index: number): Command
	local c = idle()
	local f = sim.fighters[index]
	if f.state == "Defeated" or f.state == "Dazed" or sim.countdown > 0 then
		return c
	end
	local mem = memoryFor(self, sim, index)
	if sim.finishPhase then
		if index == sim.finishWinner then
			return finisher(self, sim, index, c, mem)
		end
		return c
	end
	mem.finDo = nil
	if mem.dive > 0 then
		mem.dive -= 1
	end

	-- A KO of ours: maybe taunt once it is safe (checked on the next decisions).
	if f.kos > mem.kos then
		mem.kos = f.kos
		if self.rng:next() < mem.personality.taunt then
			mem.tauntUntil = sim.frame + 180
		end
	end
	if mem.emoteT > 0 then
		mem.emoteT -= 1
		local threatened = false
		for j, o in sim.fighters do
			if j ~= index and alive(o) and math.abs(o.x - f.x) < 2.5 and math.abs(o.y - f.y) < 2 then
				threatened = true
			end
		end
		if f.state == "Ready" and f.grounded and not threatened then
			return c
		end
		mem.emoteT = 0
	end

	local stateChanged = f.state ~= mem.lastState
	mem.lastState = f.state
	local urgent = f.state == "Ledge" or f.state == "Carrying" or offstage(f)
	if not urgent then
		watchThreats(self, sim, index, mem)
		local reactAt = mem.reactAt
		if reactAt and sim.frame >= reactAt then
			mem.reactAt = nil
			local plan, hold = defendPlan(self, sim, index, mem)
			if plan then
				mem.plan = plan
				mem.t = hold
				apply(c, plan, false)
				return c
			end
		end
	end

	local t = mem.t - 1
	local cadence = 2 + (Bot.MAX_LEVEL - self:levelOf(index)) // 3
	if urgent then
		-- Off stage / on the ledge / holding someone: decide on a short fixed cadence instead of the full
		-- reaction window, and right away when that state begins.
		t = if stateChanged then 0 else math.min(t, cadence)
	end
	if t > 0 then
		mem.t = t
		apply(c, mem.plan, true)
		return c
	end
	local hits = f.hits
	mem.plan = think(self, sim, index, mem)
	local skill = mem.skill
	local frames = skill.reaction + self.rng:int(0, skill.jitter)
	if mem.chain > 0 and hits > 0 then
		frames = math.max(3, math.floor(frames * 0.6)) -- in a combo the next press comes quicker
	end
	if urgent then
		frames = math.min(frames, cadence)
	end
	mem.t = frames
	apply(c, mem.plan, false)
	return c
end

return Bot
