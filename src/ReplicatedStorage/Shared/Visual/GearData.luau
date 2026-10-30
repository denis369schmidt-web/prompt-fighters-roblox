--!strict
-- Data-driven gear for Visual/RigBuilder. Each gear set is a list of pieces { limb, name, size, offset, color,
-- material, shape?, rotation? } in studs and degrees at scale 1, relative to the limb's visual center (rig faces
-- -Z, up is +Y). Head pieces use head units (head radius 0.6, face front at z = -0.6, top at y = 0.65).
-- RigBuilder scales every piece to the fighter's build. Shapes: Block (default), Ball, Cylinder (axis = X), Wedge
-- (slope rising toward +Z). Colors are look slots (primary, secondary, skin, glow, hair, accent, trim), fixed tones
-- (steel, gold, wood, dark, white, leather, bone, rope, red, black, brass, fur, pink, iron) or "#RRGGBB", each
-- optionally shaded with "*factor". Generators below (mirror, chain, fan, ring) turn a few numbers into curved
-- tails, capes, wings and crowns. Own designs only.

export type Piece = {
	limb: string,
	name: string,
	size: { number },
	offset: { number },
	color: string,
	material: string,
	shape: string?,
	rotation: { number }?,
	cf: CFrame?, -- overrides offset/rotation (generated pieces)
	transparency: number?,
}

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

-- Wedge piece.
local function w(
	limb: string,
	name: string,
	size: { number },
	offset: { number },
	color: string,
	material: string,
	rotation: { number }?
): Piece
	return p(limb, name, size, offset, color, material, "Wedge", rotation)
end

-- Piece placed by a CFrame (generators).
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

-- The same pieces plus their mirror image across the body's center plane (Right* limbs become Left* limbs).
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

-- Concatenates piece lists.
local function join(...: { Piece }): { Piece }
	local out = {}
	for _, list in { ... } do
		for _, d in list do
			table.insert(out, d)
		end
	end
	return out
end

local function rad(v: number): number
	return math.rad(v)
end

