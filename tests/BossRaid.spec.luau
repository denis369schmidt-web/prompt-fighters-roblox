local Arena = require(Shared.Combat.Arena)
local BossFight = require(Shared.Combat.BossFight)
local Bosses = require(Shared.Data.Bosses)
local MatchRunner = require(Shared.Combat.MatchRunner)
local ModeRewards = require(Shared.Meta.ModeRewards)
local Profile = require(Shared.Meta.Profile)

local STEP = 1 / 60
local HEROES = { "ninja", "golem", "phoenix", "valkyrie" }

local function raidRunner(boss: string, seed: number, humans: number?)
	local slots = {}
	for i, id in HEROES do
		slots[i] = { userId = if humans and i <= humans then 100 + i else nil, fighterId = id }
	end
	return MatchRunner.new({
		slots = slots,
		boss = boss,
		seed = seed,
		countdown = 0,
		botLevel = 5,
		arena = Bosses.arenaFor(boss),
	})
end

-- Runs until the raid ends (or `seconds`), counting event types.
local function run(r, seconds: number): { [string]: number }
	local counts = {}
	local t = 0
	while r.sim.result == nil and t < seconds do
		for _, e in r:step(STEP) do
			counts[e.type] = (counts[e.type] or 0) + 1
		end
		t += STEP
	end
	return counts
end

