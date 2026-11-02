--!strict
-- Builds a raid boss's display model from plain Parts: an original, procedurally built statue colossus about three
-- fighters tall (Data/Bosses.raidBody). Heaven bosses are marble with gold trim, a robe, feathered wings and a halo;
-- hell bosses are obsidian with horns, armored legs and bat-like wings. Each boss gets its color (BossData.color)
-- as the glow of eyes, core and runes. A stone shell (BossGroup "Shell") covers chest, shoulders, head and arms in
-- phase 1 and shatters in phase 2, revealing the glowing core underneath (Controllers/BossView).
--
-- Model space: feet center at the origin, front toward +Z (the fight camera), wings spread along X.
-- Every part has a BossGroup attribute (Body, Head, ArmL, ArmR, WingL, WingR, Halo, Core, Shell) and shell parts a
-- Follow attribute (the group they move with); the model has Pivot_<group> attributes for the animator.
-- Nothing is fetched from the asset service.

local Bosses = require(script.Parent.Parent.Data.Bosses)
local Visuals = require(script.Parent.Parent.Data.Visuals)

local BossRig = {}
BossRig.PART_BUDGET = 140

type Ctx = { model: Model, u: number, count: number }

local function add(
	ctx: Ctx,
	group: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = material ~= Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("BossGroup", group)
	p.Parent = ctx.model
	ctx.count += 1
	return p
end

local function wedge(
	ctx: Ctx,
	group: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material
	w:SetAttribute("BossGroup", group)
	w.Parent = ctx.model
	ctx.count += 1
	return w
end

local function shell(ctx: Ctx, follow: string, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = add(ctx, "Shell", name, size, cf, color, Enum.Material.Slate)
	p:SetAttribute("Follow", follow)
	return p
end

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

function BossRig.build(bossId: string): Model
	local def = Bosses.byId[bossId]
	assert(def, `unknown boss {bossId}`)
	local widthM, heightM = Bosses.raidBody(bossId)
	local M = Visuals.STUDS_PER_METER
	local H = heightM * M
	local u = H / 10
	local heaven = def.realm == "heaven"
	local glow = Color3.fromHex(def.color or "#ff4040")
	local body = if heaven then Color3.fromRGB(236, 233, 224) else Color3.fromRGB(38, 32, 44)
	local trim = if heaven then Color3.fromRGB(212, 169, 60) else glow:Lerp(Color3.fromRGB(60, 20, 20), 0.35)
	local bodyMat = if heaven then Enum.Material.Marble else Enum.Material.Basalt
	local stone = if heaven then Color3.fromRGB(150, 146, 140) else Color3.fromRGB(84, 76, 84)
	local eye = if heaven then glow:Lerp(Color3.new(1, 1, 1), 0.4) else glow

	local model = Instance.new("Model")
	model.Name = "Boss_" .. bossId
	local ctx: Ctx = { model = model, u = u, count = 0 }
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * u, y * u, z * u)
	end

	-- Lower body: robe (heaven) or armored legs (hell).
	if heaven then
		add(ctx, "Body", "RobeHem", v(3.6 * u, 1.2 * u, 2.6 * u), at(0, 0.6, 0), body, bodyMat)
		add(ctx, "Body", "Robe", v(3.0 * u, 2.2 * u, 2.2 * u), at(0, 2.2, 0), body, bodyMat)
		add(ctx, "Body", "RobeTop", v(2.5 * u, 1.2 * u, 1.9 * u), at(0, 3.8, 0), body, bodyMat)
		add(ctx, "Body", "HemTrim", v(3.7 * u, 0.25 * u, 2.7 * u), at(0, 1.15, 0), trim, Enum.Material.Metal)
		add(ctx, "Body", "RobeRune", v(0.3 * u, 2.6 * u, 0.1 * u), at(0, 2.0, 1.12), glow, Enum.Material.Neon)
	else
		for _, s in { -1, 1 } do
			add(ctx, "Body", "Foot", v(1.3 * u, 0.6 * u, 1.9 * u), at(s * 0.85, 0.3, 0.25), body, bodyMat)
			add(ctx, "Body", "Shin", v(1.0 * u, 2.0 * u, 1.1 * u), at(s * 0.85, 1.6, 0), body, bodyMat)
			add(ctx, "Body", "Knee", v(1.3 * u, 0.9 * u, 1.3 * u), at(s * 0.85, 2.7, 0.15), trim, Enum.Material.Metal)
			add(ctx, "Body", "Thigh", v(1.2 * u, 1.4 * u, 1.3 * u), at(s * 0.8, 3.6, 0), body, bodyMat)
			add(
				ctx,
				"Body",
				"ShinRune",
				v(0.2 * u, 1.4 * u, 0.1 * u),
				at(s * 0.85, 1.6, 0.58),
				glow,
				Enum.Material.Neon
			)
		end
	end
	add(ctx, "Body", "Belt", v(2.8 * u, 0.6 * u, 1.9 * u), at(0, 4.4, 0), trim, Enum.Material.Metal)

	-- Torso, the core and shoulders.
	add(ctx, "Body", "Waist", v(2.3 * u, 1.0 * u, 1.6 * u), at(0, 5.0, 0), body, bodyMat)
	add(ctx, "Body", "Chest", v(3.2 * u, 2.2 * u, 1.9 * u), at(0, 6.5, 0), body, bodyMat)
	add(ctx, "Body", "Collar", v(2.0 * u, 0.4 * u, 1.6 * u), at(0, 7.7, 0), trim, Enum.Material.Metal)
	add(
		ctx,
		"Core",
		"CoreGem",
		v(1.0 * u, 1.0 * u, 1.0 * u),
		at(0, 6.4, 0.75),
		glow,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	for k, a in { -0.5, 0.5 } do
		add(
			ctx,
			"Core",
			"CoreCrack" .. k,
			v(0.15 * u, 1.6 * u, 0.1 * u),
			at(a * 1.6, 6.3, 0.97) * CFrame.Angles(0, 0, a * 0.8),
			glow,
			Enum.Material.Neon
		)
	end
	for _, s in { -1, 1 } do
		add(
			ctx,
			"Body",
			"Shoulder",
			v(1.4 * u, 1.4 * u, 1.4 * u),
			at(s * 1.9, 7.2, 0),
			trim,
			Enum.Material.Metal,
			Enum.PartType.Ball
		)
	end

	-- Arms (pivot at the shoulder); the right arm carries the weapon.
	for _, s in { -1, 1 } do
		local group = if s < 0 then "ArmL" else "ArmR"
		add(ctx, group, "UpperArm", v(0.9 * u, 2.0 * u, 0.9 * u), at(s * 2.25, 5.9, 0), body, bodyMat)
		add(ctx, group, "Elbow", v(1.0 * u, 0.6 * u, 1.0 * u), at(s * 2.3, 4.8, 0), trim, Enum.Material.Metal)
		add(ctx, group, "Forearm", v(0.95 * u, 1.8 * u, 0.95 * u), at(s * 2.35, 3.8, 0.15), body, bodyMat)
		add(
			ctx,
			group,
			"Fist",
			v(1.05 * u, 1.05 * u, 1.05 * u),
			at(s * 2.4, 2.7, 0.3),
			body,
			bodyMat,
			Enum.PartType.Ball
		)
		model:SetAttribute("Pivot_" .. group, v(s * 1.9 * u, 7.2 * u, 0))
	end
	if heaven then
		-- A tall staff with a radiant head.
		add(ctx, "ArmR", "Staff", v(0.3 * u, 8.0 * u, 0.3 * u), at(2.4, 4.4, 0.3), trim, Enum.Material.Metal)
		add(
			ctx,
			"ArmR",
			"StaffHead",
			v(1.0 * u, 1.0 * u, 1.0 * u),
			at(2.4, 8.6, 0.3),
			glow,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		add(
			ctx,
			"ArmR",
			"StaffRing",
			v(0.2 * u, 1.6 * u, 1.6 * u),
			at(2.4, 8.6, 0.3) * CFrame.Angles(0, math.pi / 2, 0),
			trim,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
	else
		-- A great cleaver blade.
		add(ctx, "ArmR", "Haft", v(0.35 * u, 4.0 * u, 0.35 * u), at(2.4, 3.2, 0.3), trim, Enum.Material.Metal)
		add(
			ctx,
			"ArmR",
			"Blade",
			v(0.25 * u, 4.2 * u, 1.6 * u),
			at(2.4, 6.4, 0.6),
			Color3.fromRGB(70, 66, 78),
			Enum.Material.Metal
		)
		add(ctx, "ArmR", "BladeEdge", v(0.3 * u, 4.2 * u, 0.15 * u), at(2.4, 6.4, 1.45), glow, Enum.Material.Neon)
	end

	-- Head (pivot at the neck).
	model:SetAttribute("Pivot_Head", v(0, 7.8 * u, 0))
	add(ctx, "Head", "Neck", v(0.8 * u, 0.6 * u, 0.8 * u), at(0, 8.0, 0), body, bodyMat)
	add(ctx, "Head", "Head", v(1.5 * u, 1.6 * u, 1.5 * u), at(0, 8.9, 0), body, bodyMat)
	add(ctx, "Head", "Crest", v(0.3 * u, 0.8 * u, 1.6 * u), at(0, 9.9, -0.1), trim, Enum.Material.Metal)
	for _, s in { -1, 1 } do
		add(ctx, "Head", "Eye", v(0.42 * u, 0.16 * u, 0.1 * u), at(s * 0.35, 9.0, 0.76), eye, Enum.Material.Neon)
	end
	if not heaven then
		for _, s in { -1, 1 } do
			wedge(
				ctx,
				"Head",
				"Horn",
				v(0.4 * u, 1.8 * u, 0.7 * u),
				at(s * 0.95, 10.0, 0) * CFrame.Angles(0, 0, -s * 0.55),
				Color3.fromRGB(220, 210, 190),
				Enum.Material.Marble
			)
		end
	else
		-- Halo: a ring of light behind the head.
		model:SetAttribute("Pivot_Halo", v(0, 9.2 * u, -0.9 * u))
		local n = 12
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2
			add(
				ctx,
				"Halo",
				"HaloSegment",
				v(0.55 * u, 0.18 * u, 0.12 * u),
				at(math.cos(a) * 1.35, 9.4 + math.sin(a) * 1.35, -0.9) * CFrame.Angles(0, 0, a + math.pi / 2),
				glow:Lerp(Color3.new(1, 0.95, 0.7), 0.5),
				Enum.Material.Neon
			)
		end
	end

	-- Wings (pivot at the upper back).
	for _, s in { -1, 1 } do
		local group = if s < 0 then "WingL" else "WingR"
		model:SetAttribute("Pivot_" .. group, v(s * 0.8 * u, 7.2 * u, -1.0 * u))
		if heaven then
			for k = 0, 4 do
				local len = (4.2 + k * 0.5) * u
				local a = math.rad(15 + k * 15)
				local dir = Vector3.new(s * math.cos(a), math.sin(a), 0)
				local center = Vector3.new(s * 0.8 * u, 7.2 * u, -1.1 * u) + dir * len * 0.5
				add(
					ctx,
					group,
					"Feather",
					v(len, 0.75 * u, 0.25 * u),
					CFrame.new(center) * CFrame.Angles(0, 0, s * a),
					if k % 2 == 0 then body else body:Lerp(trim, 0.25),
					bodyMat
				)
			end
		else
			for k = 0, 2 do
				local len = (3.8 + k * 0.9) * u
				local a = math.rad(25 + k * 22)
				local dir = Vector3.new(s * math.cos(a), math.sin(a), 0)
				local center = Vector3.new(s * 0.8 * u, 7.2 * u, -1.1 * u) + dir * len * 0.5
				add(
					ctx,
					group,
					"WingSpar",
					v(len, 0.3 * u, 0.3 * u),
					CFrame.new(center) * CFrame.Angles(0, 0, s * a),
					body,
					bodyMat
				)
				add(
					ctx,
					group,
					"WingMembrane",
					v(len * 0.9, 1.2 * u, 0.1 * u),
					CFrame.new(center - Vector3.new(0, 0.6 * u, 0)) * CFrame.Angles(0, 0, s * a),
					glow:Lerp(Color3.fromRGB(20, 10, 16), 0.65),
					Enum.Material.SmoothPlastic
				)
			end
		end
	end

	-- Stone shell over the core: it shatters in phase 2.
	shell(ctx, "Body", "ShellChest", v(3.4 * u, 2.4 * u, 0.35 * u), at(0, 6.5, 1.05), stone)
	shell(ctx, "Body", "ShellBack", v(3.4 * u, 2.4 * u, 0.35 * u), at(0, 6.5, -1.05), stone)
	shell(ctx, "Body", "ShellWaist", v(2.5 * u, 1.1 * u, 1.8 * u), at(0, 5.0, 0), stone)
	shell(ctx, "Head", "ShellMask", v(1.6 * u, 1.0 * u, 0.3 * u), at(0, 8.75, 0.8), stone)
	shell(ctx, "Head", "ShellCrown", v(1.7 * u, 0.5 * u, 1.7 * u), at(0, 9.75, 0), stone)
	for _, s in { -1, 1 } do
		local group = if s < 0 then "ArmL" else "ArmR"
		shell(ctx, "Body", "ShellShoulder", v(1.7 * u, 0.9 * u, 1.7 * u), at(s * 1.95, 7.75, 0), stone)
		shell(ctx, group, "ShellBracer", v(1.15 * u, 1.4 * u, 1.15 * u), at(s * 2.35, 3.8, 0.15), stone)
	end
	-- Cracks on the shell hint at the light inside.
	for k, x in { -0.9, 0.5 } do
		local crack = add(
			ctx,
			"Shell",
			"ShellCrack" .. k,
			v(0.12 * u, 1.3 * u, 0.05 * u),
			at(x, 6.4, 1.25) * CFrame.Angles(0, 0, 0.4 * x),
			glow,
			Enum.Material.Neon
		)
		crack:SetAttribute("Follow", "Body")
	end

	model:SetAttribute("BossId", bossId)
	model:SetAttribute("Realm", def.realm)
	model:SetAttribute("Height", H)
	model:SetAttribute("Width", widthM * M)
	model:SetAttribute("Glow", def.color)
	model:SetAttribute("PartCount", ctx.count)
	return model
end

return BossRig
