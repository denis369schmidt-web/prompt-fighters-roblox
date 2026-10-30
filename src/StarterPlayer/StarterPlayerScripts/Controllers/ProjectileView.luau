--!strict
-- Draws the projectiles of signature specials: built from plain parts when the server announces one
-- ("projectile" event), moved toward the positions of the Shots remote, removed with a small puff when it ends.
-- The style from the server (shot, orb, column, storm, wall, creature ...) decides the look, the color comes
-- from the fighter's signature. Shots and blades get a white-hot core, a pulsing halo, a tapered trail and a
-- sparkle wake; they spawn with a muzzle flash and end with an impact burst.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local Effects = require(script.Parent.Effects)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local FOLLOW = 25

-- Shapes drawn as a long blade or bolt pointing along the flight path.
local LONG = {
	kunai = true,
	lance = true,
	arrow = true,
	bolt = true,
	spear = true,
	javelin = true,
	harpoon = true,
	missile = true,
	hook = true,
	glitch = true,
	chain = true,
	anchor = true,
	lasso = true,
	crescent = true,
}

type Shot = {
	model: Model,
	main: BasePart,
	style: string,
	shape: string,
	color: Color3,
	position: Vector3,
	velocity: Vector3,
	size: number,
	age: number,
	pooled: boolean,
}

local ProjectileView = {}

local shots: { [number]: Shot } = {}
local folder: Folder? = nil

local function container(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local f = Instance.new("Folder")
	f.Name = "Projectiles"
	f.Parent = workspace
	folder = f
	return f
end

local function toWorld(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

local function part(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Parent = model
	return p
end

local function light(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

local function trail(p: BasePart, color: Color3, width: number, lifetime: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = p
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.3, color:Lerp(Color3.new(1, 1, 1), 0.25)),
		ColorSequenceKeypoint.new(1, color),
	})
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Lifetime = lifetime * 1.6
	t.FaceCamera = true
	t.Parent = p
end

-- Glow layers around a shot: a white core inside and a soft halo outside that pulses (see render).
local function glowLayers(model: Model, main: BasePart, color: Color3, size: Vector3, ball: boolean)
	-- The colored body turns see-through a little so the white core shines through it.
	main.Transparency = math.max(main.Transparency, 0.3)
	local core = part(model, "Core", size * 0.5, Color3.new(1, 1, 1))
	core:SetAttribute("Follow", true)
	local halo = part(model, "Halo", size * 1.7, color:Lerp(Color3.new(1, 1, 1), 0.15))
	halo.Transparency = 0.78
	halo:SetAttribute("Follow", true)
	halo:SetAttribute("Pulse", size * 1.7)
	if ball then
		core.Shape = Enum.PartType.Ball
		halo.Shape = Enum.PartType.Ball
	end
	-- Sparkle wake: small bright particles left behind.
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.min(size.X, size.Y) * 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0, 1)
	e.Lifetime = NumberRange.new(0.2, 0.45)
	e.Rate = 30
	e.Speed = NumberRange.new(0.5, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Parent = main
end

local function particles(p: BasePart, color: Color3, rate: number, size: number, speed: number, direction: Vector3?)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.3) })
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Lifetime = NumberRange.new(0.4, 0.9)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = if direction then Vector2.new(15, 15) else Vector2.new(180, 180)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Parent = p
end

