--!strict
-- The local player's saved progress as the server last sent it (coins, level, XP, owned fighters), plus
-- one-off news that came with an update: a match reward, the daily login bonus or a shop message.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type View = {
	coins: number,
	level: number,
	xp: number,
	xpNext: number,
	title: string,
	wins: number,
	owned: { string },
	winsToUnlock: number,
	saved: boolean?,
	reward: { [string]: any }?,
	loginCoins: number?,
	loginDay: number?,
	message: string?,
	bought: string?,
	prompts: { string }?, -- share codes of the player's last prompt fighters, newest first
	settings: { [string]: boolean }?, -- settings panel switches (Meta/Profile.Settings)
}

local ProfileState = {
	view = nil :: View?,
}

local listeners: { (view: View) -> () } = {}

function ProfileState.onChange(callback: (view: View) -> ())
	table.insert(listeners, callback)
	local view = ProfileState.view
	if view then
		task.spawn(callback, view)
	end
end

function ProfileState.owns(fighterId: string): boolean
	local view = ProfileState.view
	return view ~= nil and table.find(view.owned, fighterId) ~= nil
end

function ProfileState.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Profile") :: RemoteEvent
	remote.OnClientEvent:Connect(function(view: View)
		ProfileState.view = view
		for _, callback in listeners do
			task.spawn(callback, view)
		end
	end)
end

return ProfileState
