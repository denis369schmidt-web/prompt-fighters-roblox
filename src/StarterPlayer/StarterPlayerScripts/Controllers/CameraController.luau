--!strict
-- Side-view fight camera: frames every fighter still in the match, zooms out as they spread apart and
-- shakes on big hits. In the lobby it slowly pans across the arena.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Visuals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Visuals"))
local MatchState = require(script.Parent.Parent.State.MatchState)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local MIN_DISTANCE = 42
local MAX_DISTANCE = 95
local FOLLOW = 5

local CameraController = {}

local shake = 0
local focus = Vector3.new(0, BASE_Y + 8, 0)
local distance = 70

function CameraController.shake(amount: number)
	shake = math.max(shake, amount)
end

local function frame(dt: number)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 40
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
		targetDistance = math.clamp(MIN_DISTANCE + spread * M * 1.1, MIN_DISTANCE, MAX_DISTANCE)
	else
		local t = os.clock() * 0.15
		targetFocus = Vector3.new(math.sin(t) * 18, BASE_Y + 10, 0)
		targetDistance = 80
	end
	local alpha = 1 - math.exp(-FOLLOW * dt)
	focus = focus:Lerp(targetFocus, alpha)
	distance += (targetDistance - distance) * alpha

	shake = math.max(0, shake - dt * 3)
	local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake * 2
	local eye = focus + Vector3.new(0, distance * 0.12, distance) + jitter
	camera.CFrame = CFrame.lookAt(eye, focus + jitter * 0.5)
end

function CameraController.start()
	MatchState.onEvent(function(event)
		if event.type == "hit" and (event.impulse or 0) > 9 then
			CameraController.shake(math.clamp(event.impulse / 15, 0.3, 1.2))
		elseif event.type == "ring_out" or event.type == "finisher" then
			CameraController.shake(1.2)
		end
	end)
	RunService:BindToRenderStep("FightCamera", Enum.RenderPriority.Camera.Value + 1, frame)
end

return CameraController