-- Builds the model of one projectile. Sizes are meters from the simulation, drawn a little larger to read.
local function build(style: string, shape: string, color: Color3, size: number): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = if shape ~= "" then shape else style
	local d = math.max(0.35, size * 2) * M
	local main: Part
	if style == "column" then
		main = part(model, "Beam", Vector3.new(9 * M, d, d), color)
		main.Shape = Enum.PartType.Cylinder
		main.Transparency = 0.85
		light(main, color, 24, 3)
	elseif style == "storm" then
		main = part(
			model,
			"Cloud",
			Vector3.new(d * 2.2, d * 0.9, d * 1.6),
			Color3.fromRGB(225, 235, 250),
			Enum.Material.SmoothPlastic
		)
		main.Shape = Enum.PartType.Ball
		main.Transparency = 0.35
		particles(main, Color3.fromRGB(235, 245, 255), 40, 0.5, 18, Vector3.yAxis)
	elseif style == "wall" then
		main = part(model, "Wall", Vector3.new(d * 0.6, 2.4 * M, d * 1.4), color)
		main.Transparency = 0.25
		particles(main, color, 30, 1.2, 8)
		light(main, color, 18, 3)
	elseif style == "cloud" then
		main = part(model, "Cloud", Vector3.one * math.max(d, 2.6 * M), color, Enum.Material.SmoothPlastic)
		main.Shape = Enum.PartType.Ball
		main.Transparency = 0.8
		particles(main, color, 25, 2.5, 3)
	elseif style == "creature" then
		-- A small glowing figure: summoned servant, hound or shadow double.
		local dark = color:Lerp(Color3.new(0, 0, 0), 0.6)
		main = part(model, "Body", Vector3.new(1.4, 1.8, 0.9), dark, Enum.Material.SmoothPlastic)
		main.Transparency = 0.15
		local head = part(model, "Head", Vector3.new(1, 1, 1), dark, Enum.Material.SmoothPlastic)
		head.Transparency = 0.15
		local eyes = part(model, "Eyes", Vector3.new(0.7, 0.18, 0.1), color)
		head:SetAttribute("Offset", Vector3.new(0, 1.45, 0))
		eyes:SetAttribute("Offset", Vector3.new(0, 1.55, -0.5))
		light(main, color, 10, 1.5)
	elseif style == "turret" then
		main = part(
			model,
			"Turret",
			Vector3.new(1.4, 1.2, 1.4),
			color:Lerp(Color3.new(0.2, 0.2, 0.2), 0.6),
			Enum.Material.Metal
		)
		local barrel = part(model, "Barrel", Vector3.new(1.4, 0.35, 0.35), color)
		barrel:SetAttribute("Offset", Vector3.new(0.7, 0.3, 0))
		light(main, color, 10, 2)
	elseif style == "mine" then
		main = part(
			model,
			"Mine",
			Vector3.new(0.5, d, d),
			color:Lerp(Color3.new(0.15, 0.15, 0.15), 0.5),
			Enum.Material.Metal
		)
		main.Shape = Enum.PartType.Cylinder
		local lamp = part(model, "Lamp", Vector3.one * 0.4, color)
		lamp:SetAttribute("Offset", Vector3.new(0, d * 0.35, 0))
		lamp:SetAttribute("Blink", true)
	elseif style == "ground" then
		main = part(model, "Disc", Vector3.new(0.3, d * 2, d * 2), color)
		main.Shape = Enum.PartType.Cylinder
		main.Transparency = 0.45
		light(main, color, 14, 2)
	elseif LONG[shape] then
		main = part(model, "Blade", Vector3.new(d * 0.35, d * 0.35, d * 2.2), color)
		trail(main, color, d * 0.4, 0.15)
		light(main, color, 8, 1.5)
		glowLayers(model, main, color, main.Size, false)
	else
		main = part(model, "Ball", Vector3.one * d, color)
		main.Shape = Enum.PartType.Ball
		trail(main, color, d * 0.7, 0.2)
		light(main, color, 10, 2)
		glowLayers(model, main, color, main.Size, true)
	end
	model.PrimaryPart = main
	model.Parent = container()
	return model, main
end

-- Turns a lava blob into a burning pool on the floor.
local function makePool(shot: Shot)
	shot.pooled = true
	local main = shot.main :: Part
	main.Shape = Enum.PartType.Cylinder
	shot.main.Size = Vector3.new(0.4, shot.size * 2.4 * M, shot.size * 2.4 * M)
	shot.main.Transparency = 0.2
	particles(shot.main, shot.color, 20, 0.8, 4)
end

local function finish(id: number, puff: boolean)
	local shot = shots[id]
	if shot == nil then
		return
	end
	shots[id] = nil
	if puff and shot.position ~= Vector3.zero then
		-- Impact burst scaled by the shot's size.
		local d = math.max(0.35, shot.size * 2) * M
		Effects.flashBall(shot.position, shot.color, d * 2.6, 0.25)
		Effects.impactStar(shot.position, shot.color, 6 + d * 2, 0.2)
		Effects.ring(shot.position, shot.color, d * 3.2, 0.3, 0.2)
		Effects.sparks(shot.position, shot.color, 14 + d * 3, 22)
	end
	shot.model:Destroy()
