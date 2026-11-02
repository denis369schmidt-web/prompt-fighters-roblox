--!strict
-- Second pass over a built arena: background depth (parallax skyline and hill layers, crowds) and ambient motion
-- (passing trains, ships and planes, sweeping searchlights, swaying flags and lanterns, pulsing neon).
-- Decoration only: everything sits behind or far below the fight plane and never collides. Stage, platforms,
-- ledges and blast zones come from Combat/Arena and are not touched here.

local Decor = require(script.Parent.Decor)

local ArenaDressing = {}

export type Ctx = {
	model: Model,
	theme: any,
	trim: Color3,
	accent: Color3,
	name: string,
	rng: Random,
	baseY: number,
	wallZ: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function each(ctx: Ctx, name: string, fn: (BasePart, number) -> ())
	local i = 0
	for _, d in ctx.model:GetChildren() do
		if d.Name == name and d:IsA("BasePart") then
			i += 1
			fn(d, i)
		end
	end
end

-- Haze color for far layers: the theme tint, darkened for night arenas.
local function haze(ctx: Ctx, scale: number): Color3
	local t = ctx.theme.tint
	return Color3.new(math.clamp(t[1] * scale, 0, 1), math.clamp(t[2] * scale, 0, 1), math.clamp(t[3] * scale, 0, 1))
end

-- A train of `cars` boxes with lit windows that crosses the whole backdrop every few seconds.
local function train(ctx: Ctx, y: number, z: number, color: Color3, windows: Color3, speed: number, phase: number)
	local parts: { BasePart } = {}
	local m = ctx.model
	for car = 0, 3 do
		local x = 70 + car * 15
		table.insert(
			parts,
			Decor.part(
				m,
				"TrainCar",
				Vector3.new(14, 4, 4),
				Vector3.new(x, ctx.baseY + y, z),
				color,
				Enum.Material.Metal
			)
		)
		local w = Decor.part(
			m,
			"TrainWindows",
			Vector3.new(12, 1.2, 0.2),
			Vector3.new(x, ctx.baseY + y + 0.6, z + 2.05),
			windows,
			Enum.Material.Neon
		)
		w.Transparency = 0.35
		table.insert(parts, w)
	end
	table.insert(
		parts,
		Decor.part(
			m,
			"TrainLight",
			Vector3.new(0.4, 1, 3),
			Vector3.new(122.2, ctx.baseY + y, z),
			rgb(255, 250, 220),
			Enum.Material.Neon
		)
	)
	Decor.convoy(parts, speed, 520, phase)
	-- The track: one long beam with a neon edge.
	Decor.part(
		m,
		"TrainTrack",
		Vector3.new(520, 1.2, 3),
		Vector3.new(0, ctx.baseY + y - 2.6, z),
		rgb(24, 22, 34),
		Enum.Material.Metal
	)
	Decor.part(
		m,
		"TrackGlow",
		Vector3.new(520, 0.25, 0.25),
		Vector3.new(0, ctx.baseY + y - 2.1, z + 1.6),
		ctx.trim,
		Enum.Material.Neon
	).Transparency =
		0.4
end

-- A blimp with a glowing screen drifting across the sky.
local function blimp(ctx: Ctx, y: number, z: number, text: string, phase: number)
	local m = ctx.model
	local c = Vector3.new(0, ctx.baseY + y, z)
	local hullColor = rgb(200, 204, 216)
	local parts: { BasePart } = {
		Decor.part(
			m,
			"BlimpHull",
			Vector3.new(30, 11, 11),
			CFrame.new(c),
			hullColor,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		),
		Decor.part(
			m,
			"BlimpNose",
			Vector3.one * 11,
			c + Vector3.new(15, 0, 0),
			hullColor,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		),
		Decor.part(
			m,
			"BlimpTail",
			Vector3.one * 11,
			c - Vector3.new(15, 0, 0),
			hullColor,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		),
		Decor.wedge(
			m,
			"BlimpFin",
			Vector3.new(0.6, 7, 7),
			CFrame.new(c + Vector3.new(-21, 5, 0)) * CFrame.Angles(0, -math.pi / 2, 0),
			ctx.accent
		),
	}
	local screen = Decor.part(
		m,
		"BlimpScreen",
		Vector3.new(22, 5, 0.3),
		c + Vector3.new(0, -1, 5.7),
		rgb(10, 8, 20),
		Enum.Material.SmoothPlastic
	)
	Decor.text(screen, Enum.NormalId.Back, text, ctx.trim, 10)
	table.insert(parts, screen)
	Decor.convoy(parts, 7, 460, phase)
end

-- A small plane or ship silhouette (body, wing, tail) crossing at height `y`.
local function flyer(ctx: Ctx, y: number, z: number, color: Color3, light: Color3, speed: number, phase: number)
	local m = ctx.model
	local c = Vector3.new(0, ctx.baseY + y, z)
	local dir = if speed > 0 then 1 else -1
	local parts: { BasePart } = {
		Decor.part(m, "FlyerBody", Vector3.new(9, 1.6, 1.6), c, color, Enum.Material.Metal),
		Decor.part(m, "FlyerWing", Vector3.new(2.4, 0.3, 9), c, color, Enum.Material.Metal),
		Decor.part(
			m,
			"FlyerTail",
			Vector3.new(1.4, 2.6, 0.3),
			c - Vector3.new(dir * 4, 1.2, 0),
			color,
			Enum.Material.Metal
		),
		Decor.part(
			m,
			"FlyerLight",
			Vector3.one * 0.8,
			c + Vector3.new(dir * 4.8, 0, 0),
			light,
			Enum.Material.Neon,
			Enum.PartType.Ball
		),
	}
	Decor.convoy(parts, math.abs(speed), 480, phase, Vector3.new(dir, 0, 0))
end

-- Rolling hills as a far silhouette layer (pairs of wedges).
local function hills(ctx: Ctx, z: number, y: number, color: Color3, height: number, seed: number)
	local rng = Random.new(seed)
	for k = -5, 5 do
		local h = height * rng:NextNumber(0.6, 1.1)
		local w = rng:NextNumber(50, 80)
		local x = k * 42 + rng:NextNumber(-8, 8)
		for side = 0, 1 do
			Decor.wedge(
				ctx.model,
				"Hill",
				Vector3.new(6, h, w / 2),
				CFrame.new(x, ctx.baseY + y + h / 2, z)
					* CFrame.Angles(0, side * math.pi + math.pi / 2, 0)
					* CFrame.new(0, 0, -w / 4),
				color,
				Enum.Material.SmoothPlastic
			)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------

local DRESS: { [string]: (ctx: Ctx) -> () } = {}

DRESS.city_street = function(ctx)
	train(ctx, 32, ctx.wallZ - 66, rgb(40, 40, 56), rgb(255, 220, 160), 46, 0)
	each(ctx, "SignFrame", function(p, i)
		Decor.pulse(p, 0.45, 2.2 + i * 0.7, i)
	end)
	each(ctx, "Lantern", function(p, i)
		Decor.tag(p, "bob", { amp = 0.25, period = 2.5, phase = i * 0.4 })
	end)
	Decor.skyline(ctx.model, {
		from = -220,
		to = 220,
		z = ctx.wallZ - 150,
		baseY = ctx.baseY - 80,
		minHeight = 90,
		maxHeight = 150,
		width = { 14, 26 },
		color = ctx.trim:Lerp(rgb(8, 6, 18), 0.86),
		windows = ctx.accent:Lerp(rgb(20, 20, 40), 0.5),
		roof = ctx.trim,
		seed = 3,
	})
end

DRESS.city_roof = function(ctx)
	local m = ctx.model
	-- Two more tower layers between the near roofs and the sky, so the city fills the frame.
	Decor.skyline(m, {
		from = -200,
		to = 200,
		z = ctx.wallZ - 120,
		baseY = ctx.baseY - 100,
		minHeight = 80,
		maxHeight = 140,
		width = { 14, 24 },
		color = rgb(22, 20, 42),
		windows = rgb(255, 200, 130),
		roof = ctx.accent,
		seed = 5,
	})
	Decor.skyline(m, {
		from = -300,
		to = 300,
		z = ctx.wallZ - 220,
		baseY = ctx.baseY - 120,
		minHeight = 130,
		maxHeight = 220,
		width = { 18, 34 },
		color = ctx.trim:Lerp(rgb(8, 8, 22), 0.8),
		windows = ctx.trim:Lerp(rgb(10, 10, 30), 0.35),
		roof = ctx.trim,
		seed = 9,
	})
	blimp(ctx, 48, ctx.wallZ - 95, "PROMPT FIGHTERS", 20)
	train(ctx, 38, ctx.wallZ - 70, rgb(36, 40, 56), ctx.accent:Lerp(rgb(255, 255, 255), 0.4), 52, 3)
	for k, x in { -110, -30, 70, 140 } do
		Decor.searchlight(
			m,
			Vector3.new(x, ctx.baseY - 60, ctx.wallZ - 160),
			160,
			if k % 2 == 0 then ctx.trim else ctx.accent,
			(k % 2 - 0.5) * 0.5,
			k * 1.7
		)
	end
	each(ctx, "Beacon", function(p)
		Decor.pulse(p, 0.8, 1.2)
	end)
	each(ctx, "SignFrame", function(p, i)
		Decor.pulse(p, 0.5, 3 + i, i)
	end)
	if ctx.theme.variant == "storm" then
		flyer(ctx, 52, ctx.wallZ - 80, rgb(40, 44, 56), rgb(255, 60, 60), -18, 0)
	end
end

DRESS.scifi_city = function(ctx)
	each(ctx, "HoverCar", function(p, i)
		local thruster: BasePart? = nil
		for _, d in ctx.model:GetChildren() do
			if d.Name == "Thruster" and d:IsA("BasePart") and (d.Position - p.Position).Magnitude < 1.5 then
				thruster = d
			end
		end
		local parts: { BasePart } = { p }
		if thruster then
			table.insert(parts, thruster)
		end
		Decor.convoy(parts, 14 + i * 5, 260, i * 4, Vector3.new(if i % 2 == 0 then 1 else -1, 0, 0))
	end)
	each(ctx, "HoloRing", function(p, i)
		Decor.tag(p, "bob", { amp = 3, period = 5, phase = i })
		Decor.pulse(p, 0.2, 3, i)
	end)
	Decor.skyline(ctx.model, {
		from = -260,
		to = 260,
		z = ctx.wallZ - 190,
		baseY = ctx.baseY - 110,
		minHeight = 140,
		maxHeight = 230,
		width = { 10, 20 },
		color = ctx.trim:Lerp(rgb(6, 10, 26), 0.82),
		windows = ctx.trim:Lerp(rgb(6, 10, 26), 0.3),
		roof = ctx.accent,
		seed = 21,
	})
	train(ctx, 30, ctx.wallZ - 70, rgb(220, 226, 240), ctx.trim, 60, 6)
end

DRESS.temple = function(ctx)
	local m = ctx.model
	local jungle = ctx.theme.variant == "jungle"
	if jungle then
		hills(ctx, ctx.wallZ - 170, -45, rgb(70, 110, 84), 90, 4)
		-- A waterfall down the far cliff.
		local fall = Decor.part(
			m,
			"Waterfall",
			Vector3.new(6, 70, 1),
			Vector3.new(-70, ctx.baseY - 10, ctx.wallZ - 60),
			rgb(120, 190, 230),
			Enum.Material.Neon
		)
		fall.Transparency = 0.55
		Decor.pulse(fall, 0.2, 1.4)
		Decor.part(
			m,
			"Cliff",
			Vector3.new(36, 80, 14),
			Vector3.new(-70, ctx.baseY - 4, ctx.wallZ - 68),
			rgb(80, 96, 78),
			Enum.Material.Rock
		)
	else
		hills(ctx, ctx.wallZ - 100, -50, rgb(26, 28, 56), 70, 8)
	end
	-- Sky lanterns drifting up and down.
	for k = 1, 8 do
		local lantern = Decor.part(
			m,
			"SkyLantern",
			Vector3.new(1.6, 2.2, 1.6),
			Vector3.new(-90 + k * 22, ctx.baseY + 18 + (k * 7) % 22, ctx.wallZ - 30 - (k % 3) * 25),
			if jungle then ctx.trim else rgb(255, 170, 80),
			Enum.Material.Neon
		)
		Decor.tag(lantern, "bob", { amp = 2.5, period = 4 + k % 3, phase = k })
	end
	each(ctx, "Flame", function(p, i)
		Decor.pulse(p, 0.3, 0.7 + (i % 3) * 0.2, i)
	end)
	-- A matte moon: as neon it blooms into a white blot that steals focus from the fight.
	each(ctx, "Moon", function(p)
		p.Material = Enum.Material.SmoothPlastic
	end)
end

DRESS.dojo = function(ctx)
	each(ctx, "PaperLantern", function(p, i)
		Decor.tag(p, "sway", { amp = 0.12, period = 3, pivot = p.Position + Vector3.new(0, 6, 0), phase = i })
	end)
	each(ctx, "Banner", function(p, i)
		Decor.tag(p, "sway", { amp = 0.05, period = 4, pivot = p.Position + Vector3.new(0, 8, 0), phase = i * 2 })
	end)
	-- Cherry trees in the garden outside, seen through the open hall ends.
	for _, x in { -96, 96 } do
		Decor.part(
			ctx.model,
			"CherryTrunk",
			Vector3.new(2, 26, 2),
			Vector3.new(x, ctx.baseY - 6, ctx.wallZ + 2),
			rgb(70, 44, 36),
			Enum.Material.Wood
		)
		for k = 0, 2 do
			Decor.part(
				ctx.model,
				"Blossom",
				Vector3.one * (12 - k * 2),
				Vector3.new(x + (k - 1) * 5, ctx.baseY + 8 + k * 3, ctx.wallZ + 2),
				rgb(255, 170, 200),
				Enum.Material.Grass,
				Enum.PartType.Ball
			)
		end
	end
end

DRESS.colosseum = function(ctx)
	local m = ctx.model
	local radius = 150
	local colors = { ctx.trim, ctx.accent, rgb(200, 60, 50), rgb(240, 236, 220), rgb(70, 90, 160) }
	for seg = -3, 3 do
		local angle = seg * 0.24
		local x, z = math.sin(angle) * radius, -math.cos(angle) * radius + 20
		local facing = CFrame.new(x, ctx.baseY - 30, z) * CFrame.Angles(0, -angle, 0)
		-- A stepped stand (three ledges) with spectators on it.
		for row = 0, 2 do
			Decor.part(
				m,
				"Seats",
				Vector3.new(34, 3, 4),
				facing * CFrame.new(0, row * 3 + 1.5, -row * 4),
				rgb(150, 124, 92),
				Enum.Material.Sandstone
			)
		end
		Decor.crowd(m, facing * CFrame.new(0, 3, 0), {
			width = 32,
			rows = 3,
			spacing = 3.6,
			rise = Vector3.new(0, 3, -4),
			colors = colors,
			seed = seg + 10,
		})
	end
	for k = -4, 4 do
		local angle = k * 0.2
		local x, z = math.sin(angle) * 172, -math.cos(angle) * 172 + 20
		Decor.flag(m, Vector3.new(x, ctx.baseY + 46, z), 14, if k % 2 == 0 then ctx.trim else rgb(190, 40, 40), k)
	end
	each(ctx, "Fire", function(p, i)
		Decor.pulse(p, 0.25, 0.6, i)
	end)
end

DRESS.stadium = function(ctx)
	local m = ctx.model
	local future = ctx.theme.variant == "future"
	for k = -3, 3 do
		Decor.flag(
			m,
			Vector3.new(k * 32, ctx.baseY + 34, ctx.wallZ - 78),
			12,
			if k % 2 == 0 then ctx.trim else ctx.accent,
			k
		)
	end
	each(ctx, "TierTrim", function(p, i)
		Decor.pulse(p, 0.5, 1.6, i * 0.25)
	end)
	for k, x in { -140, -60, 60, 140 } do
		Decor.searchlight(
			m,
			Vector3.new(x, ctx.baseY - 20, ctx.wallZ - 110),
			150,
			if future then ctx.trim else rgb(255, 240, 200),
			(k % 2 - 0.5) * 0.6,
			k * 2
		)
	end
	if future then
		blimp(ctx, 52, ctx.wallZ - 110, "CYBER-STADION", 10)
	else
		flyer(ctx, 56, ctx.wallZ - 120, rgb(220, 220, 230), rgb(255, 80, 80), 16, 4)
	end
end

DRESS.mountains = function(ctx)
	hills(ctx, ctx.wallZ - 210, -70, rgb(60, 72, 104), 140, 6)
	each(ctx, "Aurora", function(p, i)
		Decor.tag(p, "bob", { amp = 3, period = 7, phase = i * 0.6 })
		Decor.pulse(p, 0.15, 5, i * 0.9)
	end)
	-- A cable car gliding between the peaks.
	local m = ctx.model
	local y, z = ctx.baseY + 30, ctx.wallZ - 60
	Decor.part(m, "Cable", Vector3.new(400, 0.3, 0.3), Vector3.new(0, y + 4.5, z), rgb(30, 30, 40), Enum.Material.Metal)
	local car: { BasePart } = {
		Decor.part(m, "CableCar", Vector3.new(6, 4, 4), Vector3.new(0, y, z), rgb(220, 60, 60), Enum.Material.Metal),
		Decor.part(
			m,
			"CableCarWindow",
			Vector3.new(5, 1.2, 0.2),
			Vector3.new(0, y + 0.6, z + 2.05),
			rgb(255, 230, 170),
			Enum.Material.Neon
		),
		Decor.part(
			m,
			"CableArm",
			Vector3.new(0.4, 2.6, 0.4),
			Vector3.new(0, y + 3.2, z),
			rgb(30, 30, 40),
			Enum.Material.Metal
		),
	}
	Decor.convoy(car, 9, 400, 0)
end

DRESS.industrial = function(ctx)
	local m = ctx.model
	local frozen = ctx.theme.variant == "frozen"
	-- Tall factory windows in the back wall: night light falling in gives the hall a shape.
	local glass = if frozen then rgb(150, 210, 255) else rgb(120, 150, 190)
	for k = -3, 3 do
		local c = Vector3.new(k * 30, ctx.baseY + 18, ctx.wallZ - 28.8)
		local pane = Decor.part(m, "FactoryWindow", Vector3.new(18, 26, 0.3), c, glass, Enum.Material.Neon)
		pane.Transparency = 0.6
		for _, dx in { -3, 3 } do
			Decor.part(
				m,
				"Mullion",
				Vector3.new(0.8, 26, 0.5),
				c + Vector3.new(dx, 0, 0.3),
				rgb(30, 30, 34),
				Enum.Material.Metal
			)
		end
		Decor.part(
			m,
			"Transom",
			Vector3.new(18, 0.8, 0.5),
			c + Vector3.new(0, 4, 0.3),
			rgb(30, 30, 34),
			Enum.Material.Metal
		)
	end
	-- Ceiling fans turning under the trusses.
	for _, x in { -70, 70 } do
		local hub = Vector3.new(x, ctx.baseY + 36, ctx.wallZ - 12)
		for k = 0, 1 do
			local blade = Decor.part(
				m,
				"FanBlade",
				Vector3.new(16, 0.4, 2),
				CFrame.new(hub) * CFrame.Angles(0, k * math.pi / 2, 0),
				rgb(50, 50, 50),
				Enum.Material.Metal
			)
			Decor.tag(blade, "spin", { speed = 2.5, pivot = hub })
		end
	end
	-- A crane trolley with a hook running along the front truss.
	local y, z, x = ctx.baseY + 38, ctx.wallZ - 6, 64
	Decor.part(
		m,
		"CraneRail",
		Vector3.new(300, 1.4, 1.4),
		Vector3.new(0, y + 2, z),
		rgb(200, 150, 40),
		Enum.Material.Metal
	)
	local trolley: { BasePart } = {
		Decor.part(m, "Trolley", Vector3.new(5, 2.4, 3), Vector3.new(x, y, z), rgb(210, 160, 40), Enum.Material.Metal),
		Decor.part(
			m,
			"HookCable",
			Vector3.new(0.25, 14, 0.25),
			Vector3.new(x, y - 8, z),
			rgb(30, 30, 30),
			Enum.Material.Metal
		),
		Decor.part(m, "Hook", Vector3.new(2, 2, 1), Vector3.new(x, y - 15.5, z), rgb(60, 60, 60), Enum.Material.Metal),
		Decor.part(
			m,
			"TrolleyLight",
			Vector3.new(1, 0.6, 0.2),
			Vector3.new(x, y, z + 1.6),
			rgb(255, 140, 40),
			Enum.Material.Neon
		),
	}
	Decor.convoy(trolley, 8, 220, 0)
	each(ctx, "HangLamp", function(p, i)
		Decor.tag(p, "sway", { amp = 0.06, period = 3, pivot = p.Position + Vector3.new(0, 6, 0), phase = i })
	end)
end

DRESS.foundry = function(ctx)
	local m = ctx.model
	local steel = rgb(30, 24, 22)
	-- Furnaces in the back wall with glowing mouths behind grates.
	for k = -1, 1 do
		local c = Vector3.new(k * 56, ctx.baseY + 2, ctx.wallZ - 36)
		Decor.part(m, "Furnace", Vector3.new(26, 34, 6), c, rgb(44, 34, 30), Enum.Material.Brick)
		local mouth = Decor.part(
			m,
			"FurnaceMouth",
			Vector3.new(14, 10, 0.4),
			c + Vector3.new(0, -6, 3.1),
			ctx.trim,
			Enum.Material.Neon
		)
		Decor.pulse(mouth, 0.25, 1.1 + k * 0.2, k)
		for b = -2, 2 do
			Decor.part(
				m,
				"Grate",
				Vector3.new(0.7, 10, 0.4),
				c + Vector3.new(b * 2.8, -6, 3.5),
				steel,
				Enum.Material.Metal
			)
		end
		Decor.part(m, "FurnaceHood", Vector3.new(30, 3, 9), c + Vector3.new(0, 18, 1), steel, Enum.Material.Metal)
	end
	-- A catwalk with a warning-light edge across the hall.
	Decor.part(
		m,
		"Catwalk",
		Vector3.new(240, 1, 4),
		Vector3.new(0, ctx.baseY + 24, ctx.wallZ - 20),
		steel,
		Enum.Material.DiamondPlate
	)
	Decor.part(
		m,
		"CatwalkEdge",
		Vector3.new(240, 0.3, 0.3),
		Vector3.new(0, ctx.baseY + 24.6, ctx.wallZ - 18),
		ctx.accent,
		Enum.Material.Neon
	).Transparency =
		0.3
	-- Dark girders in front of the glow frame the stage and give the heat a silhouette.
	for _, x in { -84, -52, 52, 84 } do
		Decor.part(
			m,
			"Girder",
			Vector3.new(3, 110, 3),
			Vector3.new(x, ctx.baseY + 5, ctx.wallZ - 14),
			steel,
			Enum.Material.Metal
		)
	end
	Decor.part(
		m,
		"GirderBeam",
		Vector3.new(220, 3, 3),
		Vector3.new(0, ctx.baseY + 42, ctx.wallZ - 14),
		steel,
		Enum.Material.Metal
	)
	for k = -5, 5 do
		Decor.part(
			m,
			"Brace",
			Vector3.new(0.8, 14, 0.8),
			CFrame.new(k * 18, ctx.baseY + 36, ctx.wallZ - 14) * CFrame.Angles(0, 0, if k % 2 == 0 then 0.6 else -0.6),
			steel,
			Enum.Material.Metal
		)
	end
	-- A conveyor of glowing ingots far below.
	local y, z = ctx.baseY - 16, ctx.wallZ - 26
	Decor.part(
		m,
		"Conveyor",
		Vector3.new(300, 1.5, 6),
		Vector3.new(0, y - 1.2, z),
		rgb(40, 34, 32),
		Enum.Material.DiamondPlate
	)
	local ingots: { BasePart } = {}
	for k = 0, 5 do
		table.insert(
			ingots,
			Decor.part(
				m,
				"Ingot",
				Vector3.new(4, 1.6, 3),
				Vector3.new(-150 + k * 50, y, z),
				ctx.accent,
				Enum.Material.Neon
			)
		)
	end
	Decor.convoy(ingots, 10, 300, 0)
	each(ctx, "Pour", function(p, i)
		Decor.pulse(p, 0.25, 0.5, i)
	end)
	each(ctx, "StackGlow", function(p, i)
		Decor.pulse(p, 0.4, 2, i)
	end)
end

DRESS.space = function(ctx)
	local m = ctx.model
	flyer(ctx, 40, ctx.wallZ - 90, rgb(200, 206, 220), ctx.accent, 22, 0)
	flyer(ctx, 20, ctx.wallZ - 140, rgb(160, 166, 190), ctx.trim, -14, 9)
	-- A distant station turning slowly.
	local hub = Vector3.new(90, ctx.baseY + 40, ctx.wallZ - 150)
	Decor.part(m, "StationHub", Vector3.one * 8, hub, rgb(200, 206, 220), Enum.Material.Metal, Enum.PartType.Ball)
	for k = 0, 3 do
		local angle = k * math.pi / 4
		local spoke = Decor.part(
			m,
			"StationSpoke",
			Vector3.new(44, 1.5, 1.5),
			CFrame.new(hub) * CFrame.Angles(0, 0, angle),
			rgb(150, 156, 180),
			Enum.Material.Metal
		)
		Decor.tag(spoke, "spin", { speed = 0.25, axis = Vector3.new(0, 0, 1), pivot = hub })
		local pod = Decor.part(
			m,
			"StationPod",
			Vector3.new(5, 3, 3),
			CFrame.new(hub) * CFrame.Angles(0, 0, angle) * CFrame.new(22, 0, 0),
			if k % 2 == 0 then ctx.trim else ctx.accent,
			Enum.Material.Neon
		)
		Decor.tag(pod, "spin", { speed = 0.25, axis = Vector3.new(0, 0, 1), pivot = hub })
	end
	each(ctx, "RingLight", function(p, i)
		Decor.pulse(p, 0.4, 2, i * 0.2)
	end)
end

DRESS.space_interior = function(ctx)
	flyer(ctx, 22, ctx.wallZ - 50, rgb(220, 226, 240), ctx.trim, 18, 0)
	flyer(ctx, 34, ctx.wallZ - 75, rgb(170, 176, 200), rgb(255, 90, 90), -12, 7)
	each(ctx, "GantryLight", function(p, i)
		Decor.pulse(p, 0.8, 1.4, i * 0.35)
	end)
	each(ctx, "Engine", function(p)
		Decor.pulse(p, 0.3, 0.8)
	end)
end

DRESS.war = function(ctx)
	local m = ctx.model
	local ruins = ctx.theme.variant == "ruins"
	if ruins then
		Decor.skyline(m, {
			from = -260,
			to = 260,
			z = ctx.wallZ - 200,
			baseY = ctx.baseY - 60,
			minHeight = 50,
			maxHeight = 120,
			width = { 16, 30 },
			color = haze(ctx, 0.55),
			seed = 31,
		})
		-- Overgrowth on the broken towers.
		each(ctx, "Ruin", function(p, i)
			if i % 2 == 0 then
				Decor.part(
					m,
					"Overgrowth",
					Vector3.one * 7,
					p.Position + Vector3.new((i % 3 - 1) * 5, p.Size.Y / 2, 4),
					rgb(64, 110, 64),
					Enum.Material.Grass,
					Enum.PartType.Ball
				)
			end
		end)
		-- A broken neon sign that still flickers.
		local board = Decor.part(
			m,
			"BrokenSign",
			Vector3.new(18, 5, 0.4),
			CFrame.new(-26, ctx.baseY + 12, ctx.wallZ - 22) * CFrame.Angles(0, 0, 0.12),
			rgb(10, 12, 14)
		)
		Decor.text(board, Enum.NormalId.Back, "HOTEL", ctx.trim, 10)
		local frame = Decor.part(
			m,
			"BrokenSignFrame",
			Vector3.new(18.6, 5.6, 0.2),
			CFrame.new(-26, ctx.baseY + 12, ctx.wallZ - 22.3) * CFrame.Angles(0, 0, 0.12),
			ctx.trim,
			Enum.Material.Neon
		)
		Decor.pulse(frame, 0.9, 0.35)
		-- A helicopter crossing with its searchlight.
		local y, z = 46, ctx.wallZ - 70
		local c = Vector3.new(0, ctx.baseY + y, z)
		local heli: { BasePart } = {
			Decor.part(m, "HeliBody", Vector3.new(8, 3.4, 3.4), c, rgb(40, 46, 44), Enum.Material.Metal),
			Decor.part(
				m,
				"HeliTail",
				Vector3.new(8, 0.8, 0.8),
				c - Vector3.new(7.5, -0.6, 0),
				rgb(40, 46, 44),
				Enum.Material.Metal
			),
			Decor.part(
				m,
				"HeliRotor",
				Vector3.new(16, 0.2, 0.8),
				c + Vector3.new(0, 2.1, 0),
				rgb(20, 20, 20),
				Enum.Material.Metal
			),
			Decor.part(
				m,
				"HeliLight",
				Vector3.one * 0.8,
				c + Vector3.new(4.2, -1, 0),
				rgb(255, 60, 60),
				Enum.Material.Neon,
				Enum.PartType.Ball
			),
		}
		local beam = Decor.part(
			m,
			"HeliBeam",
			Vector3.new(4, 50, 4),
			CFrame.new(c + Vector3.new(3, -26, 4)) * CFrame.Angles(0, 0, -0.25),
			rgb(255, 250, 220),
			Enum.Material.Neon
		)
		beam.Transparency = 0.86
		table.insert(heli, beam)
		Decor.convoy(heli, 12, 320, 0)
	else
		hills(ctx, ctx.wallZ - 200, -60, haze(ctx, 0.7), 70, 12)
		hills(ctx, ctx.wallZ - 120, -50, rgb(92, 80, 64), 34, 13)
		-- A wrecked tank and a watchtower on the battlefield.
		local tank = CFrame.new(-60, ctx.baseY - 31, ctx.wallZ - 40) * CFrame.Angles(0, 0.3, 0.06)
		local olive = rgb(70, 74, 52)
		Decor.part(m, "TankHull", Vector3.new(16, 4, 9), tank, olive, Enum.Material.Metal)
		Decor.part(
			m,
			"TankTracks",
			Vector3.new(17, 2.4, 10),
			tank * CFrame.new(0, -2.4, 0),
			rgb(40, 38, 34),
			Enum.Material.Metal
		)
		Decor.part(m, "TankTurret", Vector3.new(7, 3, 6), tank * CFrame.new(-1, 3.4, 0), olive, Enum.Material.Metal)
		Decor.part(
			m,
			"TankBarrel",
			Vector3.new(12, 0.9, 0.9),
			tank * CFrame.new(8, 3.6, 0) * CFrame.Angles(0, 0, -0.2),
			olive,
			Enum.Material.Metal
		)
		local tower = Vector3.new(66, ctx.baseY - 34, ctx.wallZ - 46)
		for _, dx in { -3, 3 } do
			for _, dz in { -3, 3 } do
				Decor.part(
					m,
					"TowerLeg",
					Vector3.new(0.8, 26, 0.8),
					tower + Vector3.new(dx, 13, dz),
					rgb(70, 54, 40),
					Enum.Material.Wood
				)
			end
		end
		Decor.part(
			m,
			"TowerHut",
			Vector3.new(9, 6, 9),
			tower + Vector3.new(0, 29, 0),
			rgb(96, 80, 60),
			Enum.Material.WoodPlanks
		)
		Decor.part(
			m,
			"TowerRoof",
			Vector3.new(11, 1, 11),
			tower + Vector3.new(0, 32.5, 0),
			rgb(60, 50, 40),
			Enum.Material.Wood
		)
		Decor.flag(m, Vector3.new(-30, ctx.baseY - 12, ctx.wallZ + 1), 12, rgb(170, 60, 40), 0)
		Decor.flag(m, Vector3.new(42, ctx.baseY - 12, ctx.wallZ + 1), 12, rgb(70, 90, 120), 2)
		flyer(ctx, 50, ctx.wallZ - 110, rgb(70, 74, 64), rgb(255, 200, 120), 26, 0)
		flyer(ctx, 58, ctx.wallZ - 130, rgb(70, 74, 64), rgb(255, 200, 120), 26, 1.2)
	end
	each(ctx, "Fire", function(p, i)
		Decor.pulse(p, 0.3, 0.5, i)
	end)
end

-- Adds the depth layers and moving props for the arena's motif (no-op for unknown motifs).
function ArenaDressing.dress(ctx: Ctx)
	local fn = DRESS[ctx.theme.motif]
	if fn then
		fn(ctx)
	end
end

return ArenaDressing
