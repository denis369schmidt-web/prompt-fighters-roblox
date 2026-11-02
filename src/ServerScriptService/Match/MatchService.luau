--!strict
-- Lobby -> match -> results loop for one server.
-- Players walk around the lobby plaza with their avatar, pick a fighter (SelectFighter) and vote for one of three
-- arenas by standing on its pad (or with VoteArena). The countdown starts with the first pick and shortens once
-- everyone has picked; free slots up to 4 are filled with bots. During the match avatars are frozen in the lobby
-- and every client's camera shows the arena.
-- During the match the server ticks the MatchRunner at 60 Hz, sends snapshots at 30 Hz (unreliable) and
-- match events reliably. Players who join mid-match watch and play the next round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArenaThemes = require(ReplicatedStorage.Shared.Data.ArenaThemes)
local Arenas = require(ReplicatedStorage.Shared.Data.Arenas)
local Bot = require(ReplicatedStorage.Shared.Combat.Bot)
local MatchRunner = require(ReplicatedStorage.Shared.Combat.MatchRunner)
local Fighters = require(ReplicatedStorage.Shared.Data.Fighters)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)
local Profile = require(ReplicatedStorage.Shared.Meta.Profile)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local RemoteHub = require(script.Parent.Parent.Net.RemoteHub)
local ArenaBuilder = require(script.Parent.Parent.World.ArenaBuilder)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local PromptService = require(script.Parent.Parent.Prompt.PromptService)

local LOBBY_SECONDS = 20 -- after the first fighter pick, time to vote and for friends to pick
local READY_SECONDS = 5 -- once every player in the server has picked
local VOTE_SCAN = 0.2 -- seconds between pad checks
local RESULTS_SECONDS = 16 -- GAME! card, victory scene, podium; ends early once every fighter voted
local SLOTS = 4
local SNAPSHOT_EVERY = 2 -- ticks
local BOT_LEVEL = 3 -- three bots at once: keep them beatable for new players
local INTRO_COUNTDOWN = 4.8 -- arena card and name plates, then 3 · 2 · 1 (client Cinematics)
local REMATCH_COUNTDOWN = 4.0 -- a rematch shows a short REVANCHE! card instead of the name plates

