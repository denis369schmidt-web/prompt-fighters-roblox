--!strict
-- Builds a fighter's display rig entirely from plain Parts. The R15 body parts (same part and Motor6D names as a
-- Roblox R15 character, so Visual/Pose drives it) are invisible bones; on each bone sits a sculpted body made of
-- cylinders, balls, wedges and blocks (capsule limbs, tapered torso, fists, boots, a rounded head with a face) and
-- the fighter's gear from Visual/GearData. Nothing is fetched from the asset service, so rigs render the same in an
-- unpublished Studio place, a live server and on every device. Runs on the client; each client builds its own copies.

local GearData = require(script.Parent.GearData)
local Looks = require(script.Parent.Parent.Data.Looks)

local RigBuilder = {}

type Parts = { [string]: BasePart }

-- Everything a builder needs: the bones, the look, and per-bone scale for data written at scale 1.
type Ctx = {
	look: Looks.Look,
	build: Looks.Build,
	parts: Parts,
	scales: { [string]: Vector3 },
	origins: { [string]: CFrame },
	count: number,
}

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

-- Fixed tones for gear; look slots (primary, glow, hair, accent, ...) come from the look.
local TONES: { [string]: string } = {
	steel = "#A7B4C2",
	gold = "#D4A93C",
	wood = "#6E4B30",
	dark = "#222026",
	white = "#F2F2F2",
	leather = "#5A3B22",
	bone = "#E8E4D8",
	rope = "#C8A46A",
	red = "#B3202A",
	black = "#16141C",
	brass = "#C08A3E",
	fur = "#F4EFE8",
	pink = "#F2A0B0",
	iron = "#4A4F58",
}

-- A color slot: a fixed tone, a look field, "#RRGGBB", or any of these with "*factor" to shade it
-- (e.g. "primary*0.8" for a shadow trim, "accent*1.2" for a highlight).
local function tone(look: Looks.Look, slot: string): Color3
	local base, factor = string.match(slot, "^([^*]+)%*([%d%.]+)$")
	if base and factor then
		local c = tone(look, base)
		local f = tonumber(factor) :: number
		if f <= 1 then
			return c:Lerp(Color3.new(0, 0, 0), 1 - f)
		end
		return c:Lerp(Color3.new(1, 1, 1), math.min(1, f - 1))
	end
	if string.sub(slot, 1, 1) == "#" then
		return color(slot)
	end
	local fixed = TONES[slot]
	if fixed then
		return color(fixed)
	end
	if slot == "hair" then
		return color(look.hair or "#2A2226")
	elseif slot == "accent" then
		return color(look.accent or look.glow)
	elseif slot == "trim" then
		return color(look.trim or look.accent or look.glow)
	end
	local value = (look :: any)[slot]
	return color(if type(value) == "string" then value else look.glow)
end
RigBuilder.tone = tone

local function material(name: string?): Enum.Material
	if name == nil then
		return Enum.Material.SmoothPlastic
	end
	return (Enum.Material :: any)[name] or Enum.Material.SmoothPlastic
end

-- Welds one decoration part to a bone. `offset` is relative to the bone's visual origin.
local function attach(
	ctx: Ctx,
	boneName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	c: Color3,
	mat: Enum.Material,
	shape: string?,
	transparency: number?
): BasePart?
	local found: BasePart? = ctx.parts[boneName]
	if not found then
		return nil
	end
	local bone = found :: BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if shape and shape ~= "Block" then
			part.Shape = (Enum.PartType :: any)[shape]
		end
		p = part
	end
	p.Name = name
	p.Size = size
	p.Color = c
	p.Material = mat
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = mat ~= Enum.Material.Neon and mat ~= Enum.Material.ForceField
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = bone.CFrame * (ctx.origins[boneName] or CFrame.identity) * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bone
	weld.Part1 = p
	weld.Parent = p
	p.Parent = bone
	ctx.count += 1
	return p
end

