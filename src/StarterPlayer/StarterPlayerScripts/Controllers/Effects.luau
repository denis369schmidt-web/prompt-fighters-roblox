--!strict
-- One-shot visual effects (client only): hit sparks, impact stars, shockwave rings, speed lines, debris,
-- impact frames, slash arcs, dust, damage numbers, combo counters, KO beams and banners, screen flashes.
-- Built from parts, Beams, pooled ParticleEmitters and Gui objects, so no asset uploads. Nothing here touches
-- match logic. Particle emitters are pooled (emit-and-move), everything else is destroyed when done, and the
-- counts are capped (see LIMITS and GameFeel.TUNING).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GameFeel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Visual"):WaitForChild("GameFeel"))
local Juice = require(script.Parent.Juice)

local TUNING = GameFeel.TUNING

-- Look tuning (sizes in studs, times in seconds).
local LOOK = {
	sparkLifetime = NumberRange.new(0.14, 0.34),
	sparkSize = 0.55,
	dustTexture = "rbxasset://textures/particles/smoke_main.dds", -- ships with every Roblox client
	dustColor = Color3.fromRGB(215, 205, 190),
	starSize = 9, -- impact star at strength 0
	starSizeHeavy = 20,
	speedLines = 18,
	koBeamLength = 140,
	koBeamWidth = 7,
	slashSegments = 18,
	flashOpacity = 0.35, -- screen flash at full strength (0 = invisible)
}

local LIMITS = {
	poolSize = 6, -- emitters per particle preset (round robin)
	maxSparks = 60, -- particles per burst
	maxAnims = 160, -- running custom animations
}

local Effects = {}

local folder: Folder? = nil

local function container(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local f = Instance.new("Folder")
	f.Name = "Effects"
	f.Parent = workspace
	folder = f
	return f
end

local function bare(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function anchor(position: Vector3): Part
	local p = Instance.new("Part")
	bare(p)
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Position = position
	p.Parent = container()
	return p
end

local function neon(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	bare(p)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	return p
end

-- Flashes and impact frames are softened by the same accessibility switch as the camera shake.
local function motion(): number
	return math.clamp(Juice.shakeScale(), 0.25, 1)
end

---------------------------------------------------------------------------------------------------------------
-- Custom animations: one RenderStepped loop runs every effect that tweens can't do (Beams, debris, speed lines).
-- update(dt) returns false when the effect is done; it must clean up after itself then.

type Anim = { update: (dt: number) -> boolean }

local anims: { Anim } = {}
local loop: RBXScriptConnection? = nil

local function stepAnims(dt: number)
	local scaled = dt * Juice.timeScale()
	local k = 1
	while k <= #anims do
		local ok, keep = pcall(anims[k].update, scaled)
		if ok and keep then
			k += 1
		else
			anims[k] = anims[#anims]
			anims[#anims] = nil
		end
	end
end

local function animate(update: (dt: number) -> boolean)
	if #anims >= LIMITS.maxAnims then
		-- Over budget: finish the oldest effect right away.
		pcall(anims[1].update, math.huge)
		table.remove(anims, 1)
	end
	table.insert(anims, { update = update })
	if loop == nil then
		loop = RunService.RenderStepped:Connect(stepAnims)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Pooled particle emitters: an emitter at a moved holder emits a burst, the particles stay in world space.

type Preset = {
	texture: string?,
	lightEmission: number,
	lightInfluence: number,
	size: NumberSequence,
	transparency: NumberSequence,
	lifetime: NumberRange,
	drag: number,
	acceleration: Vector3,
	orientation: Enum.ParticleOrientation,
	rotSpeed: NumberRange?,
	zOffset: number,
}

local PRESETS: { [string]: Preset } = {
	spark = {
		lightEmission = 1,
		lightInfluence = 0,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, LOOK.sparkSize),
			NumberSequenceKeypoint.new(1, 0),
		}),
		transparency = NumberSequence.new(0, 1),
		lifetime = LOOK.sparkLifetime,
		drag = 7,
		acceleration = Vector3.new(0, -30, 0),
		orientation = Enum.ParticleOrientation.VelocityParallel,
		zOffset = 2,
	},
	ember = {
		lightEmission = 1,
		lightInfluence = 0,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.6, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		}),
		transparency = NumberSequence.new(0, 1),
		lifetime = NumberRange.new(0.4, 0.9),
		drag = 3,
		acceleration = Vector3.new(0, -12, 0),
		orientation = Enum.ParticleOrientation.FacingCamera,
		zOffset = 1,
	},
	dust = {
		texture = LOOK.dustTexture,
		lightEmission = 0,
		lightInfluence = 0.6,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 2.6),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		lifetime = NumberRange.new(0.35, 0.65),
		drag = 5,
		acceleration = Vector3.new(0, 3, 0),
		orientation = Enum.ParticleOrientation.FacingCamera,
		rotSpeed = NumberRange.new(-90, 90),
		zOffset = 0,
	},
}

