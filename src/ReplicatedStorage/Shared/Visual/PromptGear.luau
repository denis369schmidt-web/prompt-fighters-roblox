--!strict
-- Extra gear sets for prompt fighters (Shared/Prompt): weapons and accessories the hand-made roster does not have
-- (hammer, axe, scythe, blaster, magic staff, gauntlets, wizard hat, capes, halo, horns, animal ears and tails).
-- Same piece format and conventions as Visual/GearData (scale-1 studs, head units on the head, rig faces -Z,
-- weapons point along -Z out of the right hand). Colors are look slots, so every set takes the prompt's palette.
-- RigBuilder looks gear up here when GearData has no set of that name. Own designs only.

local GearData = require(script.Parent.GearData)

type Piece = GearData.Piece

local function p(
	limb: string,
	name: string,
	size: { number },
	offset: { number },
	color: string,
	material: string,
	shape: string?,
	rotation: { number }?
): Piece
	return {
		limb = limb,
		name = name,
		size = size,
		offset = offset,
		color = color,
		material = material,
		shape = shape,
		rotation = rotation,
	}
end

local function c(
	limb: string,
	name: string,
	size: { number },
	cf: CFrame,
	color: string,
	material: string,
	shape: string?
): Piece
	local piece = p(limb, name, size, { 0, 0, 0 }, color, material, shape)
	piece.cf = cf
	return piece
end

local function seeThrough(piece: Piece, transparency: number): Piece
	piece.transparency = transparency
	return piece
end

