--!strict
-- Lobby leaderboards from OrderedDataStores: wins this week (a new store each Monday), all-time wins and the
-- highest level (rules in Shared/Meta/Leaderboards). Reads every ~60 s with backoff after failures, shows display
-- names (cached, pcall) and rotates the lobby board between the boards every 10 s (LobbyBuilder.setLeaderboard).
-- Scores are written after a match, at most once per player and board every WRITE_SECONDS, and once more when
-- the player leaves. Without DataStore access (Studio without API access, outage) the board ranks the players
-- in this server, so it never stays empty.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Leaderboards = require(ReplicatedStorage.Shared.Meta.Leaderboards)
local MatchRunner = require(ReplicatedStorage.Shared.Combat.MatchRunner)
local Profile = require(ReplicatedStorage.Shared.Meta.Profile)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)

local LeaderboardService = {}

local WRITE_CHECK_SECONDS = 15

local stores: { [string]: OrderedDataStore } = {}
local storesBroken = false
local entries: { [number]: { Leaderboards.Entry } } = {} -- board index -> last read rows
local names: { [number]: string } = {}
local fallback: { [number]: boolean } = {} -- board index -> rows come from this server (no store data)
local lastWrite: { [number]: { [string]: { value: number, at: number } } } = {}
local pending: { [number]: boolean } = {}
local shown = 1

local function store(boardId: string): OrderedDataStore?
	if storesBroken then
		return nil
	end
	local name = Leaderboards.storeName(boardId, os.time())
	local found = stores[name]
	if found then
		return found
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		stores[name] = result
		return result
	end
	storesBroken = true
	warn(`[Leaderboard] OrderedDataStore unavailable, showing this server only: {result}`)
	return nil
end

-- Display names for these user ids: players in the server, the cache, one batch lookup, then usernames.
local function resolveNames(ids: { number })
	local missing = {}
	for _, userId in ids do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			names[userId] = player.DisplayName
		elseif names[userId] == nil then
			table.insert(missing, userId)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
	for _, userId in missing do
		if names[userId] == nil then
			local found, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if found and type(name) == "string" then
				names[userId] = name
			end
		end
	end
end

-- Players in this server ranked by a board's score (fallback without DataStores).
local function localEntries(boardId: string): { Leaderboards.Entry }
	local list = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			local value = Leaderboards.scores(profile, os.time())[boardId] or 0
			if value > 0 then
				table.insert(list, { userId = player.UserId, value = value })
				names[player.UserId] = player.DisplayName
			end
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

-- Reads every board once. Returns false when a read failed.
local function refresh(): boolean
	local allOk = true
	local ids = {}
	for k, board in Leaderboards.BOARDS do
		local s = store(board.id)
		local list: { Leaderboards.Entry }? = nil
		if s then
			local ok, page = pcall(function()
				return s:GetSortedAsync(false, Leaderboards.ROWS):GetCurrentPage()
			end)
			if ok and type(page) == "table" then
				local rows = {}
				for _, item in page do
					local userId = tonumber(item.key)
					if userId and type(item.value) == "number" then
						table.insert(rows, { userId = userId, value = item.value })
					end
				end
				list = rows
			else
				allOk = false
			end
		end
		if list then
			fallback[k] = false
		elseif storesBroken or entries[k] == nil or fallback[k] then
			list = localEntries(board.id)
			fallback[k] = true
		end
		if list then
			entries[k] = list
		end
		local shownList = entries[k]
		if shownList then
			for _, entry in shownList do
				table.insert(ids, entry.userId)
			end
		end
	end
	resolveNames(ids)
	return allOk
end

local function show()
	local hasRows = {}
	for k, board in Leaderboards.BOARDS do
		if fallback[k] then
			entries[k] = localEntries(board.id) -- stays live between (backed-off) store reads
		end
		hasRows[k] = entries[k] ~= nil and #(entries[k] :: { Leaderboards.Entry }) > 0
	end
	shown = Leaderboards.nextBoard(shown, hasRows)
	local board = Leaderboards.BOARDS[shown]
	pcall(LobbyBuilder.setLeaderboard, Leaderboards.rows(board, entries[shown] or {}, names), board.title)
end

-- Writes the player's due scores (all changed ones when `force`, e.g. on leave).
local function write(player: Player, force: boolean)
	local found = PlayerData.get(player)
	if found == nil then
		return
	end
	local profile = found :: Profile.Profile
	local userId = player.UserId
	local last: { [string]: { value: number, at: number } } = lastWrite[userId] or {}
	lastWrite[userId] = last
	local scores = Leaderboards.scores(profile, os.time())
	local now = os.clock()
	local none: { [string]: { value: number, at: number } } = {}
	local due = Leaderboards.dueWrites(scores, if force then none else last, now)
	pending[userId] = nil
	local failed = false
	for _, boardId in due do
		local value = scores[boardId]
		if force and last[boardId] and last[boardId].value == value then
			continue
		end
		local s = store(boardId)
		if s then
			local ok, err = pcall(function()
				s:SetAsync(tostring(userId), math.floor(value))
			end)
			if ok then
				last[boardId] = { value = value, at = now }
			else
				-- No retry loop (Studio without API access would warn forever): the next match end tries again.
				failed = true
				warn(`[Leaderboard] write failed for {userId}: {err}`)
			end
		end
	end
	-- Changed scores that are still throttled wait for the next check.
	if not failed and not force and #Leaderboards.dueWrites(scores, last, math.huge) > 0 then
		pending[userId] = true
	end
end

-- MatchService, after the rewards: counts weekly wins and queues the players' score writes.
function LeaderboardService.matchFinished(runner: MatchRunner.Runner)
	local week = Leaderboards.weekKey(os.time())
	for i, slot in runner.slots do
		local player = if slot.userId then Players:GetPlayerByUserId(slot.userId) else nil
		if player then
			if runner.sim.result == i then
				PlayerData.update(player, function(profile)
					Profile.addWeeklyWin(profile, week)
				end)
			end
			pending[player.UserId] = true
		end
	end
end

function LeaderboardService.start()
	Players.PlayerRemoving:Connect(function(player)
		write(player, true)
		lastWrite[player.UserId] = nil
		pending[player.UserId] = nil
	end)
	task.spawn(function()
		local failures = 0
		while true do
			failures = if refresh() then 0 else failures + 1
			task.wait(Leaderboards.backoff(failures))
		end
	end)
	task.spawn(function()
		while true do
			show()
			task.wait(Leaderboards.ROTATE_SECONDS)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(WRITE_CHECK_SECONDS)
			local due = {}
			for userId in pending do
				table.insert(due, userId)
			end
			for _, userId in due do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					task.spawn(write, player, false)
				else
					pending[userId] = nil
				end
			end
		end
	end)
end

return LeaderboardService