type Pooled = { holder: Part, emitter: ParticleEmitter }
local pools: { [string]: { list: { Pooled }, next: number } } = {}

local function pooled(name: string): Pooled
	local pool = pools[name]
	if pool == nil then
		pool = { list = {}, next = 1 }
		pools[name] = pool
	end
	local entry = pool.list[pool.next]
	if entry == nil or entry.holder.Parent == nil then
		local preset = PRESETS[name]
		local holder = anchor(Vector3.zero)
		holder.Name = "Emitter_" .. name
		local e = Instance.new("ParticleEmitter")
		if preset.texture then
			e.Texture = preset.texture
		end
		e.LightEmission = preset.lightEmission
		e.LightInfluence = preset.lightInfluence
		e.Size = preset.size
		e.Transparency = preset.transparency
		e.Lifetime = preset.lifetime
		e.Drag = preset.drag
		e.Acceleration = preset.acceleration
		e.Orientation = preset.orientation
		e.ZOffset = preset.zOffset
		if preset.rotSpeed then
			e.RotSpeed = preset.rotSpeed
			e.Rotation = NumberRange.new(0, 360)
		end
		e.Rate = 0
		e.Parent = holder
		entry = { holder = holder, emitter = e }
		pool.list[pool.next] = entry
	end
	pool.next = pool.next % LIMITS.poolSize + 1
	return entry :: Pooled
end

-- Emit a burst. direction (optional) aims the burst, spread is the cone half-angle in degrees.
local function burst(
	preset: string,
	position: Vector3,
	count: number,
	color: Color3,
	speed: number,
	direction: Vector3?,
	spread: number?
)
	local entry = pooled(preset)
	local e = entry.emitter
	local dir = direction
	if dir and dir.Magnitude > 1e-3 then
		entry.holder.CFrame = CFrame.lookAt(position, position + dir.Unit)
		e.EmissionDirection = Enum.NormalId.Front
		local s = spread or 40
		e.SpreadAngle = Vector2.new(s, s)
	else
		entry.holder.CFrame = CFrame.new(position)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(180, 180)
	end
	e.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.25), color)
	e.Speed = NumberRange.new(speed * 0.45, speed)
	e:Emit(math.clamp(math.floor(count), 1, LIMITS.maxSparks))
end

-- Spark burst: count scales with damage. Same signature as before; now pooled and streaked.
function Effects.sparks(position: Vector3, color: Color3, amount: number, speed: number?)
	burst("spark", position, math.max(4, amount), color, speed or 30)
	if amount >= 20 then
		burst("ember", position, amount * 0.3, color, (speed or 30) * 0.5)
	end
end

-- Sparks fired along a direction (hit direction), with a few stray ones all around.
function Effects.sparksToward(position: Vector3, direction: Vector3, color: Color3, amount: number, speed: number)
	burst("spark", position, amount, color, speed, direction, 38)
	burst("spark", position, amount * 0.3, Color3.new(1, 1, 1), speed * 0.6)
end

-- Dust puff at a point (landing, dash, run). direction aims it, otherwise it spreads flat.
function Effects.dust(position: Vector3, amount: number, speed: number?, direction: Vector3?)
	burst("dust", position, amount, LOOK.dustColor, speed or 8, direction or Vector3.new(0, 0.2, 0), 75)
