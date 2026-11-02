--!strict
-- A player's saved progress and the pure rules that change it: match rewards (XP, coins, grade, level ups,
-- free fighter unlocks every few wins), the 7-day login calendar and buying fighters with coins.
-- No Roblox services here: the server (Server/Data/PlayerData) loads and saves, tests call these directly.

local Constants = require(script.Parent.Parent.Data.Constants)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local PromptCode = require(script.Parent.Parent.Prompt.Code)
local Progression = require(script.Parent.Parent.Data.Progression)
local Visuals = require(script.Parent.Parent.Data.Visuals)

export type Profile = {
	version: number,
	coins: number,
	xp: number, -- XP inside the current level
	level: number,
	wins: number,
	matches: number,
	kos: number,
	unlocked: { [string]: boolean },
	fighterXp: { [string]: number },
	loginDay: number, -- day number (days since 1970) of the last login reward
	loginStreak: number, -- 1..7, day of the login calendar reached
	promptFighters: { string }, -- share codes of the last prompt fighters (Prompt/Code), newest first
	weekKey: number, -- week (Meta/Leaderboards.weekKey) that weekWins counts
	weekWins: number, -- wins in that week (weekly leaderboard)
	groupBonus: boolean, -- the one-time group-join coin bonus was paid
	settings: Settings,
	-- Daily Challenge and Boss-Raid (Meta/ModeRewards); older saves get the defaults through migrate
	challengeDay: number, -- day number of the last completed daily challenge (paid once per day)
	challengeStreak: number, -- 1..7, streak day reached
	bossWins: { [string]: number }, -- boss id -> raid victories (the first one pays a bonus and a title)
}

-- Player options from the settings panel (UI/Settings), applied on the client.
export type Settings = {
	reduceShake: boolean, -- Kamera-Wackeln reduzieren
	sound: boolean, -- Sound an/aus
	lowParticles: boolean, -- Grafik: weniger Partikel
}

export type MatchStats = {
	won: boolean,
	place: number, -- 1 = winner
	kos: number,
	damage: number,
	finishers: number,
	stocksLost: number,
	bestCombo: number,
}

export type MatchReward = {
	xp: number,
	coins: number,
	grade: string,
	levelBefore: number,
	levelAfter: number,
	unlockedFighter: string?,
}

local Profile = {}

-- v2: promptFighters
Profile.VERSION = 2
Profile.START_COINS = 150
Profile.PROMPT_HISTORY = 3

function Profile.defaultSettings(): Settings
	return { reduceShake = false, sound = true, lowParticles = false }
end

function Profile.new(): Profile
	return {
		version = Profile.VERSION,
		coins = Profile.START_COINS,
		xp = 0,
		level = 1,
		wins = 0,
		matches = 0,
		kos = 0,
		unlocked = {},
		fighterXp = {},
		loginDay = 0,
		loginStreak = 0,
		promptFighters = {},
		challengeDay = 0,
		challengeStreak = 0,
		bossWins = {},
		weekKey = 0,
		weekWins = 0,
		groupBonus = false,
		settings = Profile.defaultSettings(),
	}
end

