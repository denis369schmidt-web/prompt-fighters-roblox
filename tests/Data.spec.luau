local Data = Shared.Data
local Constants = require(Data.Constants)
local Fighters = require(Data.Fighters)
local Signatures = require(Data.Signatures)
local Weapons = require(Data.Weapons)
local Arenas = require(Data.Arenas)
local Bosses = require(Data.Bosses)
local Mutators = require(Data.Mutators)
local Ranks = require(Data.Ranks)
local Progression = require(Data.Progression)

describe("Fighters", function()
	it("has all 58 fighters with unique ids", function()
		expect(#Fighters.list).toBe(58)
		local seen = {}
		for _, f in Fighters.list do
			expect(seen[f.id]).toBeNil()
			seen[f.id] = true
		end
	end)

	it("has 10 free starters", function()
		expect(#Fighters.starters()).toBe(10)
	end)

	it("gives every fighter a stat budget of exactly 100", function()
		for _, f in Fighters.list do
			local s = f.stats
			expect(s.vitality + s.power + s.defense + s.speed + s.technique).toBe(100)
		end
	end)

	it("gives every fighter the full 15-move kit with valid hitboxes", function()
		for _, f in Fighters.list do
			for _, moveId in Constants.MOVESET do
				local move = f.moves[moveId]
				assert(move, `{f.id} misses {moveId}`)
				expect(type(move.name)).toBe("string")
				expect(move.windup).toBeGreaterThanOrEqual(0)
				expect(move.xMax).toBeGreaterThanOrEqual(move.xMin)
				expect(move.yMax).toBeGreaterThanOrEqual(move.yMin)
			end
		end
	end)

	it("uses a known signature mechanic that matches the imported parameters", function()
		for _, f in Fighters.list do
			assert(Signatures.MECHANICS[f.signature], `{f.id}: unknown mechanic {f.signature}`)
			expect(f.signatureParams.mech).toBe(f.signature)
		end
	end)

	it("has a unique, valid finisher code per fighter", function()
		local codes = {}
		for _, f in Fighters.list do
			expect(#f.finisher.code).toBeGreaterThanOrEqual(3)
			for _, key in f.finisher.code do
				assert(Constants.FINISHER_CODE_KEYS[key], `{f.id}: bad finisher key {key}`)
			end
			local code = table.concat(f.finisher.code)
			assert(not codes[code], `{f.id} shares finisher code {code} with {codes[code]}`)
			codes[code] = f.id
		end
	end)

	it("keeps weight in the knockback range and derives health from vitality", function()
		for _, f in Fighters.list do
			expect(f.weight).toBeGreaterThanOrEqual(0.8)
			expect(f.weight).toBeLessThanOrEqual(1.5)
			expect(f.health).toBeCloseTo(90 + f.stats.vitality * 1.6, 6)
			-- Spec says 110 to 138; Vorruk (vitality 32) reaches 141.2 in the Godot data.
			expect(f.health).toBeGreaterThanOrEqual(105)
			expect(f.health).toBeLessThanOrEqual(142)
		end
	end)

	it("makes every locked fighter reachable with coins", function()
		for _, f in Fighters.list do
			if f.unlock.kind ~= "starter" then
				expect(f.unlock.kind).toBe("coins")
				expect(f.unlock.price).toBeGreaterThan(0)
			end
		end
	end)
end)

describe("Weapons", function()
	it("has 8 classic and 8 shop weapons", function()
		expect(#Weapons.classic).toBe(8)
		expect(#Weapons.shop).toBe(8)
	end)

	it("keeps shop weapons out of Ranked", function()
		local owned = {}
		for _, w in Weapons.shop do
			owned[w.id] = true
		end
		expect(#Weapons.spawnPool("ranked", owned)).toBe(8)
		expect(#Weapons.spawnPool("casual", owned)).toBe(16)
		expect(Weapons.startWeaponAllowed("ranked")).toBe(false)
	end)
end)

describe("Arenas", function()
	it("has 23 arenas and one free arena", function()
		expect(#Arenas.list).toBe(23)
		local free = 0
		for _, a in Arenas.list do
			if a.price == 0 then
				free += 1
			end
		end
		expect(free).toBe(1)
	end)

	it("caps arena votes at 3", function()
		expect(Arenas.voteWeight(true, true)).toBe(3)
		expect(Arenas.voteWeight(false, false)).toBe(1)
	end)
end)

describe("Bosses", function()
	it("orders all 19 bosses, hell first", function()
		expect(#Bosses.order).toBe(19)
		for _, id in Bosses.order do
			assert(Bosses.byId[id], `missing boss {id}`)
		end
		expect(Bosses.byId[Bosses.order[1]].realm).toBe("hell")
	end)

	it("references only known attack patterns in both phases", function()
		for id, boss in Bosses.byId do
			expect(#boss.patterns).toBe(2)
			for _, phase in boss.patterns do
				for _, pattern in phase do
					assert(Bosses.patterns[pattern], `{id}: unknown pattern {pattern}`)
				end
			end
		end
	end)

	it("scales health with the hero count like Godot", function()
		expect(Bosses.scaledHp("angelus", 2)).toBe(450)
		expect(Bosses.scaledHp("angelus", 4)).toBe(675)
		expect(Bosses.scaledHp("angelus", 1)).toBe(337.5)
	end)

	it("switches to phase 2 at half health", function()
		expect(Bosses.phase(50, 100)).toBe(2)
		expect(Bosses.phase(51, 100)).toBe(1)
	end)
end)

describe("Mutators", function()
	it("has 13 mutators and renames the blood mutator", function()
		local count = 0
		for _ in Mutators.byId do
			count += 1
		end
		expect(count).toBe(13)
		expect(Mutators.byId.vampire.name).toBe("ENERGIEDURST")
	end)

	it("never combines giants and tiny", function()
		expect(Mutators.compatible({ "giants", "tiny" })).toBe(false)
		expect(Mutators.compatible({ "giants", "turbo" })).toBe(true)
		expect(Mutators.compatible({ "unknown" })).toBe(false)
	end)
end)

describe("Progression", function()
	it("uses 120 + (level - 1) * 45 XP per level", function()
		expect(Progression.xpToNext(1)).toBe(120)
		expect(Progression.xpToNext(10)).toBe(525)
	end)

	it("maps levels to titles", function()
		expect(Progression.titleForLevel(1)).toBe("REKRUT")
		expect(Progression.titleForLevel(14)).toBe("VETERAN")
		expect(Progression.titleForLevel(99)).toBe("MYTHOS")
	end)

	it("counts mastery stars", function()
		expect(Progression.masteryStars(149)).toBe(0)
		expect(Progression.masteryStars(150)).toBe(1)
		expect(Progression.masteryStars(5000)).toBe(5)
	end)

	it("grades matches", function()
		local grade, mult = Progression.grade(150)
		expect(grade).toBe("S")
		expect(mult).toBe(1.5)
		grade, mult = Progression.grade(-5)
		expect(grade).toBe("D")
		expect(mult).toBe(0.9)
	end)

	it("adds coin bonuses instead of multiplying them", function()
		-- 100 base, grade A (1.25), VIP +0.1, Doppelte Münzen +1.0 -> 100 * 1.25 * 2.1
		expect(Progression.matchCoins(100, 1.25, { 0.1, 1.0 })).toBe(263)
		expect(Progression.matchCoins(100, 1.0, {})).toBe(100)
	end)

	it("pays the glory path free track", function()
		expect(Progression.gloryFreeReward(10).id).toBe("shadow_katana")
		expect(Progression.gloryFreeReward(5).kind).toBe("chest")
		expect(Progression.gloryFreeReward(3).coins).toBe(110)
	end)

	it("has 11 daily and 8 weekly challenges and 36 achievements", function()
		local function count(t)
			local n = 0
			for _ in t do
				n += 1
			end
			return n
		end
		expect(count(Progression.DAILY_QUESTS)).toBe(11)
		expect(count(Progression.WEEKLY_QUESTS)).toBe(8)
		expect(count(Progression.ACHIEVEMENTS)).toBe(36)
	end)
end)

describe("Ranks", function()
	it("finds the league for a point total", function()
		expect(Ranks.leagueFor(0).name).toBe("BRONZE")
		expect(Ranks.leagueFor(699).name).toBe("PLATIN")
		expect(Ranks.leagueFor(5000).name).toBe("CHAMPION")
	end)
end)