end

---------------------------------------------------------------------------------------------------------------
-- Shapes

-- Flat ring that grows and fades (big hits, landings, KOs). It faces the camera (fight plane).
function Effects.ring(position: Vector3, color: Color3, size: number, duration: number?, thickness: number?)
	local ring = neon(Vector3.new(thickness or 0.2, 1, 1), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
	ring.Transparency = 0.15
	ring.Parent = container()
	local d = duration or 0.35
	TweenService:Create(
		ring,
		TweenInfo.new(d, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, size, size), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, d + 0.1)
end

-- Ground ring (lies flat on the floor) for landings and slams.
function Effects.groundRing(position: Vector3, color: Color3, size: number, duration: number?)
	local ring = neon(Vector3.new(0.15, 1, 1), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.3
	ring.Parent = container()
	local d = duration or 0.3
	TweenService:Create(
		ring,
		TweenInfo.new(d, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, size, size), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, d + 0.1)
end

-- Two rings: a fast white one inside a slower colored one.
function Effects.shockwave(position: Vector3, color: Color3, size: number, duration: number?)
	local d = duration or 0.4
	Effects.ring(position, Color3.new(1, 1, 1), size * 0.6, d * 0.6, 0.35)
	Effects.ring(position, color, size, d, 0.25)
end

-- Glowing ball that blows up and fades.
function Effects.flashBall(position: Vector3, color: Color3, size: number, duration: number?)
	local ball = neon(Vector3.one * 1.5, color)
	ball.Shape = Enum.PartType.Ball
	ball.Position = position
	ball.Parent = container()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = math.min(60, size * 1.5)
	light.Brightness = 6
	light.Shadows = false
	light.Parent = ball
	local d = duration or 0.4
	local info = TweenInfo.new(d, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(ball, info, { Size = Vector3.one * size, Transparency = 1 }):Play()
	TweenService:Create(light, info, { Brightness = 0 }):Play()
	Debris:AddItem(ball, d + 0.1)
end

-- Four-point impact star (two long and two short rays), drawn as a billboard so it always faces the camera.
function Effects.impactStar(position: Vector3, color: Color3, size: number, duration: number?)
	local holder = anchor(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size, size)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = gui
	local spin = math.random(0, 90)
	local rays = {}
	for k = 0, 3 do
		local long = k % 2 == 0
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = if long then UDim2.fromScale(1, 0.09) else UDim2.fromScale(0.62, 0.07)
		ray.Rotation = spin + k * 45
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Color3.new(1, 1, 1)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, color),
		})
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ray
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ray
		ray.Parent = gui
		table.insert(rays, ray)
	end
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.22, 0.22)
	core.BackgroundColor3 = Color3.new(1, 1, 1)
	core.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = core
	core.Parent = gui
	table.insert(rays, core)

	local d = duration or 0.22
	local age = 0
	animate(function(dt)
		age += dt
		local f = math.min(1, age / d)
		-- Fast pop with overshoot, then the rays thin out and fade.
		scale.Scale = if f < 0.25 then 0.2 + (f / 0.25) * 1.05 else 1.25 - (f - 0.25) * 0.35
		local fade = math.clamp((f - 0.3) / 0.7, 0, 1)
		for _, ray in rays do
			ray.BackgroundTransparency = fade
		end
		if f >= 1 then
			holder:Destroy()
			return false
		end
		return holder.Parent ~= nil
	end)
end

-- Glowing streak between two points that fades (teleports, iaido cuts, chains).
function Effects.streak(from: Vector3, to: Vector3, color: Color3, width: number, duration: number?)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return
	end
	local p = neon(Vector3.new(width, width, length), color)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = container()
	local core = neon(Vector3.new(width * 0.4, width * 0.4, length), Color3.new(1, 1, 1))
	core.CFrame = p.CFrame
	core.Parent = p
	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad)
	TweenService:Create(p, info, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) }):Play()
	TweenService:Create(core, info, { Transparency = 1 }):Play()
	Debris:AddItem(p, (duration or 0.3) + 0.05)
