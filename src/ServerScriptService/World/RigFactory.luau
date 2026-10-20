--!strict
-- Builds one display rig per fighter: a standard R15 body from a HumanoidDescription (colors, proportions) plus
-- gear made from plain parts (Data/Looks). Rigs go to ReplicatedStorage.FighterRigs; every client clones and
-- animates its own copies (Visual/Pose), the server never moves them. No catalog or third-party assets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Looks = require(ReplicatedStorage.Shared.Data.Looks)

local RigFactory = {}

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
RigFactory.GEAR = GEAR

local function addGlowEyes(model: Model, look: Looks.Look)
	if model:FindFirstChild("Head") == nil then
		return
	end
	local face = (model:FindFirstChild("Head") :: Instance):FindFirstChildOfClass("Decal")
	if face then
		face:Destroy()
	end
	for side = -1, 1, 2 do
		piece(
			model,
			"Head",
			"Eye",
			Vector3.new(0.25, 0.12, 0.05),
			CFrame.new(0.22 * side, 0.05, -0.6),
			color(look.glow),
			Enum.Material.Neon
		)
	end
end

function RigFactory.build(fighterId: string): Model
	local look = Looks.get(fighterId)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = color(look.skin)
	desc.LeftArmColor = color(look.primary)
	desc.RightArmColor = color(look.primary)
	desc.TorsoColor = color(look.primary)
	desc.LeftLegColor = color(look.secondary)
	desc.RightLegColor = color(look.secondary)
	desc.HeightScale = look.scale.height
	desc.WidthScale = look.scale.width
	desc.DepthScale = look.scale.depth
	desc.HeadScale = look.scale.head
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0

	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = fighterId
	for _, child in model:GetDescendants() do
		if child:IsA("Script") or child:IsA("LocalScript") then
			child:Destroy()
		elseif child:IsA("BasePart") then
			child.CanCollide = false
			child.CanQuery = false
			child.CanTouch = false
			child.Massless = true
			if child.Name ~= "HumanoidRootPart" and look.material then
				child.Material = (Enum.Material :: any)[look.material]
			end
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	root.Transparency = 1

	if look.glowEyes then
		addGlowEyes(model, look)
	end
	for _, gearName in look.gear do
		local build = GEAR[gearName]
		if build then
			build(model, look)
		end
	end
	model:SetAttribute("Glow", look.glow)
	return model
end

-- Builds the rigs for these fighters once and puts them where clients can clone them.
function RigFactory.publish(fighterIds: { string })
	local folder = ReplicatedStorage:FindFirstChild("FighterRigs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "FighterRigs"
		folder.Parent = ReplicatedStorage
	end
	for _, id in fighterIds do
		if not (folder :: Instance):FindFirstChild(id) then
			local ok, result = pcall(RigFactory.build, id)
			if ok then
				result.Parent = folder
			else
				warn(`[PromptFighters] rig for {id} failed: {result}`)
			end
		end
	end
end

return RigFactory
