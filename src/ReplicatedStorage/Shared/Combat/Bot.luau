--!strict
-- Computer players, ported from combat.gd (_ai_command / _ai_think / _ai_finisher).
-- A bot only produces Commands, exactly like a player's controller, so it can never do anything a player can't.
-- Reaction time: a bot "thinks" every (22 - level * 2) + 0..3 frames and holds movement/shield in between;
-- buttons are only pressed on think frames. Levels 1..9.

local Arena = require(script.Parent.Arena)
local Input = require(script.Parent.Input)
local Moveset = require(script.Parent.Moveset)
local Signature = require(script.Parent.Signature)
local Simulation = require(script.Parent.Simulation)
local Rng = require(script.Parent.Parent.Util.Rng)

type Command = Input.Command
type Simulation = Simulation.Simulation

type Plan = {
	move: number?,
	up: boolean?,
	down: boolean?,
	jump: boolean?,
	standard: boolean?,
	special: boolean?,
	block: boolean?,
	grab: boolean?,
	smash: boolean?,
}

type Memory = {
	t: number,
	plan: Plan,
	standardRange: number,
	specialRange: number,
	finDo: boolean?,
	finStep: number,
	finFrame: number,
}

export type Brain = {
	level: number,
	rng: Rng.Rng,
	memory: { [number]: Memory },
	command: (self: Brain, sim: Simulation, index: number) -> Command,
}

local Bot = {}
Bot.__index = Bot

Bot.MIN_LEVEL = 1
Bot.MAX_LEVEL = 9

function Bot.new(level: number, seed: number?): Brain
	local self = setmetatable({
		level = math.clamp(math.floor(level), Bot.MIN_LEVEL, Bot.MAX_LEVEL),
		rng = Rng.new(seed or 4242),
		memory = {},
	}, Bot)
	return (self :: any) :: Brain
end

-- Reaction delay in frames before the next decision (without the 0..3 random part).
function Bot.reactionFrames(level: number): number
	return 22 - math.clamp(level, Bot.MIN_LEVEL, Bot.MAX_LEVEL) * 2
end

-- Bots never "hold" jump between presses, so every jump they press is a full jump.
local function idle(): Command
	local c = Input.idle()
	c.jumpHeld = true
	return c
end

local function sign(v: number): number
	return if v > 0 then 1 elseif v < 0 then -1 else 0
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

local function memoryFor(self: Brain, sim: Simulation, index: number): Memory
	local mem = self.memory[index]
	if not mem then
		local base = Moveset.baseAttacks(sim.fighters[index].fighterId)
		local specialRange = signatureRange(sim.fighters[index].moves.nspecial)
		mem = {
			t = 0,
			plan = {},
			standardRange = base.standard.range,
			specialRange = specialRange,
			finDo = nil,
			finStep = 1,
			finFrame = 0,
		}
		self.memory[index] = mem
	end
	return mem
end

