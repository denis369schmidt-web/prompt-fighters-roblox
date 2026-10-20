--!strict
-- One running match as the server sees it: the Simulation, the bots for empty slots, the latest input of each
-- player and a fixed-step accumulator (60 Hz no matter how fast Heartbeat fires). Instance-free and tested
-- under Lune; MatchService only connects it to remotes.
--
-- Inputs: a client sends its held buttons every frame and sets a "pressed" bit (jump, attack ...) on exactly
-- one packet. Pressed bits are latched until a tick consumes them, so a press is never lost or repeated even
-- when packets and ticks don't line up.

local Bot = require(script.Parent.Bot)
local Items = require(script.Parent.Items)
local Projectiles = require(script.Parent.Projectiles)
local Input = require(script.Parent.Input)
local Simulation = require(script.Parent.Simulation)
local Constants = require(script.Parent.Parent.Data.Constants)

type Command = Input.Command

export type Slot = { userId: number?, fighterId: string }

export type RunnerConfig = {
	slots: { Slot },
	botLevel: number?,
	seed: number?,
	stocks: number?,
	arena: string?,
	timeLimit: number?,
	countdown: number?,
}

export type Runner = {
	sim: Simulation.Simulation,
	slots: { Slot },
	brain: Bot.Brain,
	held: { [number]: { mask: number, axis: number } },
	latched: { [number]: number },
	accumulator: number,
	setInput: (self: Runner, slot: number, mask: number, axis: number) -> (),
	slotOf: (self: Runner, userId: number) -> number?,
	dropPlayer: (self: Runner, userId: number) -> (),
	step: (self: Runner, dt: number) -> ({ Simulation.Event }, number),
	snapshot: (self: Runner) -> { any },
	shots: (self: Runner) -> { number },
	items: (self: Runner) -> { number },
}

local MatchRunner = {}
MatchRunner.__index = MatchRunner

local STEP = 1 / Constants.TICK_RATE
-- At most this many ticks per step; a long server hitch is dropped instead of fast-forwarded.
MatchRunner.MAX_TICKS_PER_STEP = 5

local PRESS_BITS = bit32.bor(
	Input.BITS.jump,
	Input.BITS.standard,
	Input.BITS.special,
	Input.BITS.grab,
	Input.BITS.smash,
	Input.BITS.drop
)
MatchRunner.PRESS_BITS = PRESS_BITS

function MatchRunner.new(config: RunnerConfig): Runner
	local fighters, bots = {}, {}
	for i, slot in config.slots do
		fighters[i] = slot.fighterId
		bots[i] = slot.userId == nil
	end
	local seed = config.seed or 1
	local self = setmetatable({
		sim = Simulation.new({
			fighters = fighters,
			bots = bots,
			seed = seed,
			stocks = config.stocks,
			arena = config.arena,
			timeLimit = config.timeLimit,
			countdown = config.countdown,
		}),
		slots = config.slots,
		brain = Bot.new(config.botLevel or 4, seed + 101),
		held = {},
		latched = {},
		accumulator = 0,
	}, MatchRunner)
	return (self :: any) :: Runner
end

function MatchRunner.slotOf(self: Runner, userId: number): number?
	for i, slot in self.slots do
		if slot.userId == userId then
			return i
		end
	end
	return nil
end

function MatchRunner.setInput(self: Runner, slot: number, mask: number, axis: number)
	if not self.slots[slot] or self.slots[slot].userId == nil then
		return
	end
	-- Decode first: whatever the client sent, only a valid Command survives.
	local mask2, axis2 = Input.encode(Input.decode(mask, axis))
	self.held[slot] = { mask = bit32.band(mask2, bit32.bnot(PRESS_BITS)), axis = axis2 }
	self.latched[slot] = bit32.bor(self.latched[slot] or 0, bit32.band(mask2, PRESS_BITS))
end

-- A player who leaves mid-match is taken over by a bot, so the match stays fair for the others.
function MatchRunner.dropPlayer(self: Runner, userId: number)
	local slot = self:slotOf(userId)
	if slot then
		self.slots[slot].userId = nil
		self.sim.fighters[slot].isBot = true
		self.held[slot] = nil
		self.latched[slot] = nil
	end
end