end

-- Transparency sequence that shows only the stretch tail..head (0..1) at `alpha`, invisible elsewhere.
local function band(tail: number, head: number, alpha: number): NumberSequence
	local eps = 0.002
	local points = { { 0, 1 }, { tail, 1 }, { tail + eps, alpha }, { head, alpha }, { head + eps, 1 }, { 1, 1 } }
	local n = #points
	local keys = {}
	local last = -1
	for i, pt in points do
		local t = if i == 1 then 0 elseif i == n then 1 else math.clamp(pt[1], last + eps, 1 - (n - i) * eps)
		last = t
		keys[i] = NumberSequenceKeypoint.new(t, pt[2])
	end
	return NumberSequence.new(keys)
end

-- Curved slash arc (Beam bezier) in front of a fighter. facing = +1/-1, angle in degrees turns the arc
-- (0 = vertical swing in front, 90 = overhead, -90 = low sweep). Two beams: colored glow and a white edge.
function Effects.slashArc(center: Vector3, facing: number, color: Color3, radius: number, angle: number, heavy: boolean)
	local holder = anchor(center)
	holder.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(angle * facing))
	local f = if facing < 0 then -1 else 1
	-- Bezier control points: top + axis * CurveSize0 and bottom - axis * CurveSize1, both pushed toward
	-- the facing side, so the arc bulges forward like a half circle (4/3 r).
	local bulge = radius * 1.33
	local top = Instance.new("Attachment")
	top.CFrame = CFrame.fromMatrix(Vector3.new(0, radius, 0), Vector3.new(f, 0, 0), Vector3.new(0, 0, 1))
	top.Parent = holder
	local bottom = Instance.new("Attachment")
	bottom.CFrame = CFrame.fromMatrix(Vector3.new(0, -radius, 0), Vector3.new(f, 0, 0), Vector3.new(0, 0, 1))
	bottom.Parent = holder
	local function beam(width: number, tint: Color3, emission: number): Beam
		local b = Instance.new("Beam")
		b.Attachment0 = top
		b.Attachment1 = bottom
		b.CurveSize0 = bulge
		b.CurveSize1 = -bulge
		b.Segments = LOOK.slashSegments
		b.FaceCamera = true
		b.LightEmission = emission
		b.LightInfluence = 0
		b.Width0 = width * 0.25
		b.Width1 = width
		b.Color = ColorSequence.new(tint)
		b.Parent = holder
		return b
	end
	local glowWidth = if heavy then 2.6 else 1.6
	local glow = beam(glowWidth, color, 1)
	local edge = beam(glowWidth * 0.3, Color3.new(1, 1, 1), 1)
	local d = if heavy then 0.26 else 0.17
	local age = 0
	animate(function(dt)
		age += dt
		local p = math.min(1, age / d)
		-- The arc "draws" from the top: the head sweeps through, the tail fades behind it.
		local head = math.min(1, p * 2.2)
		local tail = math.clamp(p * 1.4 - 0.25, 0, 0.98)
		local seq = band(tail, head, 0.1 + p * 0.6)
		glow.Transparency = seq
		edge.Transparency = seq
		glow.Width1 = glowWidth * (1 - p * 0.5)
		if p >= 1 then
			holder:Destroy()
			return false
		end
		return holder.Parent ~= nil
	end)
end