local function think(self: Brain, sim: Simulation, index: number, mem: Memory): Plan
	local lvl = self.level
	local rng = self.rng
	local f = sim.fighters[index]
	local p: Plan = {}

	if f.state == "Ledge" then
		if f.ledgeTimer < 0.2 + (9 - lvl) * 0.08 then
			return p
		end
		local toward = -f.ledge
		local r = rng:next()
		if r < 0.45 then
			p.move = toward
		elseif r < 0.7 then
			p.jump = true
		elseif r < 0.85 then
			p.block = true
		else
			p.standard = true
		end
		return p
	end

	local edge = if f.x < 0 then Arena.STAGE_LEFT else Arena.STAGE_RIGHT
	local offstage = f.x < Arena.STAGE_LEFT or f.x > Arena.STAGE_RIGHT
	if offstage or (f.y < -0.3 and not f.grounded) then
		-- Recovery: jump, then climbing special, then air dodge towards the ledge.
		p.move = -sign(f.x)
		if f.vy < 1.5 then
			if f.airJumps > 0 and f.y < 0.8 then
				p.jump = true
			elseif not f.airDashUsed then
				p.special = true
				p.up = f.y < -0.6
			elseif lvl >= 4 and not f.airDodgeUsed and math.abs(f.x - edge) < 3 and f.y < 0.5 then
				p.block = true
				p.up = f.y < -0.5
			end
		end
		return p
	end

	local found = sim:nearestOpponent(index)
	if found == nil then
		return p
	end
	local oppIndex = found :: number
	local o = sim.fighters[oppIndex]
	local dx = o.x - f.x
	local adx = math.abs(dx)
	local dy = o.y - f.y
	local dir = if adx > 0.05 then sign(dx) else f.facing
	local reach = mem.standardRange

	-- Defense: shield or roll away when an attack is coming.
	local oppPending = o.pending
	if
		f.grounded
		and oppPending
		and adx < memoryFor(self, sim, oppIndex).standardRange + 0.9
		and math.abs(dy) < 1.6
	then
		local r = rng:next()
		if r < lvl * 0.07 and f.shieldHp > 15 then
			p.block = true
			return p
		end
		if lvl >= 5 and r < lvl * 0.09 then
			p.block = true
			p.move = -dir
			return p
		end
	end
	-- A shielding opponent gets grabbed.
	if o.blocking and adx < 1.3 and rng:next() < 0.2 + lvl * 0.07 then
		p.grab = true
		return p
	end

	if not f.grounded then
		if adx < reach + 0.4 and math.abs(dy) < 2.4 then
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
		end
		return p
	end

	if dy > 1.2 and adx < 1.4 then
		p.standard = true
		p.up = true
		if o.percent > 95 and lvl >= 4 then
			p.smash = true
		end
		return p
	end
	if dy > 1.2 then
		p.move = dir
		p.jump = adx < 3 and rng:next() < 0.55
		return p
	end
	if dy < -1 and f.y > 0.3 then
		p.down = true
		return p
	end
	-- Two-stage signatures: follow up (next cut, strike the mark, recall the spear ...).
	if f.state == "Ready" and Signature.followup(sim, index) and rng:next() < 0.1 + lvl * 0.03 then
		p.special = true
		p.move = dir
		return p
	end
	if adx <= reach * 0.95 and math.abs(dy) < 1.3 then
		local r = rng:next()
		local killPercent = 120 - lvl * 4
		if o.percent > killPercent and r < 0.3 + lvl * 0.05 then
			p.smash = true
			p.standard = true
			p.move = dir
		elseif r < 0.28 then
			p.standard = true
		elseif r < 0.5 then
			p.standard = true
			p.move = dir
		elseif r < 0.64 then
			p.standard = true
			p.down = true
		elseif r < 0.8 and f.cooldownSpecial <= 0 then
			p.special = true
			p.move = dir
		else
			p.grab = true
		end
		return p
	end
	if adx <= mem.specialRange and math.abs(dy) < 1.4 and f.cooldownSpecial <= 0 and rng:next() < 0.22 then
		p.special = true
		p.move = dir
		return p
	end
	p.move = dir
	if adx > 1.6 and adx < 3.5 and rng:next() < 0.1 + lvl * 0.02 then
		p.jump = true
	end
	-- Edge guarding: don't follow an opponent off stage, wait at the edge instead.
	if
		(o.x < Arena.STAGE_LEFT or o.x > Arena.STAGE_RIGHT)
		and lvl >= 6
		and math.abs(f.x - sign(o.x) * Arena.STAGE_RIGHT) < 1.2
	then
		p.move = 0
	end
	return p
end

-- The winner types its finisher code; the chance to even try grows with the level.
local function finisher(self: Brain, sim: Simulation, index: number, c: Command, mem: Memory): Command
	local f = sim.fighters[index]
	local loser = sim.fighters[sim.finishLoser]
	local toward = if loser.x >= f.x then 1 else -1
	if mem.finDo == nil then
		mem.finDo = self.rng:next() < 0.35 + self.level * 0.07
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
	local urgent = f.state == "Ledge"
		or f.x < Arena.STAGE_LEFT
		or f.x > Arena.STAGE_RIGHT
		or (f.y < -0.3 and not f.grounded)
	local t = mem.t - 1
	if t > 0 and not urgent then
		mem.t = t
		apply(c, mem.plan, true)
		return c
	end
	mem.t = Bot.reactionFrames(self.level) + self.rng:int(0, 3)
	mem.plan = think(self, sim, index, mem)
	apply(c, mem.plan, false)
	return c
end

return Bot
