local Bot = require(Shared.Combat.Bot)
local Input = require(Shared.Combat.Input)
local Rng = require(Shared.Util.Rng)
local Sim = require(Shared.Combat.Simulation)
local Constants = require(Shared.Data.Constants)

local function idles(n: number)
	local out = {}
	for i = 1, n do
		out[i] = Input.idle()
	end
	return out
end

local function run(sim, frames: number, commands)
	for _ = 1, frames do
		sim:tick(commands or idles(#sim.fighters))
	end
end

-- Events of all ticks, collected while running.
local function runCollect(sim, frames: number, commandsFor)
	local events = {}
	for frame = 1, frames do
		sim:tick(if commandsFor then commandsFor(frame) else idles(#sim.fighters))
		for _, e in sim.events do
			table.insert(events, e)
		end
		if sim.result ~= nil then
			break
		end
	end
	return events
end

local function has(events, kind: string): boolean
	for _, e in events do
		if e.type == kind then
			return true
		end
	end
	return false
end

local function duel(extra: { [string]: any }?)
	local config: { [string]: any } = { fighters = { "ninja", "golem" }, countdown = 0, seed = 1 }
	for k, v in extra or {} do
		config[k] = v
	end
	return Sim.new(config :: any)
end

local function botMatch(seed: number, level: number, frames: number)
	local sim = Sim.new({
		fighters = { "ninja", "golem", "jubei", "lepora" },
		bots = { true, true, true, true },
		stocks = 1,
		seed = seed,
		countdown = 0,
	})
	local brain = Bot.new(level, seed)
	for _ = 1, frames do
		local cmds = {}
		for i = 1, #sim.fighters do
			cmds[i] = brain:command(sim, i)
		end
		sim:tick(cmds)
		if sim.result ~= nil then
			break
		end
	end
	return sim
end

describe("Rng", function()
	it("matches a Python mulberry32 reference", function()
		local r = Rng.new(7919)
		expect(r:next()).toBeCloseTo(0.6900994985, 9)
		expect(r:next()).toBeCloseTo(0.7416439699, 9)
		expect(r:next()).toBeCloseTo(0.377083285, 9)
		local r2 = Rng.new(0xDEADBEEF)
		expect(r2:next()).toBeCloseTo(0.9413696141, 9)
		expect(r2:next()).toBeCloseTo(0.2671957498, 9)
	end)

	it("keeps int() inside its bounds", function()
		local r = Rng.new(3)
		for _ = 1, 500 do
			local v = r:int(0, 3)
			expect(v >= 0 and v <= 3 and v == math.floor(v)).toBe(true)
		end
	end)
end)

describe("Input", function()
	it("round-trips a command through encode/decode", function()
		local c = Input.idle()
		c.move, c.jump, c.standard, c.block, c.smash = -1, true, true, true, true
		local mask, axis = Input.encode(c)
		local d = Input.decode(mask, axis)
		expect(d.move).toBe(-1)
		expect(d.jump).toBe(true)
		expect(d.standard).toBe(true)
		expect(d.block).toBe(true)
		expect(d.smash).toBe(true)
		expect(d.special).toBe(false)
	end)

	it("turns garbage from the client into an idle command", function()
		expect(Input.decode("x", 4).jump).toBe(false)
		expect(Input.decode(0 / 0, 0).move).toBe(0)
		expect(Input.decode(2 ^ 40, 9999).move).toBe(1)
	end)
end)

describe("Simulation", function()
	it("holds everyone still during the countdown, then says go", function()
		local sim = Sim.new({ fighters = { "ninja", "golem" } })
		local x = sim.fighters[1].x
		local go = runCollect(sim, 200, function()
			local c = idles(2)
			c[1].move = 1
			return c
		end)
		expect(has(go, "go")).toBe(true)
		expect(sim.fighters[1].x).toBeGreaterThan(x)
	end)

	it("deals damage and knocks the target away from the attacker", function()
		local sim = duel()
		local a, b = sim.fighters[1], sim.fighters[2]
		a.x, b.x, a.facing = 0, 0.9, 1
		local events = runCollect(sim, 40, function(frame)
			local c = idles(2)
			c[1].standard = frame == 1
			return c
		end)
		expect(has(events, "hit")).toBe(true)
		expect(b.percent).toBeGreaterThan(0)
		expect(b.x).toBeGreaterThan(0.9)
		expect(a.hits).toBe(1)
	end)

	it("lets a full shield block and a broken shield stun", function()
		local sim = duel()
		local a, b = sim.fighters[1], sim.fighters[2]
		a.x, b.x, a.facing = 0, 0.9, 1
		run(
			sim,
			30,
			(function()
				local c = idles(2)
				c[2].block = true
				c[1].standard = true
				return c
			end)()
		)
		expect(b.percent).toBe(0)

		local sim2 = duel()
		local a2, b2 = sim2.fighters[1], sim2.fighters[2]
		a2.x, b2.x, a2.facing = 0, 0.9, 1
		b2.shieldHp = 0.5
		local events = runCollect(sim2, 20, function(frame)
			local c = idles(2)
			c[2].block = true
			c[1].standard = frame == 12
			return c
		end)
		expect(has(events, "shield_break")).toBe(true)
	end)

	it("respawns a ringed-out fighter with invulnerability and credits the KO", function()
		local sim = duel()
		local b = sim.fighters[2];
		(sim :: any)._lastHitBy = { [2] = 1 }
		b.x, b.y, b.grounded = 30, 2, false
		local events = runCollect(sim, 1)
		expect(has(events, "ring_out")).toBe(true)
		expect(b.lives).toBe(Constants.DEFAULT_STOCKS - 1)
		expect(b.percent).toBe(0)
		expect(b.invulnerable).toBeCloseTo(Constants.RESPAWN_INVULNERABLE, 1)
		expect(sim.fighters[1].kos).toBe(1)
	end)

	it("grabs the ledge when falling next to the stage edge", function()
		local sim = duel()
		local a = sim.fighters[1]
		a.x, a.y, a.grounded, a.vy = 9.9, -0.5, false, -1
		local events = runCollect(sim, 5)
		expect(has(events, "ledge_grab")).toBe(true)
		expect(a.state).toBe("Ledge")
	end)

	it("cancels two hits that land on each other in the same tick (clash)", function()
		local sim = duel({ fighters = { "ninja", "ninja" } })
		local a, b = sim.fighters[1], sim.fighters[2]
		a.x, b.x, a.facing, b.facing = 0, 0.9, 1, -1
		local events = runCollect(sim, 30, function(frame)
			local c = idles(2)
			c[1].standard = frame == 1
			c[2].standard = frame == 1
			return c
		end)
		expect(has(events, "clash")).toBe(true)
		expect(a.percent).toBe(0)
		expect(b.percent).toBe(0)
	end)

	it("starts the finish phase on the last stock and runs the finisher when its code is typed", function()
		local sim = duel({ stocks = 1 })
		local a, b = sim.fighters[1], sim.fighters[2]
		b.x, b.y, b.grounded = -30, 2, false
		local events = runCollect(sim, 1)
		expect(has(events, "finish_him")).toBe(true)
		expect(sim.finishPhase).toBe(true)
		expect(b.state).toBe("Dazed")

		local code = a.finisherCode
		local toward = if b.x >= a.x then 1 else -1
		local presses = {}
		for k, key in code do
			local c = idles(2)
			local frame = (k - 1) * 4 + 1
			if key == "F" then
				c[1].move = toward
			elseif key == "B" then
				c[1].move = -toward
			elseif key == "U" then
				c[1].jump = true
			elseif key == "D" then
				c[1].down = true
			elseif key == "A" then
				c[1].standard = true
			elseif key == "S" then
				c[1].special = true
			end
			presses[frame] = c
		end
		local finish = runCollect(sim, #code * 4 + 4, function(frame)
			return presses[frame] or idles(2)
		end)
		expect(has(finish, "finisher")).toBe(true)
		expect(sim.result).toBe(1)
		expect(a.finishers).toBe(1)
	end)

	it("ends without a finisher when the winner doesn't type it", function()
		local sim = duel({ stocks = 1 })
		sim.fighters[2].x = 30
		run(sim, math.ceil(Sim.FINISH_TIME * 60) + 5)
		expect(sim.result).toBe(1)
		expect(sim.fighters[1].finishers).toBe(0)
	end)

	it("goes to Sudden Death at 150 % when stocks are tied at time-up", function()
		local sim = duel({ timeLimit = 0.1 })
		local events = runCollect(sim, 10)
		expect(has(events, "sudden_death")).toBe(true)
		expect(sim.suddenDeath).toBe(true)
		expect(sim.fighters[1].percent).toBe(Constants.SUDDEN_DEATH_PERCENT)
		expect(sim.fighters[2].lives).toBe(1)
	end)

	it("gives the win at time-up to the fighter with more stocks", function()
		local sim = duel({ timeLimit = 0.1 })
		sim.fighters[2].lives = 1
		run(sim, 10)
		expect(sim.result).toBe(1)
	end)
end)

describe("Bot", function()
	it("reacts faster on higher levels", function()
		expect(Bot.reactionFrames(1)).toBe(20)
		expect(Bot.reactionFrames(9)).toBe(4)
		expect(Bot.reactionFrames(42)).toBe(4)
	end)

	it("only produces commands a real controller could send", function()
		local sim = botMatch(5, 7, 300)
		local brain = Bot.new(7, 5)
		for i = 1, #sim.fighters do
			local c = brain:command(sim, i)
			local mask, axis = Input.encode(c)
			local back = Input.decode(mask, axis)
			for key, value in c :: any do
				if key == "move" then
					expect(math.abs(back.move - value) < 0.01).toBe(true)
				else
					expect((back :: any)[key]).toBe(value)
				end
			end
		end
	end)

	it("plays a full 4-bot match to a result", function()
		local sim = botMatch(11, 9, 60 * 240)
		expect(sim.result).toBeTruthy()
		local damage = 0
		for _, f in sim.fighters do
			damage += f.damageDealt
		end
		expect(damage).toBeGreaterThan(0)
	end)

	it("replays the same match from the same seed (determinism)", function()
		local a = botMatch(23, 6, 900)
		local b = botMatch(23, 6, 900)
		local sa, sb = a:snapshot(), b:snapshot()
		for i = 1, #sa do
			expect(sa[i].x).toBe(sb[i].x)
			expect(sa[i].y).toBe(sb[i].y)
			expect(sa[i].percent).toBe(sb[i].percent)
			expect(sa[i].lives).toBe(sb[i].lives)
		end
		expect(a.frame).toBe(b.frame)
	end)
end)
