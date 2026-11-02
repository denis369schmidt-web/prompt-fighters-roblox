--!strict
-- The lobby players walk around in between matches, far away from the arena: a neon plaza laid out around a
-- central showcase stage.
--
--   north   status screen and title, a gate "ARENA-WAHL" and three arena vote pads with light beacons
--   center  showcase: a turning stage with the featured fighter at full detail (LobbyBuilder.setFeatured)
--   west    leaderboard (LobbyBuilder.setLeaderboard) and the "Halle der Kämpfer" statue row
--   east    Prompt-Terminal spot (anchor part "PromptTerminal", LobbyBuilder.terminalCFrame) and statues
--   south   spawn, training dummies (south-east) and a small lounge (south-west)
--
-- Glowing chevron paths lead from the spawn to every spot, color-coded like the signs (gold = arena vote,
-- magenta = terminal, cyan = leaderboard, green = training). The lobby collides where players walk (floor, walls,
-- pads, pedestals, stage); everything else is anchored decoration without collision, touch or query.
-- Statues are a reduced-detail build of the fighter rigs (no face details or small gear) to keep phones fast.
-- The server owns all signs and changes them with setStatus / setVote / setLeaderboard / setFeatured.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaThemes = require(ReplicatedStorage.Shared.Data.ArenaThemes)
local Arenas = require(ReplicatedStorage.Shared.Data.Arenas)
local Fighters = require(ReplicatedStorage.Shared.Data.Fighters)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local RigBuilder = require(ReplicatedStorage.Shared.Visual.RigBuilder)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)

local Decor = require(script.Parent.Decor)

local LobbyBuilder = {}

local ORIGIN = Visuals.LOBBY_ORIGIN
local SIZE = 180 -- plaza width and depth in studs
local HALF = SIZE / 2
LobbyBuilder.SIZE = SIZE
LobbyBuilder.PAD_RADIUS = 9
LobbyBuilder.PAD_COUNT = 3
LobbyBuilder.LEADERBOARD_ROWS = 8
LobbyBuilder.DEFAULT_FEATURED = "phoenix"
-- Part budget the tests hold the lobby to (statues are the expensive part).
LobbyBuilder.PART_BUDGET = 1500

local PAD_Z = -52
local PAD_SPACING = 40
local SHOWCASE_Z = -6
local SHOWCASE_RADIUS = 11
local SPAWN_Z = 66
local STATUE_SCALE = 1.4
-- Statue parts whose largest side (before scaling) is below this are left out; eyes stay so faces keep life.
local STATUE_MIN_SIZE = 0.75
local STATUE_KEEP = { EyeWhite = true, Pupil = true, Eye = true, EyeGlow = true, SkullEyes = true, SkullEye = true }

local CYAN = Color3.fromRGB(0, 240, 255)
local MAGENTA = Color3.fromRGB(255, 40, 200)
local GOLD = Color3.fromRGB(255, 210, 60)
local GREEN = Color3.fromRGB(80, 255, 140)
local INK = Color3.fromRGB(8, 6, 16)
local STEEL = Color3.fromRGB(40, 36, 60)
local FLOOR = Color3.fromRGB(26, 22, 44)
local WHITE = Color3.new(1, 1, 1)

type Pad = { part: BasePart, ring: BasePart, beacon: BasePart, frame: BasePart, name: TextLabel, votes: TextLabel }
type Row = { rank: TextLabel, name: TextLabel, value: TextLabel }

