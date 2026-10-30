--!strict
-- Small client sound layer for hits and KOs. Uses only sound files that ship inside every Roblox client
-- (rbxasset://sounds/...), never uploaded or foreign assets; see docs/ASSET_LICENSES.md. Each sound has a few
-- pooled Sound instances (round robin) so rapid hits overlap, and every play gets a little pitch variation.
-- Set Sfx.ENABLED = false to mute the whole layer.

local SoundService = game:GetService("SoundService")

local Sfx = {}

Sfx.ENABLED = true
Sfx.VOLUME = 0.6

-- name -> built-in client file, base volume, base pitch, pitch variation (+/-), pool size
local SOUNDS: { [string]: { id: string, volume: number, pitch: number, vary: number, pool: number } } = {
	slash = { id = "rbxasset://sounds/swordslash.wav", volume = 0.45, pitch = 1.15, vary = 0.1, pool = 4 },
	heavy = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.7, pitch = 0.8, vary = 0.06, pool = 3 },
	metal = { id = "rbxasset://sounds/unsheath.wav", volume = 0.55, pitch = 1.3, vary = 0.08, pool = 2 },
	jump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.25, pitch = 1.1, vary = 0.08, pool = 2 },
}

local folder: Folder? = nil
local pools: { [string]: { list: { Sound }, next: number } } = {}

local function container(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local f = Instance.new("Folder")
	f.Name = "FightSfx"
	f.Parent = SoundService
	folder = f
	return f
end

-- Play a named sound. volume and pitch scale the base values (pitch 0.5 = an octave lower).
function Sfx.play(name: string, volume: number?, pitch: number?)
	if not Sfx.ENABLED then
		return
	end
	local def = SOUNDS[name]
	if def == nil then
		return
	end
	local pool = pools[name]
	if pool == nil then
		pool = { list = {}, next = 1 }
		pools[name] = pool
	end
	local sound = pool.list[pool.next]
	if not sound or sound.Parent == nil then
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.id
		s.Parent = container()
		pool.list[pool.next] = s
		sound = s
	end
	pool.next = pool.next % def.pool + 1
	local s = sound :: Sound
	s.Volume = def.volume * Sfx.VOLUME * (volume or 1)
	s.PlaybackSpeed = def.pitch * (pitch or 1) * (1 + (math.random() * 2 - 1) * def.vary)
	s.TimePosition = 0
	s:Play()
end

return Sfx
