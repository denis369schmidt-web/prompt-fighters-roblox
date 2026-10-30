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
local Simulation = require(Shared:WaitForChild("Combat"):WaitForChild("Simulation"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local Effects = require(script.Parent.Effects)
local Juice = require(script.Parent.Juice)
local Sfx = require(script.Parent.Sfx)
local GameFeel = require(Shared:WaitForChild("Visual"):WaitForChild("GameFeel"))

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
	ice: Part,
	wings: { Part },
	scale: number,
}

local STATUS = Simulation.STATUS
local ICE = Color3.fromRGB(150, 220, 255)
local GOLD = Color3.fromRGB(255, 210, 90)
local HEX = Color3.fromRGB(170, 80, 255)
local RAGE = Color3.fromRGB(255, 60, 40)

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
	-- White-hot edge into the fighter's glow, tapering and fading (strike / tumble trails).
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.25, color:Lerp(Color3.new(1, 1, 1), 0.3)),
		ColorSequenceKeypoint.new(1, color),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.MinLength = 0.05
	trail.Lifetime = lifetime * 1.4
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

		-- Ice block while frozen, eagle wings while flying.
		local ice = Instance.new("Part")
		ice.Name = "Ice"
		ice.Size = Vector3.new(4.2, 7.5, 3.2)
		ice.Material = Enum.Material.Glass
		ice.Color = ICE
		ice.Transparency = 1
		ice.Anchored = true
		ice.CanCollide = false
		ice.CanQuery = false
		ice.CanTouch = false
		ice.Parent = model
		local wings = {}
		for side = -1, 1, 2 do
			local wing = Instance.new("Part")
			wing.Name = "Wing"
			wing.Size = Vector3.new(0.2, 1.4, 4.5)
			wing.Material = Enum.Material.Neon
			wing.Color = GOLD
			wing.Transparency = 1
			wing.Anchored = true
			wing.CanCollide = false
			wing.CanQuery = false
			wing.CanTouch = false
			wing:SetAttribute("Side", side)
			wing.Parent = model
			table.insert(wings, wing)
		end

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = slotColor
		highlight.OutlineTransparency = if i == MatchState.mySlot then 0 else 0.55
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model

		local head = model:FindFirstChild("Head") or root
		-- Small marker above the head: "DU" for your own fighter, a colored arrow for everyone else
		-- (the color matches their damage card at the bottom).
		local mine = i == MatchState.mySlot
		local tag = Instance.new("BillboardGui")
		tag.Size = if mine then UDim2.fromOffset(56, 30) else UDim2.fromOffset(22, 18)
		tag.StudsOffset = Vector3.new(0, 2.4, 0)
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
		label.Text = if mine then "DU\n▼" else "▼"
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
			ice = ice,
			wings = wings,
			scale = 1,
		}
	end
end

local function setVisible(view: View, visible: boolean)
	for _, d in view.model:GetDescendants() do
		if d:IsA("BasePart") and d ~= view.root and d.Name ~= "Shield" and d.Name ~= "Ice" and d.Name ~= "Wing" then
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
		if not view or Juice.frozen(i) then -- Juice.frozen: hitstop hold (Controllers/Juice)
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

		-- Status: ice, wings, and a colored glow for rage, curse, armor, mark and a full heat gauge.
		local status = f.status or 0
		local function has(bit: number): boolean
			return bit32.btest(status, bit)
		end
		-- Titan mushroom: the fighter grows to one and a half times the size.
		local wantScale = if has(STATUS.titan) then 1.5 else 1
		if wantScale ~= view.scale then
			view.model:ScaleTo(wantScale)
			view.standHeight = view.standHeight / view.scale * wantScale
			view.scale = wantScale
		end
		view.ice.Transparency = if has(STATUS.frozen) and alive then 0.35 else 1
		view.ice.CFrame = CFrame.new(view.position + Vector3.new(0, view.ice.Size.Y / 2, 0))
		local flying = has(STATUS.eagle) and alive
		local flap = math.sin(t * 14) * 0.5
		for _, wing in view.wings do
			local side = wing:GetAttribute("Side") :: number
			wing.Transparency = if flying then 0.15 else 1
			wing.CFrame = view.root.CFrame
				* CFrame.new(side * 1.6, 1.4, 0.6)
				* CFrame.Angles(0, 0, side * (0.5 + flap))
				* CFrame.new(side * 1.4, 0, 0)
		end
		view.flash = math.max(0, view.flash - dt)
		local fill, fillT = Color3.new(1, 1, 1), 1
		if view.flash > 0 then
			fill, fillT = Color3.new(1, 1, 1), 0.2
		elseif has(STATUS.frozen) then
			fill, fillT = ICE, 0.4
		elseif has(STATUS.hexed) then
			fill, fillT = HEX, 0.55
		elseif has(STATUS.rage) then
			fill, fillT = RAGE, 0.6
		elseif has(STATUS.heatFull) then
			fill, fillT = Color3.fromRGB(255, 110, 30), if blink then 0.5 else 0.75
		elseif has(STATUS.charging) then
			fill, fillT = view.glow, 0.5 + math.sin(t * 20) * 0.2
		elseif has(STATUS.marked) then
			fill, fillT = Color3.fromRGB(120, 230, 255), if blink then 0.55 else 0.85
		end
		view.highlight.FillColor = fill
		view.highlight.FillTransparency = fillT
		local armored = has(STATUS.armor) or has(STATUS.bulwark) or has(STATUS.turbo)
		view.highlight.OutlineColor = if armored then GOLD else view.label.TextColor3
	end
