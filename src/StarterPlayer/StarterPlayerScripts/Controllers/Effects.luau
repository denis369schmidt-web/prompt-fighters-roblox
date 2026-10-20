--!strict
-- One-shot visual effects (client only): hit sparks, shockwave rings, damage numbers, KO blasts and a screen
-- flash. Built from parts, ParticleEmitters with the default texture and BillboardGuis, so no asset uploads.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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

local function anchor(position: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Position = position
	p.Parent = container()
	return p
end

-- Spark burst: count scales with damage.
function Effects.sparks(position: Vector3, color: Color3, amount: number, speed: number?)
	local holder = anchor(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.18, 0.4)
	emitter.Speed = NumberRange.new((speed or 30) * 0.5, speed or 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(math.clamp(math.floor(amount), 4, 60))
	Debris:AddItem(holder, 1)
end

-- Flat ring that grows and fades (big hits, landings, KOs).
function Effects.ring(position: Vector3, color: Color3, size: number, duration: number?)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
	ring.Transparency = 0.2
	ring.Parent = container()
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, size, size), Transparency = 1 }
	)
	tween:Play()
	Debris:AddItem(ring, (duration or 0.35) + 0.1)
end

-- Glowing ball that blows up and fades.
function Effects.flashBall(position: Vector3, color: Color3, size: number, duration: number?)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Size = Vector3.one * 1.5
	ball.Position = position
	ball.Parent = container()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 1.5
	light.Brightness = 6
	light.Parent = ball
	local info = TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ball, info, { Size = Vector3.one * size, Transparency = 1 }):Play()
	TweenService:Create(light, info, { Brightness = 0 }):Play()
	Debris:AddItem(ball, (duration or 0.4) + 0.1)
end

-- Floating damage number; big hits are larger and redder.
function Effects.damageNumber(position: Vector3, damage: number, color: Color3?)
	local holder = anchor(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = tostring(math.floor(damage + 0.5))
	local heat = math.clamp(damage / 25, 0, 1)
	label.TextColor3 = color or Color3.new(1, 1 - heat * 0.7, 1 - heat)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local scale = 0.8 + heat * 0.8
	gui.Size = UDim2.fromOffset(90 * scale, 40 * scale)
	TweenService:Create(
		holder,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad),
		{ Position = position + Vector3.new(math.random(-10, 10) / 10, 4, 0) }
	):Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(holder, 0.8)
end

-- KO: blast at the blast zone, ring, sparks and a short white screen flash.
function Effects.knockout(position: Vector3, color: Color3)
	Effects.flashBall(position, color, 45, 0.6)
	Effects.ring(position, Color3.new(1, 1, 1), 70, 0.5)
	Effects.sparks(position, color, 60, 80)
	Effects.screenFlash(color, 0.25)
end

local flashGui: ScreenGui? = nil
function Effects.screenFlash(color: Color3, duration: number)
	local gui = flashGui
	if not gui then
		local g = Instance.new("ScreenGui")
		g.Name = "Flash"
		g.IgnoreGuiInset = true
		g.DisplayOrder = 50
		g.ResetOnSpawn = false
		g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		flashGui = g
		gui = g
	end
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Parent = gui
	TweenService:Create(frame, TweenInfo.new(duration), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(frame, duration + 0.05)
end

return Effects
