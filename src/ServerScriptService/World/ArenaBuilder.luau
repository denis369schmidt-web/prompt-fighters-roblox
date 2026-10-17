--!strict
-- Builds the visible arena from Combat/Arena geometry. Collision lives in the Simulation only; these parts are
-- anchored, non-colliding decoration so Roblox physics never fights the server's numbers.
-- Phase 1 ships one look (NEON-GASSE: dark street, neon edges, signs); other arenas reuse it with their layout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Arena = require(ReplicatedStorage.Shared.Combat.Arena)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y

local ArenaBuilder = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	neon: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = not neon
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function world(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

local function sign(parent: Instance, text: string, position: Vector3, color: Color3)
	local board = part(parent, "Sign", Vector3.new(14, 4, 0.4), position, Color3.fromRGB(12, 10, 24))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = gui
end

function ArenaBuilder.build(arenaId: string): Model
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Arena"

	local stageWidth = (Arena.STAGE_RIGHT - Arena.STAGE_LEFT) * M
	local stageDepth = 18
	local ground =
		part(model, "Stage", Vector3.new(stageWidth, 4 * M, stageDepth), world(0, -2), Color3.fromRGB(28, 26, 44))
	ground.Material = Enum.Material.Concrete
	-- Neon trims along the stage edge (front) and both ledges.
	local cyan, magenta = Color3.fromRGB(0, 240, 255), Color3.fromRGB(255, 40, 200)
	part(
		model,
		"TrimFront",
		Vector3.new(stageWidth, 0.3, 0.3),
		world(0, 0) + Vector3.new(0, -0.15, stageDepth / 2),
		cyan,
		true
	)
	part(model, "LedgeLeft", Vector3.new(0.4, 2, stageDepth), world(Arena.STAGE_LEFT, -0.3), magenta, true)
	part(model, "LedgeRight", Vector3.new(0.4, 2, stageDepth), world(Arena.STAGE_RIGHT, -0.3), magenta, true)

	for _, platform in Arena.platformsFor(arenaId) do
		local width = (platform.x2 - platform.x1) * M
		local center = (platform.x1 + platform.x2) / 2
		part(
			model,
			platform.name,
			Vector3.new(width, 0.6, 8),
			world(center, platform.y) - Vector3.new(0, 0.3, 0),
			Color3.fromRGB(40, 36, 70)
		)
		part(
			model,
			platform.name .. "Glow",
			Vector3.new(width, 0.12, 0.12),
			world(center, platform.y) + Vector3.new(0, 0, 4),
			cyan,
			true
		)
	end

	-- Back wall with signs: the street behind the fight.
	local wallZ = -stageDepth / 2 - 10
	part(model, "Backdrop", Vector3.new(220, 120, 2), Vector3.new(0, BASE_Y + 20, wallZ - 2), Color3.fromRGB(10, 8, 20))
	sign(model, "PROMPT", Vector3.new(-30, BASE_Y + 26, wallZ), magenta)
	sign(model, "FIGHTERS", Vector3.new(30, BASE_Y + 30, wallZ), cyan)
	sign(model, "NEON-GASSE", Vector3.new(0, BASE_Y + 42, wallZ), Color3.fromRGB(255, 220, 60))
	for k = -4, 4 do
		local height = 30 + (k * 37 % 23)
		part(
			model,
			"Tower",
			Vector3.new(16, height, 10),
			Vector3.new(k * 26, BASE_Y - 10 + height / 2, wallZ - 14),
			Color3.fromRGB(18, 14, 34)
		)
		part(
			model,
			"TowerLight",
			Vector3.new(16.2, 0.4, 0.4),
			Vector3.new(k * 26, BASE_Y - 10 + height, wallZ - 8.9),
			if k % 2 == 0 then cyan else magenta,
			true
		)
	end
	model.Parent = workspace

	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(70, 60, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 60, 110)
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.8
		bloom.Size = 30
		bloom.Threshold = 0.9
		bloom.Parent = Lighting
	end
	return model
end

return ArenaBuilder