end

-- A body part of a drawn fighter (ItemView puts weapons into the right hand), or nil.
function FighterView.part(slot: number, name: string): BasePart?
	local view = views[slot]
	if view == nil then
		return nil
	end
	local found = view.model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function chest(view: View): Vector3
	return view.position + Vector3.new(0, view.standHeight + 1, 0)
end

---------------------------------------------------------------------------------------------------------------
-- Game feel ("juice") for match events. Everything below is display only and runs beside render():
-- render() skips a fighter while Juice.frozen(slot) is true, and juiceStep() shakes the held fighters and
-- draws dust and slash arcs from the snapshot.

local WHITE = Color3.new(1, 1, 1)
local SHIELD_BLUE = Color3.fromRGB(150, 220, 255)
local PARRY_GOLD = Color3.fromRGB(255, 240, 160)
local CLASH_GOLD = Color3.fromRGB(255, 230, 120)
local BREAK_BLUE = Color3.fromRGB(120, 200, 255)

-- Slash arc per move kind (Pose.MOVE_KIND): angle (degrees, + = upward), radius (studs), heavy look.
local ARCS: { [string]: { angle: number, radius: number, heavy: boolean, twin: boolean? } } = {
	punch = { angle = 0, radius = 2.4, heavy = false },
	kick = { angle = 15, radius = 2.8, heavy = false },
	heavy = { angle = 10, radius = 3.6, heavy = true },
	upper = { angle = 90, radius = 3.2, heavy = false },
	low = { angle = -45, radius = 3, heavy = false },
	stomp = { angle = -90, radius = 2.8, heavy = false },
	spin = { angle = 0, radius = 3, heavy = false, twin = true },
	backkick = { angle = 180, radius = 2.8, heavy = false },
}

-- Fighters held by a hitstop get a small vibration (and, after a clash, a push away from the contact point).
type Shaker = { base: CFrame, dir: Vector3, amp: number, push: number, started: number, length: number }
local shakers: { [number]: Shaker } = {}

-- Per-slot snapshot memory for dust and slash arcs.
type Track = { grounded: boolean, stage: string, move: string, x: number, y: number, vy: number, runPuff: number }
local tracks: { [number]: Track } = {}

-- Hit direction in the fight plane from the attacker toward the target (unit vector).
local function hitDirection(attacker: View?, target: View): Vector3
	if attacker then
		local d = target.position - attacker.position
		d = Vector3.new(d.X, d.Y * 0.5 + 0.15 * math.abs(d.X), 0)
		if d.Magnitude > 1e-3 then
			return d.Unit
		end
	end
	return Vector3.yAxis
end

