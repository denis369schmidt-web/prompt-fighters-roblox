--!strict
-- Lobby -> match -> results loop for one server (Phase 1 vertical slice).
-- Players pick a fighter (SelectFighter); a short lobby countdown starts; free slots up to 4 are filled with bots.
-- During the match the server ticks the MatchRunner at 60 Hz, sends snapshots at 30 Hz (unreliable) and
-- match events reliably. Players who join mid-match watch and play the next round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MatchRunner = require(ReplicatedStorage.Shared.Combat.MatchRunner)
local Fighters = require(ReplicatedStorage.Shared.Data.Fighters)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)
local RemoteHub = require(script.Parent.Parent.Net.RemoteHub)
local ArenaBuilder = require(script.Parent.Parent.World.ArenaBuilder)

local LOBBY_SECONDS = 6
local RESULTS_SECONDS = 7
local SLOTS = 4
local SNAPSHOT_EVERY = 2 -- ticks
local BOT_LEVEL = 3 -- three bots at once: keep them beatable for new players

-- Events the clients need for effects and the HUD (others stay on the server).
local NET_EVENTS = {
	go = true,
	hit = true,
	block = true,
	parry = true,
	clash = true,
	ring_out = true,
	respawn = true,
	fighter_eliminated = true,
	finish_him = true,
	finisher = true,
	finish = true,
	sudden_death = true,
	shield_break = true,
	super_used = true,
	ledge_grab = true,
	throw = true,
	-- items
	item_spawned = true,
	item_pickup = true,
	item_throw = true,
	item_explode = true,
	item_break = true,
	weapon_pickup = true,
	weapon_break = true,
	powerup = true,
	-- signature specials
	signature = true,
	projectile = true,
	projectile_end = true,
	blast = true,
	pool = true,
	teleport = true,
	marked = true,
	iai_cut = true,
	slam = true,
	reflect = true,
	wall_block = true,
	catch = true,
	stuck = true,
	recall = true,
	nova_launch = true,
	clone_ready = true,
	eagle_summon = true,
	eagle_leave = true,
	eagle_strike = true,
	turbo_ram = true,
	freeze_hit = true,
	rebirth_heal = true,
	war_horn = true,
	crown_shift = true,
	swap = true,
	lasso = true,
	yank = true,
	hexed = true,
	leashed = true,
	anchor_zip = true,
	bomb_stuck = true,
	decoy = true,
	heat_full = true,
	one_punch_ko = true,
	flashbang = true,
	echo_strike = true,
	soul_weigh = true,
	bulwark_block = true,
	counter = true,
}

local MatchService = {}

type Phase = "lobby" | "match" | "results"

local phase: Phase = "lobby"
local lobbyTimer = 0
local resultsTimer = 0
local selections: { [number]: string } = {}
local runner: MatchRunner.Runner? = nil
local lastSnapshotFrame = 0
local hadShots = false
local roundSeed = os.time() % 100000

local function sliceAllowed(fighterId: string): boolean
	return table.find(Visuals.SLICE_FIGHTERS, fighterId) ~= nil
end

local function broadcastState()
	local current = runner
	RemoteHub.fireAll("MatchEvent", {
		{
			type = "phase",
			phase = phase,
			timer = if phase == "lobby" then lobbyTimer elseif phase == "results" then resultsTimer else 0,
			slots = if current
				then (function()
					local out = {}
					for i, slot in current.slots do
						local def = Fighters.get(slot.fighterId)
						local player = if slot.userId then Players:GetPlayerByUserId(slot.userId) else nil
						out[i] = {
							fighterId = slot.fighterId,
							name = def.name,
							element = def.element,
							userId = slot.userId,
							player = if player then player.DisplayName else nil,
						}
					end
					return out
				end)()
				else nil,
		},
	})
end