-- Fills fields missing in an older or damaged save with defaults and drops wrong types.
function Profile.migrate(data: any): Profile
	local fresh = Profile.new()
	if type(data) ~= "table" then
		return fresh
	end
	for key, default in fresh :: any do
		local value = data[key]
		if type(value) == type(default) then
			(fresh :: any)[key] = value
		end
	end
	-- Only well-formed codes survive (the list is shown and rebuilt on the client).
	local codes: { string } = {}
	for _, code in fresh.promptFighters do
		if type(code) == "string" and PromptCode.normalize(code) == code and #codes < Profile.PROMPT_HISTORY then
			table.insert(codes, code)
		end
	end
	fresh.promptFighters = codes
	-- Raid victories: only whole, positive counts under string keys survive.
	local wins: { [string]: number } = {}
	for id, count in fresh.bossWins do
		if type(id) == "string" and type(count) == "number" and count >= 1 then
			wins[id] = math.floor(count)
		end
	end
	fresh.bossWins = wins
	fresh.challengeStreak = math.clamp(math.floor(fresh.challengeStreak), 0, 7)
	-- Settings: known keys with the right type survive, the rest falls back to the defaults.
	local settings = Profile.defaultSettings()
	local savedSettings = if type(data.settings) == "table" then data.settings else {}
	for key, default in settings :: any do
		if type(savedSettings[key]) == type(default) then
			(settings :: any)[key] = savedSettings[key]
		end
	end
	fresh.settings = settings
	fresh.weekWins = math.max(0, math.floor(fresh.weekWins))
	fresh.version = Profile.VERSION
	fresh.level = math.max(1, math.floor(fresh.level))
	fresh.coins = math.max(0, math.floor(fresh.coins))
	return fresh
end

-- Counts a win for the weekly leaderboard; a new week starts again at 0.
function Profile.addWeeklyWin(profile: Profile, week: number)
	if profile.weekKey ~= week then
		profile.weekKey = week
		profile.weekWins = 0
	end
	profile.weekWins += 1
end

-- One-time coin bonus for joining the Roblox group (the server checks the membership). Returns the coins paid.
function Profile.claimGroupBonus(profile: Profile): number
	if profile.groupBonus then
		return 0
	end
	profile.groupBonus = true
	profile.coins += Constants.GROUP_BONUS_COINS
	return Constants.GROUP_BONUS_COINS
end

-- Changes one setting from the settings panel. Unknown keys and wrong types are refused.
function Profile.setSetting(profile: Profile, key: string, value: any): boolean
	local defaults = Profile.defaultSettings() :: any
	if type(key) ~= "string" or defaults[key] == nil or type(value) ~= type(defaults[key]) then
		return false
	end
	(profile.settings :: any)[key] = value
	return true
end

-- Remembers a prompt fighter by its share code (newest first, at most PROMPT_HISTORY, no duplicates).
function Profile.addPromptFighter(profile: Profile, code: string): boolean
	if PromptCode.normalize(code) ~= code then
		return false
	end
	local at = table.find(profile.promptFighters, code)
	if at then
		table.remove(profile.promptFighters, at)
	end
	table.insert(profile.promptFighters, 1, code)
	while #profile.promptFighters > Profile.PROMPT_HISTORY do
		table.remove(profile.promptFighters)
	end
	return true
end

-- Starter fighters are always usable; the others once unlocked (coins or free unlock).
function Profile.owns(profile: Profile, fighterId: string): boolean
	local def = Fighters.byId[fighterId]
	if def == nil then
		return false
	end
	return def.unlock.kind == "starter" or profile.unlocked[fighterId] == true
end

function Profile.price(fighterId: string): number?
	local def = Fighters.byId[fighterId]
	if def and def.unlock.kind == "coins" then
		return (def.unlock :: any).price
	end
	return nil
end

-- Buys a fighter with coins. Returns ok and, if not ok, a reason for the player.
function Profile.buyFighter(profile: Profile, fighterId: string): (boolean, string?)
	if Profile.owns(profile, fighterId) then
		return false, "Hast du schon"
	end
	local found = Profile.price(fighterId)
	if found == nil or table.find(Visuals.SLICE_FIGHTERS, fighterId) == nil then
		return false, "Nicht im Shop"
	end
	local price = found :: number
	if profile.coins < price then
		return false, `Dir fehlen {price - profile.coins} Münzen`
	end
	profile.coins -= price
	profile.unlocked[fighterId] = true
	return true, nil
end

-- The cheapest launch fighter the player does not own yet (free unlock every few wins).
function Profile.nextLocked(profile: Profile): string?
	local best, bestPrice = nil, math.huge
	for _, id in Visuals.SLICE_FIGHTERS do
		local price = Profile.price(id)
		if price and not Profile.owns(profile, id) and price < bestPrice then
			best, bestPrice = id, price
		end
	end
	return best
