local DailyChallenge = require(Shared.Data.DailyChallenge)
local MatchRunner = require(Shared.Combat.MatchRunner)
local ModeRewards = require(Shared.Meta.ModeRewards)
local Mutators = require(Shared.Data.Mutators)
local MutatorRules = require(Shared.Combat.MutatorRules)
local Profile = require(Shared.Meta.Profile)
local Progression = require(Shared.Data.Progression)
local Visuals = require(Shared.Data.Visuals)

local STEP = 1 / 60
local DAY = 20759 -- 2026-11-02

describe("Daily Challenge", function()
	it("is the same for everyone on a day and changes between days", function()
		local a, b = DailyChallenge.forDay(DAY), DailyChallenge.forDay(DAY)
		expect(a.fighter).toBe(b.fighter)
		expect(a.goal).toBe(b.goal)
		expect(a.mutators[1]).toBe(b.mutators[1])
		expect(DailyChallenge.dayOf(DAY * 86400 + 86399)).toBe(DAY)
		local seen = {}
		local different = 0
		for d = DAY, DAY + 29 do
			local c = DailyChallenge.forDay(d)
			local key = c.fighter .. c.goal .. table.concat(c.mutators, ",")
			if not seen[key] then
				seen[key] = true
				different += 1
			end
		end
		expect(different > 20).toBe(true)
	end)

	it("always rolls a valid challenge", function()
		local goals = {}
		for d = DAY, DAY + 120 do
			local c = DailyChallenge.forDay(d)
			goals[c.goal] = true
			assert(table.find(Visuals.SLICE_FIGHTERS, c.fighter), "fighter not in the launch roster")
			expect(#c.mutators).toBe(2)
			expect(c.mutators[1] ~= c.mutators[2]).toBe(true)
			expect(Mutators.compatible(c.mutators)).toBe(true)
			for _, id in c.mutators do
				assert(table.find(DailyChallenge.MUTATOR_POOL, id), `{id} not in the pool`)
			end
			expect(c.botLevel >= 4 and c.botLevel <= 7).toBe(true)
			expect(table.find(c.opponents, c.fighter)).toBeNil()
			if c.goal == "handicap" then
				expect(#c.opponents).toBe(2)
				expect(c.teams and c.teams[1] == 1 and c.teams[2] == 2 and c.teams[3] == 2).toBe(true)
			end
			local info = DailyChallenge.describe(c)
			expect(type(info.goalText)).toBe("string")
			expect(#info.mutators).toBe(2)
		end
		for _, goal in DailyChallenge.GOAL_ORDER do
			assert(goals[goal], `goal {goal} never rolled`)
		end
	end)

	it("checks the goals", function()
		local c = DailyChallenge.forDay(DAY)
		c.goal = "fast"
		expect(DailyChallenge.check(c, { won = true, seconds = 59, stocksLost = 1 })).toBe(true)
		expect(DailyChallenge.check(c, { won = true, seconds = 61, stocksLost = 0 })).toBe(false)
		c.goal = "flawless"
		expect(DailyChallenge.check(c, { won = true, seconds = 90, stocksLost = 0 })).toBe(true)
		expect(DailyChallenge.check(c, { won = true, seconds = 90, stocksLost = 1 })).toBe(false)
		c.goal = "win"
		expect(DailyChallenge.check(c, { won = false, seconds = 10, stocksLost = 0 })).toBe(false)
	end)

	it("pays once per day with a streak that resets after a missed day", function()
		local p = Profile.new()
		local coins, streak = ModeRewards.claimDaily(p, DAY)
		expect(coins).toBe(Progression.DAILY_CHALLENGE_REWARD[1])
		expect(streak).toBe(1)
		expect(ModeRewards.claimDaily(p, DAY)).toBe(0)
		expect(ModeRewards.dailyDone(p, DAY)).toBe(true)
		local second = ModeRewards.claimDaily(p, DAY + 1)
		expect(second).toBe(Progression.DAILY_CHALLENGE_REWARD[2])
		local _, after = ModeRewards.claimDaily(p, DAY + 5)
		expect(after).toBe(1)
	end)

	it("runs a challenge match with its mutators to the end", function()
		for d = DAY, DAY + 5 do
			local c = DailyChallenge.forDay(d)
			local slots = { { userId = nil, fighterId = c.fighter } }
			for _, id in c.opponents do
				table.insert(slots, { userId = nil, fighterId = id })
			end
			local r = MatchRunner.new({
				slots = slots,
				seed = d,
				countdown = 0,
				arena = c.arena,
				mutators = c.mutators,
				teams = c.teams,
				stocks = c.stocks,
				botLevel = c.botLevel,
			})
			local t = 0
			while r.sim.result == nil and t < 200 do
				r:step(STEP)
				t += STEP
			end
			assert(r.sim.result ~= nil, `day {d}: no result`)
		end
	end)
end)

describe("Mutator rules", function()
	local function runner(ids: { string })
		return MatchRunner.new({
			slots = { { fighterId = "ninja" }, { fighterId = "golem" }, { fighterId = "zip" } },
			seed = 4,
			countdown = 0,
			mutators = ids,
			stocks = 3,
		})
	end

	it("applies start effects: Sudden Death percent, full super, low gravity", function()
		local plain = runner({})
		local r = runner({ "sudden_death", "super_start", "low_gravity" })
		for i, f in r.sim.fighters do
			expect(f.percent).toBe(150)
			expect(f.super).toBe(100)
			expect(f.phys.gravity).toBeCloseTo(plain.sim.fighters[i].phys.gravity * 0.45, 4)
		end
	end)

	it("doubles hit damage with GLASKANONEN", function()
		local r = runner({ "glass" })
		local checked = false
		local t = 0
		while not checked and t < 30 do
			local before = {}
			for i, f in r.sim.fighters do
				before[i] = f.percent
			end
			for _, e in r:step(STEP) do
				if e.type == "hit" and not checked then
					local f = r.sim.fighters[e.target]
					expect(f.percent - before[e.target]).toBeCloseTo(math.min(999, e.damage * 2), 3)
					checked = true
				end
			end
			t += STEP
		end
		expect(checked).toBe(true)
	end)

	it("swaps places every 15 seconds and drops warned bombs", function()
		local r = runner({ "swap", "bomb_rain" })
		local counts = {}
		local sawZone = false
		local t = 0
		while t < 16 and r.sim.result == nil do
			for _, e in r:step(STEP) do
				counts[e.type] = (counts[e.type] or 0) + 1
			end
			local state = r:modeState()
			if state and #state[2] > 0 then
				sawZone = true
			end
			t += STEP
		end
		expect((counts.mutator_swap or 0) >= 1).toBe(true)
		expect((counts.mutator_bomb or 0) >= 3).toBe(true)
		expect(sawZone).toBe(true)
		expect(MutatorRules.damageMult((r :: any).mutators)).toBe(1)
	end)

	it("escalates to double damage after a minute", function()
		local state = MutatorRules.apply(runner({}).sim, { "escalation" }, 1)
		expect(MutatorRules.damageMult(state)).toBe(1)
		state.elapsed = 90
		expect(MutatorRules.damageMult(state)).toBe(2)
	end)
end)