-- A hanging or curling chain of segments (tails, ponytails, scarf ends, cape strips, horns). Starts at `start`,
-- first segment points along the frame's -Y after rotating by `angles` (degrees, XYZ); each next segment turns by
-- `bend`. Segment sizes go from `from` to `to` ({ width, thickness }); colors cycle through `colors` by segment.
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
	material: string,
	shape: string?
): { Piece }
	local out = {}
	local frame = CFrame.new(start[1], start[2], start[3])
		* CFrame.Angles(rad(angles[1]), rad(angles[2]), rad(angles[3]))
	for i = 1, count do
		local t = if count > 1 then (i - 1) / (count - 1) else 0
		local wd = from[1] + (to[1] - from[1]) * t
		local th = from[2] + (to[2] - from[2]) * t
		local col = colors[math.min(i, #colors)]
		local center = frame * CFrame.new(0, -length / 2, 0)
		if shape == "Ball" then
			table.insert(out, c(limb, name, { wd, wd, wd }, center, col, material, "Ball"))
		elseif shape == "Wedge" then
			table.insert(out, c(limb, name, { th, length * 1.15, wd }, center, col, material, "Wedge"))
		else
			table.insert(out, c(limb, name, { wd, length * 1.12, th }, center, col, material))
		end
		frame = frame * CFrame.new(0, -length, 0) * CFrame.Angles(rad(bend[1]), rad(bend[2]), rad(bend[3]))
	end
	return out
end

-- A fan of feathers or blades from one pivot (wings, crests, tail fans). Feather i points up, rotated outward by
-- `spread` degrees (from first to last) around the frame's Z after the frame turns by `angles`; lengths and colors
-- per feather. Feathers are flat blocks { thickness, length, width }.
local function fan(
	limb: string,
	name: string,
	pivot: { number },
	angles: { number },
	spread: { number },
	lengths: { number },
	width: number,
	thickness: number,
	colors: { string },
	material: string
): { Piece }
	local out = {}
	local base = CFrame.new(pivot[1], pivot[2], pivot[3])
		* CFrame.Angles(rad(angles[1]), rad(angles[2]), rad(angles[3]))
	local n = #lengths
	for i, len in lengths do
		local t = if n > 1 then (i - 1) / (n - 1) else 0
		local a = spread[1] + (spread[2] - spread[1]) * t
		local cf = base * CFrame.Angles(0, 0, rad(-a)) * CFrame.new(0, len / 2, 0)
		table.insert(out, c(limb, name, { thickness, len, width }, cf, colors[math.min(i, #colors)], material))
	end
	return out
end

-- Pieces around a vertical ring (skirts, crowns, collars): `count` pieces from angle `from` to `to` (degrees,
-- 0 = front, 90 = the rig's right), each facing outward and tilted out at the bottom by `flare` degrees.
local function ring(
	limb: string,
	name: string,
	center: { number },
	radius: { number },
	count: number,
	from: number,
	to: number,
	size: { number },
	flare: number,
	colors: { string },
	material: string,
	shape: string?
): { Piece }
	local out = {}
	for i = 1, count do
		local t = if count > 1 then (i - 1) / (count - 1) else 0.5
		local a = rad(from + (to - from) * t)
		local pos = Vector3.new(center[1] + math.sin(a) * radius[1], center[2], center[3] - math.cos(a) * radius[2])
		local cf = CFrame.new(pos) * CFrame.Angles(0, -a, 0) * CFrame.Angles(rad(flare), 0, 0)
		table.insert(out, c(limb, name, size, cf, colors[(i - 1) % #colors + 1], material, shape))
	end
	return out
end

-- An isosceles triangle (two wedges) standing on `base` in the frame's X-Y plane, `height` tall, rolled by `roll`
-- degrees and pitched by `pitch` (spikes, fox ears, bangs, kite-shield points).
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
	local frame = CFrame.new(base[1], base[2], base[3]) * CFrame.Angles(rad(pitch), 0, rad(roll))
	return {
		c(
			limb,
			name,
			{ thick, height, width / 2 },
			frame * CFrame.new(width / 4, height / 2, 0) * CFrame.Angles(0, rad(-90), 0),
			color,
			material,
			"Wedge"
		),
		c(
			limb,
			name,
			{ thick, height, width / 2 },
			frame * CFrame.new(-width / 4, height / 2, 0) * CFrame.Angles(0, rad(90), 0),
			color,
			material,
			"Wedge"
		),
	}
end

-- A vertical band (cylinder around a limb) at height y.
local function band(limb: string, name: string, y: number, d: number, h: number, color: string, material: string): Piece
	return p(limb, name, { h, d, d }, { 0, y, 0 }, color, material, "Cylinder", { 0, 0, 90 })
end

-- A cylinder lying along Z (weapon shafts, discs facing forward).
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

local gear: { [string]: { Piece } } = {}

---------------------------------------------------------------------------------------------------------------
-- Generic (fallback look)

gear.hair_short = join({
	p("Head", "Hair", { 1.3, 1.3, 1.3 }, { 0, 0.14, 0.07 }, "hair", "Fabric", "Ball"),
}, spike("Head", "Bang", { 0.15, 0.62, -0.5 }, 0.5, 0.35, 0.18, 160, 20, "hair", "Fabric"))

gear.scarf = join(
	{
		band("UpperTorso", "Scarf", 0.98, 0.95, 0.32, "glow", "Fabric"),
	},
	chain("UpperTorso", "ScarfTail", { 0.2, 0.95, 0.42 }, { -70, 0, 0 }, 3, 0.5, { 12, 0, 6 }, { 0.34, 0.07 }, {
		0.26,
		0.06,
	}, { "glow" }, "Fabric")
)

---------------------------------------------------------------------------------------------------------------
-- VOLT NINJA

gear.ninja_hood = join(
	{
		p("Head", "Hood", { 1.38, 1.38, 1.38 }, { 0, 0.1, 0.12 }, "primary", "Fabric", "Ball"),
		band("Head", "Headband", 0.3, 1.42, 0.15, "primary*0.6", "Fabric"),
		p("Head", "HeadPlate", { 0.5, 0.2, 0.06 }, { 0, 0.3, -0.7 }, "accent", "Metal"),
		p("Head", "PlateBolt", { 0.08, 0.16, 0.04 }, { 0, 0.3, -0.74 }, "glow", "Neon", nil, { 0, 0, 30 }),
	},
	chain(
		"Head",
		"BandTail",
		{ 0.12, 0.3, 0.68 },
		{ -75, 15, 0 },
		2,
		0.45,
		{ 12, 0, 10 },
		{ 0.16, 0.05 },
		{ 0.12, 0.05 },
		{ "primary*0.6" },
		"Fabric"
	),
	chain(
		"Head",
		"BandTail",
		{ -0.08, 0.28, 0.68 },
		{ -60, -10, 0 },
		2,
		0.4,
		{ 15, 0, -8 },
		{ 0.14, 0.05 },
		{ 0.1, 0.05 },
		{ "primary*0.6" },
		"Fabric"
	)
)

gear.ninja_mask = {
	p("Head", "Mask", { 0.44, 1.27, 1.27 }, { 0, -0.43, 0 }, "primary*0.75", "Fabric", "Cylinder", { 0, 0, 90 }),
	p("Head", "MaskSeam", { 0.06, 0.4, 0.05 }, { 0, -0.43, -0.64 }, "primary*0.5", "Fabric"),
}

gear.ninja_suit = join(
	{
		p("UpperTorso", "Strap", { 0.16, 1.3, 0.06 }, { 0, 0.3, -0.53 }, "accent*0.6", "Leather", nil, { 0, 0, 38 }),
		p("UpperTorso", "Strap", { 0.16, 1.3, 0.06 }, { 0, 0.3, -0.53 }, "accent*0.6", "Leather", nil, { 0, 0, -38 }),
		p("UpperTorso", "StrapRing", { 0.22, 0.22, 0.07 }, { 0, 0.3, -0.56 }, "accent", "Metal", nil, { 0, 0, 45 }),
		-- Lightning bolt on the chest.
		p("UpperTorso", "Bolt", { 0.09, 0.34, 0.04 }, { 0.5, 0.56, -0.53 }, "glow", "Neon", nil, { 0, 0, -22 }),
		p("UpperTorso", "Bolt", { 0.24, 0.08, 0.04 }, { 0.5, 0.4, -0.53 }, "glow", "Neon", nil, { 0, 0, 12 }),
		p("UpperTorso", "Bolt", { 0.09, 0.3, 0.04 }, { 0.53, 0.25, -0.53 }, "glow", "Neon", nil, { 0, 0, -22 }),
		-- One armored shoulder.
		p(
			"LeftUpperArm",
			"ShoulderGuard",
			{ 0.95, 0.16, 0.95 },
			{ -0.08, 0.78, 0 },
			"accent",
			"Metal",
			nil,
			{ 0, 0, 18 }
		),
		p(
			"LeftUpperArm",
			"ShoulderGuard2",
			{ 0.85, 0.14, 0.85 },
			{ -0.22, 0.56, 0 },
			"accent*0.8",
			"Metal",
			nil,
			{ 0, 0, 32 }
		),
		p(
			"LowerTorso",
			"SashKnot",
			{ 0.26, 0.26, 0.12 },
			{ 0.42, 0.32, -0.52 },
			"glow*0.6",
			"Fabric",
			nil,
			{ 0, 0, 45 }
		),
	},
	chain(
		"LowerTorso",
		"SashTail",
		{ 0.45, 0.25, -0.52 },
		{ 0, 0, 12 },
		2,
		0.32,
		{ 0, 0, -6 },
		{ 0.16, 0.05 },
		{ 0.13, 0.05 },
		{ "glow*0.6" },
		"Fabric"
	)
)

gear.scarf_tails = join(
	{ band("UpperTorso", "Scarf", 0.98, 0.98, 0.34, "glow*0.85", "Fabric") },
	mirror(
		chain(
			"UpperTorso",
			"ScarfTail",
			{ 0.16, 0.98, 0.42 },
			{ -78, 12, 0 },
			4,
			0.48,
			{ 8, 0, 5 },
			{ 0.34, 0.06 },
			{ 0.22, 0.05 },
			{ "glow*0.85", "glow*0.85", "glow*0.85", "glow" },
			"Fabric"
		)
	)
)

local function shortBlade(angle: number): { Piece }
	local frame = CFrame.new(0, 0.3, 0.62) * CFrame.Angles(0, 0, rad(angle))
	return {
		c("UpperTorso", "BackHilt", { 0.12, 0.5, 0.12 }, frame * CFrame.new(0, 1.0, 0), "black", "Fabric"),
		c("UpperTorso", "BackGuard", { 0.36, 0.08, 0.14 }, frame * CFrame.new(0, 0.72, 0), "accent", "Metal"),
		c("UpperTorso", "BackBlade", { 0.12, 1.45, 0.05 }, frame * CFrame.new(0, -0.02, 0), "steel", "Metal"),
		c("UpperTorso", "BackEdge", { 0.03, 1.35, 0.06 }, frame * CFrame.new(0.06, -0.02, 0), "glow", "Neon"),
	}
end
gear.blades_back = join(shortBlade(32), shortBlade(-32))

gear.arm_wraps = mirror({
	band("RightLowerArm", "Wrap", 0.18, 0.6, 0.1, "accent*0.75", "Fabric"),
	band("RightLowerArm", "Wrap", -0.12, 0.6, 0.1, "accent*0.75", "Fabric"),
})

gear.shin_wraps = mirror({
	band("RightLowerLeg", "ShinWrap", 0.35, 0.64, 0.1, "accent*0.75", "Fabric"),
	band("RightLowerLeg", "ShinWrap", 0.12, 0.66, 0.1, "accent*0.75", "Fabric"),
})

---------------------------------------------------------------------------------------------------------------
-- MAGMOR (golem)

gear.rock_head = {
	p("Head", "BrowRock", { 1.2, 0.26, 0.4 }, { 0, 0.2, -0.48 }, "skin*0.85", "Slate", nil, { -12, 0, 0 }),
	p("Head", "JawRock", { 1.05, 0.38, 0.55 }, { 0, -0.55, -0.3 }, "skin*0.9", "Slate", nil, { 6, 0, 0 }),
	p("Head", "MouthGlow", { 0.55, 0.06, 0.04 }, { 0, -0.36, -0.6 }, "glow", "Neon"),
	p("Head", "CrownRock", { 0.5, 0.42, 0.5 }, { -0.28, 0.55, 0.05 }, "skin*1.1", "Slate", nil, { 20, 30, 15 }),
	p("Head", "CrownRock", { 0.45, 0.5, 0.45 }, { 0.28, 0.6, 0.1 }, "skin*1.05", "Slate", nil, { -15, 45, -20 }),
	p("Head", "CrownRock", { 0.42, 0.4, 0.42 }, { 0, 0.62, 0.32 }, "skin*0.95", "Slate", nil, { 30, 10, 10 }),
}

gear.rock_body = join(
	mirror({
		p("UpperTorso", "PecRock", { 0.92, 0.72, 0.34 }, { 0.46, 0.42, -0.46 }, "primary*1.15", "Slate", nil, {
			-6,
			-10,
			-8,
		}),
		p("UpperTorso", "AbRock", { 0.5, 0.32, 0.24 }, { 0.24, -0.25, -0.42 }, "primary*1.05", "Slate", nil, {
			0,
			-6,
			-4,
		}),
		p("UpperTorso", "AbRock", { 0.46, 0.3, 0.22 }, { 0.22, -0.6, -0.4 }, "primary*0.95", "Slate", nil, {
			0,
			-6,
			4,
		}),
	}),
	{
		p("UpperTorso", "Hump", { 1.5, 1.0, 0.65 }, { 0, 0.5, 0.42 }, "skin*0.95", "Slate", nil, { 15, 0, 0 }),
		p("UpperTorso", "HumpRock", { 0.6, 0.55, 0.5 }, { 0.35, 0.95, 0.6 }, "skin*1.1", "Slate", nil, { 30, 25, 15 }),
		p(
			"UpperTorso",
			"HumpRock",
			{ 0.55, 0.5, 0.45 },
			{ -0.4, 0.9, 0.62 },
			"skin*1.05",
			"Slate",
			nil,
			{ 20, -30, -10 }
		),
	}
)

gear.rock_shoulders = mirror({
	p("RightUpperArm", "Boulder", { 1.25, 1.0, 1.2 }, { 0.12, 0.7, 0 }, "primary*1.2", "Slate", nil, { 10, 25, -15 }),
	p(
		"RightUpperArm",
		"BoulderTop",
		{ 0.65, 0.6, 0.65 },
		{ 0.3, 1.05, 0.15 },
		"primary*1.1",
		"Slate",
		nil,
		{ 30, 45, 10 }
	),
	p("RightUpperArm", "BoulderGlow", { 0.06, 0.6, 0.04 }, { 0.1, 0.65, -0.62 }, "glow", "Neon", nil, { 0, 0, 30 }),
})

gear.magma_cracks = join(
	{
		p("UpperTorso", "Crack", { 0.08, 0.85, 0.04 }, { 0, 0.32, -0.53 }, "glow", "Neon", nil, { 0, 0, 8 }),
		p("UpperTorso", "Crack", { 0.07, 0.5, 0.04 }, { 0.28, -0.4, -0.44 }, "glow", "Neon", nil, { 0, 0, -40 }),
		p("UpperTorso", "Crack", { 0.07, 0.45, 0.04 }, { -0.3, -0.15, -0.44 }, "glow", "Neon", nil, { 0, 0, 35 }),
		p("UpperTorso", "Core", { 0.42, 0.42, 0.42 }, { 0, 0.15, -0.5 }, "glow", "Neon", "Ball"),
		p("LowerTorso", "Crack", { 0.9, 0.07, 0.04 }, { 0, 0.05, -0.48 }, "glow", "Neon", nil, { 0, 0, 6 }),
	},
	mirror({
		p("RightUpperArm", "ArmCrack", { 0.06, 0.65, 0.04 }, { 0.05, -0.1, -0.31 }, "glow", "Neon", nil, { 0, 0, 20 }),
		p("RightLowerArm", "ArmCrack", { 0.06, 0.55, 0.04 }, { -0.03, 0, -0.29 }, "glow", "Neon", nil, { 0, 0, -25 }),
		p("RightUpperLeg", "LegCrack", { 0.06, 0.7, 0.04 }, { 0.05, 0, -0.39 }, "glow", "Neon", nil, { 0, 0, 15 }),
	})
)

gear.magma_fists = mirror({
	p("RightHand", "Gauntlet", { 0.62, 0.62, 0.68 }, { 0, -0.02, 0 }, "skin*1.15", "Slate", nil, { 5, 10, 5 }),
	p("RightHand", "KnuckleGlow", { 0.66, 0.14, 0.56 }, { 0, -0.3, 0 }, "glow", "Neon"),
	p("RightLowerArm", "Bracer", { 0.74, 0.5, 0.74 }, { 0, -0.25, 0 }, "primary*1.1", "Slate", nil, { 0, 20, 0 }),
})

gear.rock_legs = mirror({
	p(
		"RightLowerLeg",
		"KneeRock",
		{ 0.66, 0.5, 0.42 },
		{ 0, 0.55, -0.24 },
		"primary*1.15",
		"Slate",
		nil,
		{ -20, 15, 5 }
	),
	p("RightUpperLeg", "ThighRock", { 0.8, 0.6, 0.45 }, { 0.05, 0.12, -0.24 }, "primary*1.05", "Slate", nil, {
		-5,
		-10,
		-5,
	}),
	p("RightFoot", "ToeGlow", { 0.5, 0.06, 0.04 }, { 0, 0.05, -0.62 }, "glow", "Neon"),
})

---------------------------------------------------------------------------------------------------------------
-- BOLTAR (valkyrie)

gear.winged_helm = join(
	{
		p("Head", "Helm", { 1.24, 1.24, 1.24 }, { 0, 0.42, 0.03 }, "gold", "Metal", "Ball"),
		band("Head", "HelmBand", 0.36, 1.3, 0.18, "gold*0.8", "Metal"),
		p("Head", "HelmGem", { 0.14, 0.14, 0.06 }, { 0, 0.36, -0.67 }, "glow", "Neon", nil, { 0, 0, 45 }),
		p("Head", "HairCap", { 1.28, 1.28, 1.28 }, { 0, 0.1, 0.1 }, "hair", "Fabric", "Ball"),
		p("Head", "HairBack", { 1.05, 1.15, 0.3 }, { 0, -0.35, 0.48 }, "hair", "Fabric"),
	},
	mirror(
		fan(
			"Head",
			"HelmWing",
			{ 0.62, 0.42, 0.1 },
			{ 30, 0, 0 },
			{ 20, 70 },
			{ 0.62, 0.78, 0.6 },
			0.22,
			0.06,
			{ "white", "white", "white*0.9" },
			"Fabric"
		)
	)
)

gear.braids = mirror(
	join(
		chain(
			"Head",
			"Braid",
			{ 0.42, -0.25, 0.1 },
			{ 18, 0, -6 },
			4,
			0.27,
			{ -4, 0, 3 },
			{ 0.3, 0.3 },
			{ 0.22, 0.22 },
			{ "hair", "hair*0.92" },
			"Fabric",
			"Ball"
		),
		{ p("Head", "BraidTie", { 0.18, 0.2, 0.2 }, { 0.5, -1.38, -0.22 }, "gold", "Metal", "Cylinder", { 0, 0, 90 }) }
	)
)

gear.valkyrie_armor = join(
	{
		p("UpperTorso", "Breastplate", { 1.6, 0.88, 0.14 }, { 0, 0.38, -0.52 }, "steel*1.1", "Metal"),
		p("UpperTorso", "PlateRidge", { 0.12, 0.85, 0.18 }, { 0, 0.38, -0.54 }, "gold", "Metal"),
		p("UpperTorso", "PlateTrim", { 1.62, 0.1, 0.17 }, { 0, -0.04, -0.53 }, "gold", "Metal"),
		p("UpperTorso", "ChestGem", { 0.22, 0.22, 0.22 }, { 0, 0.55, -0.62 }, "glow", "Neon", "Ball"),
		band("UpperTorso", "Collar", 0.86, 0.82, 0.18, "gold", "Metal"),
	},
	mirror({
		p("RightUpperArm", "Pauldron", { 0.98, 0.98, 0.98 }, { 0.1, 0.5, 0 }, "gold", "Metal", "Ball"),
		p(
			"RightUpperArm",
			"Pauldron2",
			{ 0.8, 0.18, 0.92 },
			{ 0.26, 0.14, 0 },
			"steel*1.1",
			"Metal",
			nil,
			{ 0, 0, -22 }
		),
	})
)

gear.skirt_plates = ring(
	"LowerTorso",
	"Tasset",
	{ 0, -0.12, 0 },
	{ 0.84, 0.52 },
	7,
	-120,
	120,
	{ 0.44, 0.72, 0.07 },
	12,
	{ "gold", "steel*1.1" },
	"Metal"
)

gear.feather_wings = mirror(
	join(
		fan(
			"UpperTorso",
			"Feather",
			{ 0.3, 0.45, 0.6 },
			{ 28, 0, 0 },
			{ 40, 135 },
			{ 2.1, 2.45, 2.3, 1.9 },
			0.52,
			0.08,
			{ "white", "white", "white*0.95", "glow" },
			"Fabric"
		),
		fan(
			"UpperTorso",
			"Covert",
			{ 0.3, 0.45, 0.66 },
			{ 28, 0, 0 },
			{ 50, 120 },
			{ 1.2, 1.2 },
			0.5,
			0.08,
			{ "gold" },
			"Metal"
		)
	)
)

gear.lance = {
	zcyl("RightHand", "Shaft", 4.8, 0.16, { 0, -0.18, -1.2 }, "accent*0.6", "Wood"),
	zcyl("RightHand", "Grip", 0.5, 0.21, { 0, -0.18, 0.1 }, "leather", "Leather"),
	zcyl("RightHand", "Vamplate", 0.1, 0.6, { 0, -0.18, -3.4 }, "gold", "Metal"),
	p("RightHand", "Blade", { 0.26, 0.26, 1.25 }, { 0, -0.18, -4.15 }, "steel*1.15", "Metal", nil, { 0, 0, 45 }),
	p("RightHand", "LanceEdge", { 0.05, 0.05, 1.15 }, { 0, -0.18, -4.15 }, "glow", "Neon"),
}

gear.greaves = mirror({
	p("RightLowerLeg", "Greave", { 0.52, 0.72, 0.12 }, { 0, 0.12, -0.32 }, "gold", "Metal"),
	p("RightLowerLeg", "KneeCop", { 0.48, 0.48, 0.48 }, { 0, 0.6, -0.2 }, "gold", "Metal", "Ball"),
})

---------------------------------------------------------------------------------------------------------------
-- KAIRO (wind monk)

gear.monk_vest = {
	p("UpperTorso", "Lapel", { 0.2, 1.02, 0.06 }, { -0.2, 0.36, -0.53 }, "primary*1.35", "Fabric", nil, { 0, 0, 24 }),
	p("UpperTorso", "Lapel", { 0.2, 1.02, 0.06 }, { 0.2, 0.36, -0.53 }, "primary*1.35", "Fabric", nil, { 0, 0, -24 }),
	p("UpperTorso", "VestHem", { 1.42, 0.14, 0.9 }, { 0, -0.75, 0.02 }, "primary*1.3", "Fabric"),
	p("UpperTorso", "BackSigil", { 0.5, 0.5, 0.04 }, { 0, 0.35, 0.52 }, "glow", "Neon", nil, { 0, 0, 45 }),
	p("UpperTorso", "BackSigilIn", { 0.34, 0.34, 0.05 }, { 0, 0.35, 0.525 }, "primary", "Fabric", nil, { 0, 0, 45 }),
}

gear.prayer_beads = join(
	ring(
		"UpperTorso",
		"Bead",
		{ 0, 0.8, 0.02 },
		{ 0.64, 0.52 },
		11,
		-150,
		150,
		{ 0.24, 0.24, 0.24 },
		0,
		{ "wood", "wood*0.8" },
		"Wood",
		"Ball"
	),
	{
		p("UpperTorso", "BeadGlow", { 0.32, 0.32, 0.32 }, { 0, 0.5, -0.58 }, "glow", "Neon", "Ball"),
		p("UpperTorso", "BeadTassel", { 0.1, 0.32, 0.06 }, { 0, 0.26, -0.56 }, "red", "Fabric"),
	}
)

gear.forehead_mark = {
	p("Head", "Mark", { 0.16, 0.16, 0.04 }, { 0, 0.33, -0.55 }, "glow", "Neon", nil, { 28, 0, 45 }),
	p("Head", "MarkDot", { 0.07, 0.07, 0.04 }, { -0.14, 0.3, -0.555 }, "glow", "Neon", nil, { 25, 14, 45 }),
	p("Head", "MarkDot", { 0.07, 0.07, 0.04 }, { 0.14, 0.3, -0.555 }, "glow", "Neon", nil, { 25, -14, 45 }),
}

gear.wrist_wraps = mirror({
	band("RightLowerArm", "WristWrap", -0.28, 0.62, 0.34, "white", "Fabric"),
	band("RightLowerArm", "WristWrap2", 0.04, 0.6, 0.1, "white*0.9", "Fabric"),
})

gear.monk_sash = join(
	{
		p("LowerTorso", "Sash", { 1.68, 0.32, 0.98 }, { 0, 0.3, 0 }, "glow*0.6", "Fabric"),
		p("LowerTorso", "SashKnot", { 0.3, 0.3, 0.3 }, { 0.55, 0.3, -0.42 }, "glow*0.55", "Fabric", "Ball"),
	},
	chain(
		"LowerTorso",
		"SashTail",
		{ 0.58, 0.18, -0.46 },
		{ 0, 0, 10 },
		2,
		0.42,
		{ 0, 0, -6 },
		{ 0.22, 0.06 },
		{ 0.18, 0.06 },
		{ "glow*0.6" },
		"Fabric"
	)
)

gear.wide_pants = mirror({
	p("RightUpperLeg", "Baggy", { 1.1, 0.94, 0.94 }, { 0, -0.05, 0 }, "secondary", "Fabric", "Cylinder", { 0, 0, 90 }),
	p("RightLowerLeg", "BaggyLow", { 0.55, 0.84, 0.84 }, { 0, 0.28, 0 }, "secondary*0.95", "Fabric", "Cylinder", {
		0,
		0,
		90,
	}),
	band("RightLowerLeg", "AnkleWrap", -0.05, 0.7, 0.3, "white*0.88", "Fabric"),
})

---------------------------------------------------------------------------------------------------------------
-- GLACIEM (frost assassin)

gear.frost_hair = join(
	{
		p("Head", "Hair", { 1.32, 1.32, 1.32 }, { 0, 0.14, 0.07 }, "hair", "Fabric", "Ball"),
		p("Head", "HairBack", { 1.15, 1.2, 0.34 }, { 0, -0.38, 0.46 }, "hair", "Fabric"),
		p("Head", "HairShard", { 0.3, 0.3, 0.26 }, { -0.36, -0.95, 0.46 }, "hair", "Fabric", nil, { 0, 0, 45 }),
		p("Head", "HairShard", { 0.36, 0.36, 0.28 }, { 0, -1.02, 0.5 }, "hair", "Fabric", nil, { 0, 0, 45 }),
		p("Head", "HairShard", { 0.3, 0.3, 0.26 }, { 0.36, -0.95, 0.46 }, "hair", "Fabric", nil, { 0, 0, 45 }),
	},
	mirror({
		p("Head", "SideLock", { 0.18, 0.72, 0.3 }, { 0.53, -0.18, -0.2 }, "hair", "Fabric", nil, { 0, 0, 6 }),
	}),
	spike("Head", "Bang", { 0.22, 0.6, -0.5 }, 0.55, 0.42, 0.18, 165, 18, "hair", "Fabric"),
	spike("Head", "Bang", { -0.2, 0.62, -0.48 }, 0.45, 0.32, 0.18, 195, 18, "hair", "Fabric")
)

gear.ice_crown = join(
	ring(
		"Head",
		"CrownShard",
		{ 0, 0.5, 0.06 },
		{ 0.55, 0.55 },
		5,
		-64,
		64,
		{ 0.14, 0.5, 0.14 },
		-18,
		{ "glow" },
		"Glass"
	),
	{
		p("Head", "CrownTip", { 0.18, 0.75, 0.18 }, { 0, 0.82, -0.44 }, "glow", "Glass", nil, { -18, 0, 0 }),
		p("Head", "CrownCore", { 0.14, 0.14, 0.05 }, { 0, 0.55, -0.58 }, "glow", "Neon", nil, { 25, 0, 45 }),
	}
)

gear.frost_coat = join(
	{
		p("UpperTorso", "CollarBack", { 1.05, 0.62, 0.12 }, { 0, 1.05, 0.32 }, "accent", "Fabric", nil, { -15, 0, 0 }),
		p("UpperTorso", "CoatTrim", { 0.14, 0.95, 0.04 }, { -0.22, 0.33, -0.52 }, "accent", "Fabric"),
		p("UpperTorso", "CoatTrim", { 0.14, 0.95, 0.04 }, { 0.22, 0.33, -0.52 }, "accent", "Fabric"),
		p("UpperTorso", "Clasp", { 0.16, 0.16, 0.06 }, { 0, 0.55, -0.54 }, "glow", "Neon", nil, { 0, 0, 45 }),
	},
	mirror({
		p("UpperTorso", "CollarSide", { 0.12, 0.58, 0.62 }, { 0.43, 1.0, 0 }, "accent", "Fabric", nil, { 0, 0, -12 }),
	}),
	ring(
		"LowerTorso",
		"CoatTail",
		{ 0, -0.6, 0.04 },
		{ 0.84, 0.56 },
		5,
		95,
		265,
		{ 0.52, 1.5, 0.07 },
		10,
		{ "primary", "primary*0.85" },
		"Fabric"
	),
	mirror({
		p("LowerTorso", "CoatFront", { 0.45, 1.3, 0.07 }, { 0.5, -0.5, -0.5 }, "primary", "Fabric", nil, { 8, 0, 0 }),
		p("LowerTorso", "CoatEdge", { 0.06, 1.3, 0.08 }, { 0.26, -0.5, -0.51 }, "accent", "Fabric", nil, { 8, 0, 0 }),
	})
)

gear.ice_shards = mirror({
	p("RightUpperArm", "Shard", { 0.3, 1.0, 0.3 }, { 0.15, 0.85, 0 }, "glow", "Glass", nil, { 0, 0, -25 }),
	p("RightUpperArm", "Shard", { 0.22, 0.7, 0.22 }, { 0.35, 0.65, 0.16 }, "glow", "Glass", nil, { 20, 0, -50 }),
	p("RightUpperArm", "Shard", { 0.2, 0.6, 0.2 }, { 0.05, 0.75, -0.2 }, "glow", "Glass", nil, { -25, 0, -10 }),
})

gear.ice_daggers = mirror({
	zcyl("RightHand", "DaggerGrip", 0.45, 0.14, { 0, -0.18, -0.05 }, "dark", "Leather"),
	p("RightHand", "DaggerGuard", { 0.4, 0.08, 0.08 }, { 0, -0.18, -0.3 }, "accent", "Metal"),
	p("RightHand", "Blade", { 0.08, 0.3, 1.4 }, { 0, -0.18, -1.0 }, "glow", "Glass"),
	p("RightHand", "DaggerEdge", { 0.04, 0.05, 1.3 }, { 0, -0.04, -1.0 }, "glow", "Neon"),
})

---------------------------------------------------------------------------------------------------------------
-- JUBEI (ronin)

gear.topknot = join(
	{
		p("Head", "Hair", { 1.3, 1.3, 1.3 }, { 0, 0.12, 0.08 }, "hair", "Fabric", "Ball"),
		p("Head", "Bun", { 0.42, 0.42, 0.42 }, { 0, 0.7, 0.22 }, "hair", "Fabric", "Ball"),
		band("Head", "BunTie", 0.56, 0.3, 0.12, "red", "Fabric"),
	},
	chain(
		"Head",
		"BunTail",
		{ 0, 0.78, 0.36 },
		{ -125, 0, 0 },
		2,
		0.3,
		{ -30, 0, 0 },
		{ 0.2, 0.12 },
		{ 0.14, 0.1 },
		{ "hair" },
		"Fabric"
	),
	mirror({
		p("Head", "Strand", { 0.12, 0.55, 0.12 }, { 0.46, -0.05, -0.42 }, "hair", "Fabric", nil, { 0, 0, -8 }),
	}),
	spike("Head", "Bang", { 0.18, 0.62, -0.5 }, 0.42, 0.3, 0.16, 160, 20, "hair", "Fabric")
)

gear.haori = join(
	{
		p("UpperTorso", "Under", { 0.5, 0.55, 0.04 }, { 0, 0.55, -0.51 }, "secondary", "Fabric"),
		p("UpperTorso", "Lapel", { 0.2, 1.02, 0.06 }, { -0.2, 0.36, -0.53 }, "accent", "Fabric", nil, { 0, 0, 24 }),
		p("UpperTorso", "Lapel", { 0.2, 1.02, 0.06 }, { 0.2, 0.36, -0.53 }, "accent", "Fabric", nil, { 0, 0, -24 }),
		zcyl("UpperTorso", "Crest", 0.04, 0.5, { 0, 0.4, 0.52 }, "accent", "Fabric"),
		zcyl("UpperTorso", "CrestIn", 0.05, 0.28, { 0, 0.4, 0.53 }, "primary", "Fabric"),
	},
	ring(
		"LowerTorso",
		"HaoriHem",
		{ 0, -0.32, 0.02 },
		{ 0.86, 0.56 },
		6,
		70,
		290,
		{ 0.55, 1.0, 0.07 },
		8,
		{ "primary", "primary*0.88" },
		"Fabric"
	),
	mirror({
		p("LowerTorso", "HaoriFlap", { 0.42, 0.95, 0.07 }, { 0.5, -0.35, -0.5 }, "primary", "Fabric", nil, { 8, 0, 0 }),
		p(
			"RightLowerArm",
			"WideSleeve",
			{ 0.5, 0.82, 0.82 },
			{ 0, 0.2, 0 },
			"primary",
			"Fabric",
			"Cylinder",
			{ 0, 0, 90 }
		),
		band("RightLowerArm", "SleeveTrim", -0.04, 0.84, 0.1, "accent", "Fabric"),
	})
)

gear.hakama = mirror({
	p(
		"RightUpperLeg",
		"Hakama",
		{ 1.15, 0.96, 0.96 },
		{ 0, -0.05, 0 },
		"secondary",
		"Fabric",
		"Cylinder",
		{ 0, 0, 90 }
	),
	p("RightLowerLeg", "HakamaLow", { 0.75, 0.9, 0.9 }, { 0, 0.22, 0 }, "secondary*0.9", "Fabric", "Cylinder", {
		0,
		0,
		90,
	}),
})

gear.katana = {
	zcyl("RightHand", "Hilt", 0.75, 0.15, { 0, -0.18, -0.05 }, "black", "Fabric"),
	zcyl("RightHand", "Guard", 0.06, 0.46, { 0, -0.18, -0.45 }, "gold", "Metal"),
	p("RightHand", "Blade", { 0.07, 0.2, 3.2 }, { 0, -0.15, -2.1 }, "steel*1.15", "Metal"),
	p("RightHand", "Edge", { 0.04, 0.05, 3.1 }, { 0, -0.05, -2.1 }, "glow", "Neon"),
}

local function sheathed(x: number, z: number, pitch: number, yaw: number, saya: string): { Piece }
	local frame = CFrame.new(x, 0.12, z) * CFrame.Angles(rad(pitch), rad(yaw), 0)
	return {
		c("LowerTorso", "Saya", { 0.18, 0.2, 2.4 }, frame, saya, "SmoothPlastic"),
		c("LowerTorso", "SayaGuard", { 0.32, 0.32, 0.06 }, frame * CFrame.new(0, 0, -1.23), "gold", "Metal"),
		c("LowerTorso", "SayaHilt", { 0.14, 0.14, 0.62 }, frame * CFrame.new(0, 0, -1.56), "black", "Fabric"),
	}
end
gear.hip_swords = join(sheathed(-0.9, 0.25, 22, 10, "black"), sheathed(-0.98, 0.35, 32, 16, "accent*0.9"))

gear.straw_hat = {
	zcyl("UpperTorso", "HatBrim", 0.08, 1.9, { 0, 0.05, 0.62 }, "rope", "Fabric"),
	zcyl("UpperTorso", "HatCone", 0.14, 1.1, { 0, 0.05, 0.7 }, "rope*0.9", "Fabric"),
	zcyl("UpperTorso", "HatTip", 0.12, 0.45, { 0, 0.05, 0.8 }, "rope*0.8", "Fabric"),
	p("UpperTorso", "HatCord", { 0.05, 1.0, 0.04 }, { 0.3, 0.55, -0.55 }, "dark", "Fabric", nil, { 0, 0, -28 }),
}

---------------------------------------------------------------------------------------------------------------
-- ZIP (jet speedster)

gear.racer_helmet = join(
	{
		p("Head", "Helmet", { 1.4, 1.4, 1.4 }, { 0, 0.15, 0.14 }, "primary", "SmoothPlastic", "Ball"),
		p("Head", "HelmetStripe", { 0.28, 0.08, 1.1 }, { 0, 0.82, 0.16 }, "secondary", "SmoothPlastic"),
		w("Head", "HelmetFin", { 0.12, 0.42, 0.75 }, { 0, 0.98, 0.42 }, "accent", "SmoothPlastic"),
		seeThrough(p("Head", "Visor", { 1.12, 0.3, 0.06 }, { 0, 0.0, -0.69 }, "glow", "Glass"), 0.45),
		p("Head", "VisorRim", { 1.16, 0.08, 0.1 }, { 0, 0.17, -0.67 }, "accent", "SmoothPlastic"),
	},
	mirror({
		p("Head", "EarPod", { 0.16, 0.46, 0.46 }, { 0.68, -0.02, 0.06 }, "secondary", "SmoothPlastic", "Cylinder"),
		p("Head", "EarLight", { 0.05, 0.2, 0.2 }, { 0.77, -0.02, 0.06 }, "glow", "Neon", "Cylinder"),
	}),
	spike("Head", "HelmetTuft", { 0.15, 0.4, -0.58 }, 0.4, 0.28, 0.14, 150, 30, "hair", "Fabric")
)

gear.racer_suit = join(
	{
		p("UpperTorso", "Chevron", { 0.08, 0.42, 0.04 }, { 0.12, 0.42, -0.53 }, "glow", "Neon", nil, { 0, 0, 38 }),
		p("UpperTorso", "Chevron", { 0.08, 0.42, 0.04 }, { -0.12, 0.42, -0.53 }, "glow", "Neon", nil, { 0, 0, -38 }),
		p("UpperTorso", "AbPanel", { 0.9, 0.55, 0.04 }, { 0, -0.42, -0.45 }, "secondary", "SmoothPlastic"),
	},
	mirror({
		p("UpperTorso", "Stripe", { 0.16, 0.95, 0.04 }, { 0.38, 0.33, -0.52 }, "accent", "SmoothPlastic"),
		p(
			"RightUpperArm",
			"AeroPlate",
			{ 0.78, 0.2, 0.86 },
			{ 0.1, 0.76, 0 },
			"secondary",
			"Metal",
			nil,
			{ 0, 0, -20 }
		),
		p("RightUpperArm", "AeroEdge", { 0.05, 0.05, 0.82 }, { 0.48, 0.63, 0 }, "glow", "Neon", nil, { 0, 0, -20 }),
		p("RightLowerLeg", "KneePad", { 0.5, 0.45, 0.16 }, { 0, 0.58, -0.3 }, "accent", "SmoothPlastic"),
	})
)

gear.backpack_thrusters = join(
	{
		p("UpperTorso", "Pack", { 1.2, 1.1, 0.45 }, { 0, 0.3, 0.7 }, "accent", "Metal"),
		w("UpperTorso", "PackFin", { 0.1, 0.45, 0.5 }, { 0, 1.05, 0.75 }, "primary", "Metal", { 0, 180, 0 }),
	},
	mirror({
		p(
			"UpperTorso",
			"Nozzle",
			{ 0.5, 0.38, 0.38 },
			{ 0.35, -0.42, 0.75 },
			"steel",
			"Metal",
			"Cylinder",
			{ 0, 0, 90 }
		),
		p("UpperTorso", "Jet", { 0.35, 0.28, 0.28 }, { 0.35, -0.8, 0.75 }, "glow", "Neon", "Cylinder", { 0, 0, 90 }),
	})
)

gear.jet_boots = mirror({
	band("RightLowerLeg", "BootCuff", 0.02, 0.76, 0.24, "primary", "SmoothPlastic"),
	zcyl("RightFoot", "HeelJet", 0.3, 0.34, { 0, 0.08, 0.56 }, "steel", "Metal"),
	p("RightFoot", "HeelFlame", { 0.26, 0.26, 0.26 }, { 0, 0.08, 0.74 }, "glow", "Neon", "Ball"),
	w("RightFoot", "BootFin", { 0.08, 0.32, 0.42 }, { 0.36, 0.16, 0.3 }, "primary", "SmoothPlastic"),
})

---------------------------------------------------------------------------------------------------------------
-- LEPORA (bunny archer)

local function bunnyEar(x: number, roll: number): { Piece }
	local base = CFrame.new(x, 0.58, 0.05) * CFrame.Angles(rad(-8), 0, rad(roll))
	local lower = base * CFrame.new(0, 0.33, 0)
	local upper = base * CFrame.new(0, 0.62, 0) * CFrame.Angles(rad(28), 0, 0) * CFrame.new(0, 0.3, 0)
	return {
		c("Head", "Ear", { 0.3, 0.7, 0.16 }, lower, "hair", "Fabric"),
		c("Head", "EarTip", { 0.28, 0.62, 0.15 }, upper, "hair", "Fabric"),
		c("Head", "EarInner", { 0.16, 0.6, 0.05 }, lower * CFrame.new(0, 0.02, -0.07), "pink", "SmoothPlastic"),
		c("Head", "EarInner", { 0.14, 0.5, 0.05 }, upper * CFrame.new(0, 0, -0.07), "pink", "SmoothPlastic"),
	}
end
gear.bunny_ears = join(bunnyEar(0.26, -10), bunnyEar(-0.26, 14))

gear.hair_bob = join(
	{
		p("Head", "Hair", { 1.32, 1.32, 1.32 }, { 0, 0.12, 0.06 }, "hair", "Fabric", "Ball"),
		p("Head", "HairBack", { 1.12, 0.62, 0.3 }, { 0, -0.25, 0.48 }, "hair", "Fabric"),
	},
	mirror({
		p("Head", "Bob", { 0.22, 0.78, 0.72 }, { 0.55, -0.22, 0.08 }, "hair", "Fabric"),
	}),
	spike("Head", "Bang", { 0.2, 0.62, -0.5 }, 0.5, 0.36, 0.16, 162, 20, "hair", "Fabric"),
	spike("Head", "Bang", { -0.2, 0.62, -0.5 }, 0.5, 0.32, 0.16, 198, 20, "hair", "Fabric")
)

gear.archer_cape = join(
	{
		p("UpperTorso", "Capelet", { 2.0, 0.3, 1.15 }, { 0, 0.76, 0.02 }, "accent", "Fabric"),
		p("UpperTorso", "Hoodie", { 0.62, 0.62, 0.62 }, { 0, 1.05, 0.45 }, "accent*0.95", "Fabric", "Ball"),
		p("UpperTorso", "CapeClasp", { 0.2, 0.2, 0.2 }, { 0, 0.78, -0.6 }, "glow", "Neon", "Ball"),
	},
	chain(
		"UpperTorso",
		"Cape",
		{ 0, 0.85, 0.56 },
		{ 8, 0, 0 },
		3,
		0.55,
		{ 4, 0, 0 },
		{ 1.5, 0.08 },
		{ 1.3, 0.08 },
		{ "accent", "accent", "accent*0.85" },
		"Fabric"
	),
	ring(
		"LowerTorso",
		"Tunic",
		{ 0, -0.22, 0 },
		{ 0.82, 0.52 },
		8,
		-157,
		157,
		{ 0.6, 0.62, 0.07 },
		15,
		{ "primary", "primary*0.9" },
		"Fabric"
	)
)

gear.bow = {
	p("LeftHand", "BowGrip", { 0.2, 0.6, 0.2 }, { -0.12, -0.2, 0.02 }, "leather", "Leather"),
	p("LeftHand", "BowUpper", { 0.16, 1.4, 0.18 }, { -0.12, 0.7, -0.18 }, "wood", "Wood", nil, { 16, 0, 0 }),
	p("LeftHand", "BowLower", { 0.16, 1.4, 0.18 }, { -0.12, -1.1, -0.18 }, "wood", "Wood", nil, { -16, 0, 0 }),
	p("LeftHand", "BowTip", { 0.16, 0.42, 0.16 }, { -0.12, 1.48, -0.24 }, "glow", "Neon", nil, { -20, 0, 0 }),
	p("LeftHand", "BowTip", { 0.16, 0.42, 0.16 }, { -0.12, -1.88, -0.24 }, "glow", "Neon", nil, { 20, 0, 0 }),
	p("LeftHand", "String", { 0.03, 3.3, 0.03 }, { -0.12, -0.2, -0.5 }, "glow", "Neon"),
}

gear.quiver = {
	p(
		"UpperTorso",
		"Quiver",
		{ 1.5, 0.42, 0.42 },
		{ 0.38, 0.25, 0.66 },
		"leather",
		"Leather",
		"Cylinder",
		{ 0, 0, 70 }
	),
	p("UpperTorso", "QuiverRim", { 0.12, 0.48, 0.48 }, { 0.62, 0.95, 0.66 }, "gold", "Metal", "Cylinder", { 0, 0, 70 }),
	p("UpperTorso", "Fletching", { 0.08, 0.4, 0.16 }, { 0.62, 1.25, 0.6 }, "glow", "Neon", nil, { 0, 0, -20 }),
	p("UpperTorso", "Fletching", { 0.08, 0.36, 0.16 }, { 0.76, 1.2, 0.72 }, "glow", "Neon", nil, { 0, 0, -28 }),
	p("UpperTorso", "Fletching", { 0.08, 0.38, 0.16 }, { 0.52, 1.18, 0.74 }, "white", "Fabric", nil, { 0, 0, -12 }),
	p("UpperTorso", "QuiverStrap", { 0.12, 1.5, 0.05 }, { 0.05, 0.35, -0.53 }, "leather", "Leather", nil, { 0, 0, 40 }),
}

gear.bunny_tail = {
	p("LowerTorso", "Tail", { 0.5, 0.5, 0.5 }, { 0, -0.05, 0.6 }, "fur", "Fabric", "Ball"),
}

gear.fur_boots = join(
	mirror({
		band("RightLowerLeg", "FurCuff", 0.0, 0.84, 0.24, "fur*0.95", "Fabric"),
	}),
	{
		band("LeftLowerArm", "Bracer", -0.1, 0.62, 0.55, "#6E5A8C", "Leather"),
	}
)

---------------------------------------------------------------------------------------------------------------
-- CARDINAL (steel knight)

gear.knight_helm = {
	band("Head", "Helm", -0.1, 1.38, 1.08, "steel*1.08", "Metal"),
	p("Head", "HelmDome", { 1.38, 1.38, 1.38 }, { 0, 0.22, 0 }, "steel*1.08", "Metal", "Ball"),
	band("Head", "HelmBrow", 0.2, 1.44, 0.14, "steel*0.8", "Metal"),
	p("Head", "Slit", { 1.0, 0.12, 0.05 }, { 0, 0.06, -0.7 }, "black", "SmoothPlastic"),
	p("Head", "SlitV", { 0.12, 0.5, 0.05 }, { 0, -0.18, -0.7 }, "black", "SmoothPlastic"),
	p("Head", "SlitGlow", { 0.8, 0.05, 0.04 }, { 0, 0.06, -0.72 }, "glow", "Neon"),
}

gear.plume = chain(
	"Head",
	"Plume",
	{ 0, 0.85, -0.15 },
	{ 160, 0, 0 },
	5,
	0.34,
	{ 22, 0, 0 },
	{ 0.24, 0.3 },
	{ 0.16, 0.22 },
	{ "accent", "accent", "accent*0.9", "accent*0.8", "accent*0.7" },
	"Fabric"
)

gear.plate_armor = join(
	{
		p("UpperTorso", "Breastplate", { 1.72, 0.92, 0.14 }, { 0, 0.36, -0.5 }, "steel*1.12", "Metal"),
		p("UpperTorso", "Lame", { 1.45, 0.22, 0.92 }, { 0, -0.3, 0.02 }, "steel*0.9", "Metal"),
		p("UpperTorso", "Lame", { 1.42, 0.22, 0.92 }, { 0, -0.58, 0.02 }, "steel*0.85", "Metal"),
		band("UpperTorso", "Gorget", 0.88, 0.98, 0.36, "steel*0.85", "Metal"),
	},
	ring(
		"LowerTorso",
		"Fauld",
		{ 0, -0.08, 0 },
		{ 0.84, 0.52 },
		5,
		-90,
		90,
		{ 0.52, 0.45, 0.08 },
		15,
		{ "steel*1.05", "steel*0.95" },
		"Metal"
	),
	mirror({
		p("RightUpperLeg", "Cuisse", { 0.6, 0.8, 0.14 }, { 0, 0.05, -0.37 }, "steel*1.05", "Metal"),
		p("RightLowerLeg", "Greave", { 0.56, 0.82, 0.14 }, { 0, 0.05, -0.33 }, "steel*1.05", "Metal"),
		p("RightLowerLeg", "KneeCop", { 0.55, 0.55, 0.55 }, { 0, 0.58, -0.17 }, "steel*1.15", "Metal", "Ball"),
	})
)

gear.tabard = {
	p("UpperTorso", "TabardTop", { 0.92, 0.88, 0.04 }, { 0, 0.33, -0.58 }, "accent", "Fabric"),
	p("LowerTorso", "Tabard", { 0.78, 1.35, 0.06 }, { 0, -0.48, -0.53 }, "accent", "Fabric"),
	p("LowerTorso", "TabardHem", { 0.82, 0.08, 0.07 }, { 0, -1.14, -0.53 }, "gold", "Fabric"),
	p("UpperTorso", "Flake", { 0.07, 0.5, 0.03 }, { 0, 0.36, -0.61 }, "glow", "Neon"),
	p("UpperTorso", "Flake", { 0.07, 0.5, 0.03 }, { 0, 0.36, -0.61 }, "glow", "Neon", nil, { 0, 0, 60 }),
	p("UpperTorso", "Flake", { 0.07, 0.5, 0.03 }, { 0, 0.36, -0.61 }, "glow", "Neon", nil, { 0, 0, -60 }),
}

gear.pauldrons = mirror({
	p("RightUpperArm", "Pauldron", { 1.12, 1.12, 1.12 }, { 0.12, 0.5, 0 }, "steel*1.1", "Metal", "Ball"),
	p("RightUpperArm", "Pauldron2", { 0.9, 0.2, 1.02 }, { 0.3, 0.12, 0 }, "steel*0.95", "Metal", nil, { 0, 0, -22 }),
	p(
		"RightUpperArm",
		"PauldronTrim",
		{ 0.12, 1.16, 1.16 },
		{ 0.12, 0.52, 0 },
		"accent",
		"Metal",
		"Cylinder",
		{ 0, 0, -20 }
	),
})

gear.kite_shield = join({
	p("LeftLowerArm", "Shield", { 0.18, 2.0, 1.6 }, { -0.55, 0.1, 0 }, "steel*1.1", "Metal"),
	p("LeftLowerArm", "ShieldRim", { 0.2, 0.14, 1.66 }, { -0.55, 1.12, 0 }, "accent", "Metal"),
	p("LeftLowerArm", "ShieldBand", { 0.04, 2.0, 0.3 }, { -0.66, 0.1, 0 }, "accent", "Metal"),
	p("LeftLowerArm", "ShieldBar", { 0.04, 0.3, 1.6 }, { -0.66, 0.45, 0 }, "accent", "Metal"),
	p("LeftLowerArm", "Emblem", { 0.06, 0.5, 0.5 }, { -0.69, 0.45, 0 }, "glow", "Neon", nil, { 45, 0, 0 }),
}, {
	c(
		"LeftLowerArm",
		"ShieldPoint",
		{ 0.18, 0.9, 0.8 },
		CFrame.new(-0.55, -1.35, 0.4) * CFrame.Angles(math.pi, 0, 0),
		"steel*1.1",
		"Metal",
		"Wedge"
	),
	c(
		"LeftLowerArm",
		"ShieldPoint",
		{ 0.18, 0.9, 0.8 },
		CFrame.new(-0.55, -1.35, -0.4) * CFrame.Angles(0, 0, math.pi),
		"steel*1.1",
		"Metal",
		"Wedge"
	),
})

gear.knight_sword = {
	zcyl("RightHand", "Grip", 0.55, 0.16, { 0, -0.18, -0.05 }, "leather", "Leather"),
	p("RightHand", "Pommel", { 0.24, 0.24, 0.24 }, { 0, -0.18, 0.28 }, "gold", "Metal", "Ball"),
	p("RightHand", "CrossGuard", { 0.95, 0.12, 0.16 }, { 0, -0.18, -0.4 }, "gold", "Metal"),
	p("RightHand", "Blade", { 0.08, 0.3, 2.9 }, { 0, -0.18, -1.9 }, "steel*1.2", "Metal"),
	p("RightHand", "Fuller", { 0.1, 0.06, 2.6 }, { 0, -0.18, -1.85 }, "glow", "Neon"),
}

---------------------------------------------------------------------------------------------------------------
-- GRIMBOLT (tinkerer)

gear.wild_hair = join(
	{
		p("Head", "Tuft", { 0.6, 0.6, 0.6 }, { -0.35, 0.55, 0.1 }, "hair", "Fabric", "Ball"),
		p("Head", "Tuft", { 0.66, 0.66, 0.66 }, { 0.3, 0.6, 0.02 }, "hair", "Fabric", "Ball"),
		p("Head", "Tuft", { 0.6, 0.6, 0.6 }, { 0, 0.68, 0.3 }, "hair", "Fabric", "Ball"),
		p("Head", "Tuft", { 0.55, 0.55, 0.55 }, { -0.25, 0.4, 0.45 }, "hair*0.9", "Fabric", "Ball"),
		p("Head", "Tuft", { 0.55, 0.55, 0.55 }, { 0.35, 0.35, 0.4 }, "hair*0.9", "Fabric", "Ball"),
	},
	spike("Head", "HairSpike", { 0.1, 0.8, 0.1 }, 0.4, 0.45, 0.2, -25, 0, "hair", "Fabric"),
	spike("Head", "HairSpike", { -0.3, 0.75, 0.2 }, 0.35, 0.4, 0.2, 30, -10, "hair", "Fabric")
)

gear.beard = join(
	{
		p("Head", "Beard", { 0.92, 0.92, 0.92 }, { 0, -0.66, -0.26 }, "hair", "Fabric", "Ball"),
		p("Head", "BeardTip", { 0.5, 0.5, 0.5 }, { 0, -1.05, -0.32 }, "hair*0.9", "Fabric", "Ball"),
		band("Head", "BeardRing", -0.92, 0.32, 0.08, "brass", "Metal"),
		p("Head", "Mustache", { 0.36, 0.13, 0.12 }, { -0.16, -0.27, -0.62 }, "hair*0.9", "Fabric", nil, { 0, 0, 15 }),
		p("Head", "Mustache", { 0.36, 0.13, 0.12 }, { 0.16, -0.27, -0.62 }, "hair*0.9", "Fabric", nil, { 0, 0, -15 }),
	},
	mirror({
		p("Head", "Sideburn", { 0.2, 0.55, 0.36 }, { 0.53, -0.3, -0.12 }, "hair", "Fabric"),
	})
)

gear.goggles = join(
	{
		band("Head", "GoggleStrap", 0.32, 1.33, 0.16, "leather", "Leather"),
	},
	mirror({
		zcyl("Head", "GoggleRim", 0.16, 0.38, { 0.24, 0.36, -0.6 }, "brass", "Metal"),
		zcyl("Head", "GoggleLens", 0.05, 0.28, { 0.24, 0.36, -0.69 }, "glow", "Glass"),
	})
)

gear.apron = {
	p("UpperTorso", "Bib", { 1.1, 0.9, 0.06 }, { 0, 0.32, -0.53 }, "leather*1.2", "Leather"),
	p("LowerTorso", "ApronLow", { 1.35, 1.25, 0.06 }, { 0, -0.5, -0.54 }, "leather*1.2", "Leather"),
	p("LowerTorso", "Pocket", { 0.6, 0.32, 0.04 }, { 0, -0.4, -0.58 }, "leather*0.9", "Leather"),
	p(
		"LowerTorso",
		"Screwdriver",
		{ 0.06, 0.4, 0.06 },
		{ 0.15, -0.2, -0.6 },
		"red",
		"SmoothPlastic",
		nil,
		{ 0, 0, -10 }
	),
	p("UpperTorso", "ApronStrap", { 0.12, 0.7, 0.05 }, { -0.45, 0.72, -0.5 }, "leather", "Leather"),
	p("UpperTorso", "ApronStrap", { 0.12, 0.7, 0.05 }, { 0.45, 0.72, -0.5 }, "leather", "Leather"),
}

gear.bomb_belt = {
	p("LowerTorso", "Bomb", { 0.42, 0.42, 0.42 }, { -0.78, 0.1, -0.35 }, "black", "SmoothPlastic", "Ball"),
	p("LowerTorso", "Bomb", { 0.42, 0.42, 0.42 }, { 0.78, 0.1, -0.35 }, "black", "SmoothPlastic", "Ball"),
	p("LowerTorso", "Bomb", { 0.42, 0.42, 0.42 }, { 0.88, 0.1, 0.2 }, "black", "SmoothPlastic", "Ball"),
	p("LowerTorso", "Fuse", { 0.08, 0.2, 0.08 }, { -0.78, 0.38, -0.35 }, "glow", "Neon"),
	p("LowerTorso", "Fuse", { 0.08, 0.2, 0.08 }, { 0.78, 0.38, -0.35 }, "glow", "Neon"),
	p("LowerTorso", "Fuse", { 0.08, 0.2, 0.08 }, { 0.88, 0.38, 0.2 }, "glow", "Neon"),
}

gear.tinker_pack = {
	p("UpperTorso", "Pack", { 1.4, 1.3, 0.6 }, { 0, 0.2, 0.8 }, "steel*0.9", "Metal"),
	p("UpperTorso", "Chimney", { 0.75, 0.3, 0.3 }, { -0.4, 1.05, 0.85 }, "dark", "Metal", "Cylinder", { 0, 0, 90 }),
	p("UpperTorso", "Ember", { 0.08, 0.32, 0.32 }, { -0.4, 1.44, 0.85 }, "glow", "Neon", "Cylinder", { 0, 0, 90 }),
	p("UpperTorso", "Cog", { 0.15, 0.75, 0.75 }, { 0.75, 0.35, 0.85 }, "gold", "Metal", "Cylinder"),
	p("UpperTorso", "Tank", { 0.9, 0.42, 0.42 }, { 0.42, 0.3, 1.18 }, "brass", "Metal", "Cylinder", { 0, 0, 90 }),
	p("UpperTorso", "Pipe", { 0.1, 0.1, 0.7 }, { 0.6, 0.85, 0.45 }, "brass", "Metal", nil, { 30, 0, 0 }),
}

gear.wrench = {
	zcyl("RightHand", "WrenchHandle", 1.5, 0.15, { 0, -0.18, -0.55 }, "iron", "Metal"),
	p("RightHand", "WrenchHead", { 0.14, 0.5, 0.36 }, { 0, -0.18, -1.38 }, "iron", "Metal"),
	p("RightHand", "WrenchJaw", { 0.14, 0.16, 0.3 }, { 0, 0.02, -1.62 }, "iron", "Metal"),
}

---------------------------------------------------------------------------------------------------------------
-- TEMPLAR (dragon knight)

gear.dragon_helm = join(
	{
		band("Head", "Helm", -0.1, 1.38, 1.08, "primary", "Metal"),
		p("Head", "HelmDome", { 1.38, 1.38, 1.38 }, { 0, 0.22, 0 }, "primary", "Metal", "Ball"),
		w("Head", "Snout", { 0.72, 0.36, 0.46 }, { 0, -0.32, -0.86 }, "primary*0.92", "Metal"),
		p("Head", "Mandible", { 0.8, 0.14, 0.42 }, { 0, -0.56, -0.74 }, "accent", "Metal"),
	},
	mirror({
		p("Head", "EyeGlow", { 0.3, 0.07, 0.04 }, { 0.22, 0.06, -0.7 }, "glow", "Neon", nil, { 0, 0, 12 }),
		p("Head", "BrowPlate", { 0.46, 0.12, 0.12 }, { 0.24, 0.19, -0.68 }, "accent", "Metal", nil, { 0, 0, 16 }),
	}),
	mirror(
		chain(
			"Head",
			"Horn",
			{ 0.42, 0.45, 0.05 },
			{ 120, 0, -35 },
			4,
			0.4,
			{ 22, 0, 8 },
			{ 0.3, 0.3 },
			{ 0.1, 0.1 },
			{ "trim*0.9", "trim*0.8", "trim*0.7", "bone" },
			"Metal"
		)
	),
	{
		w("Head", "Fin", { 0.08, 0.32, 0.36 }, { 0, 0.86, -0.15 }, "accent", "Metal"),
		w("Head", "Fin", { 0.08, 0.3, 0.36 }, { 0, 0.82, 0.2 }, "accent", "Metal"),
		w("Head", "Fin", { 0.08, 0.26, 0.32 }, { 0, 0.66, 0.52 }, "accent", "Metal", { -40, 0, 0 }),
	}
)

gear.dragon_armor = join(
	{
		p("UpperTorso", "Breastplate", { 1.76, 0.92, 0.14 }, { 0, 0.36, -0.5 }, "primary*1.05", "Metal"),
		p("UpperTorso", "Scale", { 0.3, 0.3, 0.06 }, { 0, 0.62, -0.59 }, "accent", "Metal", nil, { 0, 0, 45 }),
		p("UpperTorso", "Scale", { 0.26, 0.26, 0.06 }, { 0, 0.32, -0.59 }, "accent", "Metal", nil, { 0, 0, 45 }),
		p("UpperTorso", "Scale", { 0.22, 0.22, 0.06 }, { 0, 0.06, -0.59 }, "glow", "Neon", nil, { 0, 0, 45 }),
		p("UpperTorso", "Lame", { 1.45, 0.22, 0.92 }, { 0, -0.3, 0.02 }, "primary*0.85", "Metal"),
		p("UpperTorso", "Lame", { 1.42, 0.22, 0.92 }, { 0, -0.58, 0.02 }, "primary*0.8", "Metal"),
		band("UpperTorso", "Gorget", 0.88, 1.0, 0.36, "trim", "Metal"),
		p("LowerTorso", "Tabard", { 0.8, 1.35, 0.06 }, { 0, -0.48, -0.53 }, "accent", "Fabric"),
		p("LowerTorso", "TabardHem", { 0.84, 0.08, 0.07 }, { 0, -1.14, -0.53 }, "trim", "Fabric"),
		p("LowerTorso", "TabardFlame", { 0.22, 0.22, 0.03 }, { 0, -0.5, -0.57 }, "glow", "Neon", nil, { 0, 0, 45 }),
	},
	mirror({
		p("RightLowerLeg", "Greave", { 0.56, 0.82, 0.14 }, { 0, 0.05, -0.33 }, "primary*1.05", "Metal"),
		p("RightLowerLeg", "KneeCop", { 0.55, 0.55, 0.55 }, { 0, 0.58, -0.17 }, "trim", "Metal", "Ball"),
		p("RightUpperLeg", "Cuisse", { 0.6, 0.8, 0.14 }, { 0, 0.05, -0.37 }, "primary", "Metal"),
	})
)

gear.dragon_pauldrons = mirror(join({
	p("RightUpperArm", "Pauldron", { 1.16, 1.16, 1.16 }, { 0.12, 0.5, 0 }, "primary*1.05", "Metal", "Ball"),
	p("RightUpperArm", "Pauldron2", { 0.95, 0.22, 1.06 }, { 0.3, 0.12, 0 }, "accent", "Metal", nil, { 0, 0, -22 }),
}, spike("RightUpperArm", "PauldronSpike", { 0.3, 0.95, 0 }, 0.4, 0.6, 0.14, -35, 0, "trim", "Metal")))

gear.dragon_wings = mirror(
	join(
		fan(
			"UpperTorso",
			"WingSkin",
			{ 0.3, 0.55, 0.62 },
			{ 30, 0, 0 },
			{ 35, 120 },
			{ 2.3, 2.6, 2.0 },
			0.95,
			0.05,
			{ "accent*0.75", "accent*0.65", "accent*0.55" },
			"Fabric"
		),
		fan(
			"UpperTorso",
			"WingBone",
			{ 0.3, 0.55, 0.66 },
			{ 30, 0, 0 },
			{ 22, 108 },
			{ 2.45, 2.75, 2.15 },
			0.11,
			0.12,
			{ "iron" },
			"Metal"
		)
	)
)

gear.dragon_tail = join(
	chain(
		"LowerTorso",
		"Tail",
		{ 0, -0.1, 0.42 },
		{ -40, 0, 0 },
		6,
		0.52,
		{ -11, 0, 0 },
		{ 0.52, 0.52 },
		{ 0.2, 0.2 },
		{ "primary", "accent", "primary", "accent", "primary", "accent" },
		"Metal"
	),
	{
		c(
			"LowerTorso",
			"TailSpike",
			{ 0.08, 0.4, 0.5 },
			CFrame.new(0, -1.55, 3.05) * CFrame.Angles(rad(-60), 0, 0),
			"trim",
			"Metal",
			"Wedge"
		),
	}
)

gear.flame_sword = {
	zcyl("RightHand", "Hilt", 0.6, 0.18, { 0, -0.2, -0.1 }, "dark", "Leather"),
	p("RightHand", "Guard", { 1.0, 0.14, 0.18 }, { 0, -0.2, -0.45 }, "gold", "Metal"),
	p("RightHand", "GuardGem", { 0.18, 0.18, 0.18 }, { 0, -0.2, -0.48 }, "glow", "Neon", "Ball"),
	p("RightHand", "Blade", { 0.12, 0.38, 3.4 }, { 0, -0.2, -2.25 }, "steel*1.1", "Metal"),
	p("RightHand", "Flame", { 0.06, 0.16, 3.3 }, { 0, 0.0, -2.25 }, "glow", "Neon"),
}

---------------------------------------------------------------------------------------------------------------
-- SCARLET (phoenix)

gear.flame_crest = join(
	{
		p("Head", "Hair", { 1.3, 1.3, 1.3 }, { 0, 0.14, 0.07 }, "hair", "Fabric", "Ball"),
		p("Head", "HairBack", { 1.05, 1.0, 0.3 }, { 0, -0.3, 0.46 }, "hair", "Fabric"),
		band("Head", "Circlet", 0.3, 1.34, 0.08, "gold", "Metal"),
		p("Head", "CircletGem", { 0.14, 0.14, 0.05 }, { 0, 0.32, -0.66 }, "glow", "Neon", nil, { 0, 0, 45 }),
	},
	fan(
		"Head",
		"Crest",
		{ 0, 0.5, 0.25 },
		{ 0, 90, 0 },
		{ -10, -120 },
		{ 0.75, 0.95, 1.05, 0.95, 0.75 },
		0.14,
		0.4,
		{ "hair", "hair", "hair*1.1", "hair", "hair" },
		"Fabric"
	),
	fan(
		"Head",
		"CrestFlame",
		{ 0, 0.55, 0.3 },
		{ 0, 90, 0 },
		{ -20, -110 },
		{ 0.6, 0.75, 0.6 },
		0.16,
		0.22,
		{ "accent", "glow", "accent" },
		"Neon"
	),
	spike("Head", "Bang", { 0.18, 0.62, -0.5 }, 0.5, 0.34, 0.16, 160, 20, "hair", "Fabric")
)

gear.phoenix_wings = mirror(
	join(
		fan(
			"UpperTorso",
			"FlameFeather",
			{ 0.3, 0.5, 0.62 },
			{ 30, 0, 0 },
			{ 35, 140 },
			{ 1.8, 2.3, 2.5, 2.2, 1.7 },
			0.44,
			0.07,
			{ "#FFE07A", "#FFB23D", "#FF7A2A", "#F04A1E", "#C8231E" },
			"Neon"
		),
		fan(
			"UpperTorso",
			"WingCovert",
			{ 0.3, 0.5, 0.68 },
			{ 30, 0, 0 },
			{ 45, 125 },
			{ 1.1, 1.25, 1.1 },
			0.48,
			0.08,
			{ "primary", "primary*0.9", "primary*0.8" },
			"Fabric"
		)
	)
)

gear.phoenix_garb = join(
	{
		band("UpperTorso", "Collar", 0.84, 0.95, 0.12, "gold", "Metal"),
		p("UpperTorso", "ChestGem", { 0.24, 0.24, 0.24 }, { 0, 0.55, -0.55 }, "glow", "Neon", "Ball"),
		p("UpperTorso", "ChestPlate", { 0.9, 0.5, 0.06 }, { 0, 0.45, -0.52 }, "gold*0.9", "Metal"),
	},
	mirror({
		band("RightUpperArm", "Armlet", -0.1, 0.7, 0.16, "gold", "Metal"),
		w("RightUpperArm", "ShoulderFeather", { 0.7, 0.3, 0.5 }, { 0.15, 0.78, 0 }, "accent", "Fabric", { 0, 90, -20 }),
	}),
	ring(
		"LowerTorso",
		"SkirtFeather",
		{ 0, -0.28, 0 },
		{ 0.82, 0.52 },
		7,
		-135,
		135,
		{ 0.4, 0.85, 0.06 },
		18,
		{ "primary", "accent", "primary" },
		"Fabric"
	)
)

gear.tail_feathers = join(
	fan(
		"LowerTorso",
		"TailFeather",
		{ 0, 0.05, 0.52 },
		{ 150, 0, 0 },
		{ -28, 28 },
		{ 1.4, 1.75, 1.4 },
		0.3,
		0.06,
		{ "glow", "accent", "glow" },
		"Neon"
	),
	fan(
		"LowerTorso",
		"TailFeather",
		{ 0, 0.05, 0.48 },
		{ 155, 0, 0 },
		{ -16, 16 },
		{ 1.0, 1.0 },
		0.34,
		0.06,
		{ "primary" },
		"Fabric"
	)
)

gear.glaive = {
	zcyl("RightHand", "Shaft", 4.4, 0.15, { 0, -0.18, -1.1 }, "secondary", "Wood"),
	zcyl("RightHand", "ShaftRing", 0.2, 0.22, { 0, -0.18, -3.25 }, "gold", "Metal"),
	zcyl("RightHand", "ShaftCap", 0.2, 0.22, { 0, -0.18, 1.1 }, "gold", "Metal"),
	p("RightHand", "Blade", { 0.08, 0.5, 1.3 }, { 0, -0.04, -3.9 }, "steel*1.15", "Metal", nil, { -10, 0, 0 }),
	p("RightHand", "Edge", { 0.04, 0.1, 1.2 }, { 0, 0.2, -3.9 }, "glow", "Neon", nil, { -10, 0, 0 }),
}

---------------------------------------------------------------------------------------------------------------
-- CELESTIAL FOX

gear.fox_ears = join(
	spike("Head", "FoxEar", { 0.32, 0.55, 0.05 }, 0.42, 0.55, 0.14, -18, 0, "hair", "Fabric"),
	spike("Head", "FoxEar", { -0.32, 0.55, 0.05 }, 0.42, 0.55, 0.14, 18, 0, "hair", "Fabric"),
	spike("Head", "FoxEarInner", { 0.32, 0.58, -0.02 }, 0.24, 0.36, 0.04, -18, 0, "pink", "SmoothPlastic"),
	spike("Head", "FoxEarInner", { -0.32, 0.58, -0.02 }, 0.24, 0.36, 0.04, 18, 0, "pink", "SmoothPlastic")
)

gear.fox_hair = join(
	{
		p("Head", "Hair", { 1.32, 1.32, 1.32 }, { 0, 0.13, 0.07 }, "hair", "Fabric", "Ball"),
		p("Head", "HairBack", { 1.12, 1.45, 0.34 }, { 0, -0.45, 0.46 }, "hair", "Fabric"),
	},
	mirror({
		p("Head", "Lock", { 0.2, 0.9, 0.24 }, { 0.5, -0.38, -0.22 }, "hair", "Fabric", nil, { 0, 0, 4 }),
		band("Head", "LockTie", -0.72, 0.3, 0.1, "trim", "Neon"),
	}),
	spike("Head", "Bang", { 0.2, 0.62, -0.5 }, 0.5, 0.36, 0.16, 162, 20, "hair", "Fabric"),
	spike("Head", "Bang", { -0.2, 0.62, -0.5 }, 0.5, 0.32, 0.16, 198, 20, "hair", "Fabric")
)
-- Lock ties sit on the locks, not around the head.
for _, d in gear.fox_hair do
	if d.name == "LockTie" then
		d.offset = { if d.offset[1] < 0 then -0.5 else 0.5, -0.72, -0.22 }
		d.size = { 0.1, 0.3, 0.3 }
	end
end

gear.fox_robe = join(
	{
		p("UpperTorso", "Lapel", { 0.2, 1.02, 0.06 }, { -0.2, 0.36, -0.53 }, "accent", "Fabric", nil, { 0, 0, 24 }),
		p("UpperTorso", "Lapel", { 0.2, 1.02, 0.06 }, { 0.2, 0.36, -0.53 }, "accent", "Fabric", nil, { 0, 0, -24 }),
		p("LowerTorso", "Obi", { 1.6, 0.42, 0.98 }, { 0, 0.36, 0 }, "accent", "Fabric"),
		p("LowerTorso", "ObiBow", { 0.5, 0.5, 0.5 }, { -0.28, 0.4, 0.52 }, "trim", "Fabric", "Ball"),
		p("LowerTorso", "ObiBow", { 0.5, 0.5, 0.5 }, { 0.28, 0.4, 0.52 }, "trim", "Fabric", "Ball"),
	},
	mirror({
		p(
			"RightLowerArm",
			"WideSleeve",
			{ 0.6, 0.86, 0.86 },
			{ 0, 0.15, 0 },
			"primary",
			"Fabric",
			"Cylinder",
			{ 0, 0, 90 }
		),
		band("RightLowerArm", "SleeveTrim", -0.16, 0.88, 0.08, "trim", "Fabric"),
		p(
			"RightUpperLeg",
			"Hakama",
			{ 1.15, 0.96, 0.96 },
			{ 0, -0.05, 0 },
			"secondary",
			"Fabric",
			"Cylinder",
			{ 0, 0, 90 }
		),
	})
)

local function foxTail(roll: number, x: number): { Piece }
	local pieces = chain(
		"LowerTorso",
		"FoxTail",
		{ x, -0.05, 0.5 },
		{ -118, 0, roll },
		3,
		0.42,
		{ 18, 0, 0 },
		{ 0.5, 0.5 },
		{ 0.42, 0.42 },
		{ "hair", "hair", "trim" },
		"Fabric",
		"Ball"
	)
	pieces[3].material = "Neon"
	return pieces
end
gear.fox_tails = join(foxTail(-50, -0.2), foxTail(-25, -0.1), foxTail(0, 0), foxTail(25, 0.1), foxTail(50, 0.2))

local function star(limb: string, at: { number }, size: number): { Piece }
	return {
		p(limb, "Star", { size, size, 0.04 }, at, "trim", "Neon", nil, { 0, 0, 45 }),
		p(limb, "Star", { size * 0.45, size * 1.6, 0.03 }, at, "white", "Neon"),
	}
end
gear.star_charms = join(star("LowerTorso", { 0, 0.36, -0.53 }, 0.24), star("Head", { -0.4, 0.4, -0.46 }, 0.18))

gear.foxfire = {
	p("RightHand", "Foxfire", { 0.36, 0.36, 0.36 }, { 0.15, -0.75, -0.35 }, "trim", "Neon", "Ball"),
	seeThrough(
		p("RightHand", "FoxfireHalo", { 0.6, 0.6, 0.6 }, { 0.15, -0.75, -0.35 }, "trim", "ForceField", "Ball"),
		0.3
	),
	p("LeftHand", "Foxfire", { 0.3, 0.3, 0.3 }, { -0.15, -0.7, -0.3 }, "trim", "Neon", "Ball"),
}

---------------------------------------------------------------------------------------------------------------
-- CYBORG MECH

gear.mech_head = join(
	{
		p("Head", "HeadBox", { 1.28, 1.12, 1.26 }, { 0, -0.05, 0 }, "primary", "Metal"),
		p("Head", "VisorFrame", { 1.12, 0.38, 0.08 }, { 0, 0.06, -0.64 }, "black", "Metal"),
		p("Head", "Visor", { 1.0, 0.18, 0.05 }, { 0, 0.06, -0.69 }, "glow", "Neon"),
		p("Head", "Grill", { 0.7, 0.3, 0.06 }, { 0, -0.38, -0.64 }, "iron", "Metal"),
		p("Head", "HeadCrest", { 0.3, 0.16, 1.1 }, { 0, 0.55, 0 }, "accent", "Metal"),
		p("Head", "Antenna", { 0.06, 0.8, 0.06 }, { 0.45, 0.85, 0.1 }, "steel", "Metal"),
		p("Head", "AntennaTip", { 0.14, 0.14, 0.14 }, { 0.45, 1.27, 0.1 }, "glow", "Neon", "Ball"),
	},
	mirror({
		p("Head", "EarCan", { 0.2, 0.6, 0.6 }, { 0.7, -0.02, 0 }, "steel", "Metal", "Cylinder"),
	})
)

gear.mech_armor = join(
	{
		p("UpperTorso", "ChestPlate", { 1.86, 0.86, 0.16 }, { 0, 0.4, -0.5 }, "primary*1.1", "Metal"),
		p("UpperTorso", "Lame", { 1.45, 0.22, 0.92 }, { 0, -0.3, 0.02 }, "primary*0.8", "Metal"),
		p("UpperTorso", "Lame", { 1.42, 0.22, 0.92 }, { 0, -0.58, 0.02 }, "accent", "Metal"),
		p("UpperTorso", "BackPack", { 1.4, 1.2, 0.5 }, { 0, 0.3, 0.7 }, "primary*0.8", "Metal"),
	},
	mirror({
		p("UpperTorso", "Exhaust", { 0.5, 0.3, 0.3 }, { 0.4, 1.05, 0.8 }, "iron", "Metal", "Cylinder", { 0, 0, 90 }),
		p(
			"UpperTorso",
			"ExhaustGlow",
			{ 0.06, 0.22, 0.22 },
			{ 0.4, 1.31, 0.8 },
			"glow",
			"Neon",
			"Cylinder",
			{ 0, 0, 90 }
		),
		p("RightUpperArm", "ShoulderBlock", { 0.92, 0.6, 0.95 }, { 0.1, 0.68, 0 }, "accent", "Metal"),
		p("RightUpperArm", "HazardStripe", { 0.94, 0.1, 0.97 }, { 0.1, 0.6, 0 }, "black", "Metal"),
	}),
	ring(
		"LowerTorso",
		"HipPlate",
		{ 0, -0.12, 0 },
		{ 0.86, 0.54 },
		4,
		-80,
		80,
		{ 0.58, 0.5, 0.1 },
		12,
		{ "primary*1.1" },
		"Metal"
	)
)

gear.missile_pods = mirror({
	p("UpperTorso", "Pod", { 0.8, 0.7, 1.15 }, { 0.62, 1.22, 0.2 }, "steel", "Metal"),
	p("UpperTorso", "PodFace", { 0.66, 0.54, 0.06 }, { 0.62, 1.22, -0.39 }, "black", "Metal"),
	p("UpperTorso", "Missile", { 0.18, 0.18, 0.18 }, { 0.5, 1.33, -0.42 }, "glow", "Neon", "Ball"),
	p("UpperTorso", "Missile", { 0.18, 0.18, 0.18 }, { 0.74, 1.1, -0.42 }, "glow", "Neon", "Ball"),
})

gear.mech_limbs = mirror({
	p("RightUpperArm", "Piston", { 0.8, 0.16, 0.16 }, { 0, -0.05, 0.36 }, "steel", "Metal", "Cylinder", { 0, 0, 90 }),
	p("RightLowerArm", "ForearmArmor", { 0.74, 0.82, 0.74 }, { 0, -0.02, 0 }, "primary*1.1", "Metal"),
	p("RightLowerArm", "ForearmStripe", { 0.76, 0.1, 0.76 }, { 0, 0.2, 0 }, "accent", "Metal"),
	p("RightHand", "Fist", { 0.6, 0.6, 0.66 }, { 0, -0.03, 0 }, "iron", "Metal"),
	p("RightUpperLeg", "ThighArmor", { 0.86, 0.8, 0.86 }, { 0, 0.02, 0 }, "primary*1.05", "Metal"),
	p("RightLowerLeg", "ShinArmor", { 0.78, 0.9, 0.82 }, { 0, 0.02, -0.02 }, "primary*1.1", "Metal"),
	p("RightLowerLeg", "KneeCap", { 0.5, 0.4, 0.2 }, { 0, 0.56, -0.34 }, "accent", "Metal"),
})

gear.chest_core = {
	zcyl("UpperTorso", "CoreRing", 0.1, 0.72, { 0, 0.38, -0.6 }, "iron", "Metal"),
	p("UpperTorso", "Core", { 0.48, 0.48, 0.48 }, { 0, 0.38, -0.58 }, "glow", "Neon", "Ball"),
}

---------------------------------------------------------------------------------------------------------------
-- NEKRA (necromancer)

gear.hood = join(
	{
		p("Head", "Hood", { 1.44, 1.44, 1.44 }, { 0, 0.12, 0.16 }, "primary", "Fabric", "Ball"),
		w("Head", "HoodPeak", { 0.5, 0.45, 0.5 }, { 0, 0.85, 0.3 }, "primary", "Fabric", { -20, 0, 0 }),
		p("Head", "Fringe", { 0.9, 0.22, 0.2 }, { 0, 0.4, -0.5 }, "hair", "Fabric", nil, { 20, 0, 0 }),
	},
	mirror({
		p("Head", "HoodRim", { 0.1, 0.9, 0.14 }, { 0.6, -0.12, -0.4 }, "glow*0.5", "Fabric", nil, { 0, 25, 0 }),
	}),
	chain(
		"Head",
		"HoodDrape",
		{ 0, 0.1, 0.7 },
		{ 10, 0, 0 },
		2,
		0.55,
		{ 0, 0, 0 },
		{ 0.85, 0.12 },
		{ 1.0, 0.12 },
		{ "primary", "primary*0.85" },
		"Fabric"
	)
)

gear.robe = join(
	ring(
		"LowerTorso",
		"Robe",
		{ 0, -0.95, 0 },
		{ 0.86, 0.58 },
		10,
		-162,
		162,
		{ 0.58, 2.0, 0.08 },
		9,
		{ "primary", "primary*0.82" },
		"Fabric"
	),
	{
		p("LowerTorso", "RobeSash", { 0.34, 1.7, 0.06 }, { 0, -0.85, -0.7 }, "accent", "Fabric", nil, { 9, 0, 0 }),
		p("LowerTorso", "Rune", { 0.16, 0.16, 0.03 }, { 0, -0.6, -0.75 }, "glow", "Neon", nil, { 9, 0, 45 }),
		p("LowerTorso", "Rune", { 0.12, 0.12, 0.03 }, { 0, -1.05, -0.8 }, "glow", "Neon", nil, { 9, 0, 45 }),
	}
)

gear.bone_armor = join(
	ring(
		"UpperTorso",
		"BoneSpike",
		{ 0, 0.85, 0.02 },
		{ 0.6, 0.5 },
		7,
		-120,
		120,
		{ 0.12, 0.5, 0.12 },
		-28,
		{ "bone" },
		"SmoothPlastic"
	),
	{
		p("UpperTorso", "Rib", { 0.9, 0.08, 0.06 }, { 0, 0.55, -0.54 }, "bone", "SmoothPlastic"),
		p("UpperTorso", "Rib", { 0.8, 0.08, 0.06 }, { 0, 0.35, -0.54 }, "bone", "SmoothPlastic"),
		p("UpperTorso", "Rib", { 0.66, 0.08, 0.06 }, { 0, 0.15, -0.54 }, "bone", "SmoothPlastic"),
		p("UpperTorso", "Sternum", { 0.1, 0.6, 0.07 }, { 0, 0.35, -0.55 }, "bone", "SmoothPlastic"),
		p("RightUpperArm", "SkullPauldron", { 0.66, 0.66, 0.66 }, { 0.12, 0.72, 0 }, "bone", "SmoothPlastic", "Ball"),
		p("RightUpperArm", "SkullEye", { 0.12, 0.1, 0.04 }, { 0.02, 0.74, -0.32 }, "glow", "Neon"),
		p("RightUpperArm", "SkullEye", { 0.12, 0.1, 0.04 }, { 0.24, 0.74, -0.3 }, "glow", "Neon"),
		p("RightUpperArm", "SkullJaw", { 0.4, 0.14, 0.3 }, { 0.12, 0.45, -0.18 }, "bone*0.9", "SmoothPlastic"),
	},
	spike("LeftUpperArm", "ShoulderBone", { -0.1, 0.8, 0 }, 0.28, 0.5, 0.1, 25, 0, "bone", "SmoothPlastic"),
	spike("LeftUpperArm", "ShoulderBone", { -0.3, 0.65, 0 }, 0.24, 0.4, 0.1, 45, 0, "bone", "SmoothPlastic")
)

gear.skull_staff = {
	zcyl("RightHand", "Staff", 5.0, 0.18, { 0, -0.18, -1.2 }, "#3A2A20", "Wood"),
	p("RightHand", "Skull", { 0.72, 0.72, 0.72 }, { 0, -0.1, -3.95 }, "bone", "SmoothPlastic", "Ball"),
	p("RightHand", "StaffJaw", { 0.42, 0.18, 0.36 }, { 0, -0.42, -4.05 }, "bone*0.9", "SmoothPlastic"),
	p("RightHand", "SkullEyes", { 0.14, 0.12, 0.08 }, { -0.14, -0.05, -4.3 }, "glow", "Neon"),
	p("RightHand", "SkullEyes", { 0.14, 0.12, 0.08 }, { 0.14, -0.05, -4.3 }, "glow", "Neon"),
	seeThrough(p("RightHand", "SoulFlame", { 1.0, 1.0, 1.0 }, { 0, -0.1, -3.95 }, "glow", "ForceField", "Ball"), 0.2),
	p("RightHand", "Prong", { 0.08, 0.55, 0.08 }, { 0.34, -0.12, -3.5 }, "iron", "Metal", nil, { -40, 0, 0 }),
	p("RightHand", "Prong", { 0.08, 0.55, 0.08 }, { -0.34, -0.12, -3.5 }, "iron", "Metal", nil, { -40, 0, 0 }),
}

gear.soul_orbs = mirror({
	p("UpperTorso", "SoulOrb", { 0.32, 0.32, 0.32 }, { 1.25, 1.25, 0.35 }, "glow", "Neon", "Ball"),
	seeThrough(
		p("UpperTorso", "SoulHalo", { 0.55, 0.55, 0.55 }, { 1.25, 1.25, 0.35 }, "glow", "ForceField", "Ball"),
		0.3
	),
})

---------------------------------------------------------------------------------------------------------------
-- DUSTY (rodeo grappler)

gear.cowboy_hat = {
	p("Head", "HatHair", { 1.26, 1.26, 1.26 }, { 0, 0.08, 0.15 }, "hair", "Fabric", "Ball"),
	band("Head", "Brim", 0.45, 2.15, 0.08, "accent", "Leather"),
	band("Head", "HatCrown", 0.76, 1.12, 0.6, "accent", "Leather"),
	p("Head", "CrownTop", { 1.0, 0.16, 0.9 }, { 0, 1.1, 0.03 }, "accent*0.92", "Leather"),
	band("Head", "HatBand", 0.56, 1.15, 0.14, "#3A2414", "Leather"),
	zcyl("Head", "Concho", 0.04, 0.18, { 0, 0.56, -0.58 }, "gold", "Metal"),
	p("Head", "BrimCurl", { 0.4, 0.08, 1.7 }, { 0.98, 0.56, 0 }, "accent", "Leather", nil, { 0, 0, 28 }),
	p("Head", "BrimCurl", { 0.4, 0.08, 1.7 }, { -0.98, 0.56, 0 }, "accent", "Leather", nil, { 0, 0, -28 }),
}

gear.bandana = join({
	band("Head", "Bandana", -0.47, 1.27, 0.42, "red", "Fabric"),
	p("Head", "BandanaKnot", { 0.26, 0.26, 0.26 }, { 0, -0.36, 0.62 }, "red*0.85", "Fabric", "Ball"),
	p("Head", "BandanaDot", { 0.06, 0.06, 0.03 }, { -0.2, -0.45, -0.65 }, "white", "Fabric"),
	p("Head", "BandanaDot", { 0.06, 0.06, 0.03 }, { 0.22, -0.55, -0.64 }, "white", "Fabric"),
}, spike("Head", "BandanaTip", { 0, -0.66, -0.6 }, 0.6, 0.4, 0.06, 180, 0, "red", "Fabric"))

gear.cowboy_vest = join(
	mirror({
		p("UpperTorso", "Vest", { 0.6, 0.95, 0.07 }, { 0.6, 0.33, -0.52 }, "accent", "Leather"),
		p("UpperTorso", "VestLow", { 0.42, 0.72, 0.07 }, { 0.46, -0.42, -0.45 }, "accent*0.9", "Leather"),
		w("UpperTorso", "ShirtCollar", { 0.25, 0.22, 0.25 }, { 0.16, 0.82, -0.45 }, "primary*1.05", "Fabric", {
			0,
			180,
			-30,
		}),
	}),
	{
		p("UpperTorso", "VestBack", { 1.75, 0.95, 0.07 }, { 0, 0.33, 0.52 }, "accent", "Leather"),
		p("UpperTorso", "Badge", { 0.2, 0.2, 0.04 }, { -0.55, 0.5, -0.57 }, "gold", "Metal"),
		p("UpperTorso", "Badge", { 0.2, 0.2, 0.04 }, { -0.55, 0.5, -0.57 }, "gold", "Metal", nil, { 0, 0, 45 }),
		p("UpperTorso", "ShirtButtons", { 0.05, 0.7, 0.03 }, { 0, 0.3, -0.51 }, "primary*0.8", "Fabric"),
	}
)

gear.chaps = mirror({
	p("RightUpperLeg", "Chap", { 0.5, 1.15, 0.84 }, { 0.17, 0, 0 }, "accent*0.85", "Leather"),
	p("RightUpperLeg", "Fringe", { 0.06, 1.1, 0.3 }, { 0.44, 0, 0 }, "accent*1.25", "Leather"),
	p("RightLowerLeg", "ChapLow", { 0.42, 0.75, 0.72 }, { 0.15, 0.25, 0 }, "accent*0.85", "Leather"),
})

gear.lasso_coil = ring(
	"LowerTorso",
	"Rope",
	{ 0, 0, 0 },
	{ 0.32, 0.32 },
	9,
	0,
	320,
	{ 0.4, 0.14, 0.14 },
	0,
	{ "rope" },
	"Fabric"
)
-- The coil hangs on the right hip, turned to face sideways.
for _, d in gear.lasso_coil do
	d.cf = CFrame.new(1.02, -0.05, 0.1) * CFrame.Angles(0, 0, rad(90)) * (d.cf :: CFrame)
end

gear.spurs = mirror({
	p("RightFoot", "SpurStrap", { 0.72, 0.08, 0.2 }, { 0, 0.16, 0.48 }, "leather", "Leather"),
	p("RightFoot", "Spur", { 0.05, 0.3, 0.3 }, { 0, 0.14, 0.68 }, "steel", "Metal", "Cylinder"),
})

return gear
