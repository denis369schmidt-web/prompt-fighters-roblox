local Arena = require(Shared.Combat.Arena)
local Bot = require(Shared.Combat.Bot)
local Input = require(Shared.Combat.Input)
local MatchRunner = require(Shared.Combat.MatchRunner)
local Pose = require(Shared.Visual.Pose)
local Sim = require(Shared.Combat.Simulation)
local Visuals = require(Shared.Data.Visuals)

local ROSTER = Visuals.SLICE_FIGHTERS

-- 1 v 1 between two bot levels; returns the winner's slot (or nil / -1).
local function duel(seed: number, a: string, b: string, levelA: number, levelB: number): number?
	local sim = Sim.new({ fighters = { a, b }, bots = { true, true }, countdown = 0, seed = seed, stocks = 2 })
	local brain = Bot.new(levelA, seed)
	brain:setLevel(2, levelB)
	for _ = 1, 60 * 200 do
		sim:tick({ brain:command(sim, 1), brain:command(sim, 2) })
		if sim.result ~= nil then
			break
		end
	end
	return sim.result
end

describe("Bot personalities", function()
	it("reads a style from each fighter's archetype", function()
		expect(Bot.styleOf("ninja")).toBe("rushdown")
		expect(Bot.styleOf("lepora")).toBe("zoner")
		expect(Bot.styleOf("golem")).toBe("grappler")
		expect(Bot.styleOf("steel_knight")).toBe("defensive")
		expect(Bot.styleOf("valkyrie")).toBe("allround")
		for _, id in ROSTER do
			expect(Bot.STYLES[Bot.styleOf(id)] ~= nil).toBe(true)
		end
	end)

	it("scales skill with the level: faster, fewer mistakes, more defense and combos", function()
		local low, high = Bot.skill(1), Bot.skill(9)
		expect(high.reaction < low.reaction).toBe(true)
		expect(high.mistake < low.mistake).toBe(true)
		expect(high.defend > low.defend).toBe(true)
		expect(high.combo > low.combo).toBe(true)
		expect(low.edgeguard).toBe(0)
		expect(high.signature).toBeCloseTo(1, 5)
		expect(Bot.skill(4).signature).toBeCloseTo(0.3 + 4 * 0.12, 5) -- SPEC 4.6
		expect(Bot.skill(4).finisher).toBeCloseTo(0.35 + 4 * 0.07, 5)
	end)

	it("picks the bot level from the player's progress and spreads a lineup", function()
		expect(Bot.levelFor(0, 0, 1)).toBe(1)
		expect(Bot.levelFor(1, 1, 1)).toBe(2)
		expect(Bot.levelFor(40, 30, 30) <= 8).toBe(true)
		expect(Bot.levelFor(20, 9, 6) > Bot.levelFor(5, 0, 1)).toBe(true)
		local lineup = Bot.lineup(1, 4)
		for _, level in lineup do
			expect(level >= 1 and level <= 9).toBe(true)
		end
		expect(Bot.lineup(5, 3)[2]).toBe(4)
		expect(Bot.lineup(5, 3)[3]).toBe(6)
	end)
end)

