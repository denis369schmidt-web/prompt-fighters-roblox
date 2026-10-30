--!strict
-- Client-only game-feel state shared by the effect, fighter and camera code: picture hold (local hitstop),
-- slow motion, camera trauma, camera kick, zoom punch, FOV pulse and the KO focus. Display only: nothing here
-- reaches the server or changes an outcome. The numbers live in Shared/Visual/GameFeel.TUNING.
--
-- Render hooks for other code:
--   Juice.frozen(slot)  -> true while that fighter's drawn pose/position should hold (hitstop look)
--   Juice.timeScale()   -> 0..1 slow-motion factor; a renderer may multiply its easing dt by it

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameFeel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Visual"):WaitForChild("GameFeel"))

local TUNING = GameFeel.TUNING

local Juice = {}

-- Accessibility: one switch for camera shake/kicks and big screen flashes. 1 = full, 0 = off.
-- Lowered automatically when the player turned on Roblox's "Reduced Motion" setting, or when the local player
-- has the attribute ReduceShake = true (a settings menu can set it).
Juice.SHAKE_SCALE = 1
Juice.REDUCED_MOTION_SCALE = 0.3

local trauma = 0
local kickX, kickY, kickVX, kickVY = 0, 0, 0, 0
local zoom, zoomV = 0, 0
local fov, fovV = 0, 0
local holdAll = 0
local holds: { [number]: number } = {}
local slowStart, slowDuration, slowScale = 0, 0, 1
local focusPosition: Vector3? = nil
local focusStart, focusDuration, focusZoom = 0, 0, 0

-- Effective shake multiplier (0..1) after accessibility settings.
function Juice.shakeScale(): number
	local scale = Juice.SHAKE_SCALE
	local reduced = false
	pcall(function()
		reduced = GuiService.ReducedMotionEnabled
	end)
	local player = Players.LocalPlayer
	if reduced or (player and player:GetAttribute("ReduceShake") == true) then
		scale *= Juice.REDUCED_MOTION_SCALE
	end
	return scale
end

function Juice.addTrauma(amount: number)
	trauma = GameFeel.addTrauma(trauma, amount)
end

-- Kick the camera along (dx, dy) (a unit direction in the X/Y fight plane), strength 0..1.
function Juice.kick(dx: number, dy: number, strength: number)
	local v = TUNING.kickStuds * strength * 28
	kickVX += dx * v
	kickVY += dy * v
end

-- Pull the camera in by a fraction of its distance, springing back.
function Juice.zoomPunch(fraction: number)
	zoomV += fraction * 30
end

function Juice.fovPulse(degrees: number)
	fovV += degrees * 30
end

-- Hold the drawn fighters for `seconds` (local hitstop). Without slots every fighter holds.
function Juice.hold(seconds: number, slots: { number }?)
	if seconds <= 0 then
		return
	end
	local untilAt = os.clock() + seconds
	if slots then
		for _, slot in slots do
			holds[slot] = math.max(holds[slot] or 0, untilAt)
		end
	else
		holdAll = math.max(holdAll, untilAt)
	end
end

-- True while the fighter in `slot` (or, without a slot, the whole picture) is held.
function Juice.frozen(slot: number?): boolean
	local now = os.clock()
	if now < holdAll then
		return true
	end
	if slot then
		local untilAt = holds[slot]
		return untilAt ~= nil and now < untilAt
	end
	return false
end

-- Slow motion for `seconds` at `scale` (eases back to 1 at the end).
function Juice.slowmo(scale: number, seconds: number)
	slowStart, slowDuration, slowScale = os.clock(), seconds, scale
end

function Juice.timeScale(): number
	return GameFeel.slowScale(os.clock() - slowStart, slowDuration, slowScale)
end

-- Steer the camera toward a world point for `seconds`, pulled in by `zoomFraction` (KO cam).
function Juice.focus(position: Vector3, seconds: number, zoomFraction: number)
	focusPosition = position
	focusStart, focusDuration, focusZoom = os.clock(), seconds, zoomFraction
end

export type CameraJuice = {
	offset: Vector3, -- added to the camera eye and (half) to the look target
	roll: number, -- degrees
	zoom: number, -- fraction of the distance to pull in (can be negative while springing back)
	fov: number, -- degrees added to the field of view
	focus: Vector3?, -- world point to blend the framing toward
	focusWeight: number, -- 0..1
}

-- Advance the springs and trauma; the fight camera calls this once per frame.
function Juice.step(dt: number): CameraJuice
	trauma = GameFeel.decayTrauma(trauma, dt)
	kickX, kickVX = GameFeel.spring(kickX, kickVX, dt)
	kickY, kickVY = GameFeel.spring(kickY, kickVY, dt)
	zoom, zoomV = GameFeel.spring(zoom, zoomV, dt)
	fov, fovV = GameFeel.spring(fov, fovV, dt)
	local scale = Juice.shakeScale()
	local sx, sy, roll = GameFeel.shake(trauma, os.clock(), scale)
	local weight = 0
	local elapsed = os.clock() - focusStart
	if focusPosition and elapsed < focusDuration then
		local f = elapsed / focusDuration
		-- Quick ease in, hold, ease out over the last third.
		weight = math.min(1, f / 0.12)
		if f > 0.66 then
			local k = (1 - f) / 0.34
			weight = math.min(weight, k * k * (3 - 2 * k))
		end
	else
		focusPosition = nil
	end
	return {
		offset = Vector3.new(sx + kickX * scale, sy + kickY * scale, 0),
		roll = roll,
		zoom = zoom * math.max(scale, 0.5) + focusZoom * weight,
		fov = fov * math.max(scale, 0.5),
		focus = focusPosition,
		focusWeight = weight,
	}
end

-- Forget everything (new match, back to the lobby).
function Juice.reset()
	trauma = 0
	kickX, kickY, kickVX, kickVY = 0, 0, 0, 0
	zoom, zoomV, fov, fovV = 0, 0, 0, 0
	holdAll = 0
	table.clear(holds)
	slowDuration = 0
	focusPosition = nil
end

return Juice
