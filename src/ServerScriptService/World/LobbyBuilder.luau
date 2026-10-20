--!strict
-- The lobby players walk around in between matches, far away from the arena: a neon plaza with a spawn, three
-- arena vote pads, a big status screen, and the 16 launch fighters as statues on pedestals.
-- Unlike the arena, the lobby collides (players stand and walk on it). The server owns all signs and changes them
-- with LobbyBuilder.setStatus / setVote, so every player sees the same countdown and votes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaThemes = require(ReplicatedStorage.Shared.Data.ArenaThemes)
local Arenas = require(ReplicatedStorage.Shared.Data.Arenas)
local Fighters = require(ReplicatedStorage.Shared.Data.Fighters)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local RigBuilder = require(ReplicatedStorage.Shared.Visual.RigBuilder)
local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)

local LobbyBuilder = {}

local ORIGIN = Visuals.LOBBY_ORIGIN
local SIZE = 150 -- plaza width and depth in studs
LobbyBuilder.PAD_RADIUS = 9
LobbyBuilder.PAD_COUNT = 3

local CYAN = Color3.fromRGB(0, 240, 255)
local MAGENTA = Color3.fromRGB(255, 40, 200)
local GOLD = Color3.fromRGB(255, 210, 60)

local model: Model? = nil
local statusLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local pads: { { part: BasePart, ring: BasePart, name: TextLabel, votes: TextLabel } } = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame | Vector3,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
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

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

-- A text surface on the face of a part that points toward the plaza center.
local function screen(board: BasePart, face: Enum.NormalId, pixelsPerStud: number): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	return frame
end