-- Debris: small chunks that fly out along the hit direction, fall and shrink.
local debrisCount = 0
function Effects.debris(position: Vector3, direction: Vector3, color: Color3, count: number)
	local dir = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
	for _ = 1, count do
		if debrisCount >= TUNING.maxDebris then
			return
		end
		debrisCount += 1
		local s = 0.25 + math.random() * 0.45
		local chunk = neon(Vector3.new(s, s * 0.7, s * 0.5), if math.random() < 0.5 then color else Color3.new(1, 1, 1))
		chunk.Material = if math.random() < 0.6 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		chunk.CFrame = CFrame.new(position)
		chunk.Parent = container()
		local velocity = (dir + Vector3.new((math.random() - 0.5) * 1.2, math.random() * 0.9, 0)).Unit
				* (18 + math.random() * 22)
			+ Vector3.new(0, 0, (math.random() - 0.5) * 6)
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		local pos, rot = position, Vector3.zero
		local life = 0.45 + math.random() * 0.35
		local age = 0
		animate(function(dt)
			age += dt
			if age >= life or chunk.Parent == nil then
				chunk:Destroy()
				debrisCount -= 1
				return false
			end
			velocity += Vector3.new(0, -70, 0) * dt
			velocity *= 1 - math.min(1, 2 * dt)
			pos += velocity * dt
			rot += spin * dt
			local k = 1 - age / life
			chunk.Size = Vector3.new(s, s * 0.7, s * 0.5) * (0.3 + 0.7 * k)
			chunk.CFrame = CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
			chunk.Transparency = 1 - k
			return true
		end)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Screen effects

local screenGui: ScreenGui? = nil
local function screen(): ScreenGui
	local gui = screenGui
	if gui and gui.Parent then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Juice"
	g.IgnoreGuiInset = true
	g.DisplayOrder = 50
	g.ResetOnSpawn = false
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	screenGui = g
	return g
end

function Effects.screenFlash(color: Color3, duration: number, strength: number?)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6)
	frame.BackgroundTransparency = 1 - (1 - LOOK.flashOpacity) * (strength or 1) * motion()
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = screen()
	TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(frame, duration + 0.05)
end

-- Impact frame: a few frames of high contrast, low saturation, then it eases back (heavy hits, KOs).
local grade: ColorCorrectionEffect? = nil
local gradeUntil = 0
function Effects.impactFrame(strength: number, seconds: number?)
	local cc = grade
	if cc == nil or cc.Parent == nil then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "ImpactFrame"
		made.Parent = workspace.CurrentCamera or Lighting
		grade = made
		cc = made
	end
	local g = cc :: ColorCorrectionEffect
	local k = math.clamp(strength, 0, 1) * motion()
	local hold = seconds or 0.06
	gradeUntil = os.clock() + hold
	g.Contrast = 0.55 * k
	g.Saturation = -0.7 * k
	g.Brightness = 0.08 * k
	g.Enabled = true
	task.delay(hold, function()
		if os.clock() + 1e-3 < gradeUntil then
			return -- a newer impact frame is running
		end
		TweenService
			:Create(g, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Contrast = 0, Saturation = 0, Brightness = 0 })
			:Play()
	end)
end

