--!strict
-- Draws the arena items from the Items remote: crates, rocks, barrels, the explosive barrel, power-ups and
-- weapons, all built from plain parts. Lying items bob and turn so they read as "pick me up"; weapons sit in
-- the wielder's right hand, lifted items above the carrier's head.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local Weapons = require(Shared:WaitForChild("Data"):WaitForChild("Weapons"))
local Items = require(Shared:WaitForChild("Combat"):WaitForChild("Items"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local FighterView = require(script.Parent.FighterView)
local Effects = require(script.Parent.Effects)

local M = Visuals.STUDS_PER_METER
local BASE_Y = Visuals.STAGE_Y
local FOLLOW = 18

type View = { model: Model, kind: string, position: Vector3, height: number }

local ItemView = {}

local views: { [number]: View } = {}
local folder: Folder? = nil

local function container(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local f = Instance.new("Folder")
	f.Name = "Items"
	f.Parent = workspace
	folder = f
	return f
end

-- One part of an item model, placed relative to the model origin.
local function part(
	model: Model,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CastShadow = material ~= Enum.Material.Neon
	p.CFrame = offset
	p.Parent = model
	return p
end

local function glowLight(p: BasePart, color: Color3)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 9
	l.Brightness = 1.5
	l.Shadows = false
	l.Parent = p
end

local WOOD = Color3.fromRGB(150, 105, 60)
local DARK_WOOD = Color3.fromRGB(95, 62, 35)
local STEEL = Color3.fromRGB(200, 205, 215)
local GRIP = Color3.fromRGB(40, 35, 35)
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie along X; this stands them up

-- Weapons are built along -Z from the grip at the origin (same axis as a blade in the rig's hand).
local function buildWeapon(model: Model, id: string): number
	local w = Weapons.byId[id]
	local glow = if w and w.color then Color3.fromHex(w.color) else Color3.new(1, 1, 1)
	part(model, Vector3.new(0.25, 0.25, 0.8), CFrame.new(0, 0, 0), GRIP, Enum.Material.Fabric)
	local function blade(length: number, width: number, color: Color3, material: Enum.Material?)
		part(
			model,
			Vector3.new(0.7, 0.12, 0.12),
			CFrame.new(0, 0, -0.45),
			Color3.fromRGB(210, 180, 90),
			Enum.Material.Metal
		)
		part(
			model,
			Vector3.new(0.1, width, length),
			CFrame.new(0, 0, -0.5 - length / 2),
			color,
			material or Enum.Material.Metal
		)
		part(
			model,
			Vector3.new(0.05, 0.06, length * 0.95),
			CFrame.new(0, width / 2, -0.5 - length / 2),
			glow,
			Enum.Material.Neon
		)
	end
	if id == "sword_buster" then
		blade(4.2, 0.9, Color3.fromRGB(170, 175, 185))
	elseif id == "sword_plasma" or id == "shadow_katana" then
		blade(3.4, 0.25, glow, Enum.Material.Neon)
	elseif id == "sword_frost" then
		blade(3.2, 0.4, Color3.fromRGB(190, 225, 255), Enum.Material.Glass)
	elseif id == "sword_crescent" then
		blade(3, 0.5, Color3.fromRGB(120, 30, 40))
		part(
			model,
			Vector3.new(0.1, 0.5, 1.2),
			CFrame.new(0, 0.4, -3.4) * CFrame.Angles(0.6, 0, 0),
			glow,
			Enum.Material.Neon
		)
	elseif id == "blaster" or id == "plasma_cannon" then
		local big = if id == "plasma_cannon" then 1.5 else 1
		part(
			model,
			Vector3.new(0.4, 0.5, 1.4) * big,
			CFrame.new(0, 0.35, -0.6),
			Color3.fromRGB(60, 60, 75),
			Enum.Material.Metal
		)
		part(model, Vector3.new(0.25, 0.25, 0.9) * big, CFrame.new(0, 0.4, -1.6 * big), glow, Enum.Material.Neon)
	elseif id == "boomerang" then
		part(model, Vector3.new(0.12, 0.35, 1.6), CFrame.new(0, 0, -0.8) * CFrame.Angles(0, 0.6, 0), glow)
		part(model, Vector3.new(0.12, 0.35, 1.6), CFrame.new(0.9, 0, -0.9) * CFrame.Angles(0, -0.6, 0), glow)
	elseif id == "flail" then
		part(model, Vector3.new(0.18, 0.18, 1.8), CFrame.new(0, 0, -1.2), DARK_WOOD, Enum.Material.Wood)
		part(
			model,
			Vector3.new(0.08, 0.08, 1),
			CFrame.new(0, -0.3, -2.4) * CFrame.Angles(0.5, 0, 0),
			STEEL,
			Enum.Material.Metal
		)
		part(
			model,
			Vector3.one * 0.9,
			CFrame.new(0, -0.7, -3),
			Color3.fromRGB(120, 115, 110),
			Enum.Material.Metal,
			BALL
		)
	elseif id == "frost_axe" or id == "thunder_hammer" then
		part(model, Vector3.new(0.2, 0.2, 2.6), CFrame.new(0, 0, -1.4), DARK_WOOD, Enum.Material.Wood)
		local head = if id == "thunder_hammer" then Vector3.new(0.9, 0.9, 1.5) else Vector3.new(0.15, 1.3, 1)
		part(
			model,
			head,
			CFrame.new(0, 0.3, -2.7),
			if id == "thunder_hammer" then STEEL else Color3.fromRGB(170, 215, 255),
			Enum.Material.Metal
		)
		part(model, Vector3.new(0.2, 0.2, 1.6), CFrame.new(0, 0.85, -2.7), glow, Enum.Material.Neon)
	elseif id == "flame_whip" then
		for k = 0, 5 do
			part(
				model,
				Vector3.new(0.15, 0.15, 0.7),
				CFrame.new(0, -k * 0.12, -0.7 - k * 0.6) * CFrame.Angles(-0.1 * k, 0, 0),
				glow,
				Enum.Material.Neon
			)
		end
	elseif id == "crystal_bow" then
		part(
			model,
			Vector3.new(0.15, 0.2, 1.6),
			CFrame.new(0, 0.6, -0.4) * CFrame.Angles(-0.5, 0, 0),
			glow,
			Enum.Material.Glass
		)
		part(
			model,
			Vector3.new(0.15, 0.2, 1.6),
			CFrame.new(0, -0.6, -0.4) * CFrame.Angles(0.5, 0, 0),
			glow,
			Enum.Material.Glass
		)
		part(model, Vector3.new(0.03, 2.2, 0.03), CFrame.new(0, 0, 0.2), Color3.new(1, 1, 1), Enum.Material.Neon)
	elseif id == "dragon_lance" or id == "soul_scythe" then
		part(model, Vector3.new(0.18, 0.18, 4.4), CFrame.new(0, 0, -1.6), DARK_WOOD, Enum.Material.Wood)
		if id == "soul_scythe" then
			part(
				model,
				Vector3.new(0.1, 0.5, 2),
				CFrame.new(0, 0.9, -3.8) * CFrame.Angles(-1.2, 0, 0),
				STEEL,
				Enum.Material.Metal
			)
			part(
				model,
				Vector3.new(0.05, 0.1, 1.9),
				CFrame.new(0, 1, -3.9) * CFrame.Angles(-1.2, 0, 0),
				glow,
				Enum.Material.Neon
			)
		else
			part(model, Vector3.new(0.4, 0.4, 1.2), CFrame.new(0, 0, -4.3), glow, Enum.Material.Neon)
		end
	else
		blade(3.2, 0.35, STEEL)
	end
	return 1.2
end

-- Builds the model of one item kind. Returns it and the height of its center above the floor (studs).
local function build(kind: string): (Model, number)
	local model = Instance.new("Model")
	model.Name = kind
	local height = 1.2
	if kind == "light_crate" then
		part(model, Vector3.one * 2.4, CFrame.new(), WOOD, Enum.Material.WoodPlanks)
		for _, x in { -1.15, 1.15 } do
			part(model, Vector3.new(0.15, 2.5, 2.5), CFrame.new(x, 0, 0), DARK_WOOD, Enum.Material.Wood)
		end
		height = 1.2
	elseif kind == "heavy_rock" then
		part(model, Vector3.new(2.8, 2.2, 2.4), CFrame.new(), Color3.fromRGB(110, 105, 100), Enum.Material.Slate, BALL)
		part(
			model,
			Vector3.new(1.4, 1.2, 1.2),
			CFrame.new(0.9, 0.5, 0.3),
			Color3.fromRGB(95, 90, 88),
			Enum.Material.Slate,
			BALL
		)
		height = 1.1
	elseif kind == "barrel" then
		part(model, Vector3.new(2.6, 2, 2), UPRIGHT, WOOD, Enum.Material.Wood, CYL)
		for _, y in { -0.8, 0.8 } do
			part(
				model,
				Vector3.new(0.2, 2.1, 2.1),
				CFrame.new(0, y, 0) * UPRIGHT,
				Color3.fromRGB(70, 70, 75),
				Enum.Material.Metal,
				CYL
			)
		end
		height = 1.3
	elseif kind == "explosive_barrel" then
		local body = part(model, Vector3.new(2.6, 2, 2), UPRIGHT, Color3.fromRGB(190, 35, 30), Enum.Material.Metal, CYL)
		part(model, Vector3.new(0.5, 2.05, 2.05), UPRIGHT, Color3.fromRGB(250, 205, 40), Enum.Material.Neon, CYL)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		gui.Parent = body
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = "!"
		label.TextColor3 = Color3.fromRGB(255, 230, 80)
		label.Parent = gui
		glowLight(body, Color3.fromRGB(255, 120, 40))
		height = 1.3
	elseif kind == "titan_mushroom" then
		part(
			model,
			Vector3.new(0.9, 1.1, 0.9),
			CFrame.new(0, -0.3, 0),
			Color3.fromRGB(245, 235, 215),
			Enum.Material.SmoothPlastic
		)
		local cap = part(
			model,
			Vector3.new(2.2, 1.2, 2.2),
			CFrame.new(0, 0.5, 0),
			Color3.fromRGB(220, 40, 50),
			Enum.Material.SmoothPlastic,
			BALL
		)
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			part(
				model,
				Vector3.one * 0.4,
				CFrame.new(math.cos(a) * 0.75, 0.8, math.sin(a) * 0.75),
				Color3.new(1, 1, 1),
				Enum.Material.SmoothPlastic,
				BALL
			)
		end
		glowLight(cap, Color3.fromRGB(255, 120, 120))
	elseif kind == "invulnerable_star" then
		local color = Color3.fromRGB(255, 220, 60)
		for k = 0, 4 do
			local p = part(
				model,
				Vector3.new(0.35, 0.7, 1.6),
				CFrame.Angles(0, 0, k / 5 * math.pi * 2) * CFrame.new(0, 0.6, 0),
				color,
				Enum.Material.Neon
			)
			if k == 0 then
				glowLight(p, color)
			end
		end
		part(model, Vector3.new(0.45, 1, 1), CFrame.new(), color, Enum.Material.Neon, BALL)
	elseif kind == "speed_boots" then
		local blue = Color3.fromRGB(60, 160, 255)
		for _, x in { -0.5, 0.5 } do
			part(model, Vector3.new(0.6, 1, 0.7), CFrame.new(x, 0.1, 0.2), blue, Enum.Material.SmoothPlastic)
			part(model, Vector3.new(0.6, 0.4, 1.3), CFrame.new(x, -0.4, -0.1), blue, Enum.Material.SmoothPlastic)
			part(
				model,
				Vector3.new(0.1, 0.5, 0.6),
				CFrame.new(x + 0.33, 0.2, 0.4),
				Color3.new(1, 1, 1),
				Enum.Material.Neon
			)
		end
	elseif kind == "smash_hammer" then
		part(model, Vector3.new(0.25, 2.2, 0.25), CFrame.new(0, -0.2, 0), DARK_WOOD, Enum.Material.Wood)
		local head =
			part(model, Vector3.new(1.8, 1, 1), CFrame.new(0, 1, 0), Color3.fromRGB(240, 200, 60), Enum.Material.Metal)
		glowLight(head, Color3.fromRGB(255, 200, 80))
	elseif kind == "health_heart" then
		local pink = Color3.fromRGB(255, 70, 120)
		part(model, Vector3.one * 1.1, CFrame.new(-0.4, 0.3, 0), pink, Enum.Material.Neon, BALL)
		part(model, Vector3.one * 1.1, CFrame.new(0.4, 0.3, 0), pink, Enum.Material.Neon, BALL)
		local tip = part(
			model,
			Vector3.new(1.1, 1.1, 0.9),
			CFrame.new(0, -0.25, 0) * CFrame.Angles(0, 0, math.rad(45)),
			pink,
			Enum.Material.Neon
		)
		glowLight(tip, pink)
	elseif kind == "freeze_orb" then
		local ice = Color3.fromRGB(150, 225, 255)
		local orb = part(model, Vector3.one * 1.5, CFrame.new(), ice, Enum.Material.Glass, BALL)
		orb.Transparency = 0.2
		part(model, Vector3.one * 0.8, CFrame.new(), Color3.new(1, 1, 1), Enum.Material.Neon, BALL)
		glowLight(orb, ice)
	else
		height = buildWeapon(model, kind)
	end
	model.WorldPivot = CFrame.new()
	model.Parent = container()
	return model, height
end

local function toWorld(x: number, y: number): Vector3
	return Vector3.new(x * M, BASE_Y + y * M, 0)
end

local function clearAll()
	for id, view in views do
		view.model:Destroy()
		views[id] = nil
	end
end

local function render(dt: number)
	local follow = 1 - math.exp(-FOLLOW * dt)
	local t = os.clock()
	for id, data in MatchState.items do
		local kind = Items.KINDS[data.kind]
		if kind == nil then
			continue
		end
		local view = views[id]
		if view == nil or view.kind ~= kind then
			if view then
				view.model:Destroy()
			end
			local model, height = build(kind)
			view = { model = model, kind = kind, position = toWorld(data.x, data.y), height = height }
			views[id] = view
		end
		local v = view :: View
		local holder = if data.state >= 20 then data.state - 20 elseif data.state >= 10 then data.state - 10 else 0
		local hand = if data.state >= 20 then FighterView.part(holder, "RightHand") else nil
		if hand then
			-- Wielded weapon: in the right hand, along the arm like a held blade.
			v.model:PivotTo(hand.CFrame * CFrame.new(0, -0.2, 0.1))
			v.position = v.model:GetPivot().Position
			continue
		end
		local target = toWorld(data.x, data.y)
		v.position = v.position:Lerp(target, follow)
		local cf: CFrame
		if data.state >= 10 then
			-- Lifted above the head.
			local head = FighterView.part(holder, "Head")
			local above = if head then head.Position + Vector3.new(0, 2.2, 0) else v.position + Vector3.new(0, 3, 0)
			cf = CFrame.new(above)
		elseif data.state == 2 then
			cf = CFrame.new(v.position + Vector3.new(0, v.height, 0)) * CFrame.Angles(0, 0, -t * 10)
		else
			local bob = math.sin(t * 2.5 + id) * 0.25
			local isWeapon = Weapons.byId[kind] ~= nil
			local turn = CFrame.Angles(0, t * 1.2 + id, 0)
			cf = CFrame.new(v.position + Vector3.new(0, v.height + 0.6 + bob, 0))
				* turn
				* (if isWeapon then CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, 1.5) else CFrame.new())
		end
		v.model:PivotTo(cf)
	end
	for id, view in views do
		if MatchState.items[id] == nil then
			view.model:Destroy()
			views[id] = nil
		end
	end
end

function ItemView.start()
	MatchState.onEvent(function(event)
		local kind = event.type
		if kind == "phase" then
			clearAll()
		elseif kind == "item_explode" then
			local p = toWorld(event.x, event.y)
			local r = (event.radius or 3) * M
			local color = if event.freeze then Color3.fromRGB(150, 225, 255) else Color3.fromRGB(255, 140, 40)
			Effects.flashBall(p, color, r * 2, 0.45)
			Effects.ring(p, color, r * 2.6, 0.45)
			Effects.sparks(p, color, 50, 60)
			if not event.freeze then
				Effects.screenFlash(color, 0.15)
			end
		elseif kind == "item_break" then
			Effects.sparks(toWorld(event.x, event.y), Color3.fromRGB(180, 130, 80), 20, 25)
		elseif kind == "powerup" or kind == "weapon_pickup" then
			local head = FighterView.part(event.actor, "Head")
			if head then
				Effects.label(
					head.Position + Vector3.new(0, 4, 0),
					string.upper(event.name or ""),
					Color3.fromRGB(255, 230, 120)
				)
				Effects.flashBall(head.Position, Color3.fromRGB(255, 230, 120), 5, 0.25)
			end
		elseif kind == "weapon_break" then
			local hand = FighterView.part(event.actor, "RightHand")
			if hand then
				Effects.sparks(hand.Position, Color3.fromRGB(220, 220, 230), 25, 30)
			end
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return ItemView
