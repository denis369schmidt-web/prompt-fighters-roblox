--!strict
-- A player's saved progress and the pure rules that change it: match rewards (XP, coins, grade, level ups,
-- free fighter unlocks every few wins), the 7-day login calendar, buying fighters and cosmetics with coins and
-- equipping cosmetics (Data/Cosmetics). Robux purchases are applied by Meta/Purchases.
-- No Roblox services here: the server (Server/Data/PlayerData) loads and saves, tests call these directly.

local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
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
	-- v3: shop
	cosmetics: { [string]: boolean }, -- owned cosmetic ids (Data/Cosmetics)
	equippedSkins: { [string]: string }, -- fighter id -> skin id
	equippedKo: string, -- KO effect id ("" = Cosmetics.DEFAULT_KO)
	equippedPlate: string, -- name plate id ("" = none, the level title shows)
	purchases: { [string]: number }, -- Robux receipt PurchaseId -> os.time() when granted (idempotency)
	vouchers: { [string]: number }, -- "fighter:<maxPrice>" / "skin:<maxPrice>" -> count (choice products)
	choices: { [string]: string }, -- product id -> what the player picked before the purchase dialog
	items: { [string]: boolean }, -- "arena:<id>" / "weapon:<id>" from bundles, for systems that come later
	entitlements: { [string]: number }, -- bought counts: "once:<product>", seasonPremium, seasonTiers, ...
	firstSeen: number, -- os.time() of the first join (starter pack window)
	weekKey: number, -- week (Meta/Leaderboards.weekKey) that weekWins counts
	weekWins: number, -- wins in that week (weekly leaderboard)
	groupBonus: boolean, -- the one-time group-join coin bonus was paid
	settings: Settings,
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

-- v2: promptFighters. v3: cosmetics, equipped*, purchases, vouchers, choices, items, entitlements, firstSeen
-- (shop) and weekKey, weekWins, groupBonus, settings (leaderboards, settings panel).
Profile.VERSION = 3
-- Receipt ids kept for idempotency (oldest dropped first). Roblox retries only receipts we never granted.
Profile.MAX_PURCHASES = 200
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
		cosmetics = {},
		equippedSkins = {},
		equippedKo = "",
		equippedPlate = "",
		purchases = {},
		vouchers = {},
		choices = {},
		items = {},
		entitlements = {},
		firstSeen = 0,
		weekKey = 0,
		weekWins = 0,
		groupBonus = false,
		settings = Profile.defaultSettings(),
	}
end

-- Keeps only entries with the right key and value types (and, if given, keys that pass `keep`).
local function cleanMap(map: { [any]: any }, valueType: string, keep: ((key: string, value: any) -> boolean)?): any
	local out = {}
	for k, v in map do
		if type(k) == "string" and type(v) == valueType and (keep == nil or keep(k, v)) then
			out[k] = v
		end
	end
	return out
end

local function finite(_key: string, v: number): boolean
	return v == v and v > -math.huge and v < math.huge
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
	-- Shop fields: unknown cosmetics and broken entries are dropped; equipped items must still be owned.
	fresh.cosmetics = cleanMap(fresh.cosmetics, "boolean", function(id, v)
		return v and Cosmetics.byId[id] ~= nil
	end)
	fresh.purchases = cleanMap(fresh.purchases, "number", finite)
	fresh.vouchers = cleanMap(fresh.vouchers, "number", function(_k, v)
		return finite(_k, v) and v >= 1
	end)
	fresh.choices = cleanMap(fresh.choices, "string")
	fresh.items = cleanMap(fresh.items, "boolean")
	fresh.entitlements = cleanMap(fresh.entitlements, "number", finite)
	if fresh.firstSeen ~= fresh.firstSeen or fresh.firstSeen < 0 then
		fresh.firstSeen = 0
	end
	local skins = cleanMap(fresh.equippedSkins, "string")
	fresh.equippedSkins = {}
	for fighterId, skinId in skins do
		local skin = Cosmetics.skin(skinId)
		if skin and Cosmetics.fits(skin, fighterId) and fresh.cosmetics[skinId] then
			fresh.equippedSkins[fighterId] = skinId
		end
	end
	if not Profile.ownsCosmetic(fresh, fresh.equippedKo) or (Cosmetics.byId[fresh.equippedKo] :: any).kind ~= "ko" then
		fresh.equippedKo = ""
	end
	local plate = Cosmetics.byId[fresh.equippedPlate]
	if plate == nil or plate.kind ~= "plate" or not fresh.cosmetics[fresh.equippedPlate] then
		fresh.equippedPlate = ""
	end
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

