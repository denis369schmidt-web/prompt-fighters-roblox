--!strict
-- Draws the fighters from server snapshots: builds each fighter's R15-shaped rig locally (Visual/RigBuilder),
-- moves it smoothly toward the newest snapshot and animates the joints procedurally (Visual/Pose).
-- Also owns the per-fighter effects: weapon trails while striking, tumble trail when launched, shield bubble,
-- hit flash, and the hit/KO/clash effects from match events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local Looks = require(Shared:WaitForChild("Data"):WaitForChild("Looks"))
local Pose = require(Shared:WaitForChild("Visual"):WaitForChild("Pose"))
local RigBuilder = require(Shared:WaitForChild("Visual"):WaitForChild("RigBuilder"))
local MatchRunner = require(Shared:WaitForChild("Combat"):WaitForChild("MatchRunner"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local Effects = require(script.Parent.Effects)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local FOLLOW = 22
local EASE = 14
local EASE_SNAPPY = 32
local SNAP_DISTANCE = 6 * M
-- Fighters turn a little toward the camera so faces and gear read in a side view.
local CAMERA_TURN = 0.35

type View = {
	model: Model,
	root: BasePart,
	standHeight: number,
	motors: { [string]: Motor6D },
	angles: { [string]: Vector3 },
	rootY: number,
	pitch: number,
	roll: number,
	position: Vector3,
	lastX: number,
	phase: number,
	vy: number,
	lastY: number,
	glow: Color3,
	trail: Trail?,
	tumble: Trail,
	shield: Part,
	highlight: Highlight,
	label: TextLabel,
	flash: number,
}

local FighterView = {}

local views: { [number]: View } = {}
local folder: Folder? = nil

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

local function trailBetween(part: BasePart, a: Vector3, b: Vector3, color: Color3, lifetime: number): Trail
	local att0 = Instance.new("Attachment")
	att0.Position = a
	att0.Parent = part
	local att1 = Instance.new("Attachment")
	att1.Position = b
	att1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.LightEmission = 1
	trail.Lifetime = lifetime
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = part
	return trail
end

local function build()
	clear()
	local f = Instance.new("Folder")
	f.Name = "Fighters"
	f.Parent = workspace
	folder = f
	for i, slot in MatchState.slots do
		local model = RigBuilder.build(slot.fighterId)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		local standHeight = (model:GetAttribute("StandHeight") :: number?) or RigBuilder.STAND_HEIGHT
		local motors: { [string]: Motor6D } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				motors[d.Name] = d
			end
		end
		local look = Looks.get(slot.fighterId)
		local glow = Color3.fromHex(look.glow)
		local slotColor = Color3.fromHex(Visuals.SLOT_COLORS[i] or "#FFFFFF")

		-- Strike trail on the hand that hits (and along a held blade if there is one).
		local hand = model:FindFirstChild("RightHand", true)
		local trail: Trail? = nil
		if hand and hand:IsA("BasePart") then
			local blade = hand:FindFirstChild("Blade")
			if blade and blade:IsA("BasePart") then
				trail = trailBetween(hand, Vector3.new(0, -0.2, -0.6), Vector3.new(0, -0.2, -3.6), glow, 0.18)
			else
				trail = trailBetween(hand, Vector3.new(0, 0.3, 0), Vector3.new(0, -0.5, 0), glow, 0.15)
			end
		end
		local tumble = trailBetween(root, Vector3.new(0, 1.2, 0), Vector3.new(0, -1.2, 0), slotColor, 0.35)

		local shield = Instance.new("Part")
		shield.Name = "Shield"
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.one * 7
		shield.Material = Enum.Material.ForceField
		shield.Color = slotColor
		shield.Transparency = 1
		shield.Anchored = true
		shield.CanCollide = false
		shield.CanQuery = false
		shield.CanTouch = false
		shield.Parent = model

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = slotColor
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model

		local head = model:FindFirstChild("Head") or root
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(90, 22)
		-- Staggered heights so tags of fighters standing close together don't cover each other.
		tag.StudsOffset = Vector3.new(0, 2.2 + ((i - 1) % 2) * 1.1, 0)
		tag.AlwaysOnTop = true
		tag.LightInfluence = 0
		tag.Adornee = head :: BasePart
		tag.Parent = model
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = slotColor
		label.TextStrokeTransparency = 0.2
		label.Text = if slot.player then `P{i}` else `CPU {i}`
		label.Parent = tag

		model.Parent = f
		local angles = {}
		for _, name in Pose.JOINTS do
			angles[name] = Vector3.zero
		end
		views[i] = {
			model = model,
			root = root,
			standHeight = standHeight,
			motors = motors,
			angles = angles,
			rootY = 0,
			pitch = 0,
			roll = 0,
			position = Vector3.zero,
			lastX = 0,
			phase = 0,
			vy = 0,
			lastY = 0,
			glow = glow,
			trail = trail,
			tumble = tumble,
			shield = shield,
			highlight = highlight,
			label = label,
			flash = 0,
		}
	end
end

local function setVisible(view: View, visible: boolean)
	for _, d in view.model:GetDescendants() do
		if d:IsA("BasePart") and d ~= view.root and d.Name ~= "Shield" then
			d.LocalTransparencyModifier = if visible then 0 else 1
		elseif d:IsA("Decal") then
			d.Transparency = if visible then 0 else 1
		end
	end
	view.label.Visible = visible
	view.highlight.Enabled = visible
end

local function render(dt: number)
	if MatchState.snapshot == nil then
		return
	end
	local snap = MatchState.snapshot :: MatchRunner.NetSnapshot
	local follow = 1 - math.exp(-FOLLOW * dt)
	local t = os.clock()
	local blink = (t * 12) % 2 < 1
	for i, f in snap.fighters do
		local view = views[i]
		if not view then
			continue
		end
		local target = FighterView.toWorld(f.x, f.y)
		local snapped = (target - view.position).Magnitude > SNAP_DISTANCE or view.position == Vector3.zero
		view.position = if snapped then target else view.position:Lerp(target, follow)

		-- Speeds from the smoothed motion (the snapshot doesn't carry velocity).
		local dx = (view.position.X - view.lastX) / M
		local dy = (view.position.Y - view.lastY) / M
		view.lastX, view.lastY = view.position.X, view.position.Y
		local speed = if dt > 0 and not snapped then math.abs(dx) / dt else 0
		view.vy = if dt > 0 and not snapped then view.vy + (dy / dt - view.vy) * 0.3 else 0
		view.phase += math.abs(dx) * 3.2

		local pose = Pose.compute({
			state = f.state,
			move = f.move,
			stage = f.moveStage,
			grounded = f.grounded,
			blocking = f.blocking,
			speed = speed,
			vy = view.vy,
			phase = view.phase,
			t = t,
		})
		local ease = 1 - math.exp(-(if pose.snappy then EASE_SNAPPY else EASE) * dt)
		for name, motor in view.motors do
			local goal = pose.joints[name]
			if goal then
				local current = view.angles[name]:Lerp(Vector3.new(goal.x, goal.y, goal.z), ease)
				view.angles[name] = current
				motor.Transform = CFrame.Angles(math.rad(current.X), math.rad(current.Y), math.rad(current.Z))
			end
		end
		view.rootY += (pose.rootY - view.rootY) * ease
		view.pitch += (pose.pitch - view.pitch) * ease
		view.roll += (pose.roll - view.roll) * ease

		local look = Vector3.new(f.facing, 0, CAMERA_TURN).Unit
		local base = view.position + Vector3.new(0, view.standHeight + view.rootY, 0)
		view.root.CFrame = CFrame.lookAt(base, base + look)
			* CFrame.Angles(math.rad(-view.pitch), math.rad(pose.spin), math.rad(view.roll))

		local alive = f.state ~= "Defeated"
		setVisible(view, alive and not (f.invulnerable and blink))
		view.shield.Transparency = if f.blocking and alive then 0.3 else 1
		view.shield.CFrame = view.root.CFrame
		local trail = view.trail
		if trail then
			trail.Enabled = f.moveStage == "active"
		end
		view.tumble.Enabled = f.state == "HitStun" and speed > 8

		view.flash = math.max(0, view.flash - dt)
		view.highlight.FillTransparency = if view.flash > 0 then 0.2 else 1
		view.highlight.FillColor = Color3.new(1, 1, 1)
	end
end

local function chest(view: View): Vector3
	return view.position + Vector3.new(0, view.standHeight + 1, 0)
end

function FighterView.start()
	MatchState.onEvent(function(event)
		local kind = event.type
		if kind == "phase" then
			if event.phase == "match" then
				build()
			elseif event.phase == "lobby" then
				clear()
			end
		elseif kind == "hit" then
			local target = views[event.target]
			local attacker = views[event.actor]
			if target then
				target.flash = 0.1
				local color = if attacker then attacker.glow else Color3.new(1, 0.9, 0.5)
				local damage = event.damage or 5
				Effects.sparks(chest(target), color, 6 + damage, 20 + damage * 1.5)
				Effects.damageNumber(chest(target) + Vector3.new(0, 2.5, 0), damage)
				if (event.impulse or 0) > 9 or event.superHit then
					Effects.ring(chest(target), color, 10 + damage * 0.5)
					Effects.flashBall(chest(target), color, 6 + damage * 0.3, 0.25)
				end
			end
		elseif kind == "block" then
			local target = views[event.target]
			if target then
				Effects.sparks(chest(target), Color3.fromRGB(150, 220, 255), 8, 18)
			end
		elseif kind == "parry" then
			local view = views[event.actor]
			if view then
				Effects.ring(chest(view), Color3.new(1, 1, 1), 14, 0.25)
				Effects.flashBall(chest(view), Color3.fromRGB(255, 240, 160), 6, 0.2)
			end
		elseif kind == "clash" then
			local p = FighterView.toWorld(event.x, event.y)
			Effects.sparks(p, Color3.new(1, 1, 1), 30, 40)
			Effects.ring(p, Color3.fromRGB(255, 230, 120), 16, 0.3)
		elseif kind == "ring_out" then
			local view = views[event.actor]
			local x = math.clamp(event.x, -15.5, 15.5)
			local y = math.clamp(event.y, -5.5, 12.5)
			Effects.knockout(FighterView.toWorld(x, y), if view then view.glow else Color3.new(1, 1, 1))
		elseif kind == "shield_break" then
			local view = views[event.actor]
			if view then
				Effects.sparks(chest(view), Color3.fromRGB(120, 200, 255), 40, 35)
				Effects.ring(chest(view), Color3.fromRGB(120, 200, 255), 18)
			end
		elseif kind == "super_used" then
			local view = views[event.actor]
			if view then
				Effects.flashBall(chest(view), view.glow, 12, 0.35)
			end
		elseif kind == "finisher" then
			local view = views[event.target]
			if view then
				Effects.knockout(chest(view), views[event.actor] and views[event.actor].glow or view.glow)
			end
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return FighterView