-- Scales a size given in the part's own axes by the bone scale, following the part's rotation.
local function scaledSize(size: Vector3, rotation: CFrame, sc: Vector3): Vector3
	local function along(axis: Vector3): number
		return axis.X * axis.X * sc.X + axis.Y * axis.Y * sc.Y + axis.Z * axis.Z * sc.Z
	end
	return Vector3.new(
		size.X * along(rotation.RightVector),
		size.Y * along(rotation.UpVector),
		size.Z * along(-rotation.LookVector)
	)
end

-- Builds one GearData piece on its bone, scaled to the fighter's proportions.
local function buildPiece(ctx: Ctx, d: GearData.Piece)
	local sc = ctx.scales[d.limb] or Vector3.one
	local rotation: CFrame = CFrame.identity
	local position: Vector3
	if d.cf then
		local cf = d.cf :: CFrame
		position = cf.Position
		rotation = cf - cf.Position
	else
		position = Vector3.new(d.offset[1], d.offset[2], d.offset[3])
		local r = d.rotation
		if r then
			rotation = CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		end
	end
	local size = scaledSize(Vector3.new(d.size[1], d.size[2], d.size[3]), rotation, sc)
	if d.shape == "Ball" then
		local m = math.min(size.X, size.Y, size.Z)
		size = Vector3.new(m, m, m)
	elseif d.shape == "Cylinder" then
		local m = math.min(size.Y, size.Z)
		size = Vector3.new(size.X, m, m)
	end
	attach(
		ctx,
		d.limb,
		d.name,
		size,
		CFrame.new(position * sc) * rotation,
		tone(ctx.look, d.color),
		material(d.material),
		d.shape,
		d.transparency
	)
end

local GEAR: { [string]: { GearData.Piece } } = GearData :: any
RigBuilder.GEAR = GEAR

-- Bones at scale 1 (studs, rig faces -Z, feet at y = 0): name, size, center. Arm bones move out with the build's
-- shoulder width, leg bones with its stance.
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

-- Bones and joints (name without Left/Right) that move out with the build's shoulder width or stance.
local ARM_BONES = { UpperArm = true, LowerArm = true, Hand = true, Shoulder = true, Elbow = true, Wrist = true }
local LEG_BONES = { UpperLeg = true, LowerLeg = true, Foot = true, Hip = true, Knee = true, Ankle = true }

-- Height of the root part's center above the feet at scale 1.
RigBuilder.STAND_HEIGHT = 3.1
-- Heads are drawn a bit larger than the R15 bone for appeal and readable faces.
RigBuilder.HEAD_SCALE = 1.12
-- Soft budget per rig (tests hold every launch fighter to it).
RigBuilder.PART_BUDGET = 125

-- Gear that covers the lower face (no mouth or nose), the whole face (no features at all), or the ears.
local COVERS_MOUTH = { ninja_mask = true, bandana = true, helmet_visor = true }
local COVERS_FACE = { knight_helm = true, dragon_helm = true, mech_head = true }
local HIDES_EARS = {
	knight_helm = true,
	dragon_helm = true,
	mech_head = true,
	helmet_visor = true,
	ninja_hood = true,
	hood = true,
	winged_helm = true,
	bunny_ears = true,
	fox_ears = true,
	rock_head = true,
	hair_long = true,
	hair_bob = true,
	frost_hair = true,
	flame_crest = true,
	fox_hair = true,
}

local function isSide(name: string): number
	return if string.sub(name, 1, 4) == "Left" then -1 else 1
end

