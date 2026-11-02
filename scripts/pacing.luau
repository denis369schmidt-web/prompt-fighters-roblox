--!strict
-- Match pacing check: seeded bot-vs-bot free-for-alls with the live match setup (4 slots, launch roster,
-- arena pool, bot lineup around a base level) and a summary of how they end.
--
--   lune run scripts/pacing.luau [matches=24] [baseLevel=3] [stocks] [timeLimit] [maxLaunch]
--
-- Reports match length (after the countdown), how many matches hit the time limit, went to Sudden Death,
-- and the KOs per match. Target (docs/DECISIONS.md): most matches end by KOs in about 60-120 s.

local process = require("@lune/process")

local Loader = require("../tests/runtime/Loader")

local Shared = Loader.mount("src/ReplicatedStorage/Shared")
Loader.provide("ReplicatedStorage", { Shared = Shared })

local Arenas = Loader.require(Shared.Data.Arenas) :: any
local Bot = Loader.require(Shared.Combat.Bot) :: any
local Constants = Loader.require(Shared.Data.Constants) :: any
local MatchRunner = Loader.require(Shared.Combat.MatchRunner) :: any
local Visuals = Loader.require(Shared.Data.Visuals) :: any

local count = tonumber(process.args[1]) or 24
local base = tonumber(process.args[2]) or 3
local stocks = tonumber(process.args[3])
local timeLimit = tonumber(process.args[4])
-- Optional tuning override for experiments (Constants.MAX_LAUNCH).
Constants.MAX_LAUNCH = tonumber(process.args[5]) or Constants.MAX_LAUNCH

local durations: { number } = {}
local timeUps, sudden, totalKos = 0, 0, 0
local koPercentSum, koCount, damageSum, secondsSum = 0, 0, 0, 0
local slots = Constants.MAX_PLAYERS
for m = 1, count do
	local seed = 1000 + m * 37
	local pool = Visuals.SLICE_FIGHTERS
	local list = {}
	for k = 1, slots do
		list[k] = { userId = nil, fighterId = pool[(seed + k * 3) % #pool + 1] }
	end
	local arena = Arenas.list[(seed % #Arenas.list) + 1].id
	local runner = MatchRunner.new({
		slots = list,
		botLevel = base,
		botLevels = Bot.lineup(base, slots),
		seed = seed,
		arena = arena,
		countdown = 0,
		stocks = stocks,
		timeLimit = timeLimit,
	})
	local sim = runner.sim
	local limit = sim.timeLeft
	local wentSudden = false
	local frames = 0
	local lastPercent: { number } = {}
	while sim.result == nil and frames < 60 * 300 do
		for i, f in sim.fighters do
			lastPercent[i] = f.percent
		end
		local events = runner:step(1 / 60)
		frames += 1
		for _, e in events do
			if e.type == "sudden_death" then
				wentSudden = true
			elseif e.type == "ring_out" and not wentSudden then
				koPercentSum += lastPercent[e.actor] or 0
				koCount += 1
			end
		end
	end
	for _, f in sim.fighters do
		damageSum += f.damageDealt
	end
	secondsSum += frames / 60
	local seconds = frames / 60
	local kos = 0
	for _, f in sim.fighters do
		kos += f.kos
	end
	totalKos += kos
	local timeUp = seconds >= limit - 0.05
	if timeUp then
		timeUps += 1
	end
	if wentSudden then
		sudden += 1
	end
	table.insert(durations, seconds)
	print(
		string.format(
			"match %2d  %-16s %5.1f s  KOs %2d%s",
			m,
			arena,
			seconds,
			kos,
			if wentSudden then "  SUDDEN DEATH" elseif timeUp then "  TIME" else ""
		)
	)
end
table.sort(durations)
local sum, inWindow = 0, 0
for _, d in durations do
	sum += d
	if d >= 60 and d <= 120 then
		inWindow += 1
	end
end
print(
	string.format(
		"\n%d matches, stocks %s, bot base %d: median %.1f s, mean %.1f s, min %.1f, max %.1f",
		count,
		tostring(stocks or `{Constants.FFA_STOCKS} (FFA default)`),
		base,
		durations[math.ceil(#durations / 2)],
		sum / #durations,
		durations[1],
		durations[#durations]
	)
)
print(
	string.format(
		"time limit hit %d/%d, sudden death %d/%d, 60-120 s %d/%d, KOs per match %.1f",
		timeUps,
		count,
		sudden,
		count,
		inWindow,
		count,
		totalKos / count
	)
)
print(
	string.format(
		"average percent at KO %.0f %%, damage per fighter per minute %.0f %%",
		koPercentSum / math.max(1, koCount),
		damageSum / Constants.MAX_PLAYERS / math.max(1, secondsSum / 60)
	)
)