local function text(parent: Instance, value: string, size: UDim2, position: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = parent
	return label
end

local function statue(parent: Instance, fighterId: string, position: Vector3, facing: Vector3)
	local pedestal = part(
		parent,
		"Pedestal",
		Vector3.new(8, 3, 8),
		position + Vector3.new(0, 1.5, 0),
		Color3.fromRGB(30, 26, 48),
		Enum.Material.Marble,
		true
	)
	local look = Looks.get(fighterId)
	local glow = Color3.fromHex(look.glow)
	part(
		parent,
		"PedestalGlow",
		Vector3.new(8.4, 0.3, 8.4),
		position + Vector3.new(0, 3.1, 0),
		glow,
		Enum.Material.Neon
	)
	light(pedestal, glow, 14, 1.2)
	local rig = RigBuilder.build(fighterId)
	rig.Name = "Statue_" .. fighterId
	local root = rig.PrimaryPart :: BasePart
	local stand = rig:GetAttribute("StandHeight") :: number
	local scale = 1.4
	-- A statue never animates: move and scale every part by hand around the root and freeze it.
	local base = position + Vector3.new(0, 3.2, 0)
	local target =
		CFrame.lookAt(base + Vector3.new(0, stand * scale, 0), base + Vector3.new(facing.X, stand * scale, facing.Z))
	local rootCFrame = root.CFrame
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = rootCFrame:ToObjectSpace(d.CFrame)
			d.Size *= scale
			d.CFrame = target * CFrame.new(rel.Position * scale) * (rel - rel.Position)
			d.Anchored = true
		elseif d:IsA("Motor6D") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	rig.Parent = parent
	local plate = part(
		parent,
		"NamePlate",
		Vector3.new(8, 1.6, 0.4),
		CFrame.lookAt(
			position + Vector3.new(0, 1.5, 0) + facing.Unit * 4.25,
			position + Vector3.new(0, 1.5, 0) + facing.Unit * 10
		),
		Color3.fromRGB(12, 10, 22)
	)
	local frame = screen(plate, Enum.NormalId.Front, 20)
	text(frame, Fighters.get(fighterId).name, UDim2.fromScale(1, 1), UDim2.new(), glow)
end

-- Builds the lobby once at server start.
function LobbyBuilder.build(): Model
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "Lobby"
	model = m
	local half = SIZE / 2

	-- Floor: glossy tiles with a glowing ring in the middle.
	local floor = part(
		m,
		"Floor",
		Vector3.new(SIZE, 2, SIZE),
		at(0, -1, 0),
		Color3.fromRGB(26, 22, 44),
		Enum.Material.Slate,
		true
	)
	floor.Reflectance = 0.15
	for k = -2, 2 do
		part(
			m,
			"Seam",
			Vector3.new(SIZE, 0.06, 0.3),
			at(0, 0.02, k * 30),
			Color3.fromRGB(60, 50, 100),
			Enum.Material.Neon
		).Transparency =
			0.6
		part(
			m,
			"Seam",
			Vector3.new(0.3, 0.06, SIZE),
			at(k * 30, 0.02, 0),
			Color3.fromRGB(60, 50, 100),
			Enum.Material.Neon
		).Transparency =
			0.6
	end
	local ring = part(
		m,
		"CenterRing",
		Vector3.new(0.2, 26, 26),
		CFrame.new(at(0, 0.05, 10)) * CFrame.Angles(0, 0, math.pi / 2),
		MAGENTA,
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.5
	part(
		m,
		"CenterDisc",
		Vector3.new(0.25, 23, 23),
		CFrame.new(at(0, 0.06, 10)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(26, 22, 44),
		Enum.Material.Slate
	).Shape =
		Enum.PartType.Cylinder

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = at(0, 0.5, 30)
	spawn.Color = Color3.fromRGB(26, 22, 44)
	spawn.Material = Enum.Material.Slate
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = m

	-- Invisible walls and a low neon rail so nobody walks off the plaza.
	for _, side in { { 0, -half }, { 0, half }, { -half, 0 }, { half, 0 } } do
		local alongX = side[2] ~= 0
		local wallSize = if alongX then Vector3.new(SIZE, 40, 2) else Vector3.new(2, 40, SIZE)
		local wall = part(m, "Wall", wallSize, at(side[1], 20, side[2]), Color3.new(0, 0, 0), nil, true)
		wall.Transparency = 1
		part(
			m,
			"Rail",
			if alongX then Vector3.new(SIZE, 0.4, 0.4) else Vector3.new(0.4, 0.4, SIZE),
			at(side[1], 3, side[2]),
			CYAN,
			Enum.Material.Neon
		)
	end

	-- North: big status screen and the title.
	local board = part(m, "StatusBoard", Vector3.new(60, 20, 1), at(0, 22, -half + 4), Color3.fromRGB(8, 6, 16))
	part(m, "StatusFrame", Vector3.new(62, 22, 0.6), at(0, 22, -half + 3.4), CYAN, Enum.Material.Neon)
	light(board, CYAN, 40, 1.5)
	local frame = screen(board, Enum.NormalId.Back, 10)
	statusLabel = text(frame, "WÄHLE DEINEN KÄMPFER", UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0.08), GOLD)
	subLabel = text(
		frame,
		"Stell dich auf ein Feld, um die Arena zu wählen",
		UDim2.fromScale(0.96, 0.25),
		UDim2.fromScale(0.02, 0.66),
		Color3.new(1, 1, 1)
	)
	for _, leg in { -26, 26 } do
		part(
			m,
			"BoardLeg",
			Vector3.new(2, 12, 2),
			at(leg, 6, -half + 4),
			Color3.fromRGB(40, 36, 60),
			Enum.Material.Metal,
			true
		)
	end
	local title = part(m, "Title", Vector3.new(70, 9, 1), at(0, 38, -half + 4), Color3.fromRGB(8, 6, 16))
	text(screen(title, Enum.NormalId.Back, 8), "PROMPT FIGHTERS", UDim2.fromScale(1, 1), UDim2.new(), MAGENTA)
	light(title, MAGENTA, 40, 2)

	-- Vote pads in front of the screen.
	table.clear(pads)
	for k = 1, LobbyBuilder.PAD_COUNT do
		local x = (k - 2) * 36
		local center = at(x, 0.3, -half + 30)
		local padPart = part(
			m,
			"VotePad" .. k,
			Vector3.new(0.6, LobbyBuilder.PAD_RADIUS * 2, LobbyBuilder.PAD_RADIUS * 2),
			CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(40, 34, 70),
			Enum.Material.Glass,
			true
		)
		padPart.Shape = Enum.PartType.Cylinder
		local padRing = part(
			m,
			"VoteRing" .. k,
			Vector3.new(0.5, LobbyBuilder.PAD_RADIUS * 2 + 1.4, LobbyBuilder.PAD_RADIUS * 2 + 1.4),
			CFrame.new(center - Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			CYAN,
			Enum.Material.Neon
		)
		padRing.Shape = Enum.PartType.Cylinder
		light(padRing, CYAN, 18, 1)
		local sign = part(
			m,
			"VoteSign" .. k,
			Vector3.new(18, 7, 0.5),
			center + Vector3.new(0, 11, -LobbyBuilder.PAD_RADIUS - 2),
			Color3.fromRGB(8, 6, 16)
		)
		part(
			m,
			"VotePole" .. k,
			Vector3.new(0.8, 8, 0.8),
			center + Vector3.new(0, 4, -LobbyBuilder.PAD_RADIUS - 2),
			Color3.fromRGB(40, 36, 60),
			Enum.Material.Metal,
			true
		)
		local signFrame = screen(sign, Enum.NormalId.Back, 14)
		local nameLabel =
			text(signFrame, "", UDim2.fromScale(0.96, 0.55), UDim2.fromScale(0.02, 0.05), Color3.new(1, 1, 1))
		local votesLabel = text(signFrame, "", UDim2.fromScale(0.9, 0.32), UDim2.fromScale(0.05, 0.63), GOLD)
		pads[k] = { part = padPart, ring = padRing, name = nameLabel, votes = votesLabel }
	end

	-- East and west: the launch roster as statues facing the middle.
	for i, fighterId in Visuals.SLICE_FIGHTERS do
		local west = i <= 8
		local row = (i - 1) % 8
		local x = if west then -half + 10 else half - 10
		local z = -half + 30 + row * 14
		statue(m, fighterId, at(x, 0, z), Vector3.new(if west then 1 else -1, 0, 0))
	end

	-- Lamps around the plaza.
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local base = at(corner[1] * (half - 4), 0, corner[2] * (half - 4))
		part(
			m,
			"Lamp",
			Vector3.new(1, 18, 1),
			base + Vector3.new(0, 9, 0),
			Color3.fromRGB(40, 36, 60),
			Enum.Material.Metal,
			true
		)
		local bulb = part(
			m,
			"LampBulb",
			Vector3.new(2.4, 1, 2.4),
			base + Vector3.new(0, 18.5, 0),
			Color3.fromRGB(255, 220, 170),
			Enum.Material.Neon
		)
		light(bulb, Color3.fromRGB(255, 215, 170), 60, 1.6)
	end
	for _, x in { -40, 0, 40 } do
		local holder = part(m, "FillLight", Vector3.one, at(x, 30, 20), Color3.new(1, 1, 1))
		holder.Transparency = 1
		light(holder, Color3.fromRGB(220, 210, 255), 70, 1.2)
	end

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
	pad.name.Text = if info then info.name else arenaId
	pad.name.TextColor3 = if theme then Color3.fromHex(theme.trim) else Color3.new(1, 1, 1)
	pad.votes.Text = if votes == 1 then "1 STIMME" else `{votes} STIMMEN`
	pad.ring.Color = if leading then GOLD elseif theme then Color3.fromHex(theme.trim) else CYAN
end

function LobbyBuilder.model(): Model?
	return model
end

return LobbyBuilder