-- The sculpted body: capsule limbs with ball joints, a tapered chest, pelvis and belt, fists, boots, neck and head.
local function sculpt(ctx: Ctx)
	local look, b = ctx.look, ctx.build
	local skinMat = material(look.skinMaterial or "SmoothPlastic")
	local clothMat = material(look.material or "SmoothPlastic")
	local top = tone(look, "primary")
	local sleeves = tone(look, look.sleeves or "primary")
	local forearms = tone(look, look.forearms or look.sleeves or "primary")
	local sleeveMat = if (look.sleeves or "primary") == "skin" then skinMat else clothMat
	local forearmMat = if (look.forearms or look.sleeves or "primary") == "skin" then skinMat else clothMat
	local hands = tone(look, look.gloves or "skin")
	local handMat = if look.gloves then material("Leather") else skinMat
	local pants = tone(look, "secondary")
	local boots = tone(look, look.boots or "secondary*0.55")
	local soles = boots:Lerp(Color3.fromRGB(20, 18, 24), 0.6)
	local vertical = CFrame.Angles(0, 0, math.rad(90))
	local alongZ = CFrame.Angles(0, math.rad(90), 0)

	local function box(bone: string, name: string, size: Vector3, at: Vector3, c: Color3, m: Enum.Material)
		local sc = ctx.scales[bone]
		attach(ctx, bone, name, size * sc, CFrame.new(at * sc), c, m)
	end
	local function vcyl(bone: string, name: string, len: number, d: number, at: Vector3, c: Color3, m: Enum.Material)
		local sc = ctx.scales[bone]
		local dd = d * math.min(sc.X, sc.Z)
		attach(ctx, bone, name, Vector3.new(len * sc.Y, dd, dd), CFrame.new(at * sc) * vertical, c, m, "Cylinder")
	end
	local function ball(bone: string, name: string, d: number, at: Vector3, c: Color3, m: Enum.Material)
		local sc = ctx.scales[bone]
		local dd = d * math.min(sc.X, sc.Z)
		attach(ctx, bone, name, Vector3.new(dd, dd, dd), CFrame.new(at * sc), c, m, "Ball")
	end

	-- Torso: broad chest tapering to the waist (wedges at the flanks), traps sloping into the neck.
	local chestW, waistW = b.chest, b.waist
	box("UpperTorso", "Chest", Vector3.new(chestW, 0.95, 1.0), Vector3.new(0, 0.33, 0), top, clothMat)
	box(
		"UpperTorso",
		"Abdomen",
		Vector3.new(waistW, 0.8, 0.86),
		Vector3.new(0, -0.42, 0.02),
		top:Lerp(Color3.new(0, 0, 0), 0.12),
		clothMat
	)
	local flank = (chestW - waistW) / 2
	if flank > 0.04 then
		local sc = ctx.scales.UpperTorso
		for side = -1, 1, 2 do
			local x = (waistW / 2 + flank / 2) * side
			local cf =
				CFrame.fromMatrix(Vector3.new(x, -0.49, 0.02) * sc, Vector3.new(0, 0, -side), Vector3.new(0, -1, 0))
			attach(
				ctx,
				"UpperTorso",
				"Flank",
				Vector3.new(0.86 * sc.Z, 0.7 * sc.Y, flank * sc.X),
				cf,
				top:Lerp(Color3.new(0, 0, 0), 0.12),
				clothMat,
				"Wedge"
			)
		end
	end
	do
		local sc = ctx.scales.UpperTorso
		for side = -1, 1, 2 do
			local w = chestW / 2 - 0.3
			local cf = CFrame.fromMatrix(
				Vector3.new((0.3 + w / 2) * side, 0.9, 0.05) * sc,
				Vector3.new(0, 0, side),
				Vector3.new(0, 1, 0)
			)
			attach(
				ctx,
				"UpperTorso",
				"Trap",
				Vector3.new(0.75 * sc.Z, 0.2 * sc.Y, w * sc.X),
				cf,
				top:Lerp(Color3.new(1, 1, 1), 0.06),
				clothMat,
				"Wedge"
			)
		end
	end
	vcyl("UpperTorso", "Neck", 0.6, b.neck, Vector3.new(0, 0.95, 0.02), tone(look, look.neck or "skin"), skinMat)

	-- Pelvis, belt and buckle.
	box("LowerTorso", "Pelvis", Vector3.new(b.hip, 0.62, 0.92), Vector3.new(0, 0.05, 0), pants, clothMat)
	box("LowerTorso", "Crotch", Vector3.new(0.7, 0.4, 0.8), Vector3.new(0, -0.3, 0), pants, clothMat)
	if look.belt ~= "none" then
		local beltColor = tone(look, look.belt or "leather")
		box(
			"LowerTorso",
			"Belt",
			Vector3.new(math.max(b.hip, b.waist) + 0.06, 0.2, 0.96),
			Vector3.new(0, 0.32, 0),
			beltColor,
			Enum.Material.Leather
		)
		box(
			"LowerTorso",
			"Buckle",
			Vector3.new(0.3, 0.22, 0.06),
			Vector3.new(0, 0.32, -0.5),
			tone(look, "gold"),
			Enum.Material.Metal
		)
	end

	-- Arms: deltoid ball at the shoulder pivot, capsule upper arm and forearm, fist with knuckles and thumb.
	for _, sideName in { "Left", "Right" } do
		local side = isSide(sideName)
		local ua, la, hand = sideName .. "UpperArm", sideName .. "LowerArm", sideName .. "Hand"
		ball(ua, "Deltoid", 0.8, Vector3.new(0, 0.45, 0), sleeves:Lerp(Color3.new(1, 1, 1), 0.05), sleeveMat)
		vcyl(ua, "Bicep", 1.0, 0.62, Vector3.new(0, -0.05, 0), sleeves, sleeveMat)
		ball(la, "Elbow", 0.55, Vector3.new(0, 0.55, 0), forearms, forearmMat)
		vcyl(la, "Forearm", 1.0, 0.56, Vector3.new(0, 0.02, 0), forearms, forearmMat)
		if look.gloves then
			vcyl(la, "Cuff", 0.3, 0.64, Vector3.new(0, -0.42, 0), hands:Lerp(Color3.new(0, 0, 0), 0.15), handMat)
		end
		box(hand, "Palm", Vector3.new(0.4, 0.42, 0.5), Vector3.new(0, 0.04, 0), hands, handMat)
		do
			local sc = ctx.scales[hand]
			local dd = 0.38 * math.min(sc.X, sc.Y)
			attach(
				ctx,
				hand,
				"Knuckles",
				Vector3.new(0.5 * sc.Z, dd, dd),
				CFrame.new(Vector3.new(0.02 * side, -0.18, 0) * sc) * alongZ,
				hands,
				handMat,
				"Cylinder"
			)
			attach(
				ctx,
				hand,
				"Thumb",
				Vector3.new(0.16, 0.3, 0.16) * sc,
				CFrame.new(Vector3.new(-0.16 * side, -0.02, -0.2) * sc) * CFrame.Angles(0, 0, math.rad(20 * side)),
				hands:Lerp(Color3.new(0, 0, 0), 0.06),
				handMat
			)
		end
	end

	-- Legs: capsule thigh and shin, knee ball, boot shaft, foot with sole and rounded toe.
	for _, sideName in { "Left", "Right" } do
		local ul, ll, foot = sideName .. "UpperLeg", sideName .. "LowerLeg", sideName .. "Foot"
		vcyl(ul, "Thigh", 1.2, 0.76, Vector3.new(0, 0.02, 0), pants, clothMat)
		ball(ll, "Knee", 0.64, Vector3.new(0, 0.58, 0), pants, clothMat)
		vcyl(ll, "Shin", 1.05, 0.6, Vector3.new(0, 0.05, 0), pants, clothMat)
		vcyl(ll, "BootShaft", 0.62, 0.68, Vector3.new(0, -0.32, 0), boots, Enum.Material.Leather)
		box(
			foot,
			"Sole",
			Vector3.new(0.72, 0.12, 1.22),
			Vector3.new(0, -0.09, -0.07),
			soles,
			Enum.Material.SmoothPlastic
		)
		box(foot, "Instep", Vector3.new(0.66, 0.32, 0.82), Vector3.new(0, 0.1, 0.1), boots, Enum.Material.Leather)
		do
			local sc = ctx.scales[foot]
			local dd = 0.4 * math.min(sc.Y * 1.0, sc.Z)
			attach(
				ctx,
				foot,
				"Toe",
				Vector3.new(0.66 * sc.X, dd, dd),
				CFrame.new(Vector3.new(0, 0.03, -0.38) * sc),
				boots:Lerp(Color3.new(1, 1, 1), 0.06),
				Enum.Material.Leather,
				"Cylinder"
			)
		end
	end

	-- Head: a round skull on a slightly narrower cylindrical face; ears unless gear covers them.
	local hs = ctx.scales.Head.X
	local head = color(look.skin)
	attach(ctx, "Head", "Skull", Vector3.one * 1.2 * hs, CFrame.new(0, 0.05 * hs, 0), head, skinMat, "Ball")
	attach(
		ctx,
		"Head",
		"Face",
		Vector3.new(0.62 * hs, 1.2 * hs, 1.2 * hs),
		CFrame.new(0, -0.26 * hs, 0) * vertical,
		head,
		skinMat,
		"Cylinder"
	)
	attach(
		ctx,
		"Head",
		"Jaw",
		Vector3.new(0.2 * hs, 1.0 * hs, 1.0 * hs),
		CFrame.new(0, -0.6 * hs, -0.02 * hs) * vertical,
		head,
		skinMat,
		"Cylinder"
	)
	local ears = true
	for _, g in look.gear do
		if HIDES_EARS[g] then
			ears = false
		end
	end
	if ears then
		for side = -1, 1, 2 do
			attach(
				ctx,
				"Head",
				"Ear",
				Vector3.new(0.14 * hs, 0.32 * hs, 0.32 * hs),
				CFrame.new(0.6 * side * hs, -0.12 * hs, 0.04 * hs),
				head:Lerp(Color3.new(0, 0, 0), 0.06),
				skinMat,
				"Cylinder"
			)
		end
	end