end

-- Match points for the battle grade: winning, KOs, damage and finishers count, lost stocks cost a little.
function Profile.points(stats: MatchStats): number
	return (if stats.won then 60 else 0)
		+ stats.kos * 25
		+ stats.damage / 4
		+ stats.finishers * 20
		+ stats.bestCombo * 3
		- stats.stocksLost * 5
end

-- XP for one match: everyone gets a base for playing, the rest for doing well (75..215 for typical matches).
function Profile.matchXp(stats: MatchStats): number
	local xp = 60 + stats.kos * 15 + math.floor(stats.damage / 10) + stats.finishers * 25
	if stats.won then
		xp += 50
	elseif stats.place == 2 then
		xp += 20
	end
	return math.min(xp, 260)
end

function Profile.addXp(profile: Profile, amount: number)
	profile.xp += amount
	while profile.xp >= Progression.xpToNext(profile.level) do
		profile.xp -= Progression.xpToNext(profile.level)
		profile.level += 1
	end
end

-- Applies one finished match to the profile and returns what the player got.
function Profile.applyMatch(profile: Profile, fighterId: string, stats: MatchStats, bonuses: { number }?): MatchReward
	local grade, mult = Progression.grade(Profile.points(stats))
	local xp = Profile.matchXp(stats)
	local coins = Progression.matchCoins(xp / 4, mult, bonuses or {})
	local before = profile.level
	Profile.addXp(profile, xp)
	profile.coins += coins
	profile.matches += 1
	profile.kos += stats.kos
	-- Mastery is for roster fighters; prompt fighters (runtime ids) would grow the save without end.
	if Fighters.list and table.find(Fighters.list, Fighters.byId[fighterId]) then
		profile.fighterXp[fighterId] = (profile.fighterXp[fighterId] or 0) + xp
	end
	local unlocked: string? = nil
	if stats.won then
		profile.wins += 1
		if profile.wins % Progression.WINS_PER_FIGHTER_UNLOCK == 0 then
			unlocked = Profile.nextLocked(profile)
			if unlocked then
				profile.unlocked[unlocked] = true
			end
		end
	end
	return {
		xp = xp,
		coins = coins,
		grade = grade,
		levelBefore = before,
		levelAfter = profile.level,
		unlockedFighter = unlocked,
	}
end

-- Login calendar: the first login of a day pays that day's coins; a missed day restarts at day 1.
-- Returns the coins paid (0 if today was already paid) and the calendar day.
function Profile.dailyLogin(profile: Profile, today: number): (number, number)
	if profile.loginDay == today then
		return 0, profile.loginStreak
	end
	if profile.loginDay == today - 1 then
		profile.loginStreak = profile.loginStreak % #Progression.LOGIN_CALENDAR + 1
	else
		profile.loginStreak = 1
	end
	profile.loginDay = today
	local coins = Progression.LOGIN_CALENDAR[profile.loginStreak]
	profile.coins += coins
	return coins, profile.loginStreak
end

-- What the client shows: coins, level, XP bar and owned launch fighters.
function Profile.view(profile: Profile): { [string]: any }
	local owned = {}
	for _, id in Visuals.SLICE_FIGHTERS do
		if Profile.owns(profile, id) then
			table.insert(owned, id)
		end
	end
	return {
		coins = profile.coins,
		level = profile.level,
		xp = profile.xp,
		xpNext = Progression.xpToNext(profile.level),
		title = Progression.titleForLevel(profile.level),
		wins = profile.wins,
		owned = owned,
		winsToUnlock = Progression.WINS_PER_FIGHTER_UNLOCK - profile.wins % Progression.WINS_PER_FIGHTER_UNLOCK,
		prompts = table.clone(profile.promptFighters),
		challengeDay = profile.challengeDay,
		challengeStreak = profile.challengeStreak,
		bossWins = table.clone(profile.bossWins),
		settings = table.clone(profile.settings),
	}
end

return Profile