-- Events the clients need for effects and the HUD (others stay on the server).
local NET_EVENTS = {
	go = true,
	emote = true,
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
local options: { string } = {}
local votes: { [number]: { index: number, weight: number } } = {}
local padVotes: { [number]: number? } = {}
local voteScan = 0
local arenaId = Visuals.SLICE_ARENA
-- Rematch votes in the results phase: userId -> true (NOCHMAL) / false (Zur Lobby).
local rematchVotes: { [number]: boolean } = {}

local function sliceAllowed(fighterId: string): boolean
	return table.find(Visuals.SLICE_FIGHTERS, fighterId) ~= nil
end

local rematchTally: () -> { yes: number, no: number, total: number }

local function broadcastState()
	local current = runner
	RemoteHub.fireAll("MatchEvent", {
		{
			type = "phase",
			phase = phase,
			timer = if phase == "lobby" then lobbyTimer elseif phase == "results" then resultsTimer else 0,
			arena = arenaId,
			options = options,
			votes = Arenas.tally(options, votes),
			rematch = if phase == "results" then rematchTally() else nil,
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

local function readyCount(): (number, number)
	local ready, total = 0, 0
	for _, player in Players:GetPlayers() do
		total += 1
		if selections[player.UserId] then
			ready += 1
		end
	end
	return ready, total
end

local function showVotes()
	local totals = Arenas.tally(options, votes)
	local best = 0
	for _, total in totals do
		best = math.max(best, total)
	end
	for i, id in options do
		LobbyBuilder.setVote(i, id, totals[i], best > 0 and totals[i] == best)
	end
end

local function showLobbyStatus()
	local ready, total = readyCount()
	if ready == 0 then
		LobbyBuilder.setStatus("WÄHLE DEINEN KÄMPFER", "Stell dich auf ein Feld, um die Arena zu wählen")
	else
		LobbyBuilder.setStatus(
			`KAMPF IN {math.max(0, math.ceil(lobbyTimer))}`,
			`{ready}/{total} bereit · Feld betreten = Arena wählen`
		)
	end
end

local function newLobby()
	roundSeed += 1
	options = Arenas.voteOptions(roundSeed * 7 + 3, LobbyBuilder.PAD_COUNT)
	table.clear(votes)
	table.clear(padVotes)
	lobbyTimer = LOBBY_SECONDS
	showVotes()
	showLobbyStatus()
end

-- Freezes avatars during a match (the keyboard drives the fighter, not the avatar) and frees them after.
local function setFrozen(character: Model?, frozen: boolean)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		root.Anchored = frozen
	end
end

local function freezeAll(frozen: boolean)
	for _, player in Players:GetPlayers() do
		setFrozen(player.Character, frozen)
	end
end

-- Pad votes: standing on a pad counts as a vote and replaces a vote made by button.
local function scanPads()
	local changed = false
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local pad = if root and root:IsA("BasePart") then LobbyBuilder.padAt(root.Position) else nil
		if pad ~= padVotes[player.UserId] then
			padVotes[player.UserId] = pad
			if pad then
				votes[player.UserId] = { index = pad, weight = Arenas.voteWeight(false, false) }
			end
			changed = true
		end
	end
	if changed then
		showVotes()
		broadcastState()
	end
end

-- Bot levels from the players' progress (Bot.levelFor): a spread around the average so bots differ, and soft
-- bots with fewer stocks in a new player's very first match (GROWTH.md: the first finisher comes early).
local function botSetup(slots: { MatchRunner.Slot }): ({ [number]: number }, boolean)
	local sum, humans, first = 0, 0, false
	for _, slot in slots do
		local player = if slot.userId then Players:GetPlayerByUserId(slot.userId) else nil
		local profile = if player then PlayerData.get(player) else nil
		if slot.userId then
			humans += 1
			if profile then
				sum += Bot.levelFor(profile.matches, profile.wins, profile.level)
				first = first or profile.matches == 0
			else
				sum += BOT_LEVEL
			end
		end
	end
	local base = if humans > 0 then math.round(sum / humans) else BOT_LEVEL
	local gentle = first and humans == 1
	local levels: { [number]: number } = {}
	local spread = Bot.lineup(base, SLOTS)
	for i, slot in slots do
		if slot.userId == nil then
			levels[i] = if gentle then 1 else spread[i]
		end
	end
	return levels, gentle
end

local function launch(slots: { MatchRunner.Slot }, countdown: number)
	local levels, gentle = botSetup(slots)
	runner = MatchRunner.new({
		slots = slots,
		botLevel = BOT_LEVEL,
		botLevels = levels,
		gentle = gentle,
		botStocks = if gentle then 2 else nil,
		seed = roundSeed,
		arena = arenaId,
		countdown = countdown,
	})
	table.clear(rematchVotes)
	lastSnapshotFrame = 0
	phase = "match"
	freezeAll(true)
	local info = Arenas.byId[arenaId]
	LobbyBuilder.setStatus("KAMPF LÄUFT", if info then info.name else arenaId)
	broadcastState()
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
	local totals = Arenas.tally(options, votes)
	arenaId = if #options > 0 then Arenas.winner(options, totals, (roundSeed * 0.618) % 1) else Visuals.SLICE_ARENA
	ArenaBuilder.build(arenaId)
	local pool = table.clone(Visuals.SLICE_FIGHTERS)
	local k = 0
	while #slots < SLOTS do
		k += 1
		table.insert(slots, { userId = nil, fighterId = pool[(roundSeed + k) % #pool + 1] })
	end
	launch(slots, INTRO_COUNTDOWN)
end

-- Places 1..n: the winner first, then by stocks left and damage dealt.
local function places(current: MatchRunner.Runner): { [number]: number }
	local order = {}
	for i in current.sim.fighters do
		table.insert(order, i)
	end
	local winner = current.sim.result
	table.sort(order, function(a, b)
		if a == winner or b == winner then
			return a == winner
		end
		local fa, fb = current.sim.fighters[a], current.sim.fighters[b]
		if fa.lives ~= fb.lives then
			return fa.lives > fb.lives
		end
		return fa.damageDealt > fb.damageDealt
	end)
	local place = {}
	for rank, i in order do
		place[i] = rank
	end
	return place
end

-- Saves XP, coins and unlocks for every player in the match and tells each one what they got.
local function rewardPlayers(current: MatchRunner.Runner)
	local place = places(current)
	for i, slot in current.slots do
		local player = if slot.userId then Players:GetPlayerByUserId(slot.userId) else nil
		if player then
			local f = current.sim.fighters[i]
			local stats: Profile.MatchStats = {
				won = current.sim.result == i,
				place = place[i],
				kos = f.kos,
				damage = f.damageDealt,
				finishers = f.finishers,
				stocksLost = f.stocksLost,
				bestCombo = f.bestCombo,
			}
			local extra: { [string]: any } = {}
			PlayerData.update(player, function(profile)
				extra.reward = Profile.applyMatch(profile, slot.fighterId, stats)
			end, extra)
		end
	end
end

local function finishMatch(current: MatchRunner.Runner)
	rewardPlayers(current)
	local place = places(current)
	local stats = {}
	for i, f in current.sim.fighters do
		stats[i] = {
			place = place[i],
			kos = f.kos,
			damage = math.floor(f.damageDealt),
			bestCombo = f.bestCombo,
			finishers = f.finishers,
			stocksLost = f.stocksLost,
		}
	end
	phase = "results"
	resultsTimer = RESULTS_SECONDS
	table.clear(rematchVotes)
	RemoteHub.fireAll("MatchEvent", { { type = "results", winner = current.sim.result, stats = stats } })
	broadcastState()
end

local function toLobby()
	runner = nil
	phase = "lobby"
	table.clear(rematchVotes)
	newLobby()
	freezeAll(false)
	ArenaBuilder.applyLighting(ArenaThemes.neon_alley)
	broadcastState()
end

-- Players of the finished match who are still in the server.
local function matchPlayers(): { number }
	local out = {}
	local current = runner
	if current then
		for _, slot in current.slots do
			if slot.userId and Players:GetPlayerByUserId(slot.userId) then
				table.insert(out, slot.userId)
			end
		end
	end
	return out
end

rematchTally = function()
	local yes, no = 0, 0
	local ids = matchPlayers()
	for _, userId in ids do
		local vote = rematchVotes[userId]
		if vote == true then
			yes += 1
		elseif vote == false then
			no += 1
		end
	end
	return { yes = yes, no = no, total = #ids }
end

-- Same fighters, same arena: players who voted NOCHMAL keep their slot, everyone else's fighter becomes a bot.
local function startRematch()
	local current = runner :: MatchRunner.Runner
	local slots: { MatchRunner.Slot } = {}
	for i, slot in current.slots do
		local keep = slot.userId ~= nil and rematchVotes[slot.userId] == true
		slots[i] = { userId = if keep then slot.userId else nil, fighterId = slot.fighterId }
	end
	roundSeed += 1
	launch(slots, REMATCH_COUNTDOWN)
end

-- Ends the results phase once every fighter voted (or the timer ran out): rematch if anyone wants one.
local function settleResults(timeUp: boolean)
	if phase ~= "results" or runner == nil then
		return
	end
	local tally = rematchTally()
	local everyone = tally.total > 0 and tally.yes + tally.no >= tally.total
	if not timeUp and not everyone then
		return
	end
	if tally.yes > 0 then
		startRematch()
	else
		toLobby()
	end
end

local function onHeartbeat(dt: number)
	if phase == "lobby" then
		voteScan -= dt
		if voteScan <= 0 then
			voteScan = VOTE_SCAN
			scanPads()
		end
		local ready, total = readyCount()
		if ready > 0 then
			local before = math.ceil(lobbyTimer)
			if ready == total then
				lobbyTimer = math.min(lobbyTimer, READY_SECONDS)
			end
			lobbyTimer -= dt
			if math.ceil(lobbyTimer) ~= before then
				showLobbyStatus()
				broadcastState()
			end
			if lobbyTimer <= 0 then
				startMatch()
			end
		elseif lobbyTimer ~= LOBBY_SECONDS then
			lobbyTimer = LOBBY_SECONDS
			showLobbyStatus()
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
		local before = resultsTimer
		resultsTimer -= dt
		-- The final snapshot (winner in the Victory pose) goes out unreliably: repeat it now and then.
		if runner and math.floor(before * 2) ~= math.floor(resultsTimer * 2) then
			RemoteHub.fireAll("Snapshot", (runner :: MatchRunner.Runner):snapshot())
		end
		if resultsTimer <= 0 then
			settleResults(true)
		end
	end
end

function MatchService.start()
	RemoteHub.on("SelectFighter", function(player, fighterId: string)
		local profile = PlayerData.get(player)
		local owned = if profile then Profile.owns(profile, fighterId) else Profile.owns(Profile.new(), fighterId)
		-- Roster fighters the player owns, or a prompt fighter they made or loaded (bots stay roster fighters).
		if (sliceAllowed(fighterId) and owned) or PromptService.allows(player, fighterId) then
			selections[player.UserId] = fighterId
			if phase == "lobby" then
				showLobbyStatus()
			end
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
	RemoteHub.on("BuyFighter", function(player, fighterId: string)
		local extra: { [string]: any } = {}
		PlayerData.update(player, function(profile)
			local ok, reason = Profile.buyFighter(profile, fighterId)
			extra.message = if ok then `{Fighters.get(fighterId).name} freigeschaltet!` else reason
			extra.bought = if ok then fighterId else nil
		end, extra)
	end)
	RemoteHub.on("VoteRematch", function(player, again: boolean)
		local current = runner
		if phase ~= "results" or current == nil or current:slotOf(player.UserId) == nil then
			return
		end
		rematchVotes[player.UserId] = again
		broadcastState()
		settleResults(false)
	end)
	RemoteHub.on("VoteArena", function(player, id: string)
		local index = table.find(options, id)
		if phase == "lobby" and index then
			votes[player.UserId] = { index = index, weight = Arenas.voteWeight(false, false) }
			showVotes()
			broadcastState()
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if phase ~= "lobby" then
				character:WaitForChild("HumanoidRootPart", 5)
				-- The match may have ended while the avatar loaded.
				setFrozen(character, (phase :: Phase) ~= "lobby")
			end
		end)
		broadcastState()
	end)
	Players.PlayerRemoving:Connect(function(player)
		selections[player.UserId] = nil
		votes[player.UserId] = nil
		padVotes[player.UserId] = nil
		local current = runner
		if current then
			current:dropPlayer(player.UserId)
		end
	end)
	LobbyBuilder.build()
	ArenaBuilder.build(Visuals.SLICE_ARENA)
	ArenaBuilder.applyLighting(ArenaThemes.neon_alley)
	newLobby()
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MatchService