local function commandsFor(self: Runner): { Command }
	local commands = {}
	for i, slot in self.slots do
		if slot.userId == nil then
			commands[i] = self.brain:command(self.sim, i)
		else
			local held = self.held[i]
			local mask = bit32.bor(if held then held.mask else 0, self.latched[i] or 0)
			commands[i] = Input.decode(mask, if held then held.axis else 0)
			self.latched[i] = 0
		end
	end
	return commands
end

-- Advances by real time; returns all events of the ticks run and how many ticks ran.
function MatchRunner.step(self: Runner, dt: number): ({ Simulation.Event }, number)
	self.accumulator = math.min(self.accumulator + math.max(dt, 0), STEP * MatchRunner.MAX_TICKS_PER_STEP)
	local events = {}
	local ticks = 0
	while self.accumulator >= STEP - 1e-9 and self.sim.result == nil do
		self.accumulator -= STEP
		self.sim:tick(commandsFor(self))
		ticks += 1
		for _, e in self.sim.events do
			table.insert(events, e)
		end
	end
	return events, ticks
end

local function round2(v: number): number
	return math.round(v * 100) / 100
end

-- Network snapshot: { frame, timeLeft, countdown, suddenDeath, finishPhase, finishTimer, fighters... }.
-- Each fighter is a flat array to stay well below the 900-byte limit of unreliable remotes.
function MatchRunner.snapshot(self: Runner): { any }
	local sim = self.sim
	local list: { { any } } = {}
	for i, s in sim:snapshot() do
		list[i] = {
			round2(s.x),
			round2(s.y),
			s.facing,
			s.state,
			s.move or "",
			s.moveStage or "",
			round2(s.percent),
			s.lives,
			math.floor(s.super),
			math.floor(s.shield),
			(if s.blocking then 1 else 0) + (if s.invulnerable then 2 else 0) + (if s.grounded then 4 else 0),
			s.combo,
			s.status,
		}
	end
	return {
		sim.frame,
		round2(sim.timeLeft),
		round2(sim.countdown),
		sim.suddenDeath,
		sim.finishPhase,
		round2(sim.finishTimer),
		list,
	}
end

export type NetFighter = {
	x: number,
	y: number,
	facing: number,
	state: string,
	move: string,
	moveStage: string,
	percent: number,
	lives: number,
	super: number,
	shield: number,
	blocking: boolean,
	invulnerable: boolean,
	grounded: boolean,
	combo: number,
	status: number,
}

export type NetSnapshot = {
	frame: number,
	timeLeft: number,
	countdown: number,
	suddenDeath: boolean,
	finishPhase: boolean,
	finishTimer: number,
	fighters: { NetFighter },
}

MatchRunner.MAX_SHOTS = 24

-- Projectile positions for the renderer: a flat { id, x, y, size, ... } list (sent unreliable like snapshots).
function MatchRunner.shots(self: Runner): { number }
	local out = {}
	for k, pr in self.sim.projectiles do
		if k > MatchRunner.MAX_SHOTS then
			break
		end
		table.insert(out, pr.id)
		table.insert(out, round2(pr.x))
		table.insert(out, round2(pr.y))
		table.insert(out, round2(pr.sizeNow or Projectiles.num(pr.spec, "size", 0.5)))
	end
	return out
end

-- Item state for the renderer (Items.encode), sent unreliable at 10 Hz.
function MatchRunner.items(self: Runner): { number }
	return Items.encode(self.sim)
end

-- Client side of snapshot(): turns the flat arrays back into named fields.
function MatchRunner.decode(payload: { any }): NetSnapshot
	local fighters = {}
	for i, a in payload[7] do
		local flags = a[11]
		fighters[i] = {
			x = a[1],
			y = a[2],
			facing = a[3],
			state = a[4],
			move = a[5],
			moveStage = a[6],
			percent = a[7],
			lives = a[8],
			super = a[9],
			shield = a[10],
			blocking = bit32.btest(flags, 1),
			invulnerable = bit32.btest(flags, 2),
			grounded = bit32.btest(flags, 4),
			combo = a[12],
			status = a[13] or 0,
		}
	end
	return {
		frame = payload[1],
		timeLeft = payload[2],
		countdown = payload[3],
		suddenDeath = payload[4],
		finishPhase = payload[5],
		finishTimer = payload[6],
		fighters = fighters,
	}
end

return MatchRunner
