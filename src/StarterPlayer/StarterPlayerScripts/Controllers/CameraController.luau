--!strict
-- Side-view fight camera: frames every fighter still in the match and zooms out as they spread apart.
-- Game feel comes from Controllers/Juice: trauma shake (smooth noise, decays), a kick toward the hit direction,
-- zoom punches on heavy hits, an FOV pulse on supers and a slow-motion KO cam on the match-deciding KO. In the lobby the normal Roblox camera follows the player's avatar, and avatar controls are
-- switched off while a match runs (the same keys drive the fighter then).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Visuals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Visuals"))
local GameFeel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Visual"):WaitForChild("GameFeel"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local Juice = require(script.Parent.Juice)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local MIN_DISTANCE = 27
local MAX_DISTANCE = 62
local FOLLOW = 5
local BASE_FOV = 40
local TUNING = GameFeel.TUNING

local CameraController = {}

local focus = Vector3.new(0, BASE_Y + 8, 0)
local distance = 70

-- Old entry point (0..1.2 "amount"); now adds camera trauma.
function CameraController.shake(amount: number)
	Juice.addTrauma(math.clamp(amount, 0, 1.2) * 0.6)
end

local function frame(dt: number)
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if MatchState.phase == "lobby" and humanoid then
		if camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
			camera.FieldOfView = 70
		end
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local juice = Juice.step(dt)
	camera.FieldOfView = BASE_FOV + juice.fov
	local snap = MatchState.snapshot
	local targetFocus, targetDistance
	if snap and MatchState.phase ~= "lobby" then
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, f in snap.fighters do
			if f.state ~= "Defeated" then
				local x, y = math.clamp(f.x, -14, 14), math.clamp(f.y, -4, 10)
				minX, maxX = math.min(minX, x), math.max(maxX, x)
				minY, maxY = math.min(minY, y), math.max(maxY, y)
			end
		end
		if minX == math.huge then
			minX, maxX, minY, maxY = -4, 4, 0, 2
		end
		local spread = math.max(maxX - minX, (maxY - minY) * 1.6)
		targetFocus = Vector3.new((minX + maxX) / 2 * M, BASE_Y + ((minY + maxY) / 2 + 1.6) * M, 0)
		targetDistance = math.clamp(MIN_DISTANCE + spread * M * 0.95, MIN_DISTANCE, MAX_DISTANCE)
	else
		local t = os.clock() * 0.15
		targetFocus = Vector3.new(math.sin(t) * 18, BASE_Y + 10, 0)
		targetDistance = 80
	end
	local juiceFocus = juice.focus
	if juiceFocus and juice.focusWeight > 0 then
		targetFocus = targetFocus:Lerp(juiceFocus, juice.focusWeight * 0.85)
	end
	-- The KO dolly moves faster than the normal framing so the focus lands while the slow motion runs.
	local follow = if juice.focusWeight > 0 then FOLLOW * 2.2 else FOLLOW
	local alpha = 1 - math.exp(-follow * dt)
	focus = focus:Lerp(targetFocus, alpha)
	distance += (targetDistance - distance) * alpha
	-- Zoom punches and the KO dolly act on top of the smoothed distance (they are springs already).
	local shown = math.max(MIN_DISTANCE * 0.6, distance * (1 - juice.zoom))

	local offset = juice.offset
	local eye = focus + Vector3.new(0, shown * 0.12, shown) + offset
	camera.CFrame = CFrame.lookAt(eye, focus + offset * 0.5) * CFrame.Angles(0, 0, math.rad(juice.roll))
end

local function fighterXY(slot: number?): (number?, number?)
	local snap = MatchState.snapshot
	local f = if snap and slot then snap.fighters[slot] else nil
	if f then
		return f.x, f.y
	end
	return nil, nil
end

-- True when a KO leaves at most one fighter standing (the KO that decides the match).
local function decisive(loser: number): boolean
	local snap = MatchState.snapshot
	local standing = 0
	if snap then
		for i, f in snap.fighters do
			if i ~= loser and f.state ~= "Defeated" and f.lives > 0 then
				standing += 1
			end
		end
	end
	return snap ~= nil and standing <= 1
end

local function toWorld(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

local function onEvent(event: { [string]: any })
	local kind = event.type
	if kind == "phase" then
		Juice.reset()
	elseif kind == "hit" then
		local impact = GameFeel.impact(event.damage or 5, event.impulse, event.superHit, event.special)
		Juice.addTrauma(impact.trauma)
		local ax, ay = fighterXY(event.actor)
		local tx, ty = fighterXY(event.target)
		if ax and ay and tx and ty then
			local dx, dy = tx - ax, (ty - ay) * 0.5
			local length = math.sqrt(dx * dx + dy * dy)
			if length > 1e-3 then
				Juice.kick(dx / length, dy / length, impact.strength)
			end
		end
		if impact.tier == "heavy" then
			Juice.zoomPunch(TUNING.zoomPunchHeavy * (if event.superHit then 1.4 else 1))
		end
	elseif kind == "block" then
		Juice.addTrauma(TUNING.traumaLight * 0.7)
	elseif kind == "parry" or kind == "clash" then
		Juice.addTrauma(TUNING.traumaMedium)
		Juice.zoomPunch(TUNING.zoomPunchHeavy * 0.6)
	elseif kind == "shield_break" then
		Juice.addTrauma(TUNING.traumaHeavy)
		Juice.zoomPunch(TUNING.zoomPunchHeavy)
	elseif kind == "super_used" then
		Juice.fovPulse(TUNING.fovPulseSuper)
		Juice.addTrauma(TUNING.traumaMedium)
	elseif kind == "ring_out" then
		Juice.addTrauma(TUNING.traumaKo)
		local x, y = event.x or 0, event.y or 0
		local dx, dy = GameFeel.koDirection(x, y)
		Juice.kick(-dx, -dy, 1)
		Juice.zoomPunch(TUNING.zoomPunchKo)
		if (event.lives or 0) <= 0 and decisive(event.actor) then
			Juice.slowmo(TUNING.koSlowScale, TUNING.koSlowSeconds)
			local px, py = math.clamp(x, -14, 14), math.clamp(y, -4, 11)
			Juice.focus(toWorld(px, py), TUNING.koFocusSeconds, 0.3)
		end
	elseif kind == "finisher" then
		Juice.addTrauma(TUNING.traumaKo)
		Juice.zoomPunch(TUNING.zoomPunchKo)
		Juice.slowmo(TUNING.koSlowScale, TUNING.koSlowSeconds)
		local x, y = fighterXY(event.target)
		if x and y then
			Juice.focus(toWorld(x, y + 1), TUNING.koFocusSeconds, 0.35)
		end
	elseif kind == "slam" or kind == "blast" then
		Juice.addTrauma(TUNING.traumaMedium)
	elseif kind == "iai_cut" then
		Juice.addTrauma(TUNING.traumaMedium)
		Juice.zoomPunch(TUNING.zoomPunchHeavy * 0.7)
	end
end

local function avatarControls(enabled: boolean)
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return
	end
	local ok, controls = pcall(function()
		return (require(module) :: any):GetControls()
	end)
	if ok and controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

function CameraController.start()
	MatchState.onEvent(function(event)
		if event.type == "phase" then
			avatarControls(event.phase == "lobby")
		end
		onEvent(event)
	end)
	RunService:BindToRenderStep("FightCamera", Enum.RenderPriority.Camera.Value + 1, frame)
end

return CameraController