end

-- Point on the head surface (head units: radius 0.6, sphere above y = 0.05, cylinder below), facing outward,
-- `lift` studs in front of the skin, with an extra roll (degrees) for tilted brows and lids.
local function faceCF(hs: number, x: number, y: number, lift: number, roll: number?): CFrame
	local r = 0.6
	local cf: CFrame
	if y > 0.05 then
		local elev = math.asin(math.clamp((y - 0.05) / r, -1, 1))
		local ring = r * math.cos(elev)
		local yaw = -math.asin(math.clamp(x / ring, -1, 1))
		cf = CFrame.new(0, 0.05 * hs, 0)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(elev, 0, 0)
			* CFrame.new(0, 0, -(r * hs + lift))
	else
		local yaw = -math.asin(math.clamp(x / r, -1, 1))
		cf = CFrame.new(0, y * hs, 0) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -(r * hs + lift))
	end
	if roll then
		cf *= CFrame.Angles(0, 0, math.rad(roll))
	end
	return cf
end

-- Face: big readable eyes (white, colored iris, pupil, highlight, lid line), shaped brows, nose, mouth and blush.
local function face(ctx: Ctx)
	local look = ctx.look
	local f: Looks.Face = look.face or {}
	local hs = ctx.scales.Head.X
	local eyes = f.eyes or (if look.glowEyes then "glow" else "sharp")
	local mouth, brows, nose = f.mouth or "smirk", f.brows or "angry", true
	for _, gear in look.gear do
		if COVERS_MOUTH[gear] then
			mouth, nose = "none", false
		end
		if COVERS_FACE[gear] then
			return
		end
	end
	local skin = color(look.skin)
	local dark = Color3.fromRGB(28, 22, 34)
	local lidColor = if look.hair then color(look.hair):Lerp(dark, 0.75) else dark
	local browColor = if f.browColor
		then color(f.browColor)
		elseif look.hair then color(look.hair):Lerp(dark, 0.35)
		else skin:Lerp(dark, 0.7)
	local smooth = Enum.Material.SmoothPlastic
	local function feature(
		name: string,
		w: number,
		h: number,
		x: number,
		y: number,
		lift: number,
		c: Color3,
		roll: number?,
		m: Enum.Material?
	)
		attach(ctx, "Head", name, Vector3.new(w * hs, h * hs, 0.03), faceCF(hs, x, y, lift, roll), c, m or smooth)
	end

	for side = -1, 1, 2 do
		local ex = 0.24 * side
		if eyes == "glow" then
			feature("EyeSocket", 0.3, 0.17, ex, 0.0, 0.0, skin:Lerp(dark, 0.8), 6 * side)
			feature("Eye", 0.26, 0.08, ex, 0.0, 0.02, color(f.eyeColor or look.glow), 6 * side, Enum.Material.Neon)
		elseif eyes ~= "none" then
			local round = eyes == "round"
			local ew, eh = if round then 0.25 else 0.27, if round then 0.3 else 0.21
			local iris = color(f.eyeColor or "#3A2A20")
			feature("EyeWhite", ew, eh, ex, -0.02, 0.0, Color3.fromRGB(248, 248, 252))
			feature("Iris", 0.17, if round then 0.24 else 0.19, ex - 0.02 * side, -0.035, 0.012, iris)
			feature("Pupil", 0.09, if round then 0.14 else 0.12, ex - 0.02 * side, -0.04, 0.024, dark)
			feature("Glint", 0.06, 0.06, ex - 0.02 * side + 0.045, 0.02, 0.036, Color3.new(1, 1, 1))
			local lidTilt = if round then -6 * side else 9 * side
			feature("Lid", ew + 0.06, if f.lashes then 0.075 else 0.055, ex, -0.02 + eh / 2, 0.03, lidColor, lidTilt)
			if f.lashes then
				feature("Lash", 0.1, 0.05, ex + 0.15 * side, 0.1, 0.03, lidColor, -35 * side)
			end
		end
		if brows ~= "none" then
			local tilt = if brows == "angry" then 16 elseif brows == "calm" then -4 else -14
			local by = if brows == "raised" then 0.27 else 0.23
			feature("Brow", 0.3, 0.075, 0.25 * side, by, 0.03, browColor, tilt * side)
		end
		if f.blush then
			feature("Blush", 0.17, 0.07, 0.38 * side, -0.2, 0.0, skin:Lerp(Color3.fromRGB(255, 110, 130), 0.45))
		end
	end
	if nose and f.nose ~= false then
		attach(
			ctx,
			"Head",
			"Nose",
			Vector3.new(0.11 * hs, 0.13 * hs, 0.09),
			faceCF(hs, 0, -0.15, 0.02),
			skin:Lerp(dark, 0.12),
			smooth
		)
	end
	local lip = Color3.fromRGB(110, 46, 50)
	if mouth == "smirk" then
		feature("Mouth", 0.22, 0.05, 0.02, -0.33, 0.0, lip, 7)
		feature("MouthCorner", 0.07, 0.05, 0.14, -0.31, 0.0, lip, 30)
	elseif mouth == "grin" then
		feature("Mouth", 0.32, 0.13, 0, -0.33, 0.0, lip)
		feature("Teeth", 0.27, 0.06, 0, -0.305, 0.01, Color3.fromRGB(250, 248, 240))
	elseif mouth == "smile" then
		feature("Mouth", 0.16, 0.05, 0, -0.34, 0.0, lip)
		for side = -1, 1, 2 do
			feature("MouthCorner", 0.08, 0.05, 0.1 * side, -0.32, 0.0, lip, 28 * side)
		end
	elseif mouth == "frown" then
		feature("Mouth", 0.18, 0.05, 0, -0.32, 0.0, lip)
		for side = -1, 1, 2 do
			feature("MouthCorner", 0.07, 0.05, 0.11 * side, -0.34, 0.0, lip, -28 * side)
		end
	elseif mouth == "open" then
		feature("Mouth", 0.22, 0.14, 0, -0.34, 0.0, lip:Lerp(dark, 0.5))
		feature("Teeth", 0.2, 0.04, 0, -0.29, 0.01, Color3.fromRGB(250, 248, 240))
	elseif mouth == "flat" then
		feature("Mouth", 0.24, 0.05, 0, -0.33, 0.0, lip)
	end