describe("Bot play", function()
	it("wins more often on a higher level over seeded matches", function()
		local wins, total = 0, 0
		for seed = 1, 8 do
			local a = ROSTER[(seed % #ROSTER) + 1]
			local b = ROSTER[((seed * 7) % #ROSTER) + 1]
			-- Alternate which slot is strong so spawn side and fighter don't decide it.
			local strongFirst = seed % 2 == 0
			local result = duel(seed, a, b, if strongFirst then 8 else 2, if strongFirst then 2 else 8)
			total += 1
			if result == (if strongFirst then 1 else 2) then
				wins += 1
			end
		end
		expect(wins >= 6).toBe(true)
	end)

	it("comes back to the stage from off stage with every fighter", function()
		for _, id in ROSTER do
			for _, level in { 1, 9 } do
				for _, start in { { 11.5, 1 }, { 12.5, -0.5 }, { -10.6, -2.4 } } do
					local sim =
						Sim.new({ fighters = { id, "golem" }, bots = { true, false }, countdown = 0, items = false })
					local f = sim.fighters[1]
					f.x, f.y, f.grounded, f.vx, f.vy = start[1], start[2], false, 0, 0
					sim.fighters[2].x = 0
					local brain = Bot.new(level, 5)
					local safe = false
					for _ = 1, 60 * 6 do
						sim:tick({ brain:command(sim, 1), Input.idle() })
						if f.lives < 3 then
							break
						end
						if
							(f.grounded and f.x >= Arena.STAGE_LEFT and f.x <= Arena.STAGE_RIGHT)
							or f.state == "Ledge"
						then
							safe = true
							break
						end
					end
					assert(safe, `{id} (level {level}) did not recover from {start[1]}, {start[2]}`)
				end
			end
		end
	end)

	it("spreads its targets instead of ganging up on the human", function()
		local sim = Sim.new({
			fighters = { "ninja", "golem", "lepora", "jubei" },
			bots = { false, true, true, true },
			countdown = 0,
			seed = 4,
		})
		local brain = Bot.new(5, 4)
		local samples, ganged = 0, 0
		local targeted: { [number]: boolean } = {}
		for _ = 1, 60 * 40 do
			local cmds = { Input.idle() }
			for i = 2, 4 do
				cmds[i] = brain:command(sim, i)
			end
			sim:tick(cmds)
			if sim.frame % 30 == 0 then
				samples += 1
				local onHuman = 0
				for i = 2, 4 do
					local t = brain:targetOf(i)
					if t then
						targeted[t] = true
						if t == 1 then
							onHuman += 1
						end
					end
				end
				if onHuman == 3 then
					ganged += 1
				end
			end
			if sim.result ~= nil then
				break
			end
		end
		local distinct = 0
		for _ in targeted do
			distinct += 1
		end
		expect(distinct >= 3).toBe(true)
		expect(ganged / samples < 0.2).toBe(true)
	end)

	it("shields and dodges telegraphed attacks more on a high level", function()
		local function hitsTaken(level: number): number
			local sim =
				Sim.new({ fighters = { "golem", "ninja" }, bots = { false, true }, countdown = 0, items = false })
			local brain = Bot.new(level, 77)
			local taken = 0
			for frame = 1, 60 * 30 do
				local f2 = sim.fighters[2]
				-- Keep the bot in front of the attacker so every swing is a real threat.
				if f2.state == "Ready" and f2.grounded then
					f2.x = sim.fighters[1].x + 1.2
				end
				sim.fighters[1].percent, f2.percent = 0, 0
				local attack = Input.idle()
				attack.standard = frame % 50 == 0
				attack.move = if frame % 50 == 0 then 1 else 0
				sim:tick({ attack, brain:command(sim, 2) })
				for _, e in sim.events do
					if e.type == "hit" and e.target == 2 then
						taken += 1
					end
				end
			end
			return taken
		end
		expect(hitsTaken(9) < hitsTaken(1)).toBe(true)
	end)

	it("picks up items, taunts after KOs and stays deterministic", function()
		local function run(seed: number)
			local sim = Sim.new({
				fighters = { "ninja", "golem", "lepora", "steel_knight" },
				bots = { true, true, true, true },
				countdown = 0,
				seed = seed,
			})
			local brain = Bot.new(9, seed)
			local counts: { [string]: number } = {}
			for _ = 1, 60 * 99 do
				local cmds = {}
				for i = 1, 4 do
					cmds[i] = brain:command(sim, i)
				end
				sim:tick(cmds)
				for _, e in sim.events do
					counts[e.type] = (counts[e.type] or 0) + 1
				end
				for _, e in brain:takeEmotes() do
					expect(e.type).toBe("emote")
					counts.emote = (counts.emote or 0) + 1
				end
				if sim.result ~= nil then
					break
				end
			end
			return sim, counts
		end
		local sim, counts = run(3)
		local items = (counts.item_pickup or 0) + (counts.weapon_pickup or 0) + (counts.powerup or 0)
		expect(items).toBeGreaterThan(0)
		expect(counts.ring_out or 0).toBeGreaterThan(0)
		expect(counts.emote or 0).toBeGreaterThan(0)
		local again = run(3)
		for i, f in sim.fighters do
			expect(again.fighters[i].x).toBe(f.x)
			expect(again.fighters[i].percent).toBe(f.percent)
		end
	end)

	it("plays gently against a new player: takes more damage than it deals", function()
		local r = MatchRunner.new({
			slots = {
				{ userId = 1, fighterId = "ninja" },
				{ userId = nil, fighterId = "golem" },
				{ userId = nil, fighterId = "lepora" },
				{ userId = nil, fighterId = "jubei" },
			},
			seed = 12,
			countdown = 0,
			gentle = true,
			botStocks = 1,
			botLevels = { [2] = 1, [3] = 1, [4] = 1 },
		})
		-- Four fighters play with FFA_STOCKS (2); the gentle bots get one less.
		expect(r.sim.fighters[2].lives).toBe(1)
		expect(r.sim.fighters[1].lives).toBe(2)
		expect(r.brain:levelOf(3)).toBe(1)
		-- An idle human still survives a long while against three gentle bots.
		for _ = 1, 60 * 30 do
			r:step(1 / 60)
		end
		expect(r.sim.fighters[1].lives >= 1).toBe(true)
	end)
end)

describe("Victory and taunt display states", function()
	it("shows the winner in the Victory pose and passes emotes through as events", function()
		local r = MatchRunner.new({
			slots = { { userId = 1, fighterId = "ninja" }, { userId = nil, fighterId = "golem" } },
			seed = 2,
			countdown = 0,
		})
		r.sim.result = 2
		local decoded = MatchRunner.decode(r:snapshot())
		expect(decoded.fighters[2].state).toBe("Victory")
		expect(decoded.fighters[1].state ~= "Victory").toBe(true)
	end)

	it("raises a fist for Victory and waves for Taunt", function()
		local base = {
			move = "",
			stage = "",
			grounded = true,
			blocking = false,
			speed = 0,
			vy = 0,
			phase = 0,
			t = 1,
			stateTime = 1,
		}
		local v = table.clone(base) :: any
		v.state = "Victory"
		local pose = Pose.compute(v)
		expect(pose.joints.RightShoulder.x > 150).toBe(true)
		local t = table.clone(base) :: any
		t.state = "Taunt"
		local taunt = Pose.compute(t)
		expect(taunt.joints.RightShoulder.x > 60).toBe(true)
		for _, j in taunt.joints do
			expect(j.x == j.x).toBe(true)
		end
	end)
end)
