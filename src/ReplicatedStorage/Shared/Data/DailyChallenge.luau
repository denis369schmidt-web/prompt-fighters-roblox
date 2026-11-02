--!strict
-- Daily Challenge (SPEC 8.7): one challenge per UTC date, the same for everyone (seeded from the day number):
-- a given fighter, opponents, two mutators, a goal and a bot level 4-7. Completing it pays coins once per day,
-- more on a streak (Progression.DAILY_CHALLENGE_REWARD). Pure data and rules; the server (MatchService) runs it,
-- Meta/ModeRewards pays it, the lobby board and HUD show DailyChallenge.describe.

local Arenas = require(script.Parent.Arenas)
local Fighters = require(script.Parent.Fighters)
local Mutators = require(script.Parent.Mutators)
local Progression = require(script.Parent.Progression)
local Visuals = require(script.Parent.Visuals)
local Rng = require(script.Parent.Parent.Util.Rng)

export type Goal = "win" | "fast" | "flawless" | "handicap"

export type Challenge = {
	day: number, -- days since 1970-01-01 (UTC)
	fighter: string,
	opponents: { string },
	mutators: { string },
	goal: Goal,
	botLevel: number,
	arena: string,
	stocks: number,
	teams: { number }?, -- slot teams when the goal needs them (handicap: player alone vs two)
}

export type Outcome = { won: boolean, seconds: number, stocksLost: number }

local DailyChallenge = {}

DailyChallenge.GOALS = {
	win = { text = "Gewinne den Kampf", short = "SIEG" },
	fast = { text = "Gewinne in unter 60 Sekunden", short = "UNTER 60 S", seconds = 60 },
	flawless = { text = "Gewinne ohne einen Stock zu verlieren", short = "OHNE STOCK-VERLUST" },
	handicap = { text = "Gewinne allein gegen zwei", short = "1 GEGEN 2" },
} :: { [Goal]: { text: string, short: string, seconds: number? } }
DailyChallenge.GOAL_ORDER = { "win", "fast", "flawless", "handicap" } :: { Goal }

-- Mutators the challenge rolls (RIESEN / WINZLINGE are left out until body size is drawn, see Combat/MutatorRules).
DailyChallenge.MUTATOR_POOL = {
	"low_gravity",
	"turbo",
	"glass",
	"heavy",
	"sudden_death",
	"super_start",
	"bomb_rain",
	"vampire",
	"swap",
	"escalation",
	"item_rain",
}
DailyChallenge.BOT_LEVELS = { 4, 7 }
DailyChallenge.FAST_SECONDS = 60
DailyChallenge.SECONDS_PER_DAY = 86400

-- Day number of a Unix time (UTC).
function DailyChallenge.dayOf(unixTime: number): number
	return math.floor(unixTime / DailyChallenge.SECONDS_PER_DAY)
end

-- The challenge of a day. Same day -> same challenge, on every server.
function DailyChallenge.forDay(day: number): Challenge
	local rng = Rng.new(day * 7919 + 104729)
	local roster = Visuals.SLICE_FIGHTERS
	local fighter = roster[rng:int(1, #roster)]
	local goal: Goal = (DailyChallenge.GOAL_ORDER[rng:int(1, #DailyChallenge.GOAL_ORDER)] :: any) :: Goal
	local count = if goal == "handicap" or goal == "win" then 2 else 1
	local opponents = {}
	local guard = 0
	while #opponents < count and guard < 50 do
		guard += 1
		local id = roster[rng:int(1, #roster)]
		if id ~= fighter and not table.find(opponents, id) then
			table.insert(opponents, id)
		end
	end
	local mutators = {}
	guard = 0
	while #mutators < 2 and guard < 50 do
		guard += 1
		local id = DailyChallenge.MUTATOR_POOL[rng:int(1, #DailyChallenge.MUTATOR_POOL)]
		local trial = table.clone(mutators)
		table.insert(trial, id)
		-- A flawless run under Sudden Death would be a coin flip: skip that pairing.
		local unfair = goal == "flawless" and id == "sudden_death"
		if not table.find(mutators, id) and Mutators.compatible(trial) and not unfair then
			mutators = trial
		end
	end
	local lo, hi = DailyChallenge.BOT_LEVELS[1], DailyChallenge.BOT_LEVELS[2]
	local arenas = Arenas.voteOptions(rng:int(1, 1000000), 1)
	return {
		day = day,
		fighter = fighter,
		opponents = opponents,
		mutators = mutators,
		goal = goal,
		botLevel = rng:int(lo, hi),
		arena = arenas[1] or Visuals.SLICE_ARENA,
		stocks = if goal == "fast" then 2 else 3,
		teams = if goal == "handicap" then { 1, 2, 2 } else nil,
	}
end

function DailyChallenge.today(unixTime: number): Challenge
	return DailyChallenge.forDay(DailyChallenge.dayOf(unixTime))
end

-- Whether a finished match meets the challenge goal.
function DailyChallenge.check(challenge: Challenge, outcome: Outcome): boolean
	if not outcome.won then
		return false
	end
	local goal = challenge.goal
	if goal == "fast" then
		return outcome.seconds < DailyChallenge.FAST_SECONDS
	elseif goal == "flawless" then
		return outcome.stocksLost == 0
	end
	return true
end

-- Coins for completing the challenge on streak day `streak` (1..7, day 7 also gives a chest).
function DailyChallenge.reward(streak: number): number
	local list = Progression.DAILY_CHALLENGE_REWARD
	return list[math.clamp(streak, 1, #list)]
end

-- What the lobby board and the HUD show (all text German, player-facing).
function DailyChallenge.describe(challenge: Challenge): { [string]: any }
	local goal = DailyChallenge.GOALS[challenge.goal]
	local opponents = {}
	for _, id in challenge.opponents do
		table.insert(opponents, Fighters.get(id).name)
	end
	local mutators = {}
	for _, id in challenge.mutators do
		local m = Mutators.byId[id]
		table.insert(mutators, { id = id, name = m.name, icon = m.icon, text = m.text })
	end
	local arena = Arenas.byId[challenge.arena]
	return {
		day = challenge.day,
		fighter = challenge.fighter,
		fighterName = Fighters.get(challenge.fighter).name,
		opponents = opponents,
		mutators = mutators,
		goal = challenge.goal,
		goalText = goal.text,
		goalShort = goal.short,
		botLevel = challenge.botLevel,
		arena = challenge.arena,
		arenaName = if arena then arena.name else challenge.arena,
		stocks = challenge.stocks,
		rewards = table.clone(Progression.DAILY_CHALLENGE_REWARD),
	}
end

return DailyChallenge