local function freeze(slot: number, seconds: number, dir: Vector3, amp: number, push: number?)
	local view = views[slot]
	if view == nil or seconds <= 0 then
		return
	end
	local current = shakers[slot]
	local base = if current and Juice.frozen(slot) then current.base else view.root.CFrame
	Juice.hold(seconds, { slot })
	shakers[slot] = { base = base, dir = dir, amp = amp, push = push or 0, started = os.clock(), length = seconds }
end

-- White impact flash on the fighter's highlight right away (render() takes over again after the hold).
local function whiteFlash(view: View, seconds: number)
	view.flash = math.max(view.flash, seconds)
	view.highlight.FillColor = WHITE
	view.highlight.FillTransparency = 0.05
end

local function onHit(event: { [string]: any })
	local target = views[event.target]
	if target == nil then
		return
	end
	local attacker = views[event.actor]
	local damage = event.damage or 5
	local impact = GameFeel.impact(damage, event.impulse, event.superHit, event.special)
	local color = if attacker then attacker.glow else Color3.new(1, 0.9, 0.5)
	local dir = hitDirection(attacker, target)
	local at = chest(target) - dir * 0.6 + Vector3.new(0, 0, 1.5)
	local s = impact.strength

	whiteFlash(target, 0.06 + s * 0.08)
	Effects.sparksToward(at, dir, color, 8 + damage * 1.2, 30 + s * 50)
	Effects.impactStar(at, if impact.tier == "light" then WHITE else color, 7 + s * 14, 0.16 + s * 0.12)
	Effects.damageNumber(chest(target) + Vector3.new(0, 2.6, 0), damage)
	if event.armored then
		Effects.ring(at, GOLD, 8, 0.2, 0.3)
		Sfx.play("metal", 0.7, 0.8)
		return
	end

	if impact.tier ~= "light" then
		Effects.shockwave(at, color, 9 + damage * 0.7, 0.3 + s * 0.15)
		Effects.flashBall(at, color, 4 + damage * 0.3, 0.2)
	end
	if impact.tier == "heavy" then
		Effects.impactFrame(s, 0.04 + s * 0.04)
		Effects.speedLines(at, color, s)
		Effects.debris(at, dir, color, 4 + math.floor(s * 6))
		Effects.sparks(at, color, 20 + damage, 50)
		Sfx.play("heavy", 0.6 + s * 0.5, 1.1 - s * 0.25)
	else
		Sfx.play("slash", 0.5 + s, 1 + (1 - s) * 0.2)
	end
	if event.superHit then
		Effects.screenFlash(color, 0.2, 0.8)
		Effects.ring(at, WHITE, 22 + damage, 0.35, 0.5)
	end

	-- Local hitstop: both fighters hold; the target vibrates along the hit direction.
	if impact.hold > 0 then
		freeze(event.target, impact.hold, dir, 0.25 + s * 0.45)
		if event.actor and event.actor ~= event.target then
			freeze(event.actor, impact.hold, dir, 0.05)
		end
	end

	if attacker and (event.combo or 0) >= 2 then
		local head = attacker.model:FindFirstChild("Head")
		Effects.combo(event.actor, if head and head:IsA("BasePart") then head else attacker.root, event.combo, color)
	end
end

local function onRingOut(event: { [string]: any })
	local view = views[event.actor]
	local color = if view then view.glow else WHITE
	local x = math.clamp(event.x or 0, -15.5, 15.5)
	local y = math.clamp(event.y or 0, -5.5, 12.5)
	local dx, dy = GameFeel.koDirection(x, y)
	-- Match-deciding KO: last stock gone and at most one fighter left.
	local decisive = false
	if (event.lives or 0) <= 0 then
		local standing = 0
		local snap = MatchState.snapshot
		if snap then
			for i, f in snap.fighters do
				if i ~= event.actor and f.state ~= "Defeated" and f.lives > 0 then
					standing += 1
				end
			end
		end
		decisive = standing <= 1
	end
	Effects.knockout(FighterView.toWorld(x, y), color, Vector3.new(dx, dy, 0), decisive)
	Sfx.play("heavy", 1, 0.6)
	Sfx.play("slash", 0.8, 0.7)
	if decisive then
		Effects.koBanner("K.O.", color)
		Juice.hold(0.12)
	end
	Effects.comboEnd(event.actor)
end