-- Default cosmetics (the classic KO effect) belong to everyone; pass-bound ones need `passes[pass]`.
function Profile.ownsCosmetic(profile: Profile, id: string, passes: { [string]: boolean }?): boolean
	local item = Cosmetics.byId[id]
	if item == nil then
		return false
	end
	if item.kind == "ko" and id == Cosmetics.DEFAULT_KO then
		return true
	end
	local pass = (item :: any).pass
	if pass and passes and passes[pass] then
		return true
	end
	return profile.cosmetics[id] == true
end

-- Buys a cosmetic with coins. Returns ok and, if not ok, a reason for the player.
function Profile.buyCosmetic(profile: Profile, id: string): (boolean, string?)
	local item = Cosmetics.byId[id]
	if item == nil then
		return false, "Nicht im Shop"
	end
	if Profile.ownsCosmetic(profile, id) then
		return false, "Hast du schon"
	end
	if item.coins == nil or (item.coins :: number) <= 0 then
		return false, "Nicht für Münzen"
	end
	local price = item.coins :: number
	if profile.coins < price then
		return false, `Dir fehlen {price - profile.coins} Münzen`
	end
	profile.coins -= price
	profile.cosmetics[id] = true
	return true, nil
end

-- Equips a cosmetic. kind: "skin" (for fighterId), "ko" or "plate"; id "" goes back to the default.
function Profile.equip(
	profile: Profile,
	kind: string,
	fighterId: string,
	id: string,
	passes: { [string]: boolean }?
): (boolean, string?)
	if kind == "skin" then
		if Fighters.byId[fighterId] == nil or table.find(Visuals.SLICE_FIGHTERS, fighterId) == nil then
			return false, "Unbekannter Kämpfer"
		end
		if id == "" then
			profile.equippedSkins[fighterId] = nil
			return true, nil
		end
		local skin = Cosmetics.skin(id)
		if skin == nil or not Cosmetics.fits(skin, fighterId) then
			return false, "Passt nicht zu diesem Kämpfer"
		end
		if not Profile.ownsCosmetic(profile, id, passes) then
			return false, "Noch nicht gekauft"
		end
		profile.equippedSkins[fighterId] = id
		return true, nil
	elseif kind == "ko" or kind == "plate" then
		local item = Cosmetics.byId[id]
		if id ~= "" and (item == nil or item.kind ~= kind) then
			return false, "Unbekannt"
		end
		if id ~= "" and not Profile.ownsCosmetic(profile, id, passes) then
			return false, "Noch nicht gekauft"
		end
		if kind == "ko" then
			profile.equippedKo = if id == Cosmetics.DEFAULT_KO then "" else id
		else
			profile.equippedPlate = id
		end
		return true, nil
	end
	return false, "Unbekannt"
end

-- Equipped skin of a fighter (nil = normal look) and equipped KO effect (nil = classic), for match setup.
function Profile.equippedSkin(profile: Profile, fighterId: string): string?
	local id = profile.equippedSkins[fighterId]
	return if id and profile.cosmetics[id] then id else nil
end

function Profile.equippedKoEffect(profile: Profile): string?
	return if profile.equippedKo ~= "" then profile.equippedKo else nil
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

-- Applies one finished match to the profile and returns what the player got. bonuses: additive coin bonuses
-- (game passes), xpBonus: additive XP bonus (Doppelte XP = 1); coins are always based on the XP before it.
function Profile.applyMatch(
	profile: Profile,
	fighterId: string,
	stats: MatchStats,
	bonuses: { number }?,
	xpBonus: number?
): MatchReward
	local grade, mult = Progression.grade(Profile.points(stats))
	local baseXp = Profile.matchXp(stats)
	local xp = math.floor(baseXp * (1 + (xpBonus or 0)) + 0.5)
	local coins = Progression.matchCoins(baseXp / 4, mult, bonuses or {})
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
	local cosmetics = {}
	for id in profile.cosmetics do
		table.insert(cosmetics, id)
	end
	table.sort(cosmetics)
	local plate = Cosmetics.byId[profile.equippedPlate]
	return {
		coins = profile.coins,
		level = profile.level,
		xp = profile.xp,
		xpNext = Progression.xpToNext(profile.level),
		-- An equipped name plate replaces the level title.
		title = if plate and plate.kind == "plate" then plate.title else Progression.titleForLevel(profile.level),
		frame = if plate and plate.kind == "plate" then plate.frame else nil,
		cosmetics = cosmetics,
		equippedSkins = table.clone(profile.equippedSkins),
		equippedKo = if profile.equippedKo ~= "" then profile.equippedKo else Cosmetics.DEFAULT_KO,
		equippedPlate = profile.equippedPlate,
		vouchers = table.clone(profile.vouchers),
		wins = profile.wins,
		owned = owned,
		winsToUnlock = Progression.WINS_PER_FIGHTER_UNLOCK - profile.wins % Progression.WINS_PER_FIGHTER_UNLOCK,
		prompts = table.clone(profile.promptFighters),
		settings = table.clone(profile.settings),
	}
end

return Profile
