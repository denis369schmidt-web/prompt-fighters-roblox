--!strict
-- Draws the fighters from server snapshots: a simple block body per fighter (Phase 1 placeholder art),
-- smoothed toward the newest snapshot, plus hit flashes, shields, KO bursts and the finisher banner hook.
-- Real models and animations replace the blocks in Phase 4; the interface (update / effects) stays the same.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local MatchRunner = require(Shared:WaitForChild("Combat"):WaitForChild("MatchRunner"))
local MatchState = require(script.Parent.Parent.State.MatchState)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local HEIGHT = Visuals.BODY_HEIGHT_M * M
local WIDTH = Visuals.BODY_WIDTH_M * M
local SMOOTHING = 22
local SNAP_DISTANCE = 6 * M

type View = {
	model: Model,
	body: Part,
	head: Part,
	fist: Part,
	shield: Part,
	label: TextLabel,
	position: Vector3,
	color: Color3,
	flash: number,
}

local FighterView = {}

local views: { [number]: View } = {}
local folder: Folder? = nil

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

function FighterView.toWorld(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

local function clear()
	if folder then
		folder:Destroy()
	end
	folder = nil
	table.clear(views)
end

local function build()
	clear()
	local f = Instance.new("Folder")
	f.Name = "Fighters"
	f.Parent = workspace
	folder = f
	for i, slot in MatchState.slots do
		local color = Color3.fromHex(Visuals.elementColor(slot.element))
		local slotColor = Color3.fromHex(Visuals.SLOT_COLORS[i] or "#FFFFFF")
		local model = Instance.new("Model")
		model.Name = slot.name
		local body = newPart(model, "Body", Vector3.new(WIDTH, HEIGHT * 0.68, WIDTH * 0.8), color)
		local head =
			newPart(model, "Head", Vector3.new(WIDTH * 0.8, WIDTH * 0.8, WIDTH * 0.8), color, Enum.PartType.Ball)
		local fist =
			newPart(model, "Fist", Vector3.new(WIDTH * 0.55, WIDTH * 0.55, WIDTH * 0.55), color, Enum.PartType.Ball)
		fist.Material = Enum.Material.Neon
		fist.Transparency = 1
		local shield = newPart(model, "Shield", Vector3.one * HEIGHT * 1.15, slotColor, Enum.PartType.Ball)
		shield.Material = Enum.Material.ForceField
		shield.Transparency = 1
		local outline = Instance.new("Highlight")
		outline.FillTransparency = 1
		outline.OutlineColor = slotColor
		outline.Parent = model

		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(160, 28)
		tag.StudsOffset = Vector3.new(0, HEIGHT * 0.75, 0)
		tag.AlwaysOnTop = true
		tag.Adornee = head
		tag.Parent = model
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = slotColor
		label.TextStrokeTransparency = 0.3
		label.Text = if slot.player then `P{i} {slot.player}` else `CPU {slot.name}`
		label.Parent = tag

		model.Parent = f
		views[i] = {
			model = model,
			body = body,
			head = head,
			fist = fist,
			shield = shield,
			label = label,
			position = Vector3.zero,
			color = color,
			flash = 0,
		}
	end
end

local function burst(position: Vector3, color: Color3, size: number)
	if folder == nil then
		return
	end
	local ball = newPart(folder :: Folder, "Burst", Vector3.one * 2, color, Enum.PartType.Ball)
	ball.Material = Enum.Material.Neon
	ball.Position = position
	local tween = TweenService:Create(
		ball,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Once(function()
		ball:Destroy()
	end)
end

local function render(dt: number)
	if MatchState.snapshot == nil then
		return
	end
	local snap = MatchState.snapshot :: MatchRunner.NetSnapshot
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	local blink = (os.clock() * 12) % 2 < 1
	for i, f in snap.fighters do
		local view = views[i]
		if not view then
			continue
		end
		local hidden = f.state == "Defeated"
		local target = FighterView.toWorld(f.x, f.y)
		if (target - view.position).Magnitude > SNAP_DISTANCE or view.position == Vector3.zero then
			view.position = target
		else
			view.position = view.position:Lerp(target, alpha)
		end
		local base = view.position
		local lean = if f.state == "HitStun" or f.state == "ShieldBreak" then math.rad(25) * -f.facing else 0
		local crouch = if f.state == "Dazed" or f.state == "Ledge" then 0.7 else 1
		local bodyCf = CFrame.new(base + Vector3.new(0, HEIGHT * 0.34 * crouch, 0)) * CFrame.Angles(0, 0, lean)
		view.body.CFrame = bodyCf
		view.body.Size = Vector3.new(WIDTH, HEIGHT * 0.68 * crouch, WIDTH * 0.8)
		view.head.CFrame = bodyCf * CFrame.new(0, HEIGHT * 0.34 * crouch + WIDTH * 0.42, 0)

		local attacking = f.moveStage == "active"
		view.fist.Transparency = if attacking then 0 elseif f.moveStage == "windup" then 0.6 else 1
		local reach = if attacking then WIDTH * 1.4 else WIDTH * 0.7
		view.fist.CFrame = bodyCf * CFrame.new(f.facing * reach, HEIGHT * 0.1, -0.2)

		view.shield.Transparency = if f.blocking then 0.35 else 1
		view.shield.CFrame = bodyCf

		view.flash = math.max(0, view.flash - dt)
		local invisible = hidden or (f.invulnerable and blink)
		local transparency = if invisible then 1 else 0
		view.body.Transparency = transparency
		view.head.Transparency = transparency
		view.body.Color = if view.flash > 0 then Color3.new(1, 1, 1) else view.color
		view.label.Visible = not hidden
	end
end

function FighterView.start()
	MatchState.onEvent(function(event)
		if event.type == "phase" then
			if event.phase == "match" then
				build()
			elseif event.phase == "lobby" then
				clear()
			end
		elseif event.type == "hit" then
			local view = views[event.target]
			if view then
				view.flash = 0.12
				burst(view.position + Vector3.new(0, HEIGHT * 0.5, 0), Color3.new(1, 0.9, 0.5), 4 + event.damage * 0.25)
			end
		elseif event.type == "clash" then
			burst(FighterView.toWorld(event.x, event.y), Color3.new(1, 1, 1), 9)
		elseif event.type == "ring_out" then
			local view = views[event.actor]
			-- The KO burst sits on the blast zone side, like the big flash fighting games use for a stock loss.
			local x = math.clamp(event.x, -15, 15)
			local y = math.clamp(event.y, -5, 12)
			burst(FighterView.toWorld(x, y), if view then view.color else Color3.new(1, 1, 1), 40)
		elseif event.type == "shield_break" then
			local view = views[event.actor]
			if view then
				burst(view.position + Vector3.new(0, HEIGHT, 0), Color3.fromRGB(120, 200, 255), 14)
			end
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return FighterView
