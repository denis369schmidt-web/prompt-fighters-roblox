--!strict
-- Builds a fighter's display rig entirely from plain Parts: an R15-shaped body (same part and Motor6D names as
-- a Roblox R15 character, so Visual/Pose drives it) plus gear from Data/Looks. Nothing is fetched from the
-- asset service, so rigs render the same in an unpublished Studio place, a live server and on every device.
-- Runs on the client; each client builds its own copies.

local Looks = require(script.Parent.Parent.Data.Looks)

local RigBuilder = {}

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

local function piece(
	model: Model,
	limbName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	c: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): BasePart?
	local found = model:FindFirstChild(limbName, true)
	if found == nil or not found:IsA("BasePart") then
		return nil
	end
	local limb = found :: BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = c
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = material ~= Enum.Material.Neon
	p.CFrame = limb.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = p
	weld.Parent = p
	p.Parent = limb
	return p
end

-- Gear pieces. Offsets are relative to the limb (rig faces -Z, up is +Y).
local GEAR: { [string]: (model: Model, look: Looks.Look) -> () } = {
	headband = function(model, look)
		local glow = color(look.glow)
		piece(
			model,
			"Head",
			"Headband",
			Vector3.new(1.25, 0.22, 1.25),
			CFrame.new(0, 0.25, 0),
			glow,
			Enum.Material.Neon
		)
		piece(
			model,
			"Head",
			"BandTailA",
			Vector3.new(0.12, 0.12, 1.1),
			CFrame.new(0.15, 0.2, 0.95) * CFrame.Angles(0.5, 0.2, 0),
			glow,
			Enum.Material.Neon
		)
		piece(
			model,
			"Head",
			"BandTailB",
			Vector3.new(0.12, 0.12, 0.9),
			CFrame.new(-0.1, 0.1, 0.9) * CFrame.Angles(0.8, -0.2, 0),
			glow,
			Enum.Material.Neon
		)
	end,
	mask = function(model, look)
		piece(
			model,
			"Head",
			"Mask",
			Vector3.new(1.22, 0.55, 1.22),
			CFrame.new(0, -0.3, 0),
			color(look.primary),
			Enum.Material.Fabric
		)
	end,
	blades_back = function(model, look)
		local steel = Color3.fromRGB(190, 200, 215)
		piece(
			model,
			"UpperTorso",
			"BladeA",
			Vector3.new(0.15, 2.6, 0.08),
			CFrame.new(0, 0.3, 0.6) * CFrame.Angles(0, 0, math.rad(35)),
			steel,
			Enum.Material.Metal
		)
		piece(
			model,
			"UpperTorso",
			"BladeB",
			Vector3.new(0.15, 2.6, 0.08),
			CFrame.new(0, 0.3, 0.62) * CFrame.Angles(0, 0, math.rad(-35)),
			steel,
			Enum.Material.Metal
		)
		piece(
			model,
			"UpperTorso",
			"BladeGlow",
			Vector3.new(0.5, 0.5, 0.1),
			CFrame.new(0, 0.3, 0.66),
			color(look.glow),
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	end,
	scarf = function(model, look)
		piece(
			model,
			"UpperTorso",
			"Scarf",
			Vector3.new(1.5, 0.35, 1.25),
			CFrame.new(0, 0.85, 0),
			color(look.glow),
			Enum.Material.Neon
		)
		piece(
			model,
			"UpperTorso",
			"ScarfTail",
			Vector3.new(0.4, 1.2, 0.12),
			CFrame.new(0.35, 0.3, 0.6) * CFrame.Angles(0.3, 0, 0.2),
			color(look.glow),
			Enum.Material.Neon
		)
	end,
	rock_shoulders = function(model, look)
		local rock = color(Looks.shade(look.primary, 0.8))
		piece(
			model,
			"LeftUpperArm",
			"RockL",
			Vector3.new(1.5, 1.1, 1.5),
			CFrame.new(-0.15, 0.45, 0) * CFrame.Angles(0.2, 0.4, -0.3),
			rock,
			Enum.Material.Slate
		)
		piece(
			model,
			"RightUpperArm",
			"RockR",
			Vector3.new(1.5, 1.1, 1.5),
			CFrame.new(0.15, 0.45, 0) * CFrame.Angles(-0.2, -0.3, 0.3),
			rock,
			Enum.Material.Slate
		)
	end,
	magma_cracks = function(model, look)
		local glow = color(look.glow)
		piece(
			model,
			"UpperTorso",
			"CrackA",
			Vector3.new(0.12, 1.3, 0.1),
			CFrame.new(-0.3, 0, -0.52) * CFrame.Angles(0, 0, 0.4),
			glow,
			Enum.Material.Neon
		)
		piece(
			model,
			"UpperTorso",
			"CrackB",
			Vector3.new(0.12, 0.9, 0.1),
			CFrame.new(0.35, 0.2, -0.52) * CFrame.Angles(0, 0, -0.6),
			glow,
			Enum.Material.Neon
		)
		piece(
			model,
			"UpperTorso",
			"Core",
			Vector3.new(0.45, 0.45, 0.2),
			CFrame.new(0, 0.1, -0.5),
			glow,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		piece(
			model,
			"LowerTorso",
			"CrackC",
			Vector3.new(0.9, 0.1, 0.1),
			CFrame.new(0, 0, -0.52),
			glow,
			Enum.Material.Neon
		)
	end,
	magma_fists = function(model, look)
		local glow = color(look.glow)
		piece(
			model,
			"LeftHand",
			"FistL",
			Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(0, -0.1, 0),
			glow,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		piece(
			model,
			"RightHand",
			"FistR",
			Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(0, -0.1, 0),
			glow,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	end,
	katana = function(model, look)
		piece(
			model,
			"RightHand",
			"Hilt",
			Vector3.new(0.15, 0.15, 0.7),
			CFrame.new(0, -0.2, -0.1),
			Color3.fromRGB(30, 30, 35),
			Enum.Material.Fabric
		)
		piece(
			model,
			"RightHand",
			"Guard",
			Vector3.new(0.45, 0.08, 0.45),
			CFrame.new(0, -0.2, -0.5),
			Color3.fromRGB(200, 170, 80),
			Enum.Material.Metal
		)
		piece(
			model,
			"RightHand",
			"Blade",
			Vector3.new(0.08, 0.2, 3.2),
			CFrame.new(0, -0.2, -2.1),
			Color3.fromRGB(220, 230, 240),
			Enum.Material.Metal
		)
		piece(
			model,
			"RightHand",
			"Edge",
			Vector3.new(0.04, 0.05, 3.1),
			CFrame.new(0, -0.08, -2.1),
			color(look.glow),
			Enum.Material.Neon
		)
	end,
	sheath = function(model, _look)
		piece(
			model,
			"LowerTorso",
			"Sheath",
			Vector3.new(0.22, 0.22, 3),
			CFrame.new(-0.8, 0, 0.2) * CFrame.Angles(0.35, 0.25, 0),
			Color3.fromRGB(25, 25, 30),
			Enum.Material.SmoothPlastic
		)
	end,
	sash = function(model, look)
		piece(
			model,
			"LowerTorso",
			"Sash",
			Vector3.new(2.1, 0.3, 1.15),
			CFrame.new(0, 0.3, 0),
			color(Looks.shade(look.glow, 0.7)),
			Enum.Material.Fabric
		)
	end,
	topknot = function(model, _look)
		piece(
			model,
			"Head",
			"Topknot",
			Vector3.new(0.45, 0.45, 0.45),
			CFrame.new(0, 0.75, 0.2),
			Color3.fromRGB(25, 22, 22),
			Enum.Material.Fabric,
			Enum.PartType.Ball
		)
		piece(
			model,
			"Head",
			"Hair",
			Vector3.new(1.25, 0.4, 1.25),
			CFrame.new(0, 0.48, 0.05),
			Color3.fromRGB(25, 22, 22),
			Enum.Material.Fabric
		)
	end,
	ears = function(model, look)
		local fur = color(look.primary)
		local inner = color(Looks.shade(look.skin, 0.95))
		for side = -1, 1, 2 do
			local tilt = CFrame.Angles(0, 0, math.rad(-12 * side))
			piece(
				model,
				"Head",
				"Ear",
				Vector3.new(0.35, 1.5, 0.22),
				CFrame.new(0.3 * side, 1.2, 0.1) * tilt,
				fur,
				Enum.Material.Fabric
			)
			piece(
				model,
				"Head",
				"EarInner",
				Vector3.new(0.18, 1.1, 0.05),
				CFrame.new(0.3 * side, 1.15, -0.02) * tilt,
				inner,
				Enum.Material.SmoothPlastic
			)
		end
	end,
	bow = function(model, look)
		local wood = Color3.fromRGB(110, 80, 60)
		piece(
			model,
			"LeftHand",
			"BowGrip",
			Vector3.new(0.18, 0.6, 0.18),
			CFrame.new(0, -0.25, 0),
			wood,
			Enum.Material.Wood
		)
		piece(
			model,
			"LeftHand",
			"BowUpper",
			Vector3.new(0.12, 1.6, 0.12),
			CFrame.new(0, 0.45, 0.35) * CFrame.Angles(math.rad(-25), 0, 0),
			wood,
			Enum.Material.Wood
		)
		piece(
			model,
			"LeftHand",
			"BowLower",
			Vector3.new(0.12, 1.6, 0.12),
			CFrame.new(0, -0.95, 0.35) * CFrame.Angles(math.rad(25), 0, 0),
			wood,
			Enum.Material.Wood
		)
		piece(
			model,
			"LeftHand",
			"String",
			Vector3.new(0.03, 2.9, 0.03),
			CFrame.new(0, -0.25, 0.75),
			color(look.glow),
			Enum.Material.Neon
		)
	end,
	quiver = function(model, look)
		piece(
			model,
			"UpperTorso",
			"Quiver",
			Vector3.new(0.5, 1.7, 0.5),
			CFrame.new(0.4, 0.2, 0.65) * CFrame.Angles(0, 0, math.rad(-20)),
			Color3.fromRGB(90, 65, 50),
			Enum.Material.Leather,
			Enum.PartType.Cylinder
		)
		piece(
			model,
			"UpperTorso",
			"Fletching",
			Vector3.new(0.45, 0.35, 0.45),
			CFrame.new(0.7, 1.05, 0.65),
			color(look.glow),
			Enum.Material.Neon
		)
	end,
}

RigBuilder.GEAR = GEAR

-- Body layout at scale 1 (studs, rig faces -Z, feet at y = 0): name, size, center, color slot.
type PartSpec = { name: string, size: Vector3, center: Vector3, slot: string }
local BODY: { PartSpec } = {
	{ name = "LowerTorso", size = Vector3.new(2, 0.8, 1), center = Vector3.new(0, 3.1, 0), slot = "primary" },
	{ name = "UpperTorso", size = Vector3.new(2, 1.6, 1), center = Vector3.new(0, 4.3, 0), slot = "primary" },
	{ name = "Head", size = Vector3.new(1.2, 1.2, 1.2), center = Vector3.new(0, 5.8, 0), slot = "skin" },
	{ name = "LeftUpperArm", size = Vector3.new(0.9, 1.2, 0.9), center = Vector3.new(-1.5, 4.5, 0), slot = "primary" },
	{ name = "LeftLowerArm", size = Vector3.new(0.8, 1.1, 0.8), center = Vector3.new(-1.5, 3.35, 0), slot = "primary" },
	{ name = "LeftHand", size = Vector3.new(0.8, 0.5, 0.8), center = Vector3.new(-1.5, 2.55, 0), slot = "skin" },
	{ name = "RightUpperArm", size = Vector3.new(0.9, 1.2, 0.9), center = Vector3.new(1.5, 4.5, 0), slot = "primary" },
	{ name = "RightLowerArm", size = Vector3.new(0.8, 1.1, 0.8), center = Vector3.new(1.5, 3.35, 0), slot = "primary" },
	{ name = "RightHand", size = Vector3.new(0.8, 0.5, 0.8), center = Vector3.new(1.5, 2.55, 0), slot = "skin" },
	{
		name = "LeftUpperLeg",
		size = Vector3.new(0.95, 1.2, 0.95),
		center = Vector3.new(-0.5, 2.1, 0),
		slot = "secondary",
	},
	{
		name = "LeftLowerLeg",
		size = Vector3.new(0.85, 1.2, 0.85),
		center = Vector3.new(-0.5, 0.9, 0),
		slot = "secondary",
	},
	{
		name = "LeftFoot",
		size = Vector3.new(0.9, 0.3, 1.2),
		center = Vector3.new(-0.5, 0.15, -0.1),
		slot = "secondary",
	},
	{
		name = "RightUpperLeg",
		size = Vector3.new(0.95, 1.2, 0.95),
		center = Vector3.new(0.5, 2.1, 0),
		slot = "secondary",
	},
	{
		name = "RightLowerLeg",
		size = Vector3.new(0.85, 1.2, 0.85),
		center = Vector3.new(0.5, 0.9, 0),
		slot = "secondary",
	},
	{
		name = "RightFoot",
		size = Vector3.new(0.9, 0.3, 1.2),
		center = Vector3.new(0.5, 0.15, -0.1),
		slot = "secondary",
	},
}

-- Joints: name, parent part, child part, pivot (scale-1 coordinates).
type JointSpec = { name: string, from: string, to: string, pivot: Vector3 }
local JOINTS: { JointSpec } = {
	{ name = "Root", from = "HumanoidRootPart", to = "LowerTorso", pivot = Vector3.new(0, 3.1, 0) },
	{ name = "Waist", from = "LowerTorso", to = "UpperTorso", pivot = Vector3.new(0, 3.5, 0) },
	{ name = "Neck", from = "UpperTorso", to = "Head", pivot = Vector3.new(0, 5.15, 0) },
	{ name = "LeftShoulder", from = "UpperTorso", to = "LeftUpperArm", pivot = Vector3.new(-1.5, 5, 0) },
	{ name = "LeftElbow", from = "LeftUpperArm", to = "LeftLowerArm", pivot = Vector3.new(-1.5, 3.9, 0) },
	{ name = "LeftWrist", from = "LeftLowerArm", to = "LeftHand", pivot = Vector3.new(-1.5, 2.8, 0) },
	{ name = "RightShoulder", from = "UpperTorso", to = "RightUpperArm", pivot = Vector3.new(1.5, 5, 0) },
	{ name = "RightElbow", from = "RightUpperArm", to = "RightLowerArm", pivot = Vector3.new(1.5, 3.9, 0) },
	{ name = "RightWrist", from = "RightLowerArm", to = "RightHand", pivot = Vector3.new(1.5, 2.8, 0) },
	{ name = "LeftHip", from = "LowerTorso", to = "LeftUpperLeg", pivot = Vector3.new(-0.5, 2.7, 0) },
	{ name = "LeftKnee", from = "LeftUpperLeg", to = "LeftLowerLeg", pivot = Vector3.new(-0.5, 1.5, 0) },
	{ name = "LeftAnkle", from = "LeftLowerLeg", to = "LeftFoot", pivot = Vector3.new(-0.5, 0.3, 0) },
	{ name = "RightHip", from = "LowerTorso", to = "RightUpperLeg", pivot = Vector3.new(0.5, 2.7, 0) },
	{ name = "RightKnee", from = "RightUpperLeg", to = "RightLowerLeg", pivot = Vector3.new(0.5, 1.5, 0) },
	{ name = "RightAnkle", from = "RightLowerLeg", to = "RightFoot", pivot = Vector3.new(0.5, 0.3, 0) },
}

-- Height of the root part's center above the feet at scale 1.
RigBuilder.STAND_HEIGHT = 3.1

local function eyes(model: Model, look: Looks.Look)
	local glow = look.glowEyes == true
	for side = -1, 1, 2 do
		piece(
			model,
			"Head",
			"Eye",
			if glow then Vector3.new(0.26, 0.12, 0.05) else Vector3.new(0.14, 0.22, 0.05),
			CFrame.new(0.24 * side, 0.08, -0.61),
			if glow then color(look.glow) else Color3.fromRGB(25, 22, 30),
			if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		)
	end
end

function RigBuilder.build(fighterId: string): Model
	local look = Looks.get(fighterId)
	local s = look.scale
	local function at(v: Vector3): Vector3
		return Vector3.new(v.X * s.width, v.Y * s.height, v.Z * s.depth)
	end

	local model = Instance.new("Model")
	model.Name = fighterId
	local material = if look.material then (Enum.Material :: any)[look.material] else Enum.Material.SmoothPlastic

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2 * s.width, 2 * s.height, 1 * s.depth)
	root.CFrame = CFrame.new(at(Vector3.new(0, 3.1, 0)))
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root

	local parts: { [string]: BasePart } = { HumanoidRootPart = root }
	for _, spec in BODY do
		local p = Instance.new("Part")
		p.Name = spec.name
		local size = Vector3.new(spec.size.X * s.width, spec.size.Y * s.height, spec.size.Z * s.depth)
		if spec.name == "Head" then
			size = spec.size * s.head
		end
		p.Size = size
		p.CFrame = CFrame.new(at(spec.center))
		p.Color = color((look :: any)[spec.slot])
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		parts[spec.name] = p
	end
	for _, j in JOINTS do
		local part0, part1 = parts[j.from], parts[j.to]
		local pivot = CFrame.new(at(j.pivot))
		local motor = Instance.new("Motor6D")
		motor.Name = j.name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = part0.CFrame:Inverse() * pivot
		motor.C1 = part1.CFrame:Inverse() * pivot
		motor.Parent = part1
	end

	eyes(model, look)
	for _, gearName in look.gear do
		local make = GEAR[gearName]
		if make then
			make(model, look)
		end
	end
	model:SetAttribute("Glow", look.glow)
	model:SetAttribute("StandHeight", RigBuilder.STAND_HEIGHT * s.height)
	return model
end

return RigBuilder