-- Dust, landing puffs and slash arcs from snapshot changes.
local function trackFighters(snap: MatchRunner.NetSnapshot, dt: number)
	for i, f in snap.fighters do
		local view = views[i]
		if view == nil or view.position == Vector3.zero then
			continue
		end
		local t = tracks[i]
		if t == nil then
			t = {
				grounded = f.grounded,
				stage = f.moveStage,
				move = f.move,
				x = view.position.X,
				y = view.position.Y,
				vy = 0,
				runPuff = 0,
			}
			tracks[i] = t
		end
		local track = t :: Track
		local alive = f.state ~= "Defeated"
		local feet = view.position + Vector3.new(0, 0.3, 0)
		local vx = (view.position.X - track.x) / dt / M
		track.x = view.position.X
		-- Smoothed vertical speed (m/s) of the drawn fighter, for landing dust.
		local vy = (view.position.Y - track.y) / dt / M
		track.y = view.position.Y
		if not f.grounded then
			track.vy += (vy - track.vy) * 0.4
		end

		-- Landing: a dust puff that grows with the fall speed, plus a ground ring for hard landings.
		if alive and f.grounded and not track.grounded then
			local fall = math.clamp(-track.vy / 14, 0, 1)
			track.vy = 0
			Effects.dust(feet, 4 + fall * 10, 6 + fall * 10)
			if fall > 0.45 then
				Effects.groundRing(feet, WHITE, 5 + fall * 6, 0.25)
			end
		end
		-- Running: small puffs kicked up behind the feet.
		track.runPuff -= dt
		if alive and f.grounded and f.state == "Ready" and math.abs(vx) > 5.5 and track.runPuff <= 0 then
			track.runPuff = 0.11
			Effects.dust(feet, 1, 4, Vector3.new(-math.sign(vx), 0.35, 0))
		end
		-- Slash arc when a strike turns active.
		if alive and f.moveStage == "active" and (track.stage ~= "active" or track.move ~= f.move) then
			local kind = Pose.MOVE_KIND[f.move]
			local arc = if kind then ARCS[kind] else nil
			if arc then
				local facing = if f.facing < 0 then -1 else 1
				local center = chest(view) + Vector3.new(facing * 0.8, 0, 0.8)
				local radius = arc.radius * view.scale
				Effects.slashArc(center, facing, view.glow, radius, arc.angle, arc.heavy)
				if arc.twin then
					Effects.slashArc(center, facing, view.glow, radius, arc.angle + 180, false)
				end
			end
		end
		track.grounded, track.stage, track.move = f.grounded, f.moveStage, f.move
	end
end

-- Vibration of held fighters, then dust and slash arcs.
local function juiceStep(dt: number)
	local now = os.clock()
	for slot, s in shakers do
		local view = views[slot]
		if view == nil or not Juice.frozen(slot) then
			shakers[slot] = nil
			continue
		end
		local f = math.clamp((now - s.started) / math.max(0.01, s.length), 0, 1)
		local wobble = math.sin(now * 95) * s.amp * (1 - f)
		view.root.CFrame = s.base + s.dir * (wobble - s.push * math.sin(f * math.pi))
	end
	local snap = MatchState.snapshot
	if snap and dt > 0 then
		trackFighters(snap, dt)
	end
end

local WORDS: { [string]: string } = {
	marked = "MARKIERT",
	freeze_hit = "EINGEFROREN",
	counter = "KONTER!",
	reflect = "ZURÜCK!",
	bulwark_block = "GEBLOCKT",
	heat_full = "KERNSCHMELZE BEREIT",
	one_punch_ko = "EIN SCHLAG!",
	hexed = "VERFLUCHT",
	leashed = "ANGEKETTET",
	crown_shift = "ELEMENTWECHSEL",
	catch = "GEFANGEN",
}
local ON_TARGET: { [string]: boolean } = { marked = true, freeze_hit = true, hexed = true, leashed = true }