end

local function clearAll()
	for id in shots do
		finish(id, false)
	end
end

local function render(dt: number)
	local follow = 1 - math.exp(-FOLLOW * dt)
	local blink = (os.clock() * 4) % 1 < 0.5
	for id, shot in shots do
		local data = MatchState.shots[id]
		shot.age += dt
		if data then
			local target = toWorld(data.x, data.y)
			local before = shot.position
			shot.position = if before == Vector3.zero then target else before:Lerp(target, follow)
			if dt > 0 then
				shot.velocity = shot.velocity:Lerp((shot.position - before) / dt, 0.3)
			end
			if math.abs(data.size - shot.size) > 0.05 and shot.style == "orb" then
				shot.size = data.size
				shot.main.Size = Vector3.one * math.max(0.35, data.size * 2) * M
			end
		elseif shot.age > 1.5 then
			-- The server stopped sending this one and the end event got lost.
			finish(id, false)
			continue
		end
		local cf: CFrame
		if shot.style == "column" then
			cf = CFrame.new(shot.position + Vector3.new(0, 4.5 * M, 0)) * CFrame.Angles(0, 0, math.rad(90))
			shot.main.Transparency = if shot.age < 0.6 then 0.85 else 0.15
		elseif shot.pooled or shot.style == "ground" or shot.style == "mine" then
			cf = CFrame.new(shot.position) * CFrame.Angles(0, 0, math.rad(90))
		elseif shot.velocity.Magnitude > 1 then
			cf = CFrame.lookAt(shot.position, shot.position + shot.velocity)
		else
			cf = CFrame.new(shot.position)
		end
		shot.main.CFrame = cf
		for _, p in shot.model:GetChildren() do
			if p:IsA("BasePart") and p ~= shot.main and p:GetAttribute("Follow") then
				-- Core and halo ride on the main part; the halo breathes.
				p.CFrame = cf
				local base = p:GetAttribute("Pulse") :: Vector3?
				if base then
					p.Size = base * (1 + 0.14 * math.sin(shot.age * 22))
				end
			elseif p:IsA("BasePart") and p ~= shot.main then
				local offset = p:GetAttribute("Offset") :: Vector3?
				local facing = if shot.velocity.X < 0 then -1 else 1
				local o = offset or Vector3.zero
				p.CFrame = CFrame.new(shot.position + Vector3.new(o.X * facing, o.Y, o.Z))
				if p:GetAttribute("Blink") then
					p.Transparency = if blink then 0 else 0.8
				end
			end
		end
	end
end

local function hexColor(value: any, fallback: Color3): Color3
	if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
		return Color3.fromHex(value)
	end
	return fallback
end

function ProjectileView.start()
	MatchState.onEvent(function(event)
		local kind = event.type
		if kind == "phase" then
			clearAll()
		elseif kind == "projectile" then
			finish(event.id, false)
			local color = hexColor(event.color, Color3.fromRGB(255, 220, 120))
			local style = event.style or "shot"
			local shape = event.shape or ""
			local model, main = build(style, shape, color, event.size or 0.5)
			local data = MatchState.shots[event.id]
			if data then
				-- Muzzle flash where the shot appears.
				local at = toWorld(data.x, data.y)
				Effects.flashBall(at, color, 4, 0.18)
				Effects.ring(at, color, 6, 0.2, 0.15)
			end
			shots[event.id] = {
				model = model,
				main = main,
				style = style,
				shape = shape,
				color = color,
				position = if data then toWorld(data.x, data.y) else Vector3.zero,
				velocity = Vector3.zero,
				size = event.size or 0.5,
				age = 0,
				pooled = false,
			}
		elseif kind == "projectile_end" then
			finish(event.id, true)
		elseif kind == "pool" then
			local shot = shots[event.id]
			if shot then
				makePool(shot)
			end
		elseif kind == "blast" then
			local p = toWorld(event.x, event.y)
			local color = hexColor(event.color, Color3.fromRGB(255, 150, 60))
			local r = (event.radius or 1.5) * M
			Effects.flashBall(p, color, r * 2, 0.35)
			Effects.ring(p, color, r * 2.4, 0.35)
			Effects.sparks(p, color, 30, 40)
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return ProjectileView
