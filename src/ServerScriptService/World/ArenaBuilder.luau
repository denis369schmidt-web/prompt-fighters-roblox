--!strict
-- Builds the visible arena from Combat/Arena geometry and Data/ArenaThemes. Collision lives in the Simulation only;
-- these parts are anchored, non-colliding decoration so Roblox physics never fights the server's numbers.
-- Every arena shares the stage and platform layout code; its motif (street, temple, dojo, colosseum, stadium,
-- mountains, warehouse, foundry, space, hangar, war zone, ...) decides materials, backdrop props, weather and light.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Arena = require(ReplicatedStorage.Shared.Combat.Arena)
local ArenaThemes = require(ReplicatedStorage.Shared.Data.ArenaThemes)
local Arenas = require(ReplicatedStorage.Shared.Data.Arenas)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local DEPTH = 20 -- stage depth in studs (toward the camera is +Z)
local WALL_Z = -DEPTH / 2 - 12

local ArenaBuilder = {}

type Ctx = {
	model: Model,
	theme: ArenaThemes.Theme,
	trim: Color3,
	accent: Color3,
	name: string,
	rng: Random,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame | Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if shape then
		p.Shape = shape
	end
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

local function wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.Parent = parent
	return w
end

-- Simulation meters (x, y) to a world position on the fight plane (z = 0).
local function world(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

-- Backdrop position in studs relative to the stage surface center.
local function at(x: number, y: number, z: number): Vector3
	return Vector3.new(x, BASE_Y + y, z)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function glowBall(ctx: Ctx, name: string, position: Vector3, size: number, color: Color3, range: number?)
	local b = part(ctx.model, name, Vector3.one * size, position, color, Enum.Material.Neon, Enum.PartType.Ball)
	if range then
		light(b, color, range, 1.5)
	end
	return b
end

local function sign(ctx: Ctx, text: string, position: Vector3, color: Color3, width: number)
	local board = part(ctx.model, "Sign", Vector3.new(width, 5, 0.4), position, rgb(8, 6, 16))
	local frame = part(
		ctx.model,
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

-- Wide floor far below the stage, so the void reads as a place (sand, snow, lava, street) instead of sky.
local function ground(ctx: Ctx, color: Color3, material: Enum.Material, y: number?)
	return part(ctx.model, "Ground", Vector3.new(420, 2, 320), at(0, y or -40, -100), color, material)
end

local function tree(ctx: Ctx, x: number, z: number, height: number, leaf: Color3)
	local base = at(x, -40, z)
	part(
		ctx.model,
		"Trunk",
		Vector3.new(2.2, height, 2.2),
		base + Vector3.new(0, height / 2, 0),
		rgb(84, 58, 40),
		Enum.Material.Wood
	)
	for k = 0, 2 do
		part(
			ctx.model,
			"Leaves",
			Vector3.one * (13 - k * 3),
			base + Vector3.new((k - 1) * 3, height + k * 4, (k % 2) * 2),
			leaf,
			Enum.Material.Grass,
			Enum.PartType.Ball
		)
	end
end

local function pine(ctx: Ctx, x: number, z: number, height: number, snowy: boolean)
	local base = at(x, -40, z)
	part(
		ctx.model,
		"Trunk",
		Vector3.new(1.6, height * 0.3, 1.6),
		base + Vector3.new(0, height * 0.15, 0),
		rgb(70, 50, 36)
	)
	for k = 0, 3 do
		local w = (4 - k) * height * 0.11
		local y = height * (0.25 + k * 0.19)
		for side = 0, 1 do
			wedge(
				ctx.model,
				"Needles",
				Vector3.new(w * 2, height * 0.22, w),
				CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, side * math.pi, 0) * CFrame.new(0, 0, -w / 2),
				if snowy and k == 3 then rgb(235, 242, 250) else rgb(36, 74, 58),
				Enum.Material.Grass
			)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Stage and platforms
--------------------------------------------------------------------------------------------------------------------

type StageStyle = {
	side: Color3,
	top: Color3,
	sideMaterial: Enum.Material,
	topMaterial: Enum.Material,
	reflect: number,
	platform: Color3,
	platformMaterial: Enum.Material,
}

local function style(
	side: Color3,
	top: Color3,
	sideMaterial: Enum.Material,
	topMaterial: Enum.Material,
	reflect: number,
	platform: Color3,
	platformMaterial: Enum.Material
): StageStyle
	return {
		side = side,
		top = top,
		sideMaterial = sideMaterial,
		topMaterial = topMaterial,
		reflect = reflect,
		platform = platform,
		platformMaterial = platformMaterial,
	}
end

local STYLES: { [string]: StageStyle } = {
	city_street = style(
		rgb(30, 27, 46),
		rgb(58, 52, 86),
		Enum.Material.Concrete,
		Enum.Material.SmoothPlastic,
		0.3,
		rgb(44, 40, 76),
		Enum.Material.Metal
	),
	city_roof = style(
		rgb(52, 56, 66),
		rgb(40, 42, 50),
		Enum.Material.Concrete,
		Enum.Material.Asphalt,
		0.25,
		rgb(70, 74, 86),
		Enum.Material.Metal
	),
	scifi_city = style(
		rgb(24, 32, 52),
		rgb(36, 50, 80),
		Enum.Material.Metal,
		Enum.Material.Glass,
		0.35,
		rgb(30, 44, 74),
		Enum.Material.Glass
	),
	temple = style(
		rgb(86, 88, 100),
		rgb(120, 118, 128),
		Enum.Material.Slate,
		Enum.Material.Cobblestone,
		0,
		rgb(110, 104, 96),
		Enum.Material.Slate
	),
	dojo = style(
		rgb(92, 52, 34),
		rgb(168, 116, 70),
		Enum.Material.Wood,
		Enum.Material.WoodPlanks,
		0.05,
		rgb(140, 90, 52),
		Enum.Material.WoodPlanks
	),
	colosseum = style(
		rgb(176, 146, 104),
		rgb(184, 156, 110),
		Enum.Material.Sandstone,
		Enum.Material.Sand,
		0,
		rgb(188, 160, 116),
		Enum.Material.Sandstone
	),
	stadium = style(
		rgb(46, 50, 62),
		rgb(60, 66, 80),
		Enum.Material.Metal,
		Enum.Material.DiamondPlate,
		0.1,
		rgb(70, 76, 92),
		Enum.Material.Metal
	),
	mountains = style(
		rgb(84, 90, 104),
		rgb(232, 240, 250),
		Enum.Material.Rock,
		Enum.Material.Snow,
		0,
		rgb(200, 220, 236),
		Enum.Material.Ice
	),
	industrial = style(
		rgb(60, 58, 54),
		rgb(84, 82, 76),
		Enum.Material.CorrodedMetal,
		Enum.Material.DiamondPlate,
		0.1,
		rgb(96, 84, 60),
		Enum.Material.Wood
	),
	foundry = style(
		rgb(34, 30, 30),
		rgb(56, 48, 46),
		Enum.Material.Metal,
		Enum.Material.DiamondPlate,
		0.15,
		rgb(58, 46, 40),
		Enum.Material.Metal
	),
	space = style(
		rgb(36, 38, 54),
		rgb(54, 58, 80),
		Enum.Material.Metal,
		Enum.Material.Metal,
		0.3,
		rgb(48, 52, 76),
		Enum.Material.Metal
	),
	space_interior = style(
		rgb(70, 76, 90),
		rgb(96, 104, 120),
		Enum.Material.Metal,
		Enum.Material.DiamondPlate,
		0.2,
		rgb(110, 118, 134),
		Enum.Material.Metal
	),
	war = style(
		rgb(74, 66, 56),
		rgb(96, 86, 70),
		Enum.Material.Concrete,
		Enum.Material.Ground,
		0,
		rgb(90, 84, 74),
		Enum.Material.Concrete
	),
}

local function buildStage(ctx: Ctx, arenaId: string, s: StageStyle)
	local model = ctx.model
	local stageWidth = (Arena.STAGE_RIGHT - Arena.STAGE_LEFT) * M
	part(model, "Stage", Vector3.new(stageWidth, 4 * M, DEPTH), world(0, -2), s.side, s.sideMaterial)
	local top = part(
		model,
		"StageTop",
		Vector3.new(stageWidth, 0.2, DEPTH),
		world(0, 0) - Vector3.new(0, 0.1, 0),
		s.top,
		s.topMaterial
	)
	top.Reflectance = s.reflect
	-- Front face: panels with seams, so the block reads as a built platform and not one flat wall.
	local panels = 8
	for k = 0, panels - 1 do
		local x = Arena.STAGE_LEFT + (k + 0.5) * (Arena.STAGE_RIGHT - Arena.STAGE_LEFT) / panels
		local h, sat, v = s.side:ToHSV()
		part(
			model,
			"Panel",
			Vector3.new(stageWidth / panels - 0.5, 4 * M - 2.2, 0.3),
			world(x, -2.1) + Vector3.new(0, 0, DEPTH / 2 + 0.1),
			Color3.fromHSV(h, sat, math.clamp(v * (if k % 2 == 0 then 1.2 else 1.05), 0, 1)),
			s.sideMaterial
		)
	end
	part(
		model,
		"Underside",
		Vector3.new(stageWidth * 0.7, 6 * M, DEPTH * 0.6),
		world(0, -6.5),
		s.side:Lerp(Color3.new(0, 0, 0), 0.4),
		s.sideMaterial
	)
	part(
		model,
		"TrimFront",
		Vector3.new(stageWidth, 0.35, 0.35),
		world(0, 0) + Vector3.new(0, -0.2, DEPTH / 2),
		ctx.accent,
		Enum.Material.Neon
	)
	part(
		model,
		"TrimBack",
		Vector3.new(stageWidth, 0.35, 0.35),
		world(0, 0) + Vector3.new(0, -0.2, -DEPTH / 2),
		ctx.trim,
		Enum.Material.Neon
	)
	for _, x in { Arena.STAGE_LEFT, Arena.STAGE_RIGHT } do
		local ledge = part(model, "Ledge", Vector3.new(0.5, 2.5, DEPTH), world(x, -0.35), ctx.trim, Enum.Material.Neon)
		light(ledge, ctx.trim, 18, 1.5)
	end

	for _, platform in Arena.platformsFor(arenaId) do
		local width = (platform.x2 - platform.x1) * M
		local center = (platform.x1 + platform.x2) / 2
		local slab = part(
			model,
			platform.name,
			Vector3.new(width, 0.7, 8),
			world(center, platform.y) - Vector3.new(0, 0.35, 0),
			s.platform,
			s.platformMaterial
		)
		slab.Reflectance = s.reflect * 0.4
		local glow = part(
			model,
			platform.name .. "Glow",
			Vector3.new(width, 0.15, 0.15),
			world(center, platform.y) + Vector3.new(0, -0.05, 4),
			ctx.accent,
			Enum.Material.Neon
		)
		local under = part(
			model,
			platform.name .. "Under",
			Vector3.new(width * 0.8, 0.1, 6),
			world(center, platform.y) - Vector3.new(0, 0.75, 0),
			ctx.accent,
			Enum.Material.Neon
		)
		under.Transparency = 0.82
		local surface = Instance.new("SurfaceLight")
		surface.Face = Enum.NormalId.Bottom
		surface.Color = ctx.accent
		surface.Range = 10
		surface.Brightness = 1.5
		surface.Angle = 90
		surface.Parent = glow
	end
end

-- Invisible lights in front of the fight so fighters read clearly in every arena.
local function keyLights(ctx: Ctx)
	for _, x in { -6, 0, 6 } do
		local holder = part(ctx.model, "KeyLight", Vector3.one, world(x, 7) + Vector3.new(0, 0, 14), rgb(255, 255, 255))
		holder.Transparency = 1
		light(holder, rgb(235, 230, 255), 50, 2.5)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Backdrops per motif
--------------------------------------------------------------------------------------------------------------------

local function skyline(ctx: Ctx, z: number, baseY: number, window: Color3)
	for k = -6, 6 do
		local height = 40 + (k * 37 % 29) + math.abs(k) * 4
		local width = 18 + (k * 13 % 7)
		local x = k * 24
		local tower = part(
			ctx.model,
			"Tower",
			Vector3.new(width, height, 14),
			at(x, baseY + height / 2, z),
			rgb(14, 11, 28),
			Enum.Material.SmoothPlastic
		)
		tower.CastShadow = false
		-- Lit windows: a sparse grid of small warm squares (long strips read as floating lines on screen).
		for row = 1, math.floor(height / 7) do
			for col = -1, 1 do
				if (k * 7 + row * 3 + col * 5) % 4 == 0 then
					local w = part(
						ctx.model,
						"Window",
						Vector3.new(2.2, 2.6, 0.1),
						at(x + col * width * 0.28, baseY + row * 7, z + 7.05),
						window,
						Enum.Material.Neon
					)
					w.Transparency = 0.55
				end
			end
		end
		if k % 3 == 0 then
			part(
				ctx.model,
				"Roofline",
				Vector3.new(width + 0.4, 0.5, 0.5),
				at(x, baseY + height, z + 7.1),
				if k % 2 == 0 then ctx.accent else ctx.trim,
				Enum.Material.Neon
			)
		end
	end
end

local function lamp(ctx: Ctx, x: number, z: number)
	local base = world(x, 0)
	local dark = rgb(30, 30, 40)
	part(ctx.model, "LampPost", Vector3.new(0.5, 16, 0.5), base + Vector3.new(0, 8, z), dark, Enum.Material.Metal)
	local dir = if x > 0 then -1 else 1
	part(
		ctx.model,
		"LampArm",
		Vector3.new(3, 0.4, 0.4),
		base + Vector3.new(dir * 1.3, 16, z),
		dark,
		Enum.Material.Metal
	)
	local bulb = part(
		ctx.model,
		"LampBulb",
		Vector3.new(1.4, 0.6, 1.4),
		base + Vector3.new(dir * 2.6, 15.6, z),
		rgb(255, 220, 170),
		Enum.Material.Neon
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = 30
	spot.Brightness = 3
	spot.Color = rgb(255, 210, 160)
	spot.Parent = bulb
end

local function backWall(ctx: Ctx, color: Color3, material: Enum.Material?, z: number?)
	return part(ctx.model, "Backdrop", Vector3.new(320, 160, 2), at(0, 10, z or WALL_Z - 60), color, material)
end

local GRAFFITI = { "#FF4DD2", "#4DFFEA", "#FFE14D", "#7CFF4D", "#FF7A2F", "#A07CFF" }

local MOTIFS: { [string]: (ctx: Ctx) -> () } = {}

MOTIFS.city_street = function(ctx)
	backWall(ctx, rgb(10, 7, 22))
	sign(ctx, "PROMPT", at(-34, 24, WALL_Z), ctx.trim, 16)
	sign(ctx, "FIGHTERS", at(34, 28, WALL_Z), ctx.accent, 18)
	sign(ctx, ctx.name, at(0, 40, WALL_Z - 6), rgb(255, 210, 60), math.max(22, #ctx.name * 2))
	lamp(ctx, Arena.STAGE_LEFT + 0.6, -DEPTH / 2 + 1)
	lamp(ctx, Arena.STAGE_RIGHT - 0.6, -DEPTH / 2 + 1)
	if ctx.theme.variant == "graffiti" then
		-- A low brick wall full of color blocks right behind the stage.
		part(
			ctx.model,
			"GraffitiWall",
			Vector3.new(150, 26, 2),
			at(0, -4, WALL_Z + 2),
			rgb(70, 40, 48),
			Enum.Material.Brick
		)
		for k = 1, 18 do
			local c = Color3.fromHex(GRAFFITI[(k % #GRAFFITI) + 1])
			part(
				ctx.model,
				"Tag",
				Vector3.new(4 + ctx.rng:NextNumber() * 8, 2 + ctx.rng:NextNumber() * 5, 0.2),
				CFrame.new(at(-70 + k * 7.8, -6 + ctx.rng:NextNumber() * 14, WALL_Z + 3.1))
					* CFrame.Angles(0, 0, (ctx.rng:NextNumber() - 0.5) * 0.5),
				c,
				Enum.Material.SmoothPlastic
			)
		end
	else
		-- Market stalls with paper lanterns along the back of the street.
		for k = -3, 3 do
			local x = k * 22
			part(ctx.model, "Stall", Vector3.new(14, 8, 6), at(x, -4, WALL_Z + 4), rgb(40, 30, 46), Enum.Material.Wood)
			wedge(
				ctx.model,
				"Awning",
				Vector3.new(15, 2, 5),
				CFrame.new(at(x, 1, WALL_Z + 8)),
				if k % 2 == 0 then ctx.trim else ctx.accent,
				Enum.Material.Fabric
			)
			glowBall(ctx, "Lantern", at(x - 4, 5, WALL_Z + 9), 1.6, rgb(255, 150, 80), if k % 2 == 0 then 14 else nil)
			glowBall(ctx, "Lantern", at(x + 4, 5, WALL_Z + 9), 1.6, rgb(255, 90, 90))
		end
	end
	skyline(ctx, WALL_Z - 45, -20, rgb(255, 196, 130))
end

MOTIFS.city_roof = function(ctx)
	backWall(ctx, rgb(8, 8, 20))
	-- We stand on a rooftop: the rest of the city is lower and further away.
	skyline(ctx, WALL_Z - 30, -70, rgb(255, 210, 150))
	skyline(ctx, WALL_Z - 70, -50, ctx.accent)
	-- Railing posts and a water tank on the roof.
	for k = -10, 10, 2 do
		part(
			ctx.model,
			"Rail",
			Vector3.new(0.3, 3, 0.3),
			world(k * 0.95, 0) + Vector3.new(0, 1.5, -DEPTH / 2 + 0.5),
			rgb(120, 126, 140),
			Enum.Material.Metal
		)
	end
	local tankX = -42
	for _, dx in { -3, 3 } do
		for _, dz in { -3, 3 } do
			part(
				ctx.model,
				"TankLeg",
				Vector3.new(0.6, 12, 0.6),
				at(tankX + dx, 6, WALL_Z + dz),
				rgb(60, 50, 44),
				Enum.Material.Metal
			)
		end
	end
	part(
		ctx.model,
		"Tank",
		Vector3.new(12, 10, 10),
		CFrame.new(at(tankX, 17, WALL_Z)) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(110, 80, 60),
		Enum.Material.Wood,
		Enum.PartType.Cylinder
	)
	part(
		ctx.model,
		"Antenna",
		Vector3.new(0.5, 34, 0.5),
		at(40, 17, WALL_Z - 4),
		rgb(140, 140, 150),
		Enum.Material.Metal
	)
	glowBall(ctx, "Beacon", at(40, 34.5, WALL_Z - 4), 1.2, rgb(255, 40, 40), 20)
	for k = 0, 2 do
		part(
			ctx.model,
			"AirCon",
			Vector3.new(6, 4, 5),
			at(20 + k * 7, 2, WALL_Z + 3),
			rgb(150, 154, 162),
			Enum.Material.Metal
		)
	end
	sign(ctx, ctx.name, at(-10, 30, WALL_Z - 20), ctx.trim, math.max(22, #ctx.name * 2))
	if ctx.theme.variant == "storm" then
		-- Lightning: a sky light that flashes every few seconds while the arena exists.
		local flash = part(ctx.model, "Lightning", Vector3.one, at(0, 80, -40), rgb(255, 255, 255))
		flash.Transparency = 1
		local l = Instance.new("PointLight")
		l.Range = 200
		l.Brightness = 0
		l.Color = rgb(200, 210, 255)
		l.Parent = flash
		task.spawn(function()
			while flash.Parent do
				task.wait(3 + math.random() * 4)
				l.Brightness = 6
				task.wait(0.08)
				l.Brightness = 0
				task.wait(0.1)
				l.Brightness = 4
				task.wait(0.06)
				l.Brightness = 0
			end
		end)
	end
end

MOTIFS.scifi_city = function(ctx)
	backWall(ctx, rgb(6, 10, 26))
	for k = -7, 7 do
		local height = 70 + (k * 23 % 40)
		local width = 10 + (k * 7 % 5)
		local x = k * 18
		local z = WALL_Z - 30 - (k % 3) * 18
		part(
			ctx.model,
			"Spire",
			Vector3.new(width, height, width),
			at(x, -30 + height / 2, z),
			rgb(18, 26, 48),
			Enum.Material.Glass
		)
		-- Vertical light strips (vertical lines read as architecture, not clutter).
		part(
			ctx.model,
			"Strip",
			Vector3.new(0.5, height * 0.8, 0.2),
			at(x, -30 + height * 0.5, z + width / 2 + 0.15),
			if k % 2 == 0 then ctx.trim else ctx.accent,
			Enum.Material.Neon
		)
		if k % 3 == 0 then
			local ring = part(
				ctx.model,
				"HoloRing",
				Vector3.new(0.6, width * 2.2, width * 2.2),
				CFrame.new(at(x, -30 + height * 0.7, z)) * CFrame.Angles(0, 0, math.pi / 2),
				ctx.accent,
				Enum.Material.Neon,
				Enum.PartType.Cylinder
			)
			ring.Transparency = 0.7
		end
	end
	-- Hover cars parked in the air.
	for k = 1, 6 do
		local car = part(
			ctx.model,
			"HoverCar",
			Vector3.new(5, 1.6, 2.4),
			at(-60 + k * 20, 20 + (k * 7 % 15), WALL_Z - 10 - k * 3),
			rgb(220, 226, 240),
			Enum.Material.Metal
		)
		glowBall(ctx, "Thruster", car.Position - Vector3.new(0, 1, 0), 1, ctx.trim)
	end
	sign(ctx, ctx.name, at(0, 36, WALL_Z - 8), ctx.trim, math.max(22, #ctx.name * 2))
end

MOTIFS.temple = function(ctx)
	local jungle = ctx.theme.variant == "jungle"
	local stone = if jungle then rgb(96, 110, 90) else rgb(104, 104, 118)
	if jungle then
		ground(ctx, rgb(60, 92, 50), Enum.Material.Grass)
		for k = -6, 6 do
			tree(ctx, k * 22 + (k % 2) * 6, WALL_Z - 20 - (k % 3) * 14, 30 + (k * 11 % 14), rgb(52, 120, 60))
		end
	else
		backWall(ctx, rgb(14, 14, 34))
		glowBall(ctx, "Moon", at(46, 58, WALL_Z - 55), 28, rgb(236, 232, 210))
	end
	-- Stepped temple behind the stage.
	for tier = 0, 4 do
		local w = 90 - tier * 16
		part(
			ctx.model,
			"Step",
			Vector3.new(w, 6, 30 - tier * 4),
			at(0, -14 + tier * 6, WALL_Z - 24),
			stone,
			Enum.Material.Slate
		)
	end
	part(
		ctx.model,
		"Shrine",
		Vector3.new(16, 12, 10),
		at(0, 22, WALL_Z - 24),
		stone:Lerp(rgb(0, 0, 0), 0.15),
		Enum.Material.Slate
	)
	for side = -1, 1, 2 do
		wedge(
			ctx.model,
			"Roof",
			Vector3.new(24, 5, 9),
			CFrame.new(at(0, 30.5, WALL_Z - 24 + side * 4.5)) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			rgb(120, 40, 36),
			Enum.Material.Slate
		)
	end
	glowBall(ctx, "ShrineFire", at(0, 20, WALL_Z - 18.5), 2.4, ctx.trim, 30)
	-- Pillars with braziers.
	for k = -4, 4 do
		if k ~= 0 then
			local x = k * 15
			part(ctx.model, "Pillar", Vector3.new(3, 28, 3), at(x, -8, WALL_Z + 2), stone, Enum.Material.Slate)
			part(
				ctx.model,
				"Bowl",
				Vector3.new(4, 1.2, 4),
				at(x, 6.6, WALL_Z + 2),
				rgb(70, 60, 50),
				Enum.Material.Metal
			)
			glowBall(ctx, "Flame", at(x, 8, WALL_Z + 2), 1.8, ctx.accent, if k % 2 == 0 then 20 else nil)
			if jungle then
				part(
					ctx.model,
					"Vine",
					Vector3.new(0.4, 14, 3.2),
					at(x + 1.6, -2, WALL_Z + 2),
					rgb(60, 120, 60),
					Enum.Material.Grass
				)
			end
		end
	end
end

MOTIFS.dojo = function(ctx)
	-- Inside a wooden hall: paper wall, red pillars, ceiling beams, banners.
	backWall(ctx, rgb(60, 36, 24), Enum.Material.Wood, WALL_Z - 6)
	for k = -6, 6 do
		local x = k * 12
		local panel = part(
			ctx.model,
			"Shoji",
			Vector3.new(10, 22, 0.3),
			at(x, 6, WALL_Z - 4.8),
			rgb(242, 232, 206),
			Enum.Material.SmoothPlastic
		)
		panel.Transparency = 0.05
		light(panel, rgb(255, 210, 150), 14, 0.6)
		for row = 1, 3 do
			part(
				ctx.model,
				"Lattice",
				Vector3.new(10, 0.3, 0.2),
				at(x, -5 + row * 5.5, WALL_Z - 4.5),
				rgb(70, 44, 30),
				Enum.Material.Wood
			)
		end
		part(
			ctx.model,
			"Post",
			Vector3.new(1.4, 34, 1.4),
			at(x + 6, 4, WALL_Z - 4),
			rgb(150, 40, 30),
			Enum.Material.Wood
		)
	end
	for k = 0, 2 do
		part(
			ctx.model,
			"Beam",
			Vector3.new(170, 2, 2),
			at(0, 24, WALL_Z - 4 + k * 12),
			rgb(70, 44, 30),
			Enum.Material.Wood
		)
	end
	for _, x in { -30, 30 } do
		part(ctx.model, "Banner", Vector3.new(6, 16, 0.2), at(x, 12, WALL_Z - 4.2), ctx.trim, Enum.Material.Fabric)
		glowBall(ctx, "Emblem", at(x, 14, WALL_Z - 4), 3, ctx.accent)
	end
	for _, x in { -55, -42, 42, 55 } do
		local l = part(
			ctx.model,
			"PaperLantern",
			Vector3.new(3, 4, 3),
			at(x, 16, WALL_Z + 2),
			rgb(255, 196, 120),
			Enum.Material.Neon
		)
		light(l, rgb(255, 190, 120), 22, 1.5)
	end
	-- Weapon rack.
	part(ctx.model, "Rack", Vector3.new(14, 1, 1), at(0, 6, WALL_Z - 4.2), rgb(70, 44, 30), Enum.Material.Wood)
	for k = -2, 2 do
		part(
			ctx.model,
			"Staff",
			Vector3.new(0.4, 12, 0.4),
			CFrame.new(at(k * 2.5, 6, WALL_Z - 4)) * CFrame.Angles(0, 0, 0.12),
			rgb(150, 110, 70),
			Enum.Material.Wood
		)
	end
	ground(ctx, rgb(80, 52, 34), Enum.Material.WoodPlanks, -30)
end

MOTIFS.colosseum = function(ctx)
	ground(ctx, rgb(214, 186, 132), Enum.Material.Sand, -30)
	local stone = rgb(196, 170, 128)
	-- A half ring of arched walls in two tiers.
	local radius = 120
	for k = -9, 9 do
		local angle = k * 0.1 -- +-0.9 rad: the whole arc stays well behind the fight
		local x, z = math.sin(angle) * radius, -math.cos(angle) * radius + 20
		local facing = CFrame.new(at(x, 0, z)) * CFrame.Angles(0, -angle, 0)
		for tier = 0, 1 do
			local y = -30 + tier * 24
			part(
				ctx.model,
				"Pier",
				Vector3.new(4, 22, 6),
				facing * CFrame.new(-7, y + 11, 0),
				stone,
				Enum.Material.Sandstone
			)
			part(
				ctx.model,
				"Lintel",
				Vector3.new(18, 3, 6),
				facing * CFrame.new(0, y + 23.5, 0),
				stone,
				Enum.Material.Sandstone
			)
		end
		if k % 3 == 0 then
			part(
				ctx.model,
				"Banner",
				Vector3.new(6, 14, 0.3),
				facing * CFrame.new(0, 26, 3.4),
				if k % 2 == 0 then ctx.trim else ctx.accent,
				Enum.Material.Fabric
			)
		end
		if ctx.theme.variant == "statues" and k % 3 == 1 then
			part(ctx.model, "Plinth", Vector3.new(6, 4, 6), facing * CFrame.new(0, -28, 6), stone, Enum.Material.Marble)
			part(
				ctx.model,
				"Statue",
				Vector3.new(4, 12, 3),
				facing * CFrame.new(0, -20, 6),
				rgb(232, 224, 206),
				Enum.Material.Marble
			)
			part(
				ctx.model,
				"StatueHead",
				Vector3.one * 3,
				facing * CFrame.new(0, -12.5, 6),
				rgb(232, 224, 206),
				Enum.Material.Marble,
				Enum.PartType.Ball
			)
		end
	end
	part(ctx.model, "Rim", Vector3.new(260, 4, 6), at(0, 20, WALL_Z - 82), stone, Enum.Material.Sandstone)
	for _, x in { -24, 24 } do
		part(ctx.model, "Brazier", Vector3.new(3, 8, 3), at(x, -4, WALL_Z + 2), rgb(90, 70, 50), Enum.Material.Metal)
		glowBall(ctx, "Fire", at(x, 1.5, WALL_Z + 2), 2.6, rgb(255, 150, 60), 24)
	end
end

MOTIFS.stadium = function(ctx)
	local future = ctx.theme.variant == "future"
	ground(ctx, rgb(52, 120, 64), Enum.Material.Grass, -36)
	-- Stands rising away from the stage, filled with a crowd of colored blocks.
	for tier = 0, 5 do
		local z = WALL_Z - 16 - tier * 8
		local y = -30 + tier * 7
		part(ctx.model, "Tier", Vector3.new(240, 7, 8), at(0, y, z), rgb(70, 74, 86), Enum.Material.Concrete)
		for k = -22, 22 do
			if (k + tier) % 3 ~= 0 then
				part(
					ctx.model,
					"Fan",
					Vector3.new(2.6, 3, 2),
					at(k * 5.2 + (tier % 2) * 2, y + 5, z),
					Color3.fromHSV(ctx.rng:NextNumber(), 0.5, 0.85),
					Enum.Material.SmoothPlastic
				)
			end
		end
		part(
			ctx.model,
			"TierTrim",
			Vector3.new(240, 0.4, 0.4),
			at(0, y + 3.6, z + 4),
			if tier % 2 == 0 then ctx.trim else ctx.accent,
			Enum.Material.Neon
		)
	end
	-- Floodlight towers.
	for _, x in { -90, 90 } do
		part(ctx.model, "Mast", Vector3.new(2, 90, 2), at(x, 15, WALL_Z - 50), rgb(160, 164, 172), Enum.Material.Metal)
		local head = part(
			ctx.model,
			"Floodlight",
			Vector3.new(14, 6, 2),
			at(x, 60, WALL_Z - 49),
			rgb(255, 255, 240),
			Enum.Material.Neon
		)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Back
		spot.Angle = 60
		spot.Range = 160
		spot.Brightness = 2
		spot.Parent = head
	end
	local screen = part(ctx.model, "Jumbotron", Vector3.new(44, 20, 1), at(0, 48, WALL_Z - 66), rgb(10, 10, 16))
	part(ctx.model, "ScreenFrame", Vector3.new(46, 22, 0.6), at(0, 48, WALL_Z - 66.6), ctx.trim, Enum.Material.Neon)
	sign(ctx, ctx.name, screen.Position + Vector3.new(0, 0, 0.8), if future then ctx.trim else ctx.accent, 40)
end

MOTIFS.mountains = function(ctx)
	ground(ctx, rgb(230, 238, 248), Enum.Material.Snow)
	backWall(ctx, rgb(8, 12, 30), nil, WALL_Z - 150)
	for k = -5, 5 do
		local h = 70 + (k * 31 % 40)
		local x = k * 34
		local z = WALL_Z - 70 - (k % 2) * 25
		for side = 0, 1 do
			wedge(
				ctx.model,
				"Peak",
				Vector3.new(46, h, 23),
				CFrame.new(at(x, -40 + h / 2, z)) * CFrame.Angles(0, side * math.pi, 0) * CFrame.new(0, 0, -11.5),
				rgb(92, 100, 118),
				Enum.Material.Rock
			)
			wedge(
				ctx.model,
				"Snowcap",
				Vector3.new(16, h * 0.32, 8),
				CFrame.new(at(x, -40 + h * 0.84, z)) * CFrame.Angles(0, side * math.pi, 0) * CFrame.new(0, 0, -4),
				rgb(240, 246, 255),
				Enum.Material.Snow
			)
		end
	end
	for k = -8, 8 do
		pine(ctx, k * 16 + (k % 3) * 4, WALL_Z - 10 - (k % 4) * 9, 22 + (k * 7 % 10), true)
	end
	-- Aurora: tall translucent curtains in the sky.
	for k = -6, 6 do
		local curtain = part(
			ctx.model,
			"Aurora",
			Vector3.new(16, 40 + (k % 3) * 8, 0.2),
			CFrame.new(at(k * 15, 70 + math.sin(k) * 6, WALL_Z - 120)) * CFrame.Angles(0, math.sin(k * 0.7) * 0.4, 0),
			if k % 2 == 0 then ctx.trim else rgb(160, 110, 255),
			Enum.Material.Neon
		)
		curtain.Transparency = 0.75
	end
end

MOTIFS.industrial = function(ctx)
	local frozen = ctx.theme.variant == "frozen"
	local metal = if frozen then rgb(150, 176, 200) else rgb(74, 72, 68)
	backWall(ctx, metal:Lerp(rgb(0, 0, 0), 0.5), Enum.Material.CorrodedMetal, WALL_Z - 30)
	ground(
		ctx,
		if frozen then rgb(200, 226, 244) else rgb(50, 48, 46),
		if frozen then Enum.Material.Ice else Enum.Material.Concrete,
		-30
	)
	local containerColors = { rgb(176, 64, 44), rgb(40, 96, 150), rgb(60, 128, 70), rgb(200, 150, 40) }
	for k = -5, 5 do
		local x = k * 24
		local stack = 1 + (k * 5 % 3)
		for level = 0, stack - 1 do
			local c = containerColors[(k + level) % #containerColors + 1]
			part(
				ctx.model,
				"Container",
				Vector3.new(20, 8.5, 8),
				at(x, -26 + level * 8.6, WALL_Z - 16),
				if frozen then c:Lerp(rgb(220, 236, 250), 0.55) else c,
				Enum.Material.CorrodedMetal
			)
		end
		part(ctx.model, "Column", Vector3.new(2, 90, 2), at(x + 12, 10, WALL_Z - 26), metal, Enum.Material.Metal)
	end
	for k = -2, 2 do
		part(
			ctx.model,
			"Truss",
			Vector3.new(260, 2, 2),
			at(0, 40 + (k % 2) * 4, WALL_Z - 26 + k * 10),
			metal,
			Enum.Material.Metal
		)
	end
	for _, x in { -40, 0, 40 } do
		part(ctx.model, "Cable", Vector3.new(0.2, 12, 0.2), at(x, 36, WALL_Z - 4), rgb(20, 20, 20))
		local lampShade = part(
			ctx.model,
			"HangLamp",
			Vector3.new(4, 1.4, 4),
			at(x, 29.5, WALL_Z - 4),
			rgb(255, 230, 180),
			Enum.Material.Neon
		)
		light(lampShade, rgb(255, 225, 170), 40, 1.6)
	end
	for k = -3, 3 do
		part(
			ctx.model,
			"Crate",
			Vector3.new(4, 4, 4),
			at(k * 9 + 4, -2, WALL_Z + 2),
			rgb(140, 104, 64),
			Enum.Material.WoodPlanks
		)
	end
	if frozen then
		for k = -12, 12 do
			wedge(
				ctx.model,
				"Icicle",
				Vector3.new(0.8, 3 + (k * 7 % 4), 0.8),
				CFrame.new(at(k * 10, 37.5, WALL_Z - 25)) * CFrame.Angles(math.pi, 0, 0),
				rgb(200, 236, 255),
				Enum.Material.Ice
			)
		end
	end
	sign(ctx, ctx.name, at(0, 22, WALL_Z - 28.5), ctx.trim, math.max(22, #ctx.name * 2))
end

MOTIFS.foundry = function(ctx)
	local molten = ctx.theme.variant == "molten"
	backWall(ctx, rgb(26, 18, 16), Enum.Material.Metal, WALL_Z - 40)
	-- A lava lake below the stage lights everything from beneath.
	local lava = ground(ctx, rgb(255, 96, 20), Enum.Material.Neon, -34)
	lava.Transparency = 0.1
	for _, x in { -60, 0, 60 } do
		local glow = part(ctx.model, "LavaGlow", Vector3.one, at(x, -28, 0), rgb(255, 120, 40))
		glow.Transparency = 1
		light(glow, rgb(255, 110, 30), 60, 2)
	end
	for k = -3, 3 do
		local x = k * 30
		part(
			ctx.model,
			"Stack",
			Vector3.new(90, 8, 8),
			CFrame.new(at(x, 10, WALL_Z - 36)) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(52, 44, 40),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		glowBall(ctx, "StackGlow", at(x, 55, WALL_Z - 36), 5, ctx.accent)
	end
	-- Crucible pouring a stream of molten metal.
	local pours: { number } = if molten then { -38, 38 } else { 38 }
	for _, x in pours do
		part(
			ctx.model,
			"Crucible",
			Vector3.new(14, 10, 12),
			CFrame.new(at(x, 30, WALL_Z - 10)) * CFrame.Angles(0, 0, -0.5),
			rgb(60, 50, 46),
			Enum.Material.Metal
		)
		part(
			ctx.model,
			"Pour",
			Vector3.new(2.4, 60, 2.4),
			at(x - 6, 0, WALL_Z - 10),
			rgb(255, 140, 30),
			Enum.Material.Neon
		)
		for c = -1, 1, 2 do
			part(
				ctx.model,
				"Chain",
				Vector3.new(0.6, 40, 0.6),
				at(x + c * 5, 55, WALL_Z - 10),
				rgb(40, 36, 34),
				Enum.Material.Metal
			)
		end
	end
	for k = -6, 6 do
		part(
			ctx.model,
			"Pipe",
			Vector3.new(2, 2, 60),
			at(k * 18, 32 + (k % 2) * 5, WALL_Z - 10),
			rgb(80, 64, 54),
			Enum.Material.Metal
		)
	end
	sign(ctx, ctx.name, at(-30, 26, WALL_Z - 38.5), ctx.trim, math.max(22, #ctx.name * 2))
end

local function stars(ctx: Ctx, z: number, count: number)
	for _ = 1, count do
		local s = 0.4 + ctx.rng:NextNumber() * 0.9
		part(
			ctx.model,
			"Star",
			Vector3.one * s,
			at(ctx.rng:NextNumber(-180, 180), ctx.rng:NextNumber(-40, 110), z - ctx.rng:NextNumber() * 20),
			rgb(255, 255, 255),
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	end
end

MOTIFS.space = function(ctx)
	backWall(ctx, rgb(2, 2, 8), nil, WALL_Z - 160)
	stars(ctx, WALL_Z - 140, 90)
	local planet = part(
		ctx.model,
		"Planet",
		Vector3.one * 90,
		at(-60, -50, WALL_Z - 120),
		rgb(70, 90, 170),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	planet.CastShadow = false
	local ring = part(
		ctx.model,
		"PlanetRing",
		Vector3.new(0.5, 150, 150),
		CFrame.new(planet.Position) * CFrame.Angles(0.35, 0, math.pi / 2 + 0.2),
		ctx.trim,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.8
	glowBall(ctx, "Moon", at(70, 60, WALL_Z - 100), 14, rgb(220, 220, 236))
	-- The orbital ring: struts and lit modules curving away behind the stage.
	for k = -8, 8 do
		local angle = k * 0.12
		local x, z = math.sin(angle) * 120, -math.cos(angle) * 120 + 40
		local facing = CFrame.new(at(x, -10, z)) * CFrame.Angles(0, -angle, 0)
		part(ctx.model, "RingSegment", Vector3.new(15, 6, 10), facing, rgb(120, 126, 150), Enum.Material.Metal)
		part(
			ctx.model,
			"RingLight",
			Vector3.new(12, 0.6, 0.4),
			facing * CFrame.new(0, 0, 5.2),
			if k % 2 == 0 then ctx.trim else ctx.accent,
			Enum.Material.Neon
		)
		if k % 4 == 0 then
			part(
				ctx.model,
				"Spoke",
				Vector3.new(2, 60, 2),
				facing * CFrame.new(0, 32, 0),
				rgb(110, 116, 140),
				Enum.Material.Metal
			)
		end
	end
end

MOTIFS.space_interior = function(ctx)
	local wallZ = WALL_Z - 20
	-- Hangar wall with a big window onto the stars.
	for _, x in { -110, 110 } do
		part(ctx.model, "WallSide", Vector3.new(140, 120, 2), at(x, 20, wallZ), rgb(70, 76, 92), Enum.Material.Metal)
	end
	part(ctx.model, "WallTop", Vector3.new(80, 50, 2), at(0, 70, wallZ), rgb(70, 76, 92), Enum.Material.Metal)
	part(ctx.model, "WallLow", Vector3.new(80, 30, 2), at(0, -25, wallZ), rgb(70, 76, 92), Enum.Material.Metal)
	for _, y in { -10, 45 } do
		part(ctx.model, "WindowFrame", Vector3.new(82, 1.2, 1), at(0, y, wallZ + 1), ctx.trim, Enum.Material.Neon)
	end
	backWall(ctx, rgb(2, 2, 8), nil, wallZ - 80)
	stars(ctx, wallZ - 60, 50)
	part(
		ctx.model,
		"Planet",
		Vector3.one * 40,
		at(20, 10, wallZ - 70),
		rgb(200, 120, 70),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	-- A parked ship and gantries.
	local hull = part(
		ctx.model,
		"ShipHull",
		Vector3.new(60, 10, 18),
		at(-50, -6, wallZ + 14),
		rgb(200, 206, 220),
		Enum.Material.Metal
	)
	wedge(
		ctx.model,
		"ShipNose",
		Vector3.new(18, 10, 16),
		CFrame.new(hull.Position + Vector3.new(38, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0),
		rgb(200, 206, 220),
		Enum.Material.Metal
	)
	part(
		ctx.model,
		"Cockpit",
		Vector3.new(8, 3, 8),
		hull.Position + Vector3.new(22, 5.5, 0),
		ctx.trim,
		Enum.Material.Glass
	)
	glowBall(ctx, "Engine", hull.Position - Vector3.new(31, 0, 0), 6, ctx.accent, 30)
	for k = -3, 3 do
		part(
			ctx.model,
			"Gantry",
			Vector3.new(2, 70, 2),
			at(k * 26, 10, wallZ + 4),
			rgb(110, 116, 132),
			Enum.Material.Metal
		)
		part(
			ctx.model,
			"GantryLight",
			Vector3.new(1.2, 1.2, 0.4),
			at(k * 26, 30, wallZ + 5.2),
			rgb(255, 80, 80),
			Enum.Material.Neon
		)
	end
	part(
		ctx.model,
		"CeilingBeam",
		Vector3.new(260, 3, 3),
		at(0, 44, wallZ + 6),
		rgb(110, 116, 132),
		Enum.Material.Metal
	)
	ground(ctx, rgb(60, 64, 76), Enum.Material.DiamondPlate, -32)
end

MOTIFS.war = function(ctx)
	local ruins = ctx.theme.variant == "ruins"
	ground(ctx, if ruins then rgb(70, 74, 72) else rgb(104, 92, 72), Enum.Material.Ground, -34)
	backWall(ctx, if ruins then rgb(60, 66, 70) else rgb(120, 112, 104), nil, WALL_Z - 150)
	if ruins then
		-- Broken buildings with dark empty windows.
		for k = -6, 6 do
			local h = 30 + (k * 19 % 30)
			local w = 18 + (k * 5 % 6)
			local x, z = k * 24, WALL_Z - 30 - (k % 3) * 16
			part(
				ctx.model,
				"Ruin",
				Vector3.new(w, h, 12),
				at(x, -34 + h / 2, z),
				rgb(88, 92, 94),
				Enum.Material.Concrete
			)
			wedge(
				ctx.model,
				"Break",
				Vector3.new(w, 8, 12),
				CFrame.new(at(x, -34 + h + 4, z)) * CFrame.Angles(0, if k % 2 == 0 then 0 else math.pi, 0),
				rgb(88, 92, 94),
				Enum.Material.Concrete
			)
			for row = 1, math.floor(h / 9) do
				part(ctx.model, "Hole", Vector3.new(3, 4, 0.2), at(x - w / 4, -34 + row * 9, z + 6.1), rgb(16, 18, 20))
				part(ctx.model, "Hole", Vector3.new(3, 4, 0.2), at(x + w / 4, -34 + row * 9, z + 6.1), rgb(16, 18, 20))
			end
		end
	else
		-- Trenches: sandbags, posts with wire, a burnt-out tree line.
		for k = -8, 8 do
			for level = 0, 1 do
				part(
					ctx.model,
					"Sandbag",
					Vector3.new(4.5, 1.8, 2.5),
					at(k * 9 + level * 2, -4 + level * 1.8, WALL_Z + 2),
					rgb(150, 132, 96),
					Enum.Material.Fabric
				)
			end
			part(
				ctx.model,
				"Post",
				Vector3.new(0.6, 8, 0.6),
				CFrame.new(at(k * 9, -18, WALL_Z - 20)) * CFrame.Angles(0, 0, 0.2),
				rgb(70, 54, 40),
				Enum.Material.Wood
			)
		end
		for k = -6, 6 do
			part(
				ctx.model,
				"DeadTree",
				Vector3.new(1.5, 24, 1.5),
				CFrame.new(at(k * 22, -24, WALL_Z - 50)) * CFrame.Angles(0, 0, (k % 3 - 1) * 0.2),
				rgb(46, 38, 32),
				Enum.Material.Wood
			)
		end
	end
	-- Smoke columns and distant fires.
	for _, x in { -50, 35 } do
		local fire = glowBall(ctx, "Fire", at(x, -30, WALL_Z - 40), 4, ctx.accent, 40)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Rate = 6
		smoke.Lifetime = NumberRange.new(6, 9)
		smoke.Speed = NumberRange.new(4, 7)
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 16) })
		smoke.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		smoke.Color = ColorSequence.new(rgb(60, 58, 56))
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = fire
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Weather and light
--------------------------------------------------------------------------------------------------------------------

local function weather(ctx: Ctx)
	local kind = ctx.theme.weather
	local cloud = part(ctx.model, "Weather", Vector3.new(160, 1, 60), at(0, 70, 0), rgb(0, 0, 0))
	cloud.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	if kind == "rain" then
		e.Rate = 400
		e.Lifetime = NumberRange.new(1.2, 1.6)
		e.Speed = NumberRange.new(70, 90)
		e.Size = NumberSequence.new(0.12)
		e.Squash = NumberSequence.new(-4)
		e.Transparency = NumberSequence.new(0.55)
		e.Color = ColorSequence.new(rgb(170, 200, 255))
		e.LightEmission = 0.4
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
	elseif kind == "snow" then
		e.Rate = 160
		e.Lifetime = NumberRange.new(8, 10)
		e.Speed = NumberRange.new(8, 12)
		e.SpreadAngle = Vector2.new(20, 20)
		e.Size = NumberSequence.new(0.35)
		e.Transparency = NumberSequence.new(0.15)
		e.Color = ColorSequence.new(rgb(255, 255, 255))
		e.RotSpeed = NumberRange.new(-40, 40)
	elseif kind == "embers" then
		cloud.Position = at(0, -30, 0)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 70
		e.Lifetime = NumberRange.new(5, 8)
		e.Speed = NumberRange.new(10, 18)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Color = ColorSequence.new(rgb(255, 160, 60), rgb(255, 60, 20))
		e.LightEmission = 1
	elseif kind == "fireflies" then
		cloud.Position = at(0, 10, -10)
		cloud.Size = Vector3.new(140, 30, 40)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Rate = 18
		e.Lifetime = NumberRange.new(4, 7)
		e.Speed = NumberRange.new(0.5, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Color = ColorSequence.new(ctx.accent:Lerp(rgb(220, 255, 140), 0.5))
		e.LightEmission = 1
	else -- dust
		cloud.Position = at(0, 10, -10)
		cloud.Size = Vector3.new(140, 30, 40)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Rate = 25
		e.Lifetime = NumberRange.new(6, 9)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.15)
		e.Transparency = NumberSequence.new(0.5)
		e.Color = ColorSequence.new(rgb(255, 240, 210))
	end
	e.Parent = cloud
end

-- Time of day, exposure and haze per motif; the theme tint colors ambient light and fog.
type Sky = { clock: number, exposure: number, haze: number, density: number }
local SKIES: { [string]: Sky } = {
	city_street = { clock = 0, exposure = 0.4, haze = 0.6, density = 0.12 },
	city_roof = { clock = 0, exposure = 0.4, haze = 0.7, density = 0.15 },
	scifi_city = { clock = 0, exposure = 0.4, haze = 0.5, density = 0.12 },
	temple = { clock = 0, exposure = 0.5, haze = 0.8, density = 0.18 },
	dojo = { clock = 17.6, exposure = 0, haze = 0.3, density = 0.08 },
	colosseum = { clock = 17.2, exposure = -0.15, haze = 1, density = 0.15 },
	stadium = { clock = 17.8, exposure = 0, haze = 0.6, density = 0.1 },
	mountains = { clock = 0, exposure = 0.6, haze = 0.4, density = 0.1 },
	industrial = { clock = 0, exposure = 0.5, haze = 0.8, density = 0.2 },
	foundry = { clock = 0, exposure = 0.3, haze = 1.5, density = 0.25 },
	space = { clock = 0, exposure = 0.5, haze = 0, density = 0 },
	space_interior = { clock = 0, exposure = 0.5, haze = 0.2, density = 0.05 },
	war = { clock = 15, exposure = 0, haze = 2, density = 0.3 },
}

local function tintColor(tint: { number }, scale: number): Color3
	return Color3.new(
		math.clamp(tint[1] * scale, 0, 1),
		math.clamp(tint[2] * scale, 0, 1),
		math.clamp(tint[3] * scale, 0, 1)
	)
end

local function clearEffects()
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
end

-- Applies the light of a theme (also used by the lobby, which has the neon street mood).
function ArenaBuilder.applyLighting(theme: ArenaThemes.Theme)
	local sky = SKIES[theme.motif] or SKIES.city_street
	if theme.motif == "temple" and theme.variant == "jungle" then
		sky = { clock = 15, exposure = 0.1, haze = 1.2, density = 0.18 }
	elseif theme.variant == "future" then
		sky = { clock = 0, exposure = 0.4, haze = 0.4, density = 0.08 }
	end
	local day = sky.clock > 6 and sky.clock < 18.2
	Lighting.ClockTime = sky.clock
	Lighting.Brightness = if day then 2.5 else 3
	Lighting.ExposureCompensation = sky.exposure
	Lighting.Ambient = tintColor(theme.tint, 0.75):Lerp(Color3.new(0.55, 0.52, 0.6), 0.3)
	Lighting.OutdoorAmbient = tintColor(theme.tint, 0.8):Lerp(Color3.new(0.6, 0.58, 0.68), 0.3)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	clearEffects()
	if sky.density > 0 then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = sky.density
		atmosphere.Offset = 0.1
		atmosphere.Color = tintColor(theme.tint, 0.85)
		atmosphere.Decay = tintColor(theme.tint, 0.6)
		atmosphere.Glare = if day then 0.3 else 0
		atmosphere.Haze = sky.haze
		atmosphere.Parent = Lighting
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = if day then 0.35 else 0.8
	bloom.Size = 28
	bloom.Threshold = if day then 0.95 else 0.85
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.12
	cc.Saturation = 0.2
	cc.TintColor = tintColor(theme.tint, 1):Lerp(Color3.new(1, 1, 1), 0.75)
	cc.Parent = Lighting
end

--------------------------------------------------------------------------------------------------------------------

-- Every arena id that has a look (all of Data/Arenas).
function ArenaBuilder.hasTheme(arenaId: string): boolean
	local theme = ArenaThemes[arenaId]
	return theme ~= nil and MOTIFS[theme.motif] ~= nil and STYLES[theme.motif] ~= nil
end

-- Builds the arena as workspace.Arena (replacing the old one) and sets the light for it.
function ArenaBuilder.build(arenaId: string): Model
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local theme = ArenaThemes[arenaId] or ArenaThemes.neon_alley
	local info = Arenas.byId[arenaId]
	local model = Instance.new("Model")
	model.Name = "Arena"
	model:SetAttribute("ArenaId", arenaId)
	local ctx: Ctx = {
		model = model,
		theme = theme,
		trim = Color3.fromHex(theme.trim),
		accent = Color3.fromHex(theme.accent),
		name = if info then info.name else arenaId,
		rng = Random.new(#arenaId * 131 + string.byte(arenaId, 1)),
	}
	buildStage(ctx, arenaId, STYLES[theme.motif] or STYLES.city_street)
	local motif = MOTIFS[theme.motif] or MOTIFS.city_street
	motif(ctx)
	keyLights(ctx)
	weather(ctx)
	model.Parent = workspace
	ArenaBuilder.applyLighting(theme)
	return model
end

return ArenaBuilder
