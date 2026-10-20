--!strict
-- Data-driven gear pieces for Visual/RigBuilder: each piece is { limb, name, size, offset, color, material,
-- shape?, rotation? } in studs and degrees, relative to the limb center (rig faces -Z, up is +Y). Colors are look
-- slots (primary, secondary, skin, glow, hair, accent) or fixed tones (steel, gold, wood, dark, white, leather,
-- bone, rope, red). Own designs only.

export type Piece = {
	limb: string,
	name: string,
	size: { number },
	offset: { number },
	color: string,
	material: string,
	shape: string?,
	rotation: { number }?,
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

return {
	hair_short = {
		p("Head", "Hair", { 1.28, 0.35, 1.28 }, { 0, 0.5, 0.05 }, "hair", "Fabric"),
	},
	hair_long = {
		p("Head", "Hair", { 1.3, 0.4, 1.3 }, { 0, 0.48, 0.05 }, "hair", "Fabric"),
		p("Head", "HairBack", { 1.25, 1.7, 0.3 }, { 0, -0.3, 0.62 }, "hair", "Fabric"),
	},
	forehead_mark = {
		p("Head", "Mark", { 0.2, 0.2, 0.05 }, { 0, 0.32, -0.62 }, "glow", "Neon"),
	},
	prayer_beads = {
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { -0.75, 0.65, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { -0.52, 0.44, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { -0.28, 0.23, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { -0.05, 0.03, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { 0.18, -0.18, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { 0.42, -0.39, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "Bead", { 0.28, 0.28, 0.28 }, { 0.65, -0.6, -0.55 }, "wood", "Wood", "Ball"),
		p("UpperTorso", "BeadGlow", { 0.4, 0.4, 0.4 }, { 0, 0.05, -0.6 }, "glow", "Neon", "Ball"),
	},
	wrist_wraps = {
		p("LeftLowerArm", "WrapL", { 0.86, 0.5, 0.86 }, { 0, -0.3, 0 }, "white", "Fabric"),
		p("RightLowerArm", "WrapR", { 0.86, 0.5, 0.86 }, { 0, -0.3, 0 }, "white", "Fabric"),
	},
	ice_crown = {
		p("Head", "Crown", { 0.16, 0.5, 0.16 }, { -0.42, 0.85, -0.1 }, "glow", "Glass", nil, { 0, 0, 16.8 }),
		p("Head", "Crown", { 0.16, 0.7, 0.16 }, { -0.21, 0.95, -0.1 }, "glow", "Glass", nil, { 0, 0, 8.4 }),
		p("Head", "Crown", { 0.16, 0.9, 0.16 }, { 0, 1.05, -0.1 }, "glow", "Glass"),
		p("Head", "Crown", { 0.16, 0.7, 0.16 }, { 0.21, 0.95, -0.1 }, "glow", "Glass", nil, { 0, 0, -8.4 }),
		p("Head", "Crown", { 0.16, 0.5, 0.16 }, { 0.42, 0.85, -0.1 }, "glow", "Glass", nil, { 0, 0, -16.8 }),
	},
	ice_shards = {
		p("LeftUpperArm", "ShardL", { 0.45, 1.3, 0.45 }, { -0.25, 0.75, 0 }, "glow", "Glass", nil, { 0, 0, 30 }),
		p("LeftUpperArm", "ShardL2", { 0.3, 0.8, 0.3 }, { -0.45, 0.4, 0.2 }, "glow", "Glass", nil, { 0, 0, 55 }),
		p("RightUpperArm", "ShardR", { 0.45, 1.3, 0.45 }, { 0.25, 0.75, 0 }, "glow", "Glass", nil, { 0, 0, -30 }),
		p("RightUpperArm", "ShardR2", { 0.3, 0.8, 0.3 }, { 0.45, 0.4, 0.2 }, "glow", "Glass", nil, { 0, 0, -55 }),
	},
	ice_daggers = {
		p("LeftHand", "DaggerL", { 0.1, 0.18, 1.5 }, { 0, -0.2, -0.85 }, "glow", "Glass"),
		p("RightHand", "Blade", { 0.1, 0.18, 1.5 }, { 0, -0.2, -0.85 }, "glow", "Glass"),
	},
	coat_tail = {
		p("LowerTorso", "CoatTail", { 1.9, 1.8, 0.15 }, { 0, -0.9, 0.52 }, "primary", "Fabric", nil, { -10, 0, 0 }),
	},
	helmet_visor = {
		p("Head", "Helmet", { 1.36, 1, 1.36 }, { 0, 0.2, 0.04 }, "accent", "SmoothPlastic"),
		p("Head", "Visor", { 1.12, 0.36, 0.1 }, { 0, 0.02, -0.67 }, "glow", "Neon"),
		p("Head", "Fin", { 0.14, 0.45, 1 }, { 0, 0.8, 0.1 }, "primary", "SmoothPlastic"),
	},
	jet_boots = {
		p("LeftFoot", "BootL", { 1, 0.5, 1.35 }, { 0, 0.12, 0 }, "accent", "Metal"),
		p("LeftFoot", "JetL", { 0.45, 0.4, 0.3 }, { 0, 0.12, 0.75 }, "glow", "Neon"),
		p("RightFoot", "BootR", { 1, 0.5, 1.35 }, { 0, 0.12, 0 }, "accent", "Metal"),
		p("RightFoot", "JetR", { 0.45, 0.4, 0.3 }, { 0, 0.12, 0.75 }, "glow", "Neon"),
	},
	backpack_thrusters = {
		p("UpperTorso", "Pack", { 1.3, 1.3, 0.55 }, { 0, 0, 0.78 }, "accent", "Metal"),
		p(
			"UpperTorso",
			"NozzleL",
			{ 0.65, 0.42, 0.42 },
			{ -0.35, -0.85, 0.8 },
			"glow",
			"Neon",
			"Cylinder",
			{ 0, 0, 90 }
		),
		p(
			"UpperTorso",
			"NozzleR",
			{ 0.65, 0.42, 0.42 },
			{ 0.35, -0.85, 0.8 },
			"glow",
			"Neon",
			"Cylinder",
			{ 0, 0, 90 }
		),
	},
	knight_helm = {
		p("Head", "Helm", { 1.36, 1.36, 1.36 }, { 0, 0.04, 0 }, "steel", "Metal"),
		p("Head", "Slit", { 0.95, 0.12, 0.05 }, { 0, 0.12, -0.7 }, "glow", "Neon"),
	},
	plume = {
		p("Head", "Plume", { 0.22, 0.8, 1.3 }, { 0, 1.05, 0.25 }, "accent", "Fabric"),
	},
	tower_shield = {
		p("LeftLowerArm", "Shield", { 0.25, 3, 2.1 }, { -0.6, -0.25, 0 }, "steel", "Metal"),
		p("LeftLowerArm", "ShieldRim", { 0.2, 3.15, 2.25 }, { -0.52, -0.25, 0 }, "accent", "Metal"),
		p("LeftLowerArm", "Emblem", { 0.08, 0.75, 0.75 }, { -0.76, -0.1, 0 }, "glow", "Neon", nil, { 45, 0, 0 }),
	},
	tabard = {
		p("UpperTorso", "Tabard", { 1.3, 1.65, 0.1 }, { 0, -0.05, -0.56 }, "accent", "Fabric"),
		p("LowerTorso", "TabardLow", { 1.2, 1.3, 0.1 }, { 0, -0.6, -0.56 }, "accent", "Fabric"),
	},
	pauldrons = {
		p("LeftUpperArm", "PauldronL", { 1.25, 0.5, 1.25 }, { -0.1, 0.6, 0 }, "accent", "Metal", nil, { 0, 0, 15 }),
		p("RightUpperArm", "PauldronR", { 1.25, 0.5, 1.25 }, { 0.1, 0.6, 0 }, "accent", "Metal", nil, { 0, 0, -15 }),
	},
	goggles = {
		p("Head", "Strap", { 1.3, 0.2, 1.3 }, { 0, 0.28, 0 }, "leather", "Leather"),
		p("Head", "LensL", { 0.4, 0.4, 0.2 }, { -0.27, 0.28, -0.66 }, "glow", "Neon", "Ball"),
		p("Head", "LensR", { 0.4, 0.4, 0.2 }, { 0.27, 0.28, -0.66 }, "glow", "Neon", "Ball"),
	},
	wild_hair = {
		p("Head", "Tuft", { 0.75, 0.6, 0.75 }, { -0.35, 0.65, 0.1 }, "hair", "Fabric", "Ball"),
		p("Head", "Tuft", { 0.8, 0.7, 0.8 }, { 0.3, 0.7, 0 }, "hair", "Fabric", "Ball"),
		p("Head", "Tuft", { 0.7, 0.6, 0.7 }, { 0, 0.6, 0.45 }, "hair", "Fabric", "Ball"),
	},
	bomb_belt = {
		p("LowerTorso", "Belt", { 2.12, 0.28, 1.12 }, { 0, 0.15, 0 }, "leather", "Leather"),
		p("LowerTorso", "Bomb", { 0.45, 0.45, 0.45 }, { -0.6, -0.05, -0.62 }, "dark", "SmoothPlastic", "Ball"),
		p("LowerTorso", "Bomb", { 0.45, 0.45, 0.45 }, { 0, -0.05, -0.62 }, "dark", "SmoothPlastic", "Ball"),
		p("LowerTorso", "Bomb", { 0.45, 0.45, 0.45 }, { 0.6, -0.05, -0.62 }, "dark", "SmoothPlastic", "Ball"),
		p("LowerTorso", "Fuse", { 0.08, 0.2, 0.08 }, { -0.6, 0.22, -0.62 }, "glow", "Neon"),
		p("LowerTorso", "Fuse", { 0.08, 0.2, 0.08 }, { 0, 0.22, -0.62 }, "glow", "Neon"),
		p("LowerTorso", "Fuse", { 0.08, 0.2, 0.08 }, { 0.6, 0.22, -0.62 }, "glow", "Neon"),
	},
	tinker_pack = {
		p("UpperTorso", "Pack", { 1.4, 1.4, 0.7 }, { 0, -0.1, 0.86 }, "steel", "Metal"),
		p("UpperTorso", "Cog", { 0.18, 0.75, 0.75 }, { 0.78, 0.3, 0.86 }, "gold", "Metal", "Cylinder"),
		p("UpperTorso", "Chimney", { 0.3, 0.7, 0.3 }, { -0.4, 0.85, 0.9 }, "dark", "Metal"),
	},
	great_helm = {
		p("Head", "Helm", { 1.34, 1.42, 1.34 }, { 0, 0.05, 0 }, "steel", "Metal"),
		p("Head", "CrossV", { 0.12, 0.7, 0.05 }, { 0, -0.05, -0.69 }, "accent", "Neon"),
		p("Head", "CrossH", { 0.75, 0.12, 0.05 }, { 0, 0.12, -0.69 }, "accent", "Neon"),
	},
	cape = {
		p("UpperTorso", "Cape", { 1.95, 3.3, 0.12 }, { 0, -0.85, 0.62 }, "accent", "Fabric", nil, { -8, 0, 0 }),
	},
	flame_sword = {
		p("RightHand", "Hilt", { 0.18, 0.18, 0.6 }, { 0, -0.2, -0.1 }, "dark", "Fabric"),
		p("RightHand", "Guard", { 0.95, 0.12, 0.15 }, { 0, -0.2, -0.45 }, "gold", "Metal"),
		p("RightHand", "Blade", { 0.12, 0.35, 3.4 }, { 0, -0.2, -2.25 }, "steel", "Metal"),
		p("RightHand", "Flame", { 0.08, 0.14, 3.3 }, { 0, -0.02, -2.25 }, "glow", "Neon"),
	},
	flame_wings = {
		p("UpperTorso", "WingL", { 0.15, 2.4, 1.7 }, { -0.95, 0.7, 0.95 }, "glow", "Neon", nil, { 15, -25, 35 }),
		p("UpperTorso", "WingR", { 0.15, 2.4, 1.7 }, { 0.95, 0.7, 0.95 }, "glow", "Neon", nil, { 15, 25, -35 }),
	},
	wings_back = {
		p("UpperTorso", "WingL", { 0.15, 2.6, 1.8 }, { -0.95, 0.6, 0.95 }, "white", "Fabric", nil, { 15, -25, 35 }),
		p("UpperTorso", "WingR", { 0.15, 2.6, 1.8 }, { 0.95, 0.6, 0.95 }, "white", "Fabric", nil, { 15, 25, -35 }),
		p("UpperTorso", "WingEdgeL", { 0.08, 2.4, 0.15 }, { -1, 0.65, 1.7 }, "glow", "Neon", nil, { 15, -25, 35 }),
		p("UpperTorso", "WingEdgeR", { 0.08, 2.4, 0.15 }, { 1, 0.65, 1.7 }, "glow", "Neon", nil, { 15, 25, -35 }),
	},
	winged_helm = {
		p("Head", "Helm", { 1.32, 0.75, 1.32 }, { 0, 0.38, 0 }, "gold", "Metal"),
		p("Head", "HelmWingL", { 0.1, 0.6, 1 }, { -0.72, 0.6, 0.2 }, "white", "Fabric", nil, { 0, 0, 25 }),
		p("Head", "HelmWingR", { 0.1, 0.6, 1 }, { 0.72, 0.6, 0.2 }, "white", "Fabric", nil, { 0, 0, -25 }),
	},
	glaive = {
		p("RightHand", "Shaft", { 0.15, 0.15, 4.6 }, { 0, -0.2, -1.3 }, "wood", "Wood"),
		p("RightHand", "Blade", { 0.1, 0.5, 1.4 }, { 0, -0.1, -4.2 }, "steel", "Metal"),
		p("RightHand", "Edge", { 0.05, 0.1, 1.3 }, { 0, 0.15, -4.2 }, "glow", "Neon"),
	},
	fox_tails = {
		p("LowerTorso", "Tail", { 0.5, 0.5, 2.2 }, { -0.45, 0.5, 1.3 }, "primary", "Fabric", nil, { -35, -18, 0 }),
		p("LowerTorso", "TailTip", { 0.6, 0.6, 0.6 }, { -0.72, 1.15, 2.25 }, "glow", "Neon", "Ball"),
		p("LowerTorso", "Tail", { 0.5, 0.5, 2.2 }, { 0, 0.5, 1.3 }, "primary", "Fabric", nil, { -35, 0, 0 }),
		p("LowerTorso", "TailTip", { 0.6, 0.6, 0.6 }, { 0, 1.15, 2.25 }, "glow", "Neon", "Ball"),
		p("LowerTorso", "Tail", { 0.5, 0.5, 2.2 }, { 0.45, 0.5, 1.3 }, "primary", "Fabric", nil, { -35, 18, 0 }),
		p("LowerTorso", "TailTip", { 0.6, 0.6, 0.6 }, { 0.72, 1.15, 2.25 }, "glow", "Neon", "Ball"),
	},
	mech_visor = {
		p("Head", "Visor", { 1.3, 0.42, 0.15 }, { 0, 0.1, -0.63 }, "glow", "Neon"),
		p("Head", "Antenna", { 0.08, 0.85, 0.08 }, { 0.45, 0.85, 0 }, "steel", "Metal"),
	},
	missile_pods = {
		p("UpperTorso", "PodL", { 0.9, 0.8, 1.3 }, { -1.25, 1.05, 0.4 }, "steel", "Metal"),
		p("UpperTorso", "PodR", { 0.9, 0.8, 1.3 }, { 1.25, 1.05, 0.4 }, "steel", "Metal"),
		p("UpperTorso", "PodFaceL", { 0.7, 0.6, 0.1 }, { -1.25, 1.05, -0.27 }, "glow", "Neon"),
		p("UpperTorso", "PodFaceR", { 0.7, 0.6, 0.1 }, { 1.25, 1.05, -0.27 }, "glow", "Neon"),
	},
	chest_core = {
		p("UpperTorso", "Plate", { 1.7, 1.1, 0.12 }, { 0, 0.15, -0.53 }, "steel", "Metal"),
		p("UpperTorso", "Core", { 0.6, 0.6, 0.25 }, { 0, 0.15, -0.6 }, "glow", "Neon", "Ball"),
	},
	hood = {
		p("Head", "HoodTop", { 1.48, 0.35, 1.48 }, { 0, 0.65, 0.05 }, "primary", "Fabric"),
		p("Head", "HoodL", { 0.16, 1.35, 1.42 }, { -0.72, 0.05, 0.06 }, "primary", "Fabric"),
		p("Head", "HoodR", { 0.16, 1.35, 1.42 }, { 0.72, 0.05, 0.06 }, "primary", "Fabric"),
		p("Head", "HoodBack", { 1.48, 1.35, 0.16 }, { 0, 0.05, 0.72 }, "primary", "Fabric"),
	},
	robe = {
		p("LowerTorso", "Robe", { 2.2, 2.4, 1.3 }, { 0, -1.25, 0 }, "primary", "Fabric"),
		p("LowerTorso", "RobeTrim", { 2.25, 0.18, 1.35 }, { 0, -2.35, 0 }, "glow", "Neon"),
	},
	skull_staff = {
		p("RightHand", "Staff", { 0.18, 0.18, 5 }, { 0, -0.2, -1.2 }, "wood", "Wood"),
		p("RightHand", "Skull", { 0.75, 0.75, 0.75 }, { 0, -0.2, -3.95 }, "bone", "SmoothPlastic", "Ball"),
		p("RightHand", "SkullEyes", { 0.5, 0.12, 0.1 }, { 0, -0.15, -3.95 }, "glow", "Neon"),
	},
	cowboy_hat = {
		p("Head", "Brim", { 0.12, 2.3, 2.3 }, { 0, 0.6, 0 }, "accent", "Leather", "Cylinder", { 0, 0, 90 }),
		p("Head", "Crown", { 0.85, 1.15, 1.15 }, { 0, 1, 0 }, "accent", "Leather", "Cylinder", { 0, 0, 90 }),
		p("Head", "Band", { 0.18, 1.2, 1.2 }, { 0, 0.72, 0 }, "glow", "Fabric", "Cylinder", { 0, 0, 90 }),
	},
	bandana = {
		p("UpperTorso", "Bandana", { 1.32, 0.3, 1.12 }, { 0, 0.85, 0 }, "red", "Fabric"),
		p("UpperTorso", "BandanaTip", { 0.6, 0.6, 0.1 }, { 0, 0.55, -0.56 }, "red", "Fabric", nil, { 0, 0, 45 }),
	},
	lasso_coil = {
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, 0, 0.55 }, "rope", "Fabric", nil, { 90, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, 0.323, 0.445 }, "rope", "Fabric", nil, { 54, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, 0.523, 0.17 }, "rope", "Fabric", nil, { 18, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, 0.523, -0.17 }, "rope", "Fabric", nil, { -18, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, 0.323, -0.445 }, "rope", "Fabric", nil, { -54, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, 0, -0.55 }, "rope", "Fabric", nil, { -90, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, -0.323, -0.445 }, "rope", "Fabric", nil, { -126, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, -0.523, -0.17 }, "rope", "Fabric", nil, { -162, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, -0.523, 0.17 }, "rope", "Fabric", nil, { -198, 0, 0 }),
		p("LowerTorso", "Rope", { 0.14, 0.14, 0.4 }, { 1.15, -0.323, 0.445 }, "rope", "Fabric", nil, { -234, 0, 0 }),
	},
	boots = {
		p("LeftLowerLeg", "BootL", { 0.97, 0.75, 0.97 }, { 0, -0.25, 0 }, "leather", "Leather"),
		p("RightLowerLeg", "BootR", { 0.97, 0.75, 0.97 }, { 0, -0.25, 0 }, "leather", "Leather"),
	},
} :: { [string]: { Piece } }