describe("Boss-Raid", function()
	it("four bot heroes beat the first boss through both phases", function()
		local r = raidRunner("ahriman", 1)
		local counts = run(r, Bosses.RAID.TIME_LIMIT + 5)
		local raid = r.raid :: any
		expect(raid.result).toBe("victory")
		expect(raid.hp).toBe(0)
		expect(raid.phaseReached).toBe(2)
		expect(counts.boss_phase).toBe(1)
		expect(counts.boss_shatter).toBe(1)
		expect(counts.boss_defeated).toBe(1)
		expect((counts.boss_hit or 0) > 50).toBe(true)
		expect((counts.hero_hit or 0) > 5).toBe(true)
		-- Patterns from both lists fired, including the phase-2-only one.
		local phaseTwoOnly = Bosses.byId.ahriman.patterns[2][4]
		expect((raid.patternsFired[phaseTwoOnly] or 0) > 0).toBe(true)
		expect(r.sim.result ~= nil and r.sim.result >= 1 and r.sim.result <= 4).toBe(true)
	end)

	it("replays exactly from its seed", function()
		local a, b = raidRunner("baphomet", 7), raidRunner("baphomet", 7)
		run(a, 20)
		run(b, 20)
		expect((a.raid :: any).hp).toBe((b.raid :: any).hp)
		expect((a.raid :: any).x).toBe((b.raid :: any).x)
		expect(a.sim.fighters[2].x).toBe(b.sim.fighters[2].x)
	end)

	it("scales boss HP with the number of heroes", function()
		local solo =
			MatchRunner.new({ slots = { { userId = 1, fighterId = "ninja" } }, boss = "ahriman", countdown = 0 })
		local four = raidRunner("ahriman", 1)
		expect((four.raid :: any).maxHp > (solo.raid :: any).maxHp).toBe(true)
	end)

	-- Every pattern of every boss: telegraphed with a real wind-up, then it hurts a hero who just stands there.
	local names = {}
	for name in Bosses.patterns do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		it(`telegraphs and lands pattern {name}`, function()
			local r = MatchRunner.new({
				slots = { { userId = 1, fighterId = "golem" } },
				boss = "ahriman",
				seed = 3,
				countdown = 0,
				arena = "raid_hell",
			})
			local raid = r.raid :: any
			local def = table.clone(raid.def)
			def.patterns = { { name }, { name } }
			raid.def = def
			raid.x = 3
			local windupZones, windupTime = -1, 0
			local hits = 0
			local t = 0
			while t < 14 and hits == 0 do
				for _, e in r:step(STEP) do
					if e.type == "boss_windup" and windupZones < 0 then
						windupZones = #raid.zones
						windupTime = e.time
					elseif e.type == "hero_hit" then
						hits += 1
					end
				end
				t += STEP
			end
			assert(windupZones >= 1, `{name}: no telegraph zone`)
			assert(windupTime >= 0.6, `{name}: wind-up only {windupTime} s`)
			assert(hits > 0, `{name}: never hit a hero standing still`)
		end)
	end

	it("transforms at half HP: phase 2, invulnerable while the shell shatters", function()
		local r = raidRunner("angelus", 2)
		local raid = r.raid :: any
		raid.hp = raid.maxHp * 0.5 - 1
		local counts = run(r, 0.1)
		expect(raid.phase).toBe(2)
		expect(raid.state).toBe("transform")
		expect(counts.boss_phase).toBe(1)
		expect(r.sim.fighters[raid.index].invulnerable > 0).toBe(true)
		local hp = raid.hp
		run(r, 0.8)
		expect(raid.hp).toBe(hp) -- no damage during the transformation
		run(r, Bosses.RAID.TRANSFORM_SECONDS)
		expect(raid.state ~= "transform").toBe(true)
	end)

	it("keeps the boss's stand-in in place, unlaunched and out of the snapshot", function()
		local r = raidRunner("mammon", 4)
		run(r, 15)
		local raid = r.raid :: any
		local standIn = r.sim.fighters[raid.index]
		expect(standIn.x).toBe(raid.x)
		expect(standIn.percent).toBe(0)
		expect(standIn.vx).toBe(0)
		local snap = MatchRunner.decode(r:snapshot())
		expect(#snap.fighters).toBe(4)
		local state = r:modeState() :: any
		local boss = BossFight.decode(state[1])
		expect(boss.bossId).toBe("mammon")
		expect(boss.maxHp).toBe(raid.maxHp)
		expect(#boss.heroes).toBe(4)
	end)

	it("shares the team's lives: downed heroes come back after the timer, then they are out", function()
		local r = MatchRunner.new({
			slots = { { userId = 1, fighterId = "ninja" } },
			boss = "ahriman",
			bossLives = 1,
			countdown = 0,
		})
		local raid = r.raid :: any
		local hero = r.sim.fighters[1]
		hero.x = Arena.BLAST_RIGHT + 2 -- fall out of the arena
		local counts = run(r, 0.1)
		expect(counts.hero_down).toBe(1)
		expect(raid.lives).toBe(0)
		expect(hero.state).toBe("Defeated")
		run(r, Bosses.RAID.RESPAWN_SECONDS + 0.2)
		expect(hero.state ~= "Defeated").toBe(true)
		expect(raid.heroes[1].hp).toBe(raid.heroes[1].maxHp)
		-- Out of HP with the pool empty: out for good, and with nobody left the raid is lost.
		raid.heroes[1].hp = 0.5
		hero.invulnerable = 0
		local t = 0
		while r.sim.result == nil and t < 30 do
			hero.invulnerable, hero.intangible = 0, 0
			r:step(STEP)
			t += STEP
		end
		expect(raid.result).toBe("defeat")
		expect(raid.reason).toBe("wiped")
		expect(r.sim.result).toBe(-1)
	end)

	it("enrages after the enrage timer and loses the raid at the time limit", function()
		local r = raidRunner("lucifer", 5, 4) -- four idle "players": nobody hurts the boss
		local raid = r.raid :: any
		raid.elapsed = Bosses.RAID.ENRAGE_SECONDS - 0.05
		local counts = run(r, 0.2)
		expect(raid.enraged).toBe(true)
		expect(counts.boss_enrage).toBe(1)
		raid.elapsed = Bosses.RAID.TIME_LIMIT - 0.05
		for _, h in raid.heroes do
			h.hp = 9999 -- survive until the clock runs out
		end
		run(r, 1)
		expect(raid.result).toBe("defeat")
		expect(raid.reason).toBe("time")
	end)

	it("pays per boss, with a first-win bonus and title once", function()
		local p = Profile.new()
		local coins = p.coins
		local reward, details =
			ModeRewards.applyRaid(p, "ninja", "lilith", { won = true, phase = 2, damage = 300, downs = 0 })
		expect(details.firstWin).toBe(true)
		expect(details.title).toBe(Bosses.titleFor("lilith"))
		expect(p.coins - coins).toBe(reward.coins)
		expect(p.bossWins.lilith).toBe(1)
		local again = ModeRewards.applyRaid(p, "ninja", "lilith", { won = true, phase = 2, damage = 300, downs = 0 })
		expect(again.coins < reward.coins).toBe(true)
		local loss = ModeRewards.applyRaid(p, "ninja", "lilith", { won = false, phase = 1, damage = 50, downs = 3 })
		expect(loss.coins).toBe(Bosses.REWARD.lossCoins)
		expect(p.bossWins.lilith).toBe(2)
		expect(#ModeRewards.bossTitles(p)).toBe(1)
		-- later bosses pay more
		expect(Bosses.reward("lucifer", true, 2, false).coins > Bosses.reward("ahriman", true, 2, false).coins).toBe(
			true
		)
	end)

	it("migrates old saves to the raid and challenge fields", function()
		local p = Profile.migrate({ coins = 20, bossWins = { ahriman = 2, bad = "x", [3] = 1 }, challengeStreak = 40 })
		expect(p.bossWins.ahriman).toBe(2)
		expect(p.bossWins.bad).toBeNil()
		expect(p.challengeStreak).toBe(7)
		local fresh = Profile.migrate({ coins = 20 })
		expect(fresh.challengeDay).toBe(0)
		expect(next(fresh.bossWins)).toBeNil()
	end)

	it("cycles the bosses in template order and picks the realm's arena", function()
		expect(Bosses.forRound(1)).toBe("ahriman")
		expect(Bosses.forRound(#Bosses.order + 1)).toBe("ahriman")
		expect(Bosses.arenaFor("angelus")).toBe("raid_heaven")
		expect(Bosses.arenaFor("lucifer")).toBe("raid_hell")
		for _, id in Bosses.order do
			local w, h = Bosses.raidBody(id)
			expect(h > 4 and h < 6.5).toBe(true) -- about three fighters tall
			expect(w > 1.5).toBe(true)
		end
	end)
end)