-- Anime speed lines radiating from a world point (heavy hits, KOs).
function Effects.speedLines(position: Vector3, color: Color3, strength: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local point, visible = camera:WorldToViewportPoint(position)
	if not visible then
		return
	end
	local layer = Instance.new("Frame")
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 2
	layer.Parent = screen()
	local view = camera.ViewportSize
	local reach = math.max(view.X, view.Y) * 0.8
	local lines = {}
	local count = math.floor(LOOK.speedLines * (0.6 + 0.4 * strength))
	for k = 1, count do
		local angle = (k / count) * math.pi * 2 + (math.random() - 0.5) * 0.3
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BorderSizePixel = 0
		line.BackgroundColor3 = if k % 3 == 0 then color else Color3.new(1, 1, 1)
		line.Rotation = math.deg(angle)
		line.Parent = layer
		table.insert(lines, {
			frame = line,
			angle = angle,
			start = 50 + math.random() * 80,
			length = reach * (0.25 + math.random() * 0.25),
			thick = 2 + math.random() * 3 * (0.5 + strength),
		})
	end
	local d = 0.22 + strength * 0.12
	local age = 0
	animate(function(dt)
		age += dt
		local f = math.min(1, age / d)
		for _, l in lines do
			local r = l.start + f * reach * 0.6
			local length = l.length * (1 - f * 0.5)
			local cx = point.X + math.cos(l.angle) * (r + length / 2)
			local cy = point.Y + math.sin(l.angle) * (r + length / 2)
			l.frame.Position = UDim2.fromOffset(cx, cy)
			l.frame.Size = UDim2.fromOffset(length, l.thick * (1 - f))
			l.frame.BackgroundTransparency = 0.15 + f * 0.85
		end
		if f >= 1 then
			layer:Destroy()
			return false
		end
		return layer.Parent ~= nil
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Text

local numbers: { Instance } = {}

-- Floating damage number: pops in with an overshoot, colored and sized by damage, then rises and fades.
function Effects.damageNumber(position: Vector3, damage: number, color: Color3?)
	while #numbers >= TUNING.maxDamageNumbers do
		local oldest = table.remove(numbers, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local start = position + Vector3.new((math.random() - 0.5) * 1.6, 0, 0)
	local holder = anchor(start)
	table.insert(numbers, holder)
	local s = GameFeel.damageScale(damage)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110 * s, 52 * s)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = gui
	local r, g, b = GameFeel.damageColor(damage)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = tostring(math.floor(damage + 0.5))
	label.TextColor3 = color or Color3.new(r, g, b)
	label.TextStrokeTransparency = 1
	label.Rotation = (math.random() - 0.5) * 16
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.new(0.08, 0.04, 0.06)
	stroke.Parent = label
	label.Parent = gui
	local age = 0
	local drift = (math.random() - 0.5) * 2
	animate(function(dt)
		age += dt
		if holder.Parent == nil then
			return false
		end
		-- 0..0.12 s pop to 1.35, settle to 1, hold, then rise and fade.
		if age < 0.1 then
			scale.Scale = age / 0.1 * 1.35
		elseif age < 0.2 then
			scale.Scale = 1.35 - (age - 0.1) / 0.1 * 0.35
		else
			scale.Scale = 1
		end
		local rise = math.max(0, age - 0.15)
		holder.Position = start + Vector3.new(drift * rise, 3.2 * (1 - math.exp(-rise * 3)), 0)
		local fade = math.clamp((age - 0.5) / 0.3, 0, 1)
		label.TextTransparency = fade
		stroke.Transparency = fade
		if age >= 0.8 then
			holder:Destroy()
			local index = table.find(numbers, holder)
			if index then
				table.remove(numbers, index)
			end
			return false
		end
		return true
	end)
end

-- Short floating word (MARKIERT!, KONTER! ...) in a given color, popping in.
function Effects.label(position: Vector3, text: string, color: Color3)
	local holder = anchor(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 38)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Parent = gui
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService
		:Create(holder, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = position + Vector3.new(0, 3, 0) })
		:Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(holder, 1)
end

-- Combo counter that sits next to the attacker and pops on every hit ("3 HIT COMBO").
type Combo = { gui: BillboardGui, count: TextLabel, word: TextLabel, scale: UIScale, last: number, age: number }
local combos: { [number]: Combo } = {}

function Effects.combo(slot: number, adornee: BasePart, count: number, color: Color3)
	local text = GameFeel.comboText(count)
	if text == nil then
		return
	end
	local c = combos[slot]
	if c == nil or c.gui.Parent == nil then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Combo"
		gui.Size = UDim2.fromOffset(150, 64)
		gui.StudsOffset = Vector3.new(0, 3.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Parent = container()
		local scale = Instance.new("UIScale")
		scale.Parent = gui
		local number = Instance.new("TextLabel")
		number.Size = UDim2.fromScale(1, 0.66)
		number.BackgroundTransparency = 1
		number.Font = Enum.Font.GothamBlack
		number.TextScaled = true
		number.TextStrokeTransparency = 0
		number.Parent = gui
		local word = Instance.new("TextLabel")
		word.Size = UDim2.fromScale(1, 0.34)
		word.Position = UDim2.fromScale(0, 0.66)
		word.BackgroundTransparency = 1
		word.Font = Enum.Font.GothamBold
		word.TextScaled = true
		word.TextColor3 = Color3.new(1, 1, 1)
		word.TextStrokeTransparency = 0.2
		word.Text = "HIT COMBO"
		word.Parent = gui
		local made: Combo = { gui = gui, count = number, word = word, scale = scale, last = 0, age = 0 }
		c = made
		combos[slot] = made
		animate(function(dt)
			if made.gui.Parent == nil then
				if combos[slot] == made then
					combos[slot] = nil
				end
				return false
			end
			made.age += dt
			-- Pop (1.5 -> 1) after each hit, then fade out 1.2 s after the last one.
			local since = made.age - made.last
			made.scale.Scale = 1 + 0.5 * math.exp(-since * 14)
			local fade = math.clamp((since - 1.2) / 0.3, 0, 1)
			made.count.TextTransparency = fade
			made.count.TextStrokeTransparency = fade
			made.word.TextTransparency = fade
			made.word.TextStrokeTransparency = 0.2 + fade * 0.8
			if fade >= 1 then
				made.gui:Destroy()
				if combos[slot] == made then
					combos[slot] = nil
				end
				return false
			end
			return true
		end)
	end
	local combo = c :: Combo
	combo.gui.Adornee = adornee
	combo.last = combo.age
	combo.count.Text = tostring(math.floor(count))
	-- Hotter colors for longer combos.
	local heat = math.clamp((count - 2) / 8, 0, 1)
	combo.count.TextColor3 = color:Lerp(Color3.fromRGB(255, 70, 50), heat * 0.7):Lerp(Color3.new(1, 1, 1), 0.15)
	combo.count.Rotation = (math.random() - 0.5) * 10
end

function Effects.comboEnd(slot: number)
	local c = combos[slot]
	if c then
		-- Jump straight to the fade.
		c.last = math.min(c.last, c.age - 1.2)
	end
end

function Effects.clearCombos()
	for slot, c in combos do
		c.gui:Destroy()
		combos[slot] = nil
	end
end

-- Big "K.O." stinger in the middle of the screen: slams in from large with two color ghosts that converge,
-- holds, then stretches out and fades.
function Effects.koBanner(text: string, color: Color3)
	local layer = Instance.new("Frame")
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.Position = UDim2.fromScale(0.5, 0.48)
	layer.Size = UDim2.fromScale(0.7, 0.24)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 5
	layer.Parent = screen()
	local scale = Instance.new("UIScale")
	scale.Scale = 3
	scale.Parent = layer
	-- Dark band behind the text.
	local band = Instance.new("Frame")
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromScale(0, 0.62)
	band.BackgroundColor3 = Color3.new(0.04, 0.02, 0.05)
	band.BackgroundTransparency = 0.25
	band.BorderSizePixel = 0
	band.ZIndex = 5
	band.Parent = layer
	local function word(tint: Color3, z: number): TextLabel
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = tint
		l.ZIndex = z
		l.Parent = layer
		return l
	end
	local ghostA = word(color, 6)
	local ghostB = word(Color3.fromRGB(80, 220, 255), 6)
	local main = word(Color3.new(1, 1, 1), 7)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.new(0.05, 0.02, 0.05)
	stroke.Parent = main
	local age = 0
	animate(function(dt)
		age += dt
		if layer.Parent == nil then
			return false
		end
		-- Slam: 3 -> 0.92 in 0.14 s, settle to 1; ghosts converge; band wipes open.
		if age < 0.14 then
			scale.Scale = 3 - (age / 0.14) * 2.08
		else
			scale.Scale = 1 + (0.92 - 1) * math.exp(-(age - 0.14) * 18) * math.cos((age - 0.14) * 30)
		end
		local split = 0.06 * math.exp(-age * 6)
		ghostA.Position = UDim2.fromScale(0.5 - split, 0.5)
		ghostB.Position = UDim2.fromScale(0.5 + split, 0.5)
		local ghostFade = math.clamp(0.35 + age * 1.2, 0, 1)
		ghostA.TextTransparency = ghostFade
		ghostB.TextTransparency = ghostFade
		band.Size = UDim2.fromScale(math.min(1.6, age / 0.18 * 1.6), 0.62)
		local out = math.clamp((age - 1.25) / 0.35, 0, 1)
		if out > 0 then
			layer.Size = UDim2.fromScale(0.7 * (1 + out * 0.8), 0.24 * (1 - out * 0.85))
			main.TextTransparency = out
			stroke.Transparency = out
			band.BackgroundTransparency = 0.25 + out * 0.75
		end
		if age >= 1.6 then
			layer:Destroy()
			return false
		end
		return true
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Composite effects

-- Shield ripple: a force-field bubble flash plus a crisp ring where the hit landed.
function Effects.shieldRipple(center: Vector3, hitPoint: Vector3, color: Color3, size: number)
	local bubble = Instance.new("Part")
	bare(bubble)
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Color = color
	bubble.Size = Vector3.one * size * 0.9
	bubble.Position = center
	bubble.Transparency = 0
	bubble.Parent = container()
	TweenService:Create(
		bubble,
		TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size * 1.25, Transparency = 1 }
	):Play()
	Debris:AddItem(bubble, 0.35)
	Effects.ring(hitPoint, color, size * 0.7, 0.22, 0.3)
end

-- KO: a beam from the blast point back across the stage, a star flash, shockwaves, sparks, speed lines and a
-- screen flash. direction points from the blast point toward the stage center.
function Effects.knockout(position: Vector3, color: Color3, direction: Vector3?, decisive: boolean?)
	local dir = if direction and direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
	local length = LOOK.koBeamLength
	local mid = position + dir * (length / 2)
	local beamCf = CFrame.lookAt(mid, mid + dir)
	local outer = neon(Vector3.new(LOOK.koBeamWidth * 2.2, LOOK.koBeamWidth * 2.2, length), color)
	outer.Transparency = 0.55
	outer.CFrame = beamCf
	outer.Parent = container()
	local inner = neon(Vector3.new(LOOK.koBeamWidth, LOOK.koBeamWidth, length), color:Lerp(Color3.new(1, 1, 1), 0.35))
	inner.CFrame = beamCf
	inner.Parent = container()
	local core = neon(Vector3.new(LOOK.koBeamWidth * 0.35, LOOK.koBeamWidth * 0.35, length), Color3.new(1, 1, 1))
	core.CFrame = beamCf
	core.Parent = container()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 60
	light.Brightness = 8
	light.Shadows = false
	light.Parent = core
	local d = if decisive then 0.9 else 0.6
	local age = 0
	animate(function(dt)
		age += dt
		local f = math.min(1, age / d)
		-- Snap open, then pinch to a thread while fading.
		local w = if f < 0.08 then 0.4 + f / 0.08 * 0.8 else 1.2 * (1 - (f - 0.08) / 0.92) ^ 1.6
		outer.Size = Vector3.new(LOOK.koBeamWidth * 2.2 * w, LOOK.koBeamWidth * 2.2 * w, length)
		inner.Size = Vector3.new(LOOK.koBeamWidth * w, LOOK.koBeamWidth * w, length)
		local c = LOOK.koBeamWidth * 0.35 * math.max(w, 0.2)
		core.Size = Vector3.new(c, c, length)
		outer.Transparency = 0.55 + 0.45 * f
		inner.Transparency = 0.1 + 0.9 * f
		core.Transparency = f ^ 2
		light.Brightness = 8 * (1 - f)
		if f >= 1 then
			outer:Destroy()
			inner:Destroy()
			core:Destroy()
			return false
		end
		return true
	end)
	local big = if decisive then 1.35 else 1
	Effects.impactStar(position + dir * 3, color, 34 * big, 0.45)
	Effects.flashBall(position, color, 45 * big, 0.6)
	Effects.shockwave(position, color, 70 * big, 0.55)
	task.delay(0.08, function()
		Effects.ring(position, Color3.new(1, 1, 1), 45 * big, 0.4, 0.4)
	end)
	Effects.sparksToward(position, dir, color, 50, 90)
	Effects.sparks(position, color, 40, 70)
	Effects.speedLines(position + dir * 10, color, 1)
	Effects.impactFrame(1, if decisive then 0.12 else 0.07)
	Effects.screenFlash(color, if decisive then 0.45 else 0.28, 1)
end

-- Clear running per-match effects (combo counters, impact frame) when a match ends.
function Effects.reset()
	Effects.clearCombos()
	local g = grade
	if g then
		g.Contrast, g.Saturation, g.Brightness = 0, 0, 0
	end
end

return Effects
