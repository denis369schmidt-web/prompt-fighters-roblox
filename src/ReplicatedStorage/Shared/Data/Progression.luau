--!strict
-- Progression values (from progression.gd / rewards.gd) and the pure formulas that read them.

local ProgressionData = require(script.Parent.Generated.ProgressionData)

local Progression = {}

-- Player level: XP needed from `level` to `level + 1`.
function Progression.xpToNext(level: number): number
	return 120 + (level - 1) * 45
end

Progression.TITLES = {
	{ level = 1, title = "REKRUT" },
	{ level = 5, title = "KÄMPFER" },
	{ level = 10, title = "VETERAN" },
	{ level = 15, title = "CHAMPION" },
	{ level = 20, title = "MEISTER" },
	{ level = 30, title = "GROSSMEISTER" },
	{ level = 40, title = "LEGENDE" },
	{ level = 50, title = "MYTHOS" },
}

function Progression.titleForLevel(level: number): string
	local title = Progression.TITLES[1].title
	for _, entry in Progression.TITLES do
		if level >= entry.level then
			title = entry.title
		end
	end
	return title
end

-- Fighter mastery: stars at these fighter-XP totals.
Progression.MASTERY_STARS = { 150, 500, 1200, 2500, 5000 }

function Progression.masteryStars(fighterXp: number): number
	local stars = 0
	for _, threshold in Progression.MASTERY_STARS do
		if fighterXp >= threshold then
			stars += 1
		end
	end
	return stars
end

-- Battle grade from match points, with its coin multiplier.
Progression.GRADES = {
	{ grade = "S", minPoints = 150, coinMult = 1.5 },
	{ grade = "A", minPoints = 100, coinMult = 1.25 },
	{ grade = "B", minPoints = 60, coinMult = 1.1 },
	{ grade = "C", minPoints = 30, coinMult = 1.0 },
	{ grade = "D", minPoints = -math.huge, coinMult = 0.9 },
}

function Progression.grade(points: number): (string, number)
	for _, entry in Progression.GRADES do
		if points >= entry.minPoints then
			return entry.grade, entry.coinMult
		end
	end
	error("unreachable")
end

-- Daily (XP) and weekly (coins) challenges and the achievement list come from Godot (Generated/ProgressionData).
Progression.DAILY_QUESTS = (
	ProgressionData.daily :: any
) :: { [string]: { text: string, goal: number, xp: number, max: boolean? } }
Progression.DAILY_QUESTS_PER_DAY = 3
Progression.DAILY_ALL_BONUS_XP = 200
Progression.WEEKLY_QUESTS = ProgressionData.weekly :: { [string]: { text: string, goal: number, coins: number } }
Progression.WEEKLY_QUESTS_PER_WEEK = 3
Progression.ACHIEVEMENTS =
	ProgressionData.achievements :: { [string]: { title: string, text: string, stat: string, need: number } }

-- 7-day login calendar; day 7 also gives a chest. A missed day restarts at day 1.
Progression.LOGIN_CALENDAR = { 50, 75, 100, 125, 150, 200, 300 }
Progression.COMEBACK_AFTER_DAYS = 3

-- Free track of the Glory Path (Ruhmespfad).
Progression.GLORY_XP_PER_TIER = 400
Progression.GLORY_FREE_TIERS = 30
Progression.GLORY_FREE_SPECIAL = {
	[10] = { kind = "weapon", id = "shadow_katana" },
	[15] = { kind = "skin", id = "celestial" },
	[20] = { kind = "weapon", id = "dragon_lance" },
	[30] = { kind = "skin", id = "infernal" },
}

function Progression.gloryFreeReward(tier: number): { kind: string, id: string?, coins: number? }
	local special = Progression.GLORY_FREE_SPECIAL[tier]
	if special then
		return special
	end
	if tier % 5 == 0 then
		return { kind = "chest" }
	end
	return { kind = "coins", coins = 80 + tier * 10 }
end

-- Coins for one match. Bonuses (VIP +0.1, Doppelte Münzen +1.0, event +0.5 ...) ADD up instead of
-- multiplying, so stacked passes stay predictable for the economy. Grade multiplier applies on top.
function Progression.matchCoins(base: number, gradeMult: number, bonuses: { number }): number
	local total = 1
	for _, bonus in bonuses do
		total += bonus
	end
	return math.floor(base * gradeMult * total + 0.5)
end

-- Daily challenge coins by streak day (day 7 also gives a chest).
Progression.DAILY_CHALLENGE_REWARD = { 120, 150, 180, 220, 260, 320, 500 }
Progression.CHALLENGER_CHANCE = 0.18
-- Every 3rd win unlocks the next locked fighter.
Progression.WINS_PER_FIGHTER_UNLOCK = 3

return Progression
