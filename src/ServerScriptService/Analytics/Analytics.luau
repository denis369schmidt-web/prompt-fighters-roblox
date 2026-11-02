--!strict
-- Thin wrapper around AnalyticsService for the funnel and economy KPIs in docs/GROWTH.md. Every call is
-- pcall-ed (Studio, outages and API changes never break a match) and logs once per step and player.
--
-- Onboarding funnel (new players only, LogOnboardingFunnelStepEvent):
--   1 Join -> 2 Prompt erstellt -> 3 Match gestartet -> 4 Erster KO -> 5 Erstes Match beendet
--   -> 6 Zweites Match gestartet
-- Recurring funnel "Spielrunde" (LogFunnelStepEvent, one funnel session per match a player starts):
--   1 Match gestartet -> 2 Match beendet -> 3 Nächstes Match gestartet
-- Economy (LogEconomyEvent): every coin change, from PlayerData.coinsChanged.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MatchRunner = require(ReplicatedStorage.Shared.Combat.MatchRunner)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)

local Analytics = {}

-- Prints every event in Studio (where AnalyticsService does not report anything).
Analytics.DEBUG_IN_STUDIO = true
Analytics.CURRENCY = "Coins"

export type Step = { step: number, name: string }

Analytics.ONBOARDING = {
	join = { step = 1, name = "Join" },
	prompt = { step = 2, name = "Prompt erstellt" },
	matchStart = { step = 3, name = "Match gestartet" },
	firstKo = { step = 4, name = "Erster KO" },
	firstMatchDone = { step = 5, name = "Erstes Match beendet" },
	secondMatch = { step = 6, name = "Zweites Match gestartet" },
} :: { [string]: Step }

local ROUND_FUNNEL = "Spielrunde"

-- Coin change reasons (PlayerData.update extras) -> transaction type and item SKU.
local ECONOMY: { [string]: { kind: Enum.AnalyticsEconomyTransactionType, sku: string } } = {
	match = { kind = Enum.AnalyticsEconomyTransactionType.Gameplay, sku = "MatchReward" },
	login = { kind = Enum.AnalyticsEconomyTransactionType.TimedReward, sku = "DailyLogin" },
	group = { kind = Enum.AnalyticsEconomyTransactionType.Onboarding, sku = "GroupBonus" },
	fighter = { kind = Enum.AnalyticsEconomyTransactionType.Shop, sku = "Fighter" },
	shop = { kind = Enum.AnalyticsEconomyTransactionType.Shop, sku = "Shop" },
	iap = { kind = Enum.AnalyticsEconomyTransactionType.IAP, sku = "Robux" },
	other = { kind = Enum.AnalyticsEconomyTransactionType.Gameplay, sku = "Other" },
}

type Session = {
	onboarding: { [number]: boolean }, -- onboarding steps logged this session
	newPlayer: boolean, -- no finished match when they joined
	round: number, -- matches started this session (funnel session ids)
	roundOpen: boolean, -- a round funnel waits for its "Nächstes Match" step
}

local sessions: { [number]: Session } = {}

local function debugPrint(...: any)
	if Analytics.DEBUG_IN_STUDIO and RunService:IsStudio() then
		print("[Analytics]", ...)
	end
end

local function call(fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		debugPrint("call failed:", err)
	end
end

local function session(player: Player): Session
	local s = sessions[player.UserId]
	if s == nil then
		local profile = PlayerData.get(player)
		s = {
			onboarding = {},
			newPlayer = profile ~= nil and profile.matches == 0,
			round = 0,
			roundOpen = false,
		}
		sessions[player.UserId] = s
	end
	return s
end

-- Logs one onboarding step (Analytics.ONBOARDING) once per session, only for players who joined new.
function Analytics.onboarding(player: Player, step: Step)
	local s = session(player)
	local index, name = step.step, step.name
	if not s.newPlayer or s.onboarding[index] then
		return
	end
	s.onboarding[index] = true
	debugPrint("onboarding", player.UserId, index, name)
	call(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, index, name)
	end)
end

local function roundStep(player: Player, s: Session, step: number, name: string)
	local id = `{player.UserId}-{s.round}`
	debugPrint("funnel", ROUND_FUNNEL, id, step, name)
	call(function()
		AnalyticsService:LogFunnelStepEvent(player, ROUND_FUNNEL, id, step, name)
	end)
end

-- A coin change (positive = earned). Called through PlayerData.coinsChanged.
function Analytics.economy(player: Player, delta: number, balance: number, reason: string)
	local info = ECONOMY[reason] or ECONOMY.other
	local flow = if delta > 0 then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	debugPrint("economy", player.UserId, delta, balance, reason)
	call(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			Analytics.CURRENCY,
			math.abs(delta),
			balance,
			info.kind.Name,
			info.sku
		)
	end)
end

function Analytics.promptCreated(player: Player)
	Analytics.onboarding(player, Analytics.ONBOARDING.prompt)
end

-- MatchService: a match (or rematch) starts with these players.
function Analytics.matchStarted(userIds: { number })
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local s = session(player)
			if s.roundOpen then
				roundStep(player, s, 3, "Nächstes Match gestartet")
			end
			s.round += 1
			s.roundOpen = false
			roundStep(player, s, 1, "Match gestartet")
			local profile = PlayerData.get(player)
			if profile and profile.matches == 0 then
				Analytics.onboarding(player, Analytics.ONBOARDING.matchStart)
			elseif profile and profile.matches == 1 then
				Analytics.onboarding(player, Analytics.ONBOARDING.secondMatch)
			end
		end
	end
end

-- MatchService, after every runner step: a player's first KO ever (profile.kos only grows at match end).
function Analytics.afterStep(runner: MatchRunner.Runner, events: { { [string]: any } })
	local ko = false
	for _, e in events do
		if e.type == "ring_out" then
			ko = true
			break
		end
	end
	if not ko then
		return
	end
	for i, slot in runner.slots do
		local player = if slot.userId then Players:GetPlayerByUserId(slot.userId) else nil
		local profile = if player then PlayerData.get(player) else nil
		if player and profile and profile.kos == 0 and runner.sim.fighters[i].kos > 0 then
			Analytics.onboarding(player, Analytics.ONBOARDING.firstKo)
		end
	end
end

-- MatchService: the match ended (after the rewards were saved).
function Analytics.matchFinished(userIds: { number })
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local s = session(player)
			roundStep(player, s, 2, "Match beendet")
			s.roundOpen = true
			local profile = PlayerData.get(player)
			if profile and profile.matches == 1 then
				Analytics.onboarding(player, Analytics.ONBOARDING.firstMatchDone)
			end
		end
	end
end

function Analytics.start()
	PlayerData.loaded:Connect(function(player: Player)
		session(player)
		Analytics.onboarding(player, Analytics.ONBOARDING.join)
	end)
	PlayerData.coinsChanged:Connect(Analytics.economy)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player.UserId] = nil
	end)
end

return Analytics
