--!strict
-- Builds the visible arena from Combat/Arena geometry. Collision lives in the Simulation only; these parts are
-- anchored, non-colliding decoration so Roblox physics never fights the server's numbers.
-- Look: NEON-GASSE, a rainy night street. Wet glossy stage, neon trims, glowing platforms, street lamps,
-- skyline with lit windows, neon signs, fog and color grading. Other arenas reuse it with their layout for now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Arena = require(ReplicatedStorage.Shared.Combat.Arena)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y

local CYAN = Color3.fromRGB(0, 240, 255)
local MAGENTA = Color3.fromRGB(255, 40, 200)
local GOLD = Color3.fromRGB(255, 210, 60)

local ArenaBuilder = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame | Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	if typeof(cframe) == "CFrame" then
		p.CFrame = cframe
	else
		p.Position = cframe :: Vector3
	end
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CastShadow = material ~= Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function world(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function sign(parent: Instance, text: string, position: Vector3, color: Color3, width: number)
	local board = part(parent, "Sign", Vector3.new(width, 5, 0.4), position, Color3.fromRGB(8, 6, 16))
	local frame = part(
		parent,
		"SignFrame",
		Vector3.new(width + 0.6, 5.6, 0.2),
		position - Vector3.new(0, 0, 0.3),
		color,
		Enum.Material.Neon
	)
	frame.Transparency = 0.3
	light(board, color, 26, 2)
	local gui = Instance.new("SurfaceGui")
	-- Back face points toward the camera (+Z).
	gui.Face = Enum.NormalId.Back
	-- Few pixels per stud so TextScaled (capped at 100 px) fills the whole board instead of a corner of it.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 0
	gui.Brightness = 3
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

local function skyline(parent: Instance, z: number)
	for k = -6, 6 do
		local height = 40 + (k * 37 % 29) + math.abs(k) * 4
		local width = 18 + (k * 13 % 7)
		local x = k * 24
		local tower = part(
			parent,
			"Tower",
			Vector3.new(width, height, 14),
			Vector3.new(x, BASE_Y - 20 + height / 2, z),
			Color3.fromRGB(14, 11, 28)
		)
		tower.CastShadow = false
		-- Lit windows: a sparse grid of small warm squares (long strips read as floating lines on screen).
		for row = 1, math.floor(height / 7) do
			for col = -1, 1 do
				if (k * 7 + row * 3 + col * 5) % 4 == 0 then
					local window = part(
						parent,
						"Window",
						Vector3.new(2.2, 2.6, 0.1),
						Vector3.new(x + col * width * 0.28, BASE_Y - 20 + row * 7, z + 7.05),
						Color3.fromRGB(255, 196, 130),
						Enum.Material.Neon
					)
					window.Transparency = 0.55
				end
			end
		end
		if k % 3 == 0 then
			part(
				parent,
				"Roofline",
				Vector3.new(width + 0.4, 0.5, 0.5),
				Vector3.new(x, BASE_Y - 20 + height, z + 7.1),
				if k % 2 == 0 then CYAN else MAGENTA,
				Enum.Material.Neon
			)
		end
	end
end

local function lamp(parent: Instance, x: number, z: number)
	local base = world(x, 0)
	part(
		parent,
		"LampPost",
		Vector3.new(0.5, 16, 0.5),
		base + Vector3.new(0, 8, z),
		Color3.fromRGB(30, 30, 40),
		Enum.Material.Metal
	)
	part(
		parent,
		"LampArm",
		Vector3.new(3, 0.4, 0.4),
		base + Vector3.new(x > 0 and -1.3 or 1.3, 16, z),
		Color3.fromRGB(30, 30, 40),
		Enum.Material.Metal
	)
	local bulb = part(
		parent,
		"LampBulb",
		Vector3.new(1.4, 0.6, 1.4),
		base + Vector3.new(x > 0 and -2.6 or 2.6, 15.6, z),
		Color3.fromRGB(255, 220, 170),
		Enum.Material.Neon
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = 30
	spot.Brightness = 3
	spot.Color = Color3.fromRGB(255, 210, 160)
	spot.Parent = bulb
end

-- Invisible stage lights in front of the fight so fighters read clearly at night.
local function keyLights(parent: Instance)
	for _, x in { -6, 0, 6 } do
		local holder = part(parent, "KeyLight", Vector3.one, world(x, 7) + Vector3.new(0, 0, 14), Color3.new(1, 1, 1))
		holder.Transparency = 1
		light(holder, Color3.fromRGB(225, 215, 255), 50, 2.5)
	end
end

local function rain(parent: Instance)
	local cloud =
		part(parent, "RainCloud", Vector3.new(160, 1, 60), Vector3.new(0, BASE_Y + 70, 0), Color3.new(0, 0, 0))
	cloud.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Rate = 400
	emitter.Lifetime = NumberRange.new(1.2, 1.6)
	emitter.Speed = NumberRange.new(70, 90)
	emitter.Size = NumberSequence.new(0.12)
	emitter.Squash = NumberSequence.new(-4)
	emitter.Transparency = NumberSequence.new(0.55)
	emitter.Color = ColorSequence.new(Color3.fromRGB(170, 200, 255))
	emitter.LightEmission = 0.4
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Parent = cloud
end

local function grade()
	Lighting.ClockTime = 0
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.4
	Lighting.Ambient = Color3.fromRGB(140, 130, 175)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 190)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.12
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(120, 80, 170)
	atmosphere.Decay = Color3.fromRGB(90, 60, 140)
	atmosphere.Glare = 0
	atmosphere.Haze = 0.6
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 1
	bloom.Size = 28
	bloom.Threshold = 0.85
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.12
	cc.Saturation = 0.2
	cc.TintColor = Color3.fromRGB(240, 230, 255)
	cc.Parent = Lighting
end

function ArenaBuilder.build(arenaId: string): Model
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Arena"

	local stageWidth = (Arena.STAGE_RIGHT - Arena.STAGE_LEFT) * M
	local depth = 20
	-- Stage block with a glossy wet top and a darker front face.
	part(
		model,
		"Stage",
		Vector3.new(stageWidth, 4 * M, depth),
		world(0, -2),
		Color3.fromRGB(30, 27, 46),
		Enum.Material.Concrete
	)
	-- Front face: dark steel panels with seams, so the block reads as a street platform and not one flat wall.
	local panels = 8
	for k = 0, panels - 1 do
		local x = Arena.STAGE_LEFT + (k + 0.5) * (Arena.STAGE_RIGHT - Arena.STAGE_LEFT) / panels
		part(
			model,
			"Panel",
			Vector3.new(stageWidth / panels - 0.5, 4 * M - 2.2, 0.3),
			world(x, -2.1) + Vector3.new(0, 0, depth / 2 + 0.1),
			if k % 2 == 0 then Color3.fromRGB(38, 34, 56) else Color3.fromRGB(33, 30, 50),
			Enum.Material.DiamondPlate
		)
	end
	local top = part(
		model,
		"StageTop",
		Vector3.new(stageWidth, 0.2, depth),
		world(0, 0) - Vector3.new(0, 0.1, 0),
		Color3.fromRGB(58, 52, 86)
	)
	top.Reflectance = 0.3
	part(
		model,
		"Underside",
		Vector3.new(stageWidth * 0.7, 6 * M, depth * 0.6),
		world(0, -6.5),
		Color3.fromRGB(20, 16, 34),
		Enum.Material.Metal
	)
	part(
		model,
		"TrimFront",
		Vector3.new(stageWidth, 0.35, 0.35),
		world(0, 0) + Vector3.new(0, -0.2, depth / 2),
		CYAN,
		Enum.Material.Neon
	)
	part(
		model,
		"TrimBack",
		Vector3.new(stageWidth, 0.35, 0.35),
		world(0, 0) + Vector3.new(0, -0.2, -depth / 2),
		MAGENTA,
		Enum.Material.Neon
	)
	part(
		model,
		"TrimLower",
		Vector3.new(stageWidth * 0.98, 0.25, 0.25),
		world(0, -0.35) + Vector3.new(0, 0, depth / 2 + 0.35),
		MAGENTA,
		Enum.Material.Neon
	)
	local ledgeL = part(
		model,
		"LedgeLeft",
		Vector3.new(0.5, 2.5, depth),
		world(Arena.STAGE_LEFT, -0.35),
		MAGENTA,
		Enum.Material.Neon
	)
	local ledgeR = part(
		model,
		"LedgeRight",
		Vector3.new(0.5, 2.5, depth),
		world(Arena.STAGE_RIGHT, -0.35),
		MAGENTA,
		Enum.Material.Neon
	)
	light(ledgeL, MAGENTA, 18, 1.5)
	light(ledgeR, MAGENTA, 18, 1.5)
	-- Street markings on the stage.
	for k = -3, 3 do
		part(
			model,
			"Marking",
			Vector3.new(3, 0.05, 0.4),
			world(k * 2.4, 0.01),
			Color3.fromRGB(220, 200, 90),
			Enum.Material.Neon
		).Transparency =
			0.5
	end

	for _, platform in Arena.platformsFor(arenaId) do
		local width = (platform.x2 - platform.x1) * M
		local center = (platform.x1 + platform.x2) / 2
		local slab = part(
			model,
			platform.name,
			Vector3.new(width, 0.7, 8),
			world(center, platform.y) - Vector3.new(0, 0.35, 0),
			Color3.fromRGB(44, 40, 76),
			Enum.Material.Metal
		)
		slab.Reflectance = 0.1
		local glow = part(
			model,
			platform.name .. "Glow",
			Vector3.new(width, 0.15, 0.15),
			world(center, platform.y) + Vector3.new(0, -0.05, 4),
			CYAN,
			Enum.Material.Neon
		)
		local under = part(
			model,
			platform.name .. "Under",
			Vector3.new(width * 0.8, 0.1, 6),
			world(center, platform.y) - Vector3.new(0, 0.75, 0),
			CYAN,
			Enum.Material.Neon
		)
		under.Transparency = 0.6
		local surface = Instance.new("SurfaceLight")
		surface.Face = Enum.NormalId.Bottom
		surface.Color = CYAN
		surface.Range = 10
		surface.Brightness = 1.5
		surface.Angle = 90
		surface.Parent = glow
	end

	lamp(model, Arena.STAGE_LEFT + 0.6, -depth / 2 + 1)
	lamp(model, Arena.STAGE_RIGHT - 0.6, -depth / 2 + 1)

	-- Back street: wall, signs, skyline.
	local wallZ = -depth / 2 - 12
	part(
		model,
		"Backdrop",
		Vector3.new(260, 140, 2),
		Vector3.new(0, BASE_Y + 10, wallZ - 60),
		Color3.fromRGB(10, 7, 22)
	)
	sign(model, "PROMPT", Vector3.new(-34, BASE_Y + 24, wallZ), MAGENTA, 16)
	sign(model, "FIGHTERS", Vector3.new(34, BASE_Y + 28, wallZ), CYAN, 18)
	sign(model, "NEON-GASSE", Vector3.new(0, BASE_Y + 40, wallZ - 6), GOLD, 22)
	skyline(model, wallZ - 45)
	keyLights(model)
	rain(model)

	model.Parent = workspace
	grade()
	return model
end

return ArenaBuilder
