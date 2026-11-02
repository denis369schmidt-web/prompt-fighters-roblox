--!strict
-- Moves tagged decoration (Shared/Visual/DecorMotion) on this client only: turning signs, swaying flags, passing
-- ships, pulsing neon in workspace.Arena and workspace.Lobby. Cheap by design: 30 updates per second at most, one
-- BulkMoveTo per scene, and a scene the camera is far away from (the lobby during a match) is skipped entirely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DecorMotion = require(ReplicatedStorage.Shared.Visual.DecorMotion)

local STEP = 1 / 30
local VIEW_RANGE = 650 -- studs from the camera to a scene's center before it stops animating
local SCENES = { Arena = true, Lobby = true }

type Mover = { part: BasePart, base: CFrame, motion: DecorMotion.Motion }
type Pulser = { part: BasePart, base: number, motion: DecorMotion.Motion }
type Scene = { model: Model, center: Vector3, movers: { Mover }, pulsers: { Pulser } }

local scenes: { [Model]: Scene } = {}

local function register(scene: Scene, d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	local motion = DecorMotion.read(d)
	if motion == nil then
		return
	end
	if motion.kind == "pulse" then
		table.insert(scene.pulsers, { part = d, base = d.Transparency, motion = motion })
	else
		table.insert(scene.movers, { part = d, base = d.CFrame, motion = motion })
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or not SCENES[model.Name] or scenes[model] then
		return
	end
	local anchor = model:FindFirstChild("Floor") or model:FindFirstChild("Stage")
	local scene: Scene = {
		model = model,
		center = if anchor and anchor:IsA("BasePart") then anchor.Position else model:GetPivot().Position,
		movers = {},
		pulsers = {},
	}
	scenes[model] = scene
	for _, d in model:GetDescendants() do
		register(scene, d)
	end
	model.DescendantAdded:Connect(function(d)
		register(scene, d)
	end)
	model.Destroying:Connect(function()
		scenes[model] = nil
	end)
end

for _, child in workspace:GetChildren() do
	track(child)
end
workspace.ChildAdded:Connect(track)
workspace.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		scenes[child] = nil
	end
end)

local clock, pending = 0, 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	pending += dt
	if pending < STEP then
		return
	end
	pending = 0
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, scene in scenes do
		if (eye - scene.center).Magnitude > VIEW_RANGE then
			continue
		end
		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		local alive = 1
		for _, mover in scene.movers do
			if mover.part.Parent == nil then
				continue
			end
			scene.movers[alive] = mover
			alive += 1
			table.insert(parts, mover.part)
			table.insert(frames, DecorMotion.cframe(mover.motion, mover.base, clock))
		end
		for i = #scene.movers, alive, -1 do
			scene.movers[i] = nil
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		for _, pulser in scene.pulsers do
			pulser.part.Transparency = DecorMotion.transparency(pulser.motion, pulser.base, clock)
		end
	end
end)
