--!strict
-- Client view of the Boss-Raid and mutator hazards from the BossState remote (Combat/BossFight.encode, 15 Hz,
-- unreliable): boss HP, phase, position, telegraph zones, hero HP and the team's lives. Display data only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossFight = require(Shared:WaitForChild("Combat"):WaitForChild("BossFight"))
local MatchState = require(script.Parent.MatchState)

local RaidState = {
	boss = nil :: BossFight.NetBoss?,
	previous = nil :: BossFight.NetBoss?,
	at = 0,
	-- mutator bomb warnings in the same zone format (kind 2 = circle)
	hazards = {} :: { BossFight.NetZone },
}

function RaidState.active(): boolean
	return MatchState.mode == "raid" and RaidState.boss ~= nil and MatchState.phase ~= "lobby"
end

-- HP of a hero slot in the raid (nil outside the raid).
function RaidState.hero(slot: number): BossFight.NetHero?
	local boss = RaidState.boss
	return if boss and MatchState.mode == "raid" then boss.heroes[slot] else nil
end

function RaidState.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BossState") :: UnreliableRemoteEvent
	remote.OnClientEvent:Connect(function(payload: { any })
		if type(payload) ~= "table" then
			return
		end
		if payload[1] then
			RaidState.previous = RaidState.boss
			RaidState.boss = BossFight.decode(payload[1])
			RaidState.at = os.clock()
		end
		local flat = payload[2] or {}
		local hazards = {}
		for k = 1, #flat - 5, 6 do
			table.insert(hazards, {
				kind = flat[k],
				x1 = flat[k + 1],
				x2 = flat[k + 2],
				y1 = flat[k + 3],
				y2 = flat[k + 4],
				progress = math.min(1, flat[k + 5]),
				live = false,
			})
		end
		RaidState.hazards = hazards
	end)
	MatchState.onEvent(function(event)
		if event.type == "phase" and (event.phase == "lobby" or (event.phase == "match" and event.mode ~= "raid")) then
			RaidState.boss, RaidState.previous = nil, nil
			RaidState.hazards = {}
		end
	end)
end

return RaidState
