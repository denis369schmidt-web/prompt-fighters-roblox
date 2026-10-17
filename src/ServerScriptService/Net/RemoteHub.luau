--!strict
-- Creates every remote from Shared/Net/Remotes in ReplicatedStorage.Remotes and wraps the client-to-server
-- ones with the Guard (types + rate limit). Handlers only ever see validated arguments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

-- Remotes that may drop packets (state that is resent anyway).
local UNRELIABLE = { Snapshot = true }

local RemoteHub = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"
local guard = Guard.new()
local instances: { [string]: Instance } = {}

for name, def in Remotes do
	local remote: Instance
	if def.kind == "function" then
		remote = Instance.new("RemoteFunction")
	elseif UNRELIABLE[name] then
		remote = Instance.new("UnreliableRemoteEvent")
	else
		remote = Instance.new("RemoteEvent")
	end
	remote.Name = name
	remote.Parent = folder
	instances[name] = remote
end
folder.Parent = ReplicatedStorage

Players.PlayerRemoving:Connect(function(player)
	guard:forget(player.UserId)
end)

function RemoteHub.on(name: string, handler: (player: Player, ...any) -> ())
	local remote = instances[name] :: RemoteEvent
	remote.OnServerEvent:Connect(function(player, ...)
		if guard:allow(player.UserId, name, os.clock(), { ... }) then
			handler(player, ...)
		end
	end)
end

function RemoteHub.fireAll(name: string, ...: any)
	(instances[name] :: any):FireAllClients(...)
end

function RemoteHub.fire(name: string, player: Player, ...: any)
	(instances[name] :: any):FireClient(player, ...)
end

return RemoteHub