end

function RigBuilder.build(fighterId: string): Model
	local look = Looks.get(fighterId)
	local s = look.scale
	local b = Looks.BUILDS[look.build or "medium"] or Looks.BUILDS.medium
	local function at(v: Vector3, name: string?): Vector3
		local x = v.X
		local kind = if name then string.gsub(name, "^Left", ""):gsub("^Right", "") else ""
		if ARM_BONES[kind] then
			x *= b.shoulder / 1.5
		elseif LEG_BONES[kind] then
			x *= b.stance / 0.5
		end
		return Vector3.new(x * s.width, v.Y * s.height, v.Z * s.depth)
	end

	local model = Instance.new("Model")
	model.Name = fighterId

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

	local parts: Parts = { HumanoidRootPart = root }
	for _, spec in BODY do
		local p = Instance.new("Part")
		p.Name = spec.name
		local size = Vector3.new(spec.size.X * s.width, spec.size.Y * s.height, spec.size.Z * s.depth)
		if spec.name == "Head" then
			size = spec.size * s.head * RigBuilder.HEAD_SCALE
		end
		p.Size = size
		p.CFrame = CFrame.new(at(spec.center, spec.name))
		p.Color = tone(look, spec.slot)
		p.Material = material(look.material)
		-- Bones stay invisible: the sculpted body and gear welded to them are what you see.
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = model
		parts[spec.name] = p
	end
	for _, j in JOINTS do
		local part0, part1 = parts[j.from], parts[j.to]
		local pivot = CFrame.new(at(j.pivot, j.name))
		local motor = Instance.new("Motor6D")
		motor.Name = j.name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = part0.CFrame:Inverse() * pivot
		motor.C1 = part1.CFrame:Inverse() * pivot
		motor.Parent = part1
	end

	-- Per-bone scale for data written at scale 1: torso follows width/height/depth (and chest width), limbs also
	-- their build thickness, the head is uniform.
	local hs = s.head * RigBuilder.HEAD_SCALE
	local torso = Vector3.new(s.width, s.height, s.depth)
	local arm = Vector3.new(s.width * b.arm, s.height, s.depth * b.arm)
	local leg = Vector3.new(s.width * b.leg, s.height, s.depth * b.leg)
	local scales: { [string]: Vector3 } = {
		HumanoidRootPart = torso,
		UpperTorso = torso,
		LowerTorso = torso,
		Head = Vector3.new(hs, hs, hs),
	}
	for _, sideName in { "Left", "Right" } do
		scales[sideName .. "UpperArm"] = arm
		scales[sideName .. "LowerArm"] = arm
		scales[sideName .. "Hand"] = arm * b.hand
		scales[sideName .. "UpperLeg"] = leg
		scales[sideName .. "LowerLeg"] = leg
		scales[sideName .. "Foot"] = Vector3.new(s.width * b.leg, s.height, s.depth) * b.foot
	end
	local ho: { number } = look.headOffset or { 0, 0.3, 0 }
	local ctx: Ctx = {
		look = look,
		build = b,
		parts = parts,
		scales = scales,
		origins = { Head = CFrame.new(ho[1] * hs, ho[2] * hs, ho[3] * hs) },
		count = 0,
	}

	sculpt(ctx)
	face(ctx)
	for _, gearName in look.gear do
		local pieces = GEAR[gearName]
		if pieces then
			for _, d in pieces do
				buildPiece(ctx, d)
			end
		end
	end
	model:SetAttribute("Glow", look.glow)
	model:SetAttribute("StandHeight", RigBuilder.STAND_HEIGHT * s.height)
	model:SetAttribute("PartCount", ctx.count)
	return model
end

return RigBuilder