local function mirrorCF(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

local function mirror(pieces: { Piece }): { Piece }
	local out = table.clone(pieces)
	for _, d in pieces do
		local m = table.clone(d)
		local limb = d.limb
		if string.sub(limb, 1, 5) == "Right" then
			limb = "Left" .. string.sub(limb, 6)
		elseif string.sub(limb, 1, 4) == "Left" then
			limb = "Right" .. string.sub(limb, 5)
		end
		m.limb = limb
		m.offset = { -d.offset[1], d.offset[2], d.offset[3] }
		local r = d.rotation
		if r then
			m.rotation = { r[1], -r[2], -r[3] }
		end
		if d.cf then
			m.cf = mirrorCF(d.cf :: CFrame)
		end
		table.insert(out, m)
	end
	return out
end

local function join(...: { Piece }): { Piece }
	local out = {}
	for _, list in { ... } do
		for _, d in list do
			table.insert(out, d)
		end
	end
	return out
end

-- A cylinder lying along Z (weapon shafts).
local function zcyl(
	limb: string,
	name: string,
	len: number,
	d: number,
	at: { number },
	color: string,
	material: string
): Piece
	return p(limb, name, { len, d, d }, at, color, material, "Cylinder", { 0, 90, 0 })
end

-- A standing cylinder (hat cones, brims): diameter d, height h.
local function ycyl(
	limb: string,
	name: string,
	d: number,
	h: number,
	at: { number },
	color: string,
	material: string,
	tilt: number?
): Piece
	return p(limb, name, { h, d, d }, at, color, material, "Cylinder", { tilt or 0, 0, 90 })
end

-- A chain of segments from `start`, pointing along -Y after `angles`, each next one turned by `bend`.
local function chain(
	limb: string,
	name: string,
	start: { number },
	angles: { number },
	count: number,
	length: number,
	bend: { number },
	from: { number },
	to: { number },
	colors: { string },
	material: string
): { Piece }
	local out = {}
	local frame = CFrame.new(start[1], start[2], start[3])
		* CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
	for i = 1, count do
		local t = if count > 1 then (i - 1) / (count - 1) else 0
		local wd = from[1] + (to[1] - from[1]) * t
		local th = from[2] + (to[2] - from[2]) * t
		local col = colors[math.min(i, #colors)]
		table.insert(
			out,
			c(limb, name, { wd, length * 1.12, th }, frame * CFrame.new(0, -length / 2, 0), col, material)
		)
		frame = frame
			* CFrame.new(0, -length, 0)
			* CFrame.Angles(math.rad(bend[1]), math.rad(bend[2]), math.rad(bend[3]))
	end
	return out
end

-- Pieces around a vertical ring (halo, crowns), each facing outward.
local function ring(
	limb: string,
	name: string,
	center: { number },
	radius: number,
	count: number,
	size: { number },
	color: string,
	material: string
): { Piece }
	local out = {}
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2
		local pos = Vector3.new(center[1] + math.sin(a) * radius, center[2], center[3] - math.cos(a) * radius)
		table.insert(out, c(limb, name, size, CFrame.new(pos) * CFrame.Angles(0, -a, 0), color, material))
	end
	return out
end

-- A triangle of two wedges standing on `base` (ears, horns), rolled by `roll` degrees.
local function spike(
	limb: string,
	name: string,
	base: { number },
	width: number,
	height: number,
	thick: number,
	roll: number,
	pitch: number,
	color: string,
	material: string
): { Piece }
	local frame = CFrame.new(base[1], base[2], base[3]) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
	return {
		c(
			limb,
			name,
			{ thick, height, width / 2 },
			frame * CFrame.new(width / 4, height / 2, 0) * CFrame.Angles(0, math.rad(-90), 0),
			color,
			material,
			"Wedge"
		),
		c(
			limb,
			name,
			{ thick, height, width / 2 },
			frame * CFrame.new(-width / 4, height / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
			color,
			material,
			"Wedge"
		),
	}
end

local gear: { [string]: { Piece } } = {}

---------------------------------------------------------------------------------------------------------------
-- Weapons (right hand, pointing along -Z)

-- War hammer: long haft, heavy block head with glowing rune bands.
gear.hammer = {
	zcyl("RightHand", "HammerHaft", 2.5, 0.16, { 0, -0.18, -0.85 }, "#5A3B26", "Wood"),
	zcyl("RightHand", "HammerGrip", 0.6, 0.21, { 0, -0.18, 0.12 }, "leather", "Leather"),
	p("RightHand", "HammerPommel", { 0.26, 0.26, 0.26 }, { 0, -0.18, 0.48 }, "accent", "Metal", "Ball"),
	p("RightHand", "HammerHead", { 0.7, 1.15, 0.7 }, { 0, -0.18, -2.2 }, "steel*0.9", "Metal"),
	p("RightHand", "HammerCap", { 0.8, 0.16, 0.8 }, { 0, 0.42, -2.2 }, "accent", "Metal"),
	p("RightHand", "HammerCap", { 0.8, 0.16, 0.8 }, { 0, -0.78, -2.2 }, "accent", "Metal"),
	p("RightHand", "HammerRune", { 0.74, 0.1, 0.74 }, { 0, -0.18, -2.2 }, "glow", "Neon"),
	p("RightHand", "HammerRune", { 0.16, 0.7, 0.74 }, { 0, -0.18, -2.2 }, "glow", "Neon"),
}

-- Battle axe: haft with a broad blade on one side and a spike on the other.
gear.battle_axe = {
	zcyl("RightHand", "AxeHaft", 3.1, 0.16, { 0, -0.18, -1.05 }, "#5A3B26", "Wood"),
	zcyl("RightHand", "AxeGrip", 0.6, 0.21, { 0, -0.18, 0.15 }, "leather", "Leather"),
	p("RightHand", "AxeCollar", { 0.3, 0.42, 0.42 }, { 0, -0.18, -2.4 }, "accent", "Metal"),
	p("RightHand", "AxeBlade", { 0.12, 0.95, 0.9 }, { 0, 0.42, -2.4 }, "steel*1.05", "Metal"),
	p("RightHand", "AxeBlade", { 0.1, 0.5, 1.2 }, { 0, 0.85, -2.4 }, "steel*1.15", "Metal"),
	p("RightHand", "AxeEdge", { 0.14, 0.1, 1.3 }, { 0, 1.12, -2.4 }, "glow", "Neon"),
	p("RightHand", "AxeSpike", { 0.12, 0.5, 0.3 }, { 0, -0.62, -2.4 }, "steel*0.9", "Metal", "Wedge", { 180, 0, 0 }),
	p("RightHand", "AxeTip", { 0.2, 0.2, 0.35 }, { 0, -0.18, -2.75 }, "accent", "Metal"),
}

-- Scythe: tall shaft, a curved blade of three plates with a glowing edge.
gear.scythe = {
	zcyl("RightHand", "ScytheShaft", 4.6, 0.15, { 0, -0.18, -1.2 }, "#2E2630", "Wood"),
	zcyl("RightHand", "ScytheGrip", 0.5, 0.2, { 0, -0.18, -0.1 }, "leather", "Leather"),
	p("RightHand", "ScytheCollar", { 0.26, 0.3, 0.3 }, { 0, -0.18, -3.45 }, "accent", "Metal"),
	p("RightHand", "ScytheBlade", { 0.08, 1.0, 0.34 }, { 0, 0.38, -3.48 }, "steel*1.1", "Metal", nil, { -12, 0, 0 }),
	p("RightHand", "ScytheBlade", { 0.08, 0.9, 0.3 }, { 0, 1.18, -3.28 }, "steel*1.1", "Metal", nil, { -38, 0, 0 }),
	p("RightHand", "ScytheBlade", { 0.08, 0.75, 0.24 }, { 0, 1.72, -2.82 }, "steel*1.15", "Metal", nil, { -68, 0, 0 }),
	p("RightHand", "ScytheEdge", { 0.1, 1.0, 0.07 }, { 0, 0.4, -3.3 }, "glow", "Neon", nil, { -12, 0, 0 }),
	p("RightHand", "ScytheEdge", { 0.1, 0.9, 0.07 }, { 0, 1.1, -3.13 }, "glow", "Neon", nil, { -38, 0, 0 }),
	p("RightHand", "ScytheEdge", { 0.1, 0.75, 0.07 }, { 0, 1.6, -2.72 }, "glow", "Neon", nil, { -68, 0, 0 }),
}

-- Blaster: chunky energy pistol with a glowing cell and muzzle.
gear.blaster = {
	p("RightHand", "BlasterGrip", { 0.26, 0.55, 0.32 }, { 0, -0.2, 0.05 }, "dark", "SmoothPlastic", nil, { -15, 0, 0 }),
	p("RightHand", "BlasterBody", { 0.38, 0.46, 1.25 }, { 0, 0.15, -0.45 }, "primary*0.7", "Metal"),
	p("RightHand", "BlasterCell", { 0.42, 0.16, 0.6 }, { 0, 0.42, -0.4 }, "glow", "Neon"),
	zcyl("RightHand", "BlasterBarrel", 0.8, 0.24, { 0, 0.2, -1.4 }, "steel", "Metal"),
	zcyl("RightHand", "BlasterMuzzle", 0.14, 0.3, { 0, 0.2, -1.84 }, "glow", "Neon"),
	p("RightHand", "BlasterFin", { 0.06, 0.28, 0.5 }, { 0, 0.5, -0.95 }, "accent", "Metal"),
}

-- Magic staff: long shaft, a cage of prongs around a glowing orb.
gear.magic_staff = {
	zcyl("RightHand", "StaffShaft", 4.8, 0.16, { 0, -0.18, -1.1 }, "#4A3020", "Wood"),
	zcyl("RightHand", "StaffBand", 0.16, 0.22, { 0, -0.18, -3.3 }, "accent", "Metal"),
	p("RightHand", "StaffOrb", { 0.62, 0.62, 0.62 }, { 0, -0.18, -3.85 }, "glow", "Neon", "Ball"),
	seeThrough(
		p("RightHand", "StaffAura", { 1.05, 1.05, 1.05 }, { 0, -0.18, -3.85 }, "glow", "ForceField", "Ball"),
		0.25
	),
	p("RightHand", "StaffProng", { 0.08, 0.7, 0.08 }, { 0.32, -0.18, -3.75 }, "accent", "Metal", nil, { -90, 0, -20 }),
	p("RightHand", "StaffProng", { 0.08, 0.7, 0.08 }, { -0.32, -0.18, -3.75 }, "accent", "Metal", nil, { -90, 0, 20 }),
	p("RightHand", "StaffProng", { 0.08, 0.7, 0.08 }, { 0, 0.14, -3.75 }, "accent", "Metal", nil, { -110, 0, 0 }),
}

-- Power gauntlets on both fists, with glowing knuckles.
gear.power_gauntlets = mirror({
	p("RightHand", "Gauntlet", { 0.76, 0.7, 0.8 }, { 0, -0.02, 0 }, "accent*0.8", "Metal"),
	p("RightHand", "GauntletKnuckle", { 0.8, 0.16, 0.3 }, { 0, -0.3, -0.22 }, "glow", "Neon"),
	p("RightLowerArm", "GauntletCuff", { 0.86, 0.6, 0.86 }, { 0, -0.25, 0 }, "accent*0.65", "Metal", "Cylinder", {
		0,
		0,
		90,
	}),
	p("RightLowerArm", "GauntletRune", { 0.9, 0.1, 0.9 }, { 0, -0.1, 0 }, "glow", "Neon", "Cylinder", { 0, 0, 90 }),
})

---------------------------------------------------------------------------------------------------------------
-- Headwear and accessories

-- Tall pointed wizard hat with a wide brim, a glowing band and a star at the tip, leaning back.
gear.wizard_hat = {
	ycyl("Head", "HatBrim", 1.95, 0.08, { 0, 0.52, 0.04 }, "primary*0.75", "Fabric"),
	ycyl("Head", "HatBand", 1.12, 0.14, { 0, 0.62, 0.04 }, "glow", "Neon"),
	ycyl("Head", "HatCone", 1.06, 0.4, { 0, 0.78, 0.06 }, "primary*0.85", "Fabric", -6),
	ycyl("Head", "HatCone", 0.8, 0.4, { 0, 1.12, 0.14 }, "primary*0.85", "Fabric", -12),
	ycyl("Head", "HatCone", 0.54, 0.4, { 0, 1.42, 0.27 }, "primary*0.85", "Fabric", -20),
	ycyl("Head", "HatCone", 0.3, 0.36, { 0, 1.66, 0.43 }, "primary*0.85", "Fabric", -30),
	p("Head", "HatStar", { 0.24, 0.24, 0.05 }, { 0, 0.98, -0.42 }, "glow", "Neon", nil, { 0, 0, 45 }),
	p("Head", "HatTip", { 0.18, 0.18, 0.18 }, { 0, 1.84, 0.58 }, "glow", "Neon", "Ball"),
}

-- Long cape from the shoulders with a stiff high collar (vampire lords, night counts).
gear.vampire_cape = join(
	{
		p("UpperTorso", "CapeMantle", { 2.15, 0.28, 1.2 }, { 0, 0.78, 0.04 }, "secondary*0.8", "Fabric"),
		p("UpperTorso", "CapeClasp", { 0.22, 0.22, 0.22 }, { 0, 0.72, -0.62 }, "glow", "Neon", "Ball"),
		p("UpperTorso", "Collar", { 0.12, 1.1, 0.8 }, { 0.66, 1.3, 0.12 }, "glow*0.45", "Fabric", "Wedge", {
			0,
			0,
			-18,
		}),
		p("UpperTorso", "Collar", { 0.12, 1.1, 0.8 }, { -0.66, 1.3, 0.12 }, "glow*0.45", "Fabric", "Wedge", {
			0,
			0,
			18,
		}),
		p("UpperTorso", "CollarBack", { 1.4, 1.0, 0.1 }, { 0, 1.3, 0.55 }, "glow*0.45", "Fabric", nil, { -14, 0, 0 }),
	},
	chain(
		"UpperTorso",
		"Cape",
		{ 0, 0.85, 0.6 },
		{ 6, 0, 0 },
		4,
		0.75,
		{ 3, 0, 0 },
		{ 2.0, 0.08 },
		{ 2.3, 0.08 },
		{ "secondary*0.8", "secondary*0.75", "secondary*0.7", "glow*0.4" },
		"Fabric"
	)
)

-- Noble vest: a fitted waistcoat in the accent color with a white jabot and a glowing brooch.
gear.noble_vest = {
	p("UpperTorso", "Vest", { 1.5, 1.35, 0.12 }, { 0, -0.05, -0.55 }, "accent*0.55", "Fabric"),
	p("UpperTorso", "VestTrim", { 0.12, 1.35, 0.14 }, { 0.42, -0.05, -0.56 }, "accent", "Fabric"),
	p("UpperTorso", "VestTrim", { 0.12, 1.35, 0.14 }, { -0.42, -0.05, -0.56 }, "accent", "Fabric"),
	p("UpperTorso", "Jabot", { 0.42, 0.5, 0.14 }, { 0, 0.5, -0.6 }, "white", "Fabric", "Wedge", { 0, 180, 0 }),
	p("UpperTorso", "Brooch", { 0.22, 0.22, 0.08 }, { 0, 0.22, -0.66 }, "glow", "Neon", nil, { 0, 0, 45 }),
}

-- Hero cape: shorter, in the accent color.
gear.hero_cape = join(
	{
		p("UpperTorso", "CapeMantle", { 2.05, 0.24, 1.15 }, { 0, 0.78, 0.04 }, "accent", "Fabric"),
		p("UpperTorso", "CapeClasp", { 0.24, 0.24, 0.24 }, { 0.55, 0.7, -0.58 }, "glow", "Neon", "Ball"),
		p("UpperTorso", "CapeClasp", { 0.24, 0.24, 0.24 }, { -0.55, 0.7, -0.58 }, "glow", "Neon", "Ball"),
	},
	chain(
		"UpperTorso",
		"Cape",
		{ 0, 0.85, 0.58 },
		{ 8, 0, 0 },
		3,
		0.75,
		{ 4, 0, 0 },
		{ 1.8, 0.08 },
		{ 2.0, 0.08 },
		{ "accent", "accent*0.9", "accent*0.8" },
		"Fabric"
	)
)

-- Glowing halo floating above the head.
gear.halo = ring("Head", "Halo", { 0, 1.05, 0.1 }, 0.42, 10, { 0.28, 0.08, 0.08 }, "glow", "Neon")

-- Curved horns from the temples (demons, oni).
gear.demon_horns = join(
	chain("Head", "Horn", { 0.36, 0.42, -0.05 }, { 180, 0, -28 }, 3, 0.26, { 0, 0, 16 }, { 0.2, 0.2 }, {
		0.1,
		0.1,
	}, { "#2A2226", "#3A3036", "glow" }, "SmoothPlastic"),
	chain("Head", "Horn", { -0.36, 0.42, -0.05 }, { 180, 0, 28 }, 3, 0.26, { 0, 0, -16 }, { 0.2, 0.2 }, {
		0.1,
		0.1,
	}, { "#2A2226", "#3A3036", "glow" }, "SmoothPlastic")
)

-- Round bear ears.
gear.bear_ears = mirror({
	p("Head", "BearEar", { 0.4, 0.4, 0.4 }, { 0.42, 0.5, 0.05 }, "hair", "Fabric", "Ball"),
	p("Head", "BearEarInner", { 0.24, 0.24, 0.2 }, { 0.42, 0.5, -0.08 }, "hair*0.6", "Fabric", "Ball"),
})

-- Small pointed cat ears.
gear.cat_ears = join(
	spike("Head", "CatEar", { 0.34, 0.5, 0.0 }, 0.36, 0.38, 0.12, -14, 0, "hair", "Fabric"),
	spike("Head", "CatEar", { -0.34, 0.5, 0.0 }, 0.36, 0.38, 0.12, 14, 0, "hair", "Fabric"),
	spike("Head", "CatEarInner", { 0.34, 0.52, -0.06 }, 0.2, 0.24, 0.04, -14, 0, "pink", "SmoothPlastic"),
	spike("Head", "CatEarInner", { -0.34, 0.52, -0.06 }, 0.2, 0.24, 0.04, 14, 0, "pink", "SmoothPlastic")
)

-- Bushy tail with a light tip (wolves, cats).
gear.wolf_tail = chain(
	"LowerTorso",
	"Tail",
	{ 0, 0.05, 0.5 },
	{ -55, 0, 0 },
	4,
	0.42,
	{ -14, 0, 0 },
	{ 0.36, 0.36 },
	{ 0.24, 0.24 },
	{ "hair", "hair", "hair*1.1", "fur" },
	"Fabric"
)

-- Gold crown (kings, queens) with gems in the glow color.
gear.gold_crown = join(
	ring("Head", "CrownBand", { 0, 0.62, 0.06 }, 0.48, 8, { 0.4, 0.16, 0.08 }, "gold", "Metal"),
	ring("Head", "CrownPoint", { 0, 0.8, 0.06 }, 0.48, 5, { 0.14, 0.28, 0.08 }, "gold", "Metal"),
	{ p("Head", "CrownGem", { 0.16, 0.16, 0.06 }, { 0, 0.64, -0.55 }, "glow", "Neon", nil, { 0, 0, 45 }) }
)

return gear
