--!strict
-- Shared building blocks for arena and lobby decoration: plain anchored parts, signs, and cheap reusable props
-- (crowds, skyline layers, flags, searchlights, passing vehicles). Everything here is look only: anchored, never
-- collides, never queried or touched, and casts a shadow only when it is big enough for the shadow to read.
-- Motion is tagged with Shared/Visual/DecorMotion and played by the client (DecorAnimator.client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DecorMotion = require(ReplicatedStorage.Shared.Visual.DecorMotion)

local Decor = {}

-- Parts smaller than this (largest side, studs) never cast shadows: on phones shadows of small props cost more
-- than they add.
Decor.SHADOW_MIN = 8

Decor.tag = DecorMotion.tag

-- Always sets CFrame (also for a plain position), so every part reads back the same way headless and in Roblox.
function Decor.part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame | Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = if typeof(cframe) == "CFrame" then cframe else CFrame.new(cframe :: Vector3)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function Decor.wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.Parent = parent
	return w
end

function Decor.light(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

-- A text surface on one face of a part (TextScaled, so few pixels per stud keep the text filling the board).
function Decor.text(
	board: BasePart,
	face: Enum.NormalId,
	value: string,
	color: Color3,
	pixelsPerStud: number?,
	box: { number }?
): TextLabel
	local gui: SurfaceGui? = nil
	for _, child in board:GetChildren() do
		if child:IsA("SurfaceGui") and child.Face == face then
			gui = child
		end
	end
	if gui == nil then
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = pixelsPerStud or 12
		g.LightInfluence = 0
		g.Brightness = 2.5
		g.Parent = board
		gui = g
	end
	local b = box or { 0, 0, 1, 1 }
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromScale(b[1], b[2])
	label.Size = UDim2.fromScale(b[3], b[4])
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = gui
	return label
end

-- A part's position whether the builder set Position or CFrame (headless Lune keeps the two apart).
function Decor.where(p: BasePart): Vector3
	local ok, position = pcall(function()
		return p.Position
	end)
	return if ok then position else p.CFrame.Position
end

export type FinalizeOptions = {
	solid: ((BasePart) -> boolean)?, -- parts players stand on (lobby floor, walls); everything else stops colliding
	shadowMin: number?, -- smallest side length that may cast a shadow (default SHADOW_MIN)
	shadowCenter: Vector3?, -- with shadowRadius: only parts this close to the action cast shadows
	shadowRadius: number?,
}

-- Sets the cheap flags on everything in a finished scene: anchored, never touched, and shadows only for big solid
-- parts near where the camera looks.
function Decor.finalize(model: Instance, options: FinalizeOptions?)
	local o: FinalizeOptions = options or {}
	local minSize = o.shadowMin or Decor.SHADOW_MIN
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			if o.solid == nil or not o.solid(d) then
				d.CanCollide = false
				d.CanQuery = false
			end
			if d.CastShadow then
				local size = d.Size
				local cast = math.max(size.X, size.Y, size.Z) >= minSize
					and d.Material ~= Enum.Material.Neon
					and d.Transparency < 0.3
					and d:GetAttribute("Anim") == nil
				if cast and o.shadowCenter and o.shadowRadius then
					cast = (Decor.where(d) - o.shadowCenter).Magnitude <= o.shadowRadius
				end
				d.CastShadow = cast
			end
		end
	end
end

-- Number of BaseParts under `model`.
function Decor.count(model: Instance): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------------------------------------------

local SKIN = { Color3.fromRGB(255, 214, 170), Color3.fromRGB(214, 160, 116), Color3.fromRGB(150, 100, 70) }

export type CrowdSpec = {
	width: number, -- studs along the row
	rows: number,
	spacing: number, -- studs between people
	rise: Vector3, -- offset from one row to the next (up and back)
	colors: { Color3 }, -- shirt colors
	cheer: number?, -- every n-th person bobs (default 3)
	silhouette: Color3?, -- one flat color for everyone (dark crowd against bright light)
	seed: number?,
}

-- Rows of spectators facing the stage along `origin`'s -Z axis: a torso and a head each, every few cheering.
function Decor.crowd(parent: Instance, origin: CFrame, spec: CrowdSpec): number
	local rng = Random.new(spec.seed or 7)
	local count = 0
	local perRow = math.max(1, math.floor(spec.width / spec.spacing))
	for row = 0, spec.rows - 1 do
		for k = 0, perRow - 1 do
			if rng:NextNumber() < 0.12 then
				continue -- empty seats keep the rows from reading as a wall
			end
			local x = -spec.width / 2 + (k + 0.5 + (row % 2) * 0.5) * spec.spacing
			local base = origin * CFrame.new(Vector3.new(x, 0, 0) + spec.rise * row)
			local shirt = spec.silhouette or spec.colors[rng:NextInteger(1, #spec.colors)]
			local skin = spec.silhouette or SKIN[rng:NextInteger(1, #SKIN)]
			local h = 2 + rng:NextNumber() * 0.5
			local torso = Decor.part(
				parent,
				"Fan",
				Vector3.new(spec.spacing * 0.62, h, spec.spacing * 0.4),
				base * CFrame.new(0, h / 2, 0),
				shirt,
				Enum.Material.SmoothPlastic
			)
			local head = Decor.part(
				parent,
				"FanHead",
				Vector3.one * spec.spacing * 0.42,
				base * CFrame.new(0, h + spec.spacing * 0.2, 0),
				skin,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Ball
			)
			count += 2
			if (k + row * 2) % (spec.cheer or 3) == 0 then
				local motion = { amp = 0.5, period = 0.9 + rng:NextNumber() * 0.6, phase = rng:NextNumber() * 3 }
				Decor.tag(torso, "bob", motion)
				Decor.tag(head, "bob", motion)
			end
		end
	end
	return count
end

export type SkylineSpec = {
	from: number, -- x range in studs
	to: number,
	z: number,
	baseY: number, -- world y of the tower feet
	minHeight: number,
	maxHeight: number,
	width: { number }, -- min, max
	color: Color3,
	windows: Color3?, -- lit window strips (vertical) on some towers
	roof: Color3?, -- neon roof line on some towers
	frame: CFrame?, -- places the layer: x runs along the frame's X axis, the towers face its +Z (default: world)
	seed: number?,
}

-- One flat layer of tower silhouettes for parallax depth: a few parts per tower, nothing that casts shadows.
function Decor.skyline(parent: Instance, spec: SkylineSpec): number
	local rng = Random.new(spec.seed or 11)
	local frame = spec.frame or CFrame.new()
	local function place(px: number, py: number, pz: number): CFrame
		return frame * CFrame.new(px, py, pz)
	end
	local x = spec.from
	local count = 0
	while x < spec.to do
		local w = rng:NextNumber(spec.width[1], spec.width[2])
		local h = rng:NextNumber(spec.minHeight, spec.maxHeight)
		local cx = x + w / 2
		Decor.part(
			parent,
			"SkylineTower",
			Vector3.new(w, h, 4),
			place(cx, spec.baseY + h / 2, spec.z),
			spec.color,
			Enum.Material.SmoothPlastic
		)
		count += 1
		if spec.windows and rng:NextNumber() < 0.6 then
			local strips = if w > 14 then 2 else 1
			for s = 1, strips do
				local sx = cx + (s - (strips + 1) / 2) * w * 0.4
				local strip = Decor.part(
					parent,
					"SkylineWindows",
					Vector3.new(w * 0.16, h * rng:NextNumber(0.35, 0.75), 0.2),
					place(sx, spec.baseY + h * 0.45, spec.z + 2.1),
					spec.windows,
					Enum.Material.Neon
				)
				strip.Transparency = 0.45
				count += 1
			end
		end
		if spec.roof and rng:NextNumber() < 0.35 then
			Decor.part(
				parent,
				"SkylineRoof",
				Vector3.new(w, 0.5, 0.5),
				place(cx, spec.baseY + h, spec.z + 2.2),
				spec.roof,
				Enum.Material.Neon
			)
			count += 1
		end
		x += w + rng:NextNumber(0, w * 0.3)
	end
	return count
end

-- A flag on a pole; the cloth swings on the pole like a door in the wind.
function Decor.flag(parent: Instance, foot: Vector3, height: number, color: Color3, phase: number?): BasePart
	Decor.part(
		parent,
		"FlagPole",
		Vector3.new(0.5, height, 0.5),
		foot + Vector3.new(0, height / 2, 0),
		Color3.fromRGB(180, 184, 196),
		Enum.Material.Metal
	)
	local w, h = height * 0.42, height * 0.26
	local cloth = Decor.part(
		parent,
		"Flag",
		Vector3.new(w, h, 0.15),
		foot + Vector3.new(w / 2 + 0.25, height - h / 2 - 0.3, 0),
		color,
		Enum.Material.Fabric
	)
	return Decor.tag(
		cloth,
		"sway",
		{ amp = 0.28, period = 1.6, axis = Vector3.new(0, 1, 0), pivot = foot + Vector3.new(0, height, 0), phase = phase }
	)
end

-- A searchlight beam sweeping from `foot`: a long translucent neon bar tilted `tilt` radians off vertical.
function Decor.searchlight(
	parent: Instance,
	foot: Vector3,
	length: number,
	color: Color3,
	tilt: number,
	phase: number?
): BasePart
	local beam = Decor.part(
		parent,
		"SearchBeam",
		Vector3.new(length * 0.03, length, length * 0.03),
		CFrame.new(foot) * CFrame.Angles(0, 0, tilt) * CFrame.new(0, length / 2, 0),
		color,
		Enum.Material.Neon
	)
	beam.Transparency = 0.84
	return Decor.tag(
		beam,
		"sway",
		{ amp = 0.35, period = 7, axis = Vector3.new(0, 0, 1), pivot = foot, phase = phase }
	)
end

-- Makes a group of parts travel together along `axis`, looping over `span` studs.
function Decor.convoy(parts: { BasePart }, speed: number, span: number, phase: number, axis: Vector3?)
	for _, p in parts do
		Decor.tag(p, "pass", { speed = speed, amp = span, phase = phase, axis = axis })
	end
end

-- Slow neon flicker/breathing.
function Decor.pulse(p: BasePart, amp: number, period: number, phase: number?): BasePart
	return Decor.tag(p, "pulse", { amp = amp, period = period, phase = phase })
end

return Decor
