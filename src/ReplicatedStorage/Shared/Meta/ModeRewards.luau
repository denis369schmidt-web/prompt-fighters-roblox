--!strict
-- Rewards of the modes on top of the normal match reward (Meta/Profile.applyMatch): a Boss-Raid pays XP and coins
-- per boss (Data/Bosses.reward, first victory over a boss: bonus coins and a boss title), the Daily Challenge pays
-- its streak coins once per UTC day (Data/DailyChallenge.reward). Pure rules on a Profile; the server saves.
-- Nothing here can be bought: coins and XP only, no Robux-only power.

local Bosses = require(script.Parent.Parent.Data.Bosses)
local DailyChallenge = require(script.Parent.Parent.Data.DailyChallenge)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local Progression = require(script.Parent.Parent.Data.Progression)
local Profile = require(script.Parent.Profile)

local ModeRewards = {}

export type RaidStats = {
	won: boolean,
	phase: number, -- highest boss phase reached
	damage: number, -- damage dealt to the boss
	downs: number,
}

-- Applies one finished raid. Returns a MatchReward (for the reward card) plus the raid details.
function ModeRewards.applyRaid(
	profile: Profile.Profile,
	fighterId: string,
	bossId: string,
	stats: RaidStats
): (Profile.MatchReward, Bosses.RaidReward)
	local firstWin = stats.won and (profile.bossWins[bossId] or 0) == 0
	local raid = Bosses.reward(bossId, stats.won, stats.phase, firstWin)
	local xp = raid.xp + math.min(60, math.floor(stats.damage / 25))
	local before = profile.level
	Profile.addXp(profile, xp)
	profile.coins += raid.coins
	profile.matches += 1
	if stats.won then
		profile.wins += 1
		profile.bossWins[bossId] = (profile.bossWins[bossId] or 0) + 1
	end
	if Fighters.list and table.find(Fighters.list, Fighters.byId[fighterId]) then
		profile.fighterXp[fighterId] = (profile.fighterXp[fighterId] or 0) + xp
	end
	local points = (if stats.won then 90 else 20) + stats.damage / 6 - stats.downs * 10
	local grade = Progression.grade(points)
	return {
		xp = xp,
		coins = raid.coins,
		grade = grade,
		levelBefore = before,
		levelAfter = profile.level,
		unlockedFighter = nil,
	},
		raid
end

-- Pays the daily challenge once per day. Returns the coins paid (0 if today was already paid) and the streak day.
function ModeRewards.claimDaily(profile: Profile.Profile, day: number): (number, number)
	if profile.challengeDay == day then
		return 0, profile.challengeStreak
	end
	if profile.challengeDay == day - 1 then
		profile.challengeStreak = profile.challengeStreak % #Progression.DAILY_CHALLENGE_REWARD + 1
	else
		profile.challengeStreak = 1
	end
	profile.challengeDay = day
	local coins = DailyChallenge.reward(profile.challengeStreak)
	profile.coins += coins
	return coins, profile.challengeStreak
end

-- Whether the player already completed the challenge of `day`.
function ModeRewards.dailyDone(profile: Profile.Profile, day: number): boolean
	return profile.challengeDay == day
end

-- Boss titles the player earned (first victory over each boss), in raid order.
function ModeRewards.bossTitles(profile: Profile.Profile): { string }
	local out = {}
	for _, id in Bosses.order do
		if (profile.bossWins[id] or 0) > 0 then
			table.insert(out, Bosses.titleFor(id))
		end
	end
	return out
end

return ModeRewards
