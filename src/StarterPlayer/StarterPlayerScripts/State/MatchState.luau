--!strict
-- Client view of the match: latest decoded snapshot, lobby/match phase, slot info and an event fan-out.
-- Everything here is display data from the server; the client never decides an outcome.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRunner = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat"):WaitForChild("MatchRunner"))

export type SlotInfo = { fighterId: string, name: string, element: string, userId: number?, player: string? }

local MatchState = {
	phase = "lobby",
	timer = 0,
	slots = {} :: { SlotInfo },
	snapshot = nil :: MatchRunner.NetSnapshot?,
	previous = nil :: MatchRunner.NetSnapshot?,
	snapshotAt = 0,
	mySlot = nil :: number?,
	-- projectile id -> latest position and size (meters)
	shots = {} :: { [number]: { x: number, y: number, size: number } },
}

local listeners: { (event: { [string]: any }) -> () } = {}

function MatchState.onEvent(callback: (event: { [string]: any }) -> ())
	table.insert(listeners, callback)
end

local function dispatch(event: { [string]: any })
	for _, callback in listeners do
		task.spawn(callback, event)
	end
end

function MatchState.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local localUserId = Players.LocalPlayer.UserId
	local snapshotRemote = remotes:WaitForChild("Snapshot") :: UnreliableRemoteEvent
	local eventRemote = remotes:WaitForChild("MatchEvent") :: RemoteEvent

	snapshotRemote.OnClientEvent:Connect(function(payload)
		local decoded = MatchRunner.decode(payload)
		local current = MatchState.snapshot
		if current and decoded.frame <= current.frame then
			return -- late unreliable packet
		end
		MatchState.previous = current
		MatchState.snapshot = decoded
		MatchState.snapshotAt = os.clock()
	end)
	local shotsRemote = remotes:WaitForChild("Shots") :: UnreliableRemoteEvent
	shotsRemote.OnClientEvent:Connect(function(flat: { number })
		local seen = {}
		for k = 1, #flat - 3, 4 do
			local id = flat[k]
			seen[id] = true
			local entry = MatchState.shots[id]
			if entry then
				entry.x, entry.y, entry.size = flat[k + 1], flat[k + 2], flat[k + 3]
			else
				MatchState.shots[id] = { x = flat[k + 1], y = flat[k + 2], size = flat[k + 3] }
			end
		end
		for id in MatchState.shots do
			if not seen[id] then
				MatchState.shots[id] = nil
			end
		end
	end)
	eventRemote.OnClientEvent:Connect(function(events)
		for _, event in events do
			if event.type == "phase" then
				MatchState.phase = event.phase
				MatchState.timer = event.timer
				if event.slots then
					MatchState.slots = event.slots
					MatchState.mySlot = nil
					for i, slot in event.slots do
						if slot.userId == localUserId then
							MatchState.mySlot = i
						end
					end
				end
				if event.phase == "lobby" then
					MatchState.snapshot, MatchState.previous = nil, nil
					table.clear(MatchState.shots)
				end
			end
			dispatch(event)
		end
	end)
end

return MatchState
