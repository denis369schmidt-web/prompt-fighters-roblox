--!strict
-- Loads, keeps and saves each player's Profile (Shared/Meta/Profile) in a DataStore.
-- Saves on leave, on shutdown and every few minutes. If DataStores are unavailable (Studio without API access,
-- outage) the player plays on a temporary profile that is never saved, so a hiccup can never overwrite progress.
-- Every change goes through PlayerData.update, which pushes the new state to that player's client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Profile = require(ReplicatedStorage.Shared.Meta.Profile)
local RemoteHub = require(script.Parent.Parent.Net.RemoteHub)

local STORE_NAME = "PlayerProfiles_v1"
local AUTOSAVE_SECONDS = 180
local RETRIES = 3

local PlayerData = {}

type Entry = { profile: Profile.Profile, saved: boolean, dirty: boolean }

local entries: { [number]: Entry } = {}
local store: DataStore? = nil
local loaded = Instance.new("BindableEvent")

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[PlayerData] DataStore unavailable, progress is not saved this session: {result}`)
	end
end

local function key(userId: number): string
	return `p_{userId}`
end

local function retry<T>(fn: () -> T): (boolean, T | string)
	local lastError: any = nil
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(attempt)
	end
	return false, tostring(lastError)
end

local function push(player: Player, entry: Entry, extra: { [string]: any }?)
	local view = Profile.view(entry.profile)
	view.saved = entry.saved
	if extra then
		for k, v in extra do
			view[k] = v
		end
	end
	RemoteHub.fire("Profile", player, view)
end

local function save(userId: number)
	local entry = entries[userId]
	if entry == nil or store == nil or not entry.saved or not entry.dirty then
		return
	end
	local s = store :: DataStore
	local data = entry.profile
	local ok, err = retry(function()
		s:SetAsync(key(userId), data, { userId })
		return true
	end)
	if ok then
		entry.dirty = false
	else
		warn(`[PlayerData] save failed for {userId}: {err}`)
	end
end

local function load(player: Player)
	local profile: Profile.Profile
	local saved = false
	local s = store
	if s then
		local ok, result = retry(function()
			return s:GetAsync(key(player.UserId))
		end)
		if ok then
			profile = Profile.migrate(result)
			saved = true
		else
			warn(`[PlayerData] load failed for {player.UserId}, using a temporary profile: {result}`)
			profile = Profile.new()
		end
	else
		profile = Profile.new()
	end
	if player.Parent == nil then
		return
	end
	local entry = { profile = profile, saved = saved, dirty = false }
	entries[player.UserId] = entry
	-- Login calendar: paid once per UTC day.
	local coins, day = Profile.dailyLogin(profile, math.floor(os.time() / 86400))
	entry.dirty = true
	push(player, entry, if coins > 0 then { loginCoins = coins, loginDay = day } else nil)
	loaded:Fire(player)
end

-- The player's profile, or nil while it is still loading.
function PlayerData.get(player: Player): Profile.Profile?
	local entry = entries[player.UserId]
	return if entry then entry.profile else nil
end

-- Changes a profile and sends the new state to the player. `extra` rides along (e.g. a match reward).
function PlayerData.update(player: Player, change: (profile: Profile.Profile) -> (), extra: { [string]: any }?)
	local entry = entries[player.UserId]
	if entry == nil then
		return
	end
	change(entry.profile)
	entry.dirty = true
	push(player, entry, extra)
end

PlayerData.loaded = loaded.Event

function PlayerData.start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player.UserId)
		entries[player.UserId] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and store == nil then
			return
		end
		local pending = 0
		for userId in entries do
			pending += 1
			task.spawn(function()
				save(userId)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for userId in entries do
				task.spawn(save, userId)
			end
		end
	end)
end

return PlayerData