local model: Model? = nil
local statusLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local pads: { Pad } = {}
local boardRows: { Row } = {}
local boardTitle: TextLabel? = nil
local showcase: Model? = nil
local featuredLabel: TextLabel? = nil
local featuredId: string? = nil
local terminalAnchor: BasePart? = nil

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Upright CFrame at `position` looking along the flat direction toward `target`. Built from a yaw instead of
-- CFrame.lookAt so it comes out the same in Roblox and in the headless preview (Lune's lookAt mirrors Z).
local function facing(position: Vector3, target: Vector3): CFrame
	local dx, dz = target.X - position.X, target.Z - position.Z
	return CFrame.new(position) * CFrame.Angles(0, math.atan2(-dx, -dz), 0)
end

-- A plain lobby part; `collide` marks the ones players stand on or bump into.
local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame | Vector3,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	local p = Decor.part(parent, name, size, cframe, color, material)
	if collide then
		p.CanCollide = true
		p.CanQuery = true
		p.CastShadow = material ~= Enum.Material.Neon
	end
	return p
end

local function disc(
	parent: Instance,
	name: string,
	radius: number,
	height: number,
	center: Vector3,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	local p = part(
		parent,
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		collide
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A board with a neon frame behind it, facing `toward` (text on its Front face).
local function board(parent: Instance, name: string, size: Vector3, center: Vector3, toward: Vector3, frame: Color3): (Part, Part)
	local look = facing(center, toward)
	local b = part(parent, name, size, look, INK)
	local f = part(
		parent,
		name .. "Frame",
		size + Vector3.new(0.8, 0.8, -size.Z + 0.2),
		look * CFrame.new(0, 0, size.Z / 2 + 0.15),
		frame,
		Enum.Material.Neon
	)
	return b, f
end

--------------------------------------------------------------------------------------------------------------------
-- Fighters: reduced-detail statues and the full-detail showcase fighter
--------------------------------------------------------------------------------------------------------------------

-- Builds a fighter rig, frozen and scaled around its root to stand at `base` looking along `facing`.
-- minSize > 0 drops small detail parts (and every invisible bone), so only what reads from afar stays.
local function frozenFighter(fighterId: string, base: Vector3, look: Vector3, scale: number, minSize: number): Model
	local rig = RigBuilder.build(fighterId)
	local root = rig.PrimaryPart :: BasePart
	local stand = rig:GetAttribute("StandHeight") :: number
	local target =
		facing(base + Vector3.new(0, stand * scale, 0), base + Vector3.new(look.X, 0, look.Z))
	local rootCFrame = root.CFrame
	local out = Instance.new("Model")
	out.Name = fighterId
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			local size = d.Size
			local keep = d.Transparency < 1
				and (math.max(size.X, size.Y, size.Z) >= minSize or minSize <= 0 or STATUE_KEEP[d.Name] == true)
			if keep then
				local rel = rootCFrame:ToObjectSpace(d.CFrame)
				d.Size = size * scale
				d.CFrame = target * CFrame.new(rel.Position * scale) * (rel - rel.Position)
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Parent = out
			end
		end
	end
	for _, d in out:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	rig:Destroy()
	out:SetAttribute("Glow", Looks.get(fighterId).glow)
	return out
end

local function statue(parent: Instance, fighterId: string, position: Vector3, look: Vector3, lit: boolean)
	local glow = Color3.fromHex(Looks.get(fighterId).glow)
	part(parent, "Pedestal", Vector3.new(8, 3, 8), position + Vector3.new(0, 1.5, 0), Color3.fromRGB(30, 26, 48), Enum.Material.Marble, true)
	local rim = part(parent, "PedestalGlow", Vector3.new(8.3, 0.4, 8.3), position + Vector3.new(0, 2.5, 0), glow, Enum.Material.Neon)
	if lit then
		Decor.light(rim, glow, 16, 1.2)
	end
	local figure = frozenFighter(fighterId, position + Vector3.new(0, 3.2, 0), look, STATUE_SCALE, STATUE_MIN_SIZE)
	figure.Name = "Statue_" .. fighterId
	figure.Parent = parent
	local plateCenter = position + Vector3.new(0, 1.5, 0) + look.Unit * 4.25
	local plate = part(
		parent,
		"NamePlate",
		Vector3.new(7.6, 1.6, 0.4),
		facing(plateCenter, plateCenter + look),
		INK
	)
	Decor.text(plate, Enum.NormalId.Front, Fighters.get(fighterId).name, glow, 20)
end

-- Puts `fighterId` on the turning showcase stage (replacing the one before).
local function placeFeatured(fighterId: string)
	local m = model
	if m == nil then
		return
	end
	if showcase then
		showcase:Destroy()
	end
	local center = at(0, 0, SHOWCASE_Z)
	local figure = frozenFighter(fighterId, center + Vector3.new(0, 2.6, 0), Vector3.new(0, 0, 1), 1.8, 0)
	figure.Name = "Featured_" .. fighterId
	-- Turns with the stage; the client animator moves it, the server never does.
	for _, d in figure:GetDescendants() do
		if d:IsA("BasePart") then
			Decor.tag(d, "spin", { speed = 0.45, pivot = center })
		end
	end
	figure.Parent = m
	showcase = figure
	featuredId = fighterId
	if featuredLabel then
		local label = featuredLabel :: TextLabel
		label.Text = Fighters.get(fighterId).name
		label.TextColor3 = Color3.fromHex(Looks.get(fighterId).glow)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Layout pieces
--------------------------------------------------------------------------------------------------------------------

-- A glowing path on the floor from `a` to `b` (plaza x/z): two edge lines and chevrons that light up one after
-- the other toward `b`, so the floor itself points the way.
local function path(m: Instance, a: Vector2, b: Vector2, color: Color3, width: number?)
	local w = width or 4.4
	local from, to = at(a.X, 0.04, a.Y), at(b.X, 0.04, b.Y)
	local length = (to - from).Magnitude
	local frame = facing(from, to)
	for _, side in { -1, 1 } do
		local edge = part(
			m,
			"PathEdge",
			Vector3.new(0.35, 0.08, length),
			frame * CFrame.new(side * w / 2, 0, -length / 2),
			color,
			Enum.Material.Neon
		)
		edge.Transparency = 0.35
	end
	local count = math.max(1, math.floor(length / 6))
	for i = 1, count do
		local along = frame * CFrame.new(0, 0.02, -(i - 0.5) * length / count)
		for _, side in { -1, 1 } do
			local bar = part(
				m,
				"PathChevron",
				Vector3.new(0.5, 0.08, w * 0.55),
				along * CFrame.Angles(0, side * math.rad(50), 0) * CFrame.new(0, 0, w * 0.2),
				color,
				Enum.Material.Neon
			)
			bar.Transparency = 0.15
			-- Running light: each chevron lags the previous one, so the glow travels toward the target.
			Decor.pulse(bar, 0.75, 1.6, -i * 0.22)
		end
	end
end

-- A sign on two posts, facing `toward`.
local function signpost(m: Instance, text: string, center: Vector3, toward: Vector3, color: Color3, width: number)
	local b = board(m, "Sign", Vector3.new(width, 4, 0.4), center, toward, color)
	Decor.text(b, Enum.NormalId.Front, text, color, 10, { 0.03, 0.08, 0.94, 0.84 })
	for _, side in { -1, 1 } do
		local look = facing(center, toward)
		local foot = look * CFrame.new(side * (width / 2 - 0.6), 0, 0)
		part(
			m,
			"SignPost",
			Vector3.new(0.5, center.Y - ORIGIN.Y - 2, 0.5),
			foot.Position - Vector3.new(0, (center.Y - ORIGIN.Y) / 2 + 1, 0),
			STEEL,
			Enum.Material.Metal,
			true
		)
	end
end

-- Big text lying on the floor (readable from above and when walking toward -Z).
local function floorText(m: Instance, text: string, center: Vector3, size: Vector2, color: Color3)
	local p = part(m, "FloorText", Vector3.new(size.X, 0.1, size.Y), center, FLOOR)
	p.Transparency = 0.999 -- only the text shows, the floor below stays
	Decor.text(p, Enum.NormalId.Top, text, color, 8)
end

local function lamp(m: Instance, x: number, z: number, color: Color3)
	local foot = at(x, 0, z)
	part(m, "LampPost", Vector3.new(0.8, 14, 0.8), foot + Vector3.new(0, 7, 0), STEEL, Enum.Material.Metal, true)
	local bulb = part(m, "LampBulb", Vector3.new(2, 0.8, 2), foot + Vector3.new(0, 14.4, 0), color, Enum.Material.Neon)
	Decor.light(bulb, color, 34, 1.2)
end

local function buildFloor(m: Model)
	local floor = part(m, "Floor", Vector3.new(SIZE, 2, SIZE), at(0, -1, 0), FLOOR, Enum.Material.Slate, true)
	floor.Reflectance = 0.12
	-- A faint grid, and tinted zones so every area reads from above.
	for k = -2, 2 do
		for _, along in { true, false } do
			local seam = part(
				m,
				"Seam",
				if along then Vector3.new(SIZE, 0.06, 0.3) else Vector3.new(0.3, 0.06, SIZE),
				if along then at(0, 0.02, k * 36) else at(k * 36, 0.02, 0),
				Color3.fromRGB(60, 50, 100),
				Enum.Material.Neon
			)
			seam.Transparency = 0.75
		end
	end
	part(m, "VoteZone", Vector3.new(128, 0.06, 34), at(0, 0.03, PAD_Z + 2), Color3.fromRGB(46, 36, 30), Enum.Material.Slate)
	disc(m, "Hub", SHOWCASE_RADIUS + 9, 0.06, at(0, 0.03, SHOWCASE_Z), Color3.fromRGB(36, 28, 62), Enum.Material.Slate)
	local hubRing = disc(m, "HubRing", SHOWCASE_RADIUS + 9.6, 0.05, at(0, 0.02, SHOWCASE_Z), MAGENTA, Enum.Material.Neon)
	hubRing.Transparency = 0.4
	part(m, "TrainingZone", Vector3.new(36, 0.06, 28), at(56, 0.03, 66), Color3.fromRGB(26, 46, 40), Enum.Material.Slate)
end

local function buildWalls(m: Model)
	-- Invisible walls and a low neon rail so nobody walks off the plaza.
	for _, side in { { 0, -HALF }, { 0, HALF }, { -HALF, 0 }, { HALF, 0 } } do
		local alongX = side[2] ~= 0
		local wall = part(
			m,
			"Wall",
			if alongX then Vector3.new(SIZE, 40, 2) else Vector3.new(2, 40, SIZE),
			at(side[1], 20, side[2]),
			Color3.new(0, 0, 0),
			nil,
			true
		)
		wall.Transparency = 1
		part(
			m,
			"Rail",
			if alongX then Vector3.new(SIZE, 0.4, 0.4) else Vector3.new(0.4, 0.4, SIZE),
			at(side[1], 3, side[2]),
			CYAN,
			Enum.Material.Neon
		)
		part(
			m,
			"Curb",
			if alongX then Vector3.new(SIZE, 1.4, 1.2) else Vector3.new(1.2, 1.4, SIZE),
			at(side[1], 0.7, side[2]),
			STEEL,
			Enum.Material.Metal,
			true
		)
	end
end

local function buildStatusBoard(m: Model)
	local z = -HALF + 4
	local screen = part(m, "StatusBoard", Vector3.new(60, 20, 1), at(0, 32, z), INK)
	part(m, "StatusFrame", Vector3.new(62, 22, 0.6), at(0, 32, z - 0.6), CYAN, Enum.Material.Neon)
	Decor.light(screen, CYAN, 40, 1.5)
	statusLabel = Decor.text(screen, Enum.NormalId.Back, "WÄHLE DEINEN KÄMPFER", GOLD, 10, { 0, 0.08, 1, 0.55 })
	subLabel = Decor.text(
		screen,
		Enum.NormalId.Back,
		"Stell dich auf ein Feld, um die Arena zu wählen",
		WHITE,
		10,
		{ 0.02, 0.66, 0.96, 0.25 }
	)
	for _, leg in { -26, 26 } do
		part(m, "BoardLeg", Vector3.new(2, 22, 2), at(leg, 11, z), STEEL, Enum.Material.Metal, true)
	end
	local title = part(m, "Title", Vector3.new(70, 9, 1), at(0, 48, z), INK)
	Decor.text(title, Enum.NormalId.Back, "PROMPT FIGHTERS", MAGENTA, 8)
	Decor.light(title, MAGENTA, 40, 2)
	local underline = part(m, "TitleGlow", Vector3.new(66, 0.6, 0.6), at(0, 43.2, z + 0.8), MAGENTA, Enum.Material.Neon)
	Decor.pulse(underline, 0.4, 2.4)
end

local function buildVoteArea(m: Model)
	-- A gate over the way north: everyone walking up from the spawn sees where the vote is.
	local gateZ = PAD_Z + 26
	for _, x in { -60, 60 } do
		part(m, "GatePillar", Vector3.new(3, 15, 3), at(x, 7.5, gateZ), STEEL, Enum.Material.Metal, true)
		part(m, "GatePillarGlow", Vector3.new(3.4, 15, 0.4), at(x, 7.5, gateZ + 1.6), GOLD, Enum.Material.Neon).Transparency =
			0.3
	end
	local gate = part(m, "GateBeam", Vector3.new(123, 2.4, 2.4), at(0, 16, gateZ), STEEL, Enum.Material.Metal)
	local gateSign = part(m, "GateSign", Vector3.new(40, 6, 0.6), at(0, 16, gateZ + 1.6), INK)
	Decor.text(gateSign, Enum.NormalId.Back, "ARENA-WAHL", GOLD, 8, { 0.03, 0.05, 0.94, 0.9 })
	part(m, "GateSignFrame", Vector3.new(41, 7, 0.3), at(0, 16, gateZ + 1.2), GOLD, Enum.Material.Neon)
	Decor.light(gate, GOLD, 30, 1)
	floorText(m, "ARENA-WAHL", at(0, 0.1, gateZ - 6), Vector2.new(34, 7), GOLD)

	table.clear(pads)
	for k = 1, LobbyBuilder.PAD_COUNT do
		local x = (k - 2) * PAD_SPACING
		local center = at(x, 0.3, PAD_Z)
		local padPart = disc(m, "VotePad" .. k, LobbyBuilder.PAD_RADIUS, 0.6, center, Color3.fromRGB(40, 34, 70), Enum.Material.Glass, true)
		local padRing = disc(
			m,
			"VoteRing" .. k,
			LobbyBuilder.PAD_RADIUS + 0.7,
			0.5,
			center - Vector3.new(0, 0.1, 0),
			CYAN,
			Enum.Material.Neon
		)
		Decor.light(padRing, CYAN, 18, 1)
		-- A light beacon above each pad, visible from everywhere in the lobby (and from above).
		local beacon = disc(m, "VoteBeacon" .. k, 2.2, 60, center + Vector3.new(0, 30.3, 0), CYAN, Enum.Material.Neon)
		beacon.Transparency = 0.6
		Decor.pulse(beacon, 0.3, 2.4, k)
		local signCenter = center + Vector3.new(0, 13, -LobbyBuilder.PAD_RADIUS - 2)
		local sign, frame = board(m, "VoteSign" .. k, Vector3.new(22, 8, 0.5), signCenter, signCenter + Vector3.new(0, 0, 10), CYAN)
		for _, side in { -1, 1 } do
			part(
				m,
				"VotePole" .. k,
				Vector3.new(0.8, 9, 0.8),
				signCenter + Vector3.new(side * 9, -8.5, -0.3),
				STEEL,
				Enum.Material.Metal,
				true
			)
		end
		local nameLabel = Decor.text(sign, Enum.NormalId.Front, "", WHITE, 14, { 0.02, 0.05, 0.96, 0.55 })
		local votesLabel = Decor.text(sign, Enum.NormalId.Front, "", GOLD, 14, { 0.05, 0.63, 0.9, 0.32 })
		pads[k] = { part = padPart, ring = padRing, beacon = beacon, frame = frame, name = nameLabel, votes = votesLabel }
	end
end

local function buildShowcase(m: Model)
	local center = at(0, 0, SHOWCASE_Z)
	disc(m, "ShowcaseDais", SHOWCASE_RADIUS, 1.2, center + Vector3.new(0, 0.6, 0), Color3.fromRGB(30, 26, 48), Enum.Material.Marble, true)
	disc(m, "ShowcaseStep", SHOWCASE_RADIUS + 1.6, 0.6, center + Vector3.new(0, 0.3, 0), STEEL, Enum.Material.Metal, true)
	local rim = disc(m, "ShowcaseRim", SHOWCASE_RADIUS + 0.3, 0.3, center + Vector3.new(0, 0.95, 0), GOLD, Enum.Material.Neon)
	Decor.pulse(rim, 0.3, 2)
	local table_ = disc(m, "Turntable", 6.5, 1.4, center + Vector3.new(0, 1.9, 0), Color3.fromRGB(18, 16, 30), Enum.Material.Metal, true)
	local stripe = part(m, "TurntableStripe", Vector3.new(12.6, 0.1, 0.6), center + Vector3.new(0, 2.62, 0), CYAN, Enum.Material.Neon)
	Decor.tag(stripe, "spin", { speed = 0.45, pivot = center })
	Decor.light(table_, Color3.fromRGB(255, 230, 200), 26, 2)
	-- Four light pillars and a halo ring hovering above the fighter.
	for k = 0, 3 do
		local angle = k * math.pi / 2 + math.pi / 4
		local foot = center + Vector3.new(math.cos(angle) * (SHOWCASE_RADIUS + 3), 0, math.sin(angle) * (SHOWCASE_RADIUS + 3))
		part(m, "ShowcasePillar", Vector3.new(0.9, 9, 0.9), foot + Vector3.new(0, 4.5, 0), STEEL, Enum.Material.Metal, true)
		local cap = part(m, "ShowcasePillarGlow", Vector3.new(1.3, 1, 1.3), foot + Vector3.new(0, 9.5, 0), MAGENTA, Enum.Material.Neon)
		Decor.pulse(cap, 0.5, 1.8, k * 0.45)
	end
	local haloCenter = center + Vector3.new(0, 18, 0)
	for k = 0, 9 do
		local angle = k * math.pi / 5
		local seg = part(
			m,
			"Halo",
			Vector3.new(4.4, 0.4, 0.4),
			CFrame.new(haloCenter) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -6.8),
			if k % 2 == 0 then CYAN else MAGENTA,
			Enum.Material.Neon
		)
		Decor.tag(seg, "spin", { speed = -0.8, pivot = haloCenter })
	end
	-- Name sign above, readable from the spawn side (front) and from the vote side (back).
	local signCenter = center + Vector3.new(0, 22, 0)
	for _, dir in { 1, -1 } do
		local face = signCenter + Vector3.new(0, 0, dir * 0.35)
		local sign = part(m, "ShowcaseSign", Vector3.new(22, 5.5, 0.3), facing(face, face + Vector3.new(0, 0, dir)), INK)
		Decor.text(sign, Enum.NormalId.Front, "IM RAMPENLICHT", GOLD, 10, { 0.05, 0.04, 0.9, 0.36 })
		local label = Decor.text(sign, Enum.NormalId.Front, "", WHITE, 10, { 0.03, 0.42, 0.94, 0.54 })
		if dir == 1 then
			featuredLabel = label
		else
			label.Name = "FeaturedNameBack"
		end
		Decor.tag(sign, "bob", { amp = 0.5, period = 4 })
	end
	part(m, "ShowcaseSignFrame", Vector3.new(22.8, 6.2, 0.4), signCenter, GOLD, Enum.Material.Neon).Transparency = 0.5
	-- Sparkles drifting up around the stage.
	local emitterHolder = part(m, "ShowcaseSparkles", Vector3.new(16, 1, 16), center + Vector3.new(0, 3, 0), INK)
	emitterHolder.Transparency = 1
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Shape = Enum.ParticleEmitterShape.Box
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Rate = 14
	sparkles.Lifetime = NumberRange.new(3, 5)
	sparkles.Speed = NumberRange.new(1.5, 3)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Color = ColorSequence.new(GOLD, CYAN)
	sparkles.LightEmission = 1
	sparkles.Parent = emitterHolder
end

local function buildLeaderboard(m: Model)
	local center = at(-50, 12, 26)
	local toward = at(0, 12, 46)
	local b = board(m, "Leaderboard", Vector3.new(26, 18, 0.6), center, toward, CYAN)
	boardTitle = Decor.text(b, Enum.NormalId.Front, "BESTENLISTE", CYAN, 12, { 0.04, 0.03, 0.92, 0.13 })
	table.clear(boardRows)
	local rows = LobbyBuilder.LEADERBOARD_ROWS
	local rowHeight = 0.8 / rows
	for i = 1, rows do
		local y = 0.18 + (i - 1) * rowHeight
		local color = if i == 1 then GOLD elseif i <= 3 then Color3.fromRGB(220, 226, 240) else Color3.fromRGB(170, 176, 200)
		boardRows[i] = {
			rank = Decor.text(b, Enum.NormalId.Front, `{i}.`, color, 12, { 0.04, y, 0.1, rowHeight * 0.8 }),
			name = Decor.text(b, Enum.NormalId.Front, "—", color, 12, { 0.16, y, 0.56, rowHeight * 0.8 }),
			value = Decor.text(b, Enum.NormalId.Front, "", color, 12, { 0.74, y, 0.22, rowHeight * 0.8 }),
		}
		boardRows[i].name.TextXAlignment = Enum.TextXAlignment.Left
		boardRows[i].value.TextXAlignment = Enum.TextXAlignment.Right
	end
	local look = facing(center, toward)
	for _, side in { -1, 1 } do
		local foot = (look * CFrame.new(side * 10, 0, 0.6)).Position
		part(m, "LeaderboardLeg", Vector3.new(1.2, 12, 1.2), Vector3.new(foot.X, ORIGIN.Y + 6, foot.Z), STEEL, Enum.Material.Metal, true)
	end
	local crown = part(m, "LeaderboardCrown", Vector3.new(4, 2, 0.4), look * CFrame.new(0, 10.6, 0), GOLD, Enum.Material.Neon)
	Decor.tag(crown, "bob", { amp = 0.3, period = 2.5 })
end

local function buildTerminal(m: Model)
	local foot = at(50, 0, 26)
	local toward = at(0, 0, 46)
	local look = facing(foot, toward)
	disc(m, "TerminalBase", 6, 0.6, foot + Vector3.new(0, 0.3, 0), STEEL, Enum.Material.Metal, true)
	local ring = disc(m, "TerminalRing", 6.6, 0.4, foot + Vector3.new(0, 0.2, 0), MAGENTA, Enum.Material.Neon)
	Decor.pulse(ring, 0.4, 1.6)
	part(m, "TerminalConsole", Vector3.new(6, 4, 2.6), look * CFrame.new(0, 2.6, 0) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(30, 26, 48), Enum.Material.Metal, true)
	part(m, "TerminalKeys", Vector3.new(5, 0.2, 1.6), look * CFrame.new(0, 4.65, -0.3) * CFrame.Angles(math.rad(-12), 0, 0), CYAN, Enum.Material.Neon).Transparency =
		0.3
	-- A floating holo screen behind the console.
	local screen = part(m, "TerminalScreen", Vector3.new(14, 8, 0.3), look * CFrame.new(0, 11, 2.5), INK)
	Decor.text(screen, Enum.NormalId.Front, "PROMPT-TERMINAL", MAGENTA, 12, { 0.04, 0.08, 0.92, 0.42 })
	Decor.text(screen, Enum.NormalId.Front, "Beschreibe deinen Kämpfer", WHITE, 12, { 0.06, 0.58, 0.88, 0.3 })
	local screenFrame = part(m, "TerminalScreenFrame", Vector3.new(14.8, 8.8, 0.2), look * CFrame.new(0, 11, 2.75), MAGENTA, Enum.Material.Neon)
	Decor.tag(screen, "bob", { amp = 0.35, period = 3.2 })
	Decor.tag(screenFrame, "bob", { amp = 0.35, period = 3.2 })
	Decor.light(screenFrame, MAGENTA, 24, 1.5)
	-- The hook for the prompt UI: an invisible anchor where a player stands, facing the console. Another system
	-- parents its ProximityPrompt to this part (or to its PromptAttachment).
	local anchor = part(m, "PromptTerminal", Vector3.new(4, 5, 2), look * CFrame.new(0, 2.5, -4) * CFrame.Angles(0, math.pi, 0), INK)
	anchor.Transparency = 1
	anchor:SetAttribute("Purpose", "PromptTerminal")
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAttachment"
	attachment.Parent = anchor
	terminalAnchor = anchor
end

local function buildTraining(m: Model)
	signpost(m, "TRAINING", at(56, 9, 50), at(0, 9, 46), GREEN, 16)
	for k = 0, 2 do
		local foot = at(44 + k * 12, 0, 70)
		part(m, "DummyPost", Vector3.new(0.8, 3, 0.8), foot + Vector3.new(0, 1.5, 0), Color3.fromRGB(110, 80, 50), Enum.Material.Wood, true)
		local body = part(
			m,
			"DummyBody",
			Vector3.new(4, 2.4, 2.4),
			CFrame.new(foot + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(196, 160, 110),
			Enum.Material.Fabric,
			true
		)
		body.Shape = Enum.PartType.Cylinder
		local head = part(m, "DummyHead", Vector3.one * 2, foot + Vector3.new(0, 7.4, 0), Color3.fromRGB(196, 160, 110), Enum.Material.Fabric, true)
		head.Shape = Enum.PartType.Ball
		part(m, "DummyTarget", Vector3.new(1.8, 1.8, 0.1), foot + Vector3.new(0, 4.6, -1.25), Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
	end
end

local function buildLounge(m: Model)
	-- Benches around a small holo fountain in the south-west.
	local center = at(-52, 0, 66)
	disc(m, "FountainBasin", 6, 1.2, center + Vector3.new(0, 0.6, 0), STEEL, Enum.Material.Marble, true)
	disc(m, "FountainWater", 5.2, 0.2, center + Vector3.new(0, 1.15, 0), Color3.fromRGB(40, 120, 170), Enum.Material.Glass)
	disc(m, "FountainRim", 6.2, 0.3, center + Vector3.new(0, 1, 0), CYAN, Enum.Material.Neon)
	local jet = part(m, "FountainJet", Vector3.new(1.2, 6, 1.2), center + Vector3.new(0, 4, 0), Color3.fromRGB(150, 230, 255), Enum.Material.Neon)
	jet.Transparency = 0.5
	Decor.tag(jet, "bob", { amp = 0.6, period = 1.4 })
	for k = 0, 3 do
		local angle = k * math.pi / 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local spot = center + dir * 11 + Vector3.new(0, 0.9, 0)
		part(m, "Bench", Vector3.new(7, 1, 2.2), facing(spot, spot + dir), Color3.fromRGB(110, 80, 60), Enum.Material.WoodPlanks, true)
	end
end

-- Flags on tall poles in the corners and along the north wall, swaying.
local function buildBanners(m: Model)
	local colors = { MAGENTA, CYAN, GOLD, GREEN }
	local spots = { { -84, -84 }, { 84, -84 }, { -84, 84 }, { 84, 84 }, { -40, -84 }, { 40, -84 } }
	for i, s in spots do
		Decor.flag(m, at(s[1], 0, s[2]), 24, colors[(i - 1) % #colors + 1], i * 0.7)
	end
end

-- Neon towers all around outside the plaza, so the lobby sits in a city instead of a void.
local function buildSkyline(m: Model)
	local sides = {
		{ CFrame.new(ORIGIN + Vector3.new(0, 0, -HALF - 70)), 260 },
		{ CFrame.new(ORIGIN + Vector3.new(-HALF - 70, 0, 0)) * CFrame.Angles(0, -math.pi / 2, 0), 220 },
		{ CFrame.new(ORIGIN + Vector3.new(HALF + 70, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0), 220 },
	}
	for i, side in sides do
		Decor.skyline(m, {
			from = -side[2] / 2,
			to = side[2] / 2,
			z = 0,
			baseY = -60,
			minHeight = 70,
			maxHeight = 150,
			width = { 16, 28 },
			color = Color3.fromRGB(18, 14, 36),
			windows = if i == 1 then MAGENTA:Lerp(INK, 0.3) else CYAN:Lerp(INK, 0.35),
			roof = if i == 1 then CYAN else MAGENTA,
			frame = side[1],
			seed = 40 + i,
		})
	end
end

--------------------------------------------------------------------------------------------------------------------

-- Builds the lobby once at server start.
function LobbyBuilder.build(): Model
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "Lobby"
	model = m
	showcase = nil

	buildFloor(m)
	buildWalls(m)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = facing(at(0, 0.5, SPAWN_Z), at(0, 0.5, SPAWN_Z - 10))
	spawn.Color = FLOOR
	spawn.Material = Enum.Material.Slate
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = m
	disc(m, "SpawnRing", 6, 0.05, at(0, 0.03, SPAWN_Z), CYAN, Enum.Material.Neon)
	disc(m, "SpawnDisc", 5.3, 0.07, at(0, 0.04, SPAWN_Z), FLOOR, Enum.Material.Slate)

	buildStatusBoard(m)
	buildVoteArea(m)
	buildShowcase(m)
	buildLeaderboard(m)
	buildTerminal(m)
	buildTraining(m)
	buildLounge(m)
	buildBanners(m)
	buildSkyline(m)

	-- Wayfinding: from the spawn to the hub, from the hub to every pad and to each side spot.
	local hubEdge = SHOWCASE_RADIUS + 9
	path(m, Vector2.new(0, SPAWN_Z - 7), Vector2.new(0, SHOWCASE_Z + hubEdge), CYAN)
	for k = 1, LobbyBuilder.PAD_COUNT do
		local x = (k - 2) * PAD_SPACING
		local target = Vector2.new(x, PAD_Z + LobbyBuilder.PAD_RADIUS + 1.5)
		local start = Vector2.new(0, SHOWCASE_Z) + (target - Vector2.new(0, SHOWCASE_Z)).Unit * hubEdge
		path(m, start, target, GOLD)
	end
	path(m, Vector2.new(-8, 40), Vector2.new(-40, 30), CYAN, 3.6)
	path(m, Vector2.new(8, 40), Vector2.new(40, 30), MAGENTA, 3.6)
	path(m, Vector2.new(8, 52), Vector2.new(40, 62), GREEN, 3.6)
	signpost(m, "← BESTENLISTE", at(-14, 6, 46), at(-14, 6, 80), CYAN, 15)
	signpost(m, "PROMPT-TERMINAL →", at(14, 6, 46), at(14, 6, 80), MAGENTA, 17)

	-- The launch roster as statues facing the middle: the "Halle der Kämpfer" along both side walls.
	for i, fighterId in Visuals.SLICE_FIGHTERS do
		local west = i <= 8
		local row = (i - 1) % 8
		local x = if west then -HALF + 10 else HALF - 10
		local z = -42 + row * 14
		statue(m, fighterId, at(x, 0, z), Vector3.new(if west then 1 else -1, 0, 0), row % 2 == 0)
	end
	signpost(m, "HALLE DER KÄMPFER", at(-HALF + 22, 7, -56), at(0, 7, -56), CYAN, 20)
	signpost(m, "HALLE DER KÄMPFER", at(HALF - 22, 7, -56), at(0, 7, -56), CYAN, 20)

	for _, spot in { { -24, 30 }, { 24, 30 }, { -24, -30 }, { 24, -30 }, { -70, 50 }, { 70, 40 } } do
		lamp(m, spot[1], spot[2], Color3.fromRGB(255, 220, 170))
	end
	for _, x in { -50, 0, 50 } do
		local holder = part(m, "FillLight", Vector3.one, at(x, 30, 20), WHITE)
		holder.Transparency = 1
		Decor.light(holder, Color3.fromRGB(220, 210, 255), 70, 1.2)
	end

	placeFeatured(featuredId or LobbyBuilder.DEFAULT_FEATURED)
	Decor.finalize(m, {
		solid = function(p)
			return p.CanCollide
		end,
		shadowMin = 2.5,
	})
	m.Parent = workspace
	return m
end

-- World position of a vote pad's center (top surface).
function LobbyBuilder.padCenter(index: number): Vector3?
	local pad = pads[index]
	return if pad then pad.part.CFrame.Position + Vector3.new(0, 0.3, 0) else nil
end

-- Which pad (1..PAD_COUNT) a world position stands on, or nil.
function LobbyBuilder.padAt(position: Vector3): number?
	for k, pad in pads do
		local center = pad.part.CFrame.Position
		local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
		if flat.Magnitude <= LobbyBuilder.PAD_RADIUS and math.abs(position.Y - center.Y) < 8 then
			return k
		end
	end
	return nil
end

function LobbyBuilder.setStatus(title: string, sub: string)
	if statusLabel then
		statusLabel.Text = title
	end
	if subLabel then
		subLabel.Text = sub
	end
end

-- Shows an arena option and its votes on pad `index`; the leading pad glows gold.
function LobbyBuilder.setVote(index: number, arenaId: string, votes: number, leading: boolean)
	local pad = pads[index]
	if pad == nil then
		return
	end
	local info = Arenas.byId[arenaId]
	local theme = ArenaThemes[arenaId]
	local color = if theme then Color3.fromHex(theme.trim) else CYAN
	pad.name.Text = if info then info.name else arenaId
	pad.name.TextColor3 = if theme then color else WHITE
	pad.votes.Text = if votes == 1 then "1 STIMME" else `{votes} STIMMEN`
	pad.ring.Color = if leading then GOLD else color
	pad.beacon.Color = if leading then GOLD else color
	pad.frame.Color = color
end

export type LeaderboardRow = { name: string, value: (string | number)? }

-- Fills the leaderboard (best first; missing rows show a dash). `title` replaces "BESTENLISTE".
function LobbyBuilder.setLeaderboard(rows: { LeaderboardRow }, title: string?)
	if title and boardTitle then
		boardTitle.Text = title
	end
	for i, row in boardRows do
		local entry = rows[i]
		row.name.Text = if entry then entry.name else "—"
		row.value.Text = if entry and entry.value ~= nil then tostring(entry.value) else ""
	end
end

-- Puts a fighter on the showcase stage (e.g. the featured fighter of the day or the last winner).
function LobbyBuilder.setFeatured(fighterId: string)
	featuredId = fighterId
	placeFeatured(fighterId)
end

function LobbyBuilder.featured(): string?
	return featuredId
end

-- Where the Prompt-Terminal's player spot is: position and facing (toward the console). The anchor part
-- "PromptTerminal" in the lobby model sits exactly there and carries a "PromptAttachment" for a ProximityPrompt.
function LobbyBuilder.terminalCFrame(): CFrame?
	return if terminalAnchor then terminalAnchor.CFrame else nil
end

function LobbyBuilder.terminal(): BasePart?
	return terminalAnchor
end

function LobbyBuilder.model(): Model?
	return model
end

return LobbyBuilder