function FighterView.start()
	MatchState.onEvent(function(event)
		local kind = event.type
		if kind == "phase" then
			table.clear(shakers)
			table.clear(tracks)
			Effects.reset()
			if event.phase == "match" then
				build()
			elseif event.phase == "lobby" then
				clear()
			end
		elseif kind == "hit" then
			onHit(event)
		elseif kind == "block" then
			local target = views[event.target]
			if target then
				local dir = hitDirection(views[event.actor], target)
				local hit = chest(target) - dir * 3
				Effects.shieldRipple(chest(target), hit, SHIELD_BLUE, 7)
				Effects.sparksToward(hit, -dir + Vector3.new(0, 0.6, 0), SHIELD_BLUE, 10, 26)
				Sfx.play("metal", 0.5, 1.2)
			end
		elseif kind == "parry" then
			local view = views[event.actor]
			if view then
				local other = views[event.target]
				local p = if other then (chest(view) + chest(other)) / 2 else chest(view)
				Effects.impactStar(p, PARRY_GOLD, 22, 0.3)
				Effects.shockwave(p, PARRY_GOLD, 16, 0.3)
				Effects.flashBall(p, PARRY_GOLD, 6, 0.2)
				Effects.sparks(p, WHITE, 24, 40)
				Effects.screenFlash(WHITE, 0.12, 0.6)
				Effects.label(chest(view) + Vector3.new(0, 3.5, 0), "PARADE!", PARRY_GOLD)
				Juice.slowmo(0.3, 0.35)
				Juice.hold(0.12, { event.actor, event.target })
				Sfx.play("metal", 0.9, 1)
			end
		elseif kind == "clash" then
			local p = FighterView.toWorld(event.x, event.y) + Vector3.new(0, 0, 1.5)
			Effects.sparksToward(p, Vector3.new(-1, 0.7, 0), WHITE, 18, 50)
			Effects.sparksToward(p, Vector3.new(1, 0.7, 0), CLASH_GOLD, 18, 50)
			Effects.impactStar(p, CLASH_GOLD, 18, 0.25)
			Effects.shockwave(p, CLASH_GOLD, 18, 0.3)
			Sfx.play("metal", 1, 0.9)
			-- Both fighters are pushed back from the contact point during a short hold (visual only).
			for _, slot in { event.actor, event.target } do
				local view = views[slot]
				if view then
					local side = math.sign(view.position.X - p.X)
					freeze(slot, 0.1, Vector3.new(if side == 0 then 1 else side, 0, 0), 0.15, -0.9)
				end
			end
		elseif kind == "ring_out" then
			onRingOut(event)
		elseif kind == "shield_break" then
			local view = views[event.actor]
			if view then
				Effects.shieldRipple(chest(view), chest(view), BREAK_BLUE, 9)
				Effects.sparks(chest(view), BREAK_BLUE, 45, 40)
				Effects.debris(chest(view), Vector3.yAxis, BREAK_BLUE, 8)
				Effects.shockwave(chest(view), BREAK_BLUE, 20)
				Effects.impactFrame(0.6, 0.06)
				Sfx.play("metal", 1, 0.6)
			end
		elseif kind == "super_used" then
			local view = views[event.actor]
			if view then
				Effects.flashBall(chest(view), view.glow, 14, 0.4)
				Effects.shockwave(chest(view), view.glow, 26, 0.45)
				Effects.speedLines(chest(view), view.glow, 0.7)
				Effects.screenFlash(view.glow, 0.18, 0.5)
			end
		elseif kind == "signature" then
			local view = views[event.actor]
			if view then
				local color = if type(event.color) == "string" then Color3.fromHex(event.color) else view.glow
				Effects.flashBall(chest(view), color, 5, 0.22)
				Effects.ring(chest(view), color, 10, 0.25)
				if event.name and event.name ~= "" then
					Effects.label(chest(view) + Vector3.new(0, 4.5, 0), event.name, color)
				end
			end
		elseif kind == "teleport" or kind == "decoy" then
			local view = views[event.actor]
			if view and event.fromX then
				local from = FighterView.toWorld(event.fromX, event.fromY) + Vector3.new(0, view.standHeight, 0)
				Effects.flashBall(from, view.glow, 6, 0.25)
				Effects.streak(from, chest(view), view.glow, 0.6, 0.25)
				Effects.ring(chest(view), view.glow, 9, 0.25)
			end
		elseif kind == "iai_cut" then
			local view = views[event.actor]
			if view then
				local from = FighterView.toWorld(event.fromX, event.y) + Vector3.new(0, view.standHeight + 0.5, 0)
				Effects.streak(from, chest(view), view.glow, 2.2, 0.5)
				Effects.streak(from, chest(view), WHITE, 1, 0.35)
				Effects.screenFlash(WHITE, 0.12)
				Effects.impactFrame(0.8, 0.08)
				Sfx.play("slash", 1, 0.8)
			end
		elseif kind == "slam" then
			local p = FighterView.toWorld(event.x, event.y)
			local color = if type(event.color) == "string" then Color3.fromHex(event.color) else GOLD
			Effects.groundRing(p + Vector3.new(0, 0.4, 0), color, (event.radius or 6) * M * 2, 0.45)
			Effects.ring(p + Vector3.new(0, 1, 0), color, (event.radius or 6) * M, 0.35)
			Effects.sparks(p, color, 40, 45)
			Effects.dust(p, 14, 18)
			Effects.debris(p + Vector3.new(0, 0.5, 0), Vector3.yAxis, color, 6)
			Sfx.play("heavy", 0.8, 0.7)
		elseif kind == "swap" or kind == "yank" or kind == "lasso" then
			local a, b = views[event.actor], views[event.target]
			if a and b then
				Effects.streak(chest(a), chest(b), a.glow, 0.4, 0.3)
			end
		elseif kind == "flashbang" then
			Effects.screenFlash(WHITE, 0.5)
		elseif kind == "war_horn" then
			local view = views[event.actor]
			if view then
				Effects.shockwave(chest(view), GOLD, 30, 0.5)
			end
		elseif kind == "jump" or kind == "double_jump" then
			local view = views[event.actor]
			if view then
				local feet = view.position + Vector3.new(0, 0.3, 0)
				if kind == "double_jump" then
					Effects.groundRing(feet, view.glow, 5, 0.22)
					Effects.sparks(feet, view.glow, 6, 12)
				else
					Effects.dust(feet, 5, 8)
				end
				Sfx.play("jump", 0.8, if kind == "double_jump" then 1.2 else 1)
			end
		elseif kind == "dodge" or kind == "air_dash" then
			local view = views[event.actor]
			if view then
				local snap = MatchState.snapshot
				local f = if snap then snap.fighters[event.actor] else nil
				if f and f.grounded then
					local back = Vector3.new(if f.facing < 0 then 1 else -1, 0.3, 0)
					Effects.dust(view.position + Vector3.new(0, 0.3, 0), 7, 14, back)
				else
					Effects.ring(chest(view), view.glow, 6, 0.2, 0.15)
				end
			end
		elseif kind == "combo_end" then
			Effects.comboEnd(event.actor)
		elseif kind == "finisher" then
			local view = views[event.target]
			if view then
				local actor = views[event.actor]
				Effects.knockout(chest(view), if actor then actor.glow else view.glow, Vector3.yAxis, true)
				Juice.hold(0.15)
				Sfx.play("heavy", 1, 0.55)
			end
		else
			local word = WORDS[kind]
			local who = if ON_TARGET[kind] then views[event.target] else views[event.actor]
			if word and who then
				Effects.label(chest(who) + Vector3.new(0, 3.5, 0), word, who.glow)
				if kind == "one_punch_ko" or kind == "counter" then
					Effects.impactStar(chest(who), who.glow, 16, 0.25)
				end
			elseif kind == "rebirth_heal" and views[event.actor] then
				local view = views[event.actor]
				Effects.label(
					chest(view) + Vector3.new(0, 3.5, 0),
					`-{math.floor(event.amount or 0)} %`,
					Color3.fromRGB(120, 255, 140)
				)
				Effects.flashBall(chest(view), Color3.fromRGB(255, 160, 60), 10, 0.4)
			elseif (kind == "eagle_strike" or kind == "turbo_ram" or kind == "echo_strike") and views[event.actor] then
				local view = views[event.actor]
				local target = views[event.target]
				local p = if target then chest(target) else chest(view)
				Effects.sparks(p, view.glow, 14, 25)
				Effects.impactStar(p, view.glow, 10, 0.18)
			end
		end
	end)
	RunService.RenderStepped:Connect(render)
	RunService.RenderStepped:Connect(juiceStep)
end

return FighterView