local function startMatch()
	local slots: { MatchRunner.Slot } = {}
	for _, player in Players:GetPlayers() do
		local choice = selections[player.UserId]
		if choice and #slots < SLOTS then
			table.insert(slots, { userId = player.UserId, fighterId = choice })
		end
	end
	if #slots == 0 then
		return
	end
	roundSeed += 1
	local pool = table.clone(Visuals.SLICE_FIGHTERS)
	local k = 0
	while #slots < SLOTS do
		k += 1
		table.insert(slots, { userId = nil, fighterId = pool[(roundSeed + k) % #pool + 1] })
	end
	runner = MatchRunner.new({
		slots = slots,
		botLevel = BOT_LEVEL,
		seed = roundSeed,
		arena = Visuals.SLICE_ARENA,
	})
	lastSnapshotFrame = 0
	phase = "match"
	broadcastState()
end

local function finishMatch(current: MatchRunner.Runner)
	local stats = {}
	for i, f in current.sim.fighters do
		stats[i] = {
			kos = f.kos,
			damage = math.floor(f.damageDealt),
			bestCombo = f.bestCombo,
			finishers = f.finishers,
			stocksLost = f.stocksLost,
		}
	end
	phase = "results"
	resultsTimer = RESULTS_SECONDS
	RemoteHub.fireAll("MatchEvent", { { type = "results", winner = current.sim.result, stats = stats } })
	broadcastState()
end

local function onHeartbeat(dt: number)
	if phase == "lobby" then
		local anyReady = false
		for _, player in Players:GetPlayers() do
			if selections[player.UserId] then
				anyReady = true
			end
		end
		if anyReady then
			local before = math.ceil(lobbyTimer)
			lobbyTimer -= dt
			if math.ceil(lobbyTimer) ~= before then
				broadcastState()
			end
			if lobbyTimer <= 0 then
				startMatch()
			end
		else
			lobbyTimer = LOBBY_SECONDS
		end
	elseif phase == "match" then
		if runner == nil then
			return
		end
		local current = runner :: MatchRunner.Runner
		local events = current:step(dt)
		local outgoing = {}
		for _, e in events do
			if NET_EVENTS[e.type] then
				table.insert(outgoing, e)
			end
		end
		if #outgoing > 0 then
			RemoteHub.fireAll("MatchEvent", outgoing)
		end
		if current.sim.frame - lastSnapshotFrame >= SNAPSHOT_EVERY then
			lastSnapshotFrame = current.sim.frame
			RemoteHub.fireAll("Snapshot", current:snapshot())
			local shots = current:shots()
			if #shots > 0 or hadShots then
				RemoteHub.fireAll("Shots", shots)
			end
			hadShots = #shots > 0
			if current.sim.frame % 6 < SNAPSHOT_EVERY then
				RemoteHub.fireAll("Items", current:items())
			end
		end
		if current.sim.result ~= nil then
			RemoteHub.fireAll("Snapshot", current:snapshot())
			finishMatch(current)
		end
	elseif phase == "results" then
		resultsTimer -= dt
		if resultsTimer <= 0 then
			runner = nil
			phase = "lobby"
			lobbyTimer = LOBBY_SECONDS
			broadcastState()
		end
	end
end

function MatchService.start()
	RemoteHub.on("SelectFighter", function(player, fighterId: string)
		if sliceAllowed(fighterId) then
			selections[player.UserId] = fighterId
			broadcastState()
		end
	end)
	RemoteHub.on("Input", function(player, mask: number, axis: number, _stickY: number, _seq: number)
		if phase ~= "match" or runner == nil then
			return
		end
		local current = runner :: MatchRunner.Runner
		local slot = current:slotOf(player.UserId)
		if slot then
			current:setInput(slot, mask, axis)
		end
	end)
	Players.PlayerAdded:Connect(function()
		broadcastState()
	end)
	Players.PlayerRemoving:Connect(function(player)
		selections[player.UserId] = nil
		local current = runner
		if current then
			current:dropPlayer(player.UserId)
		end
	end)
	lobbyTimer = LOBBY_SECONDS
	ArenaBuilder.build(Visuals.SLICE_ARENA)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MatchService
