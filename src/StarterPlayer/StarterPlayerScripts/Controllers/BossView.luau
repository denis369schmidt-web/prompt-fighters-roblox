--!strict
-- Draws the Boss-Raid boss and every telegraph, client-side and display only:
--   * the boss model (Visual/BossRig) follows the BossState position smoothly, hovers and breathes, raises its arms
--     and leans back during a wind-up, slams forward when the attack lands, flaps its wings;
--   * telegraph decals for every zone (ground strips and discs, columns, beam lines, rolling waves) pulse faster as
--     the wind-up runs out and flash bright when live; mutator bombs use the same decals;
--   * phase 2: the stone shell breaks off piece by piece and tumbles away (the clip moment, GROWTH.md);
--   * boss hits flash the body, damage numbers pop, slams and the shatter shake the camera.
-- Boss projectiles are drawn by ProjectileView (they come as normal projectile events and in the Shots remote).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossRig = require(Shared:WaitForChild("Visual"):WaitForChild("BossRig"))
local Bosses = require(Shared:WaitForChild("Data"):WaitForChild("Bosses"))
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local RaidState = require(script.Parent.Parent.State.RaidState)
local FighterView = require(script.Parent.FighterView)
local Effects = require(script.Parent.Effects)
local Juice = require(script.Parent.Juice)
local Sfx = require(script.Parent.Sfx)

local BossView = {}

local M = Visuals.STUDS_PER_METER
local FOLLOW = 10
local TURN = 0.45 -- yaw toward the facing side; the front looks at the camera
local WARN_COLOR = Color3.fromRGB(255, 70, 50)
local LIVE_COLOR = Color3.fromRGB(255, 220, 120)
local DECAL_DEPTH = 12 -- studs across the stage

type PartRest = { part: BasePart, rest: CFrame, group: string }
type Flying = { part: BasePart, cf: CFrame, vel: Vector3, spin: Vector3, t: number }

local folder: Folder? = nil
local model: Model? = nil
local bossId: string? = nil
local parts: { PartRest } = {}
local pivots: { [string]: Vector3 } = {}
local position: Vector3? = nil
local yaw = 0
local shattered = false
local flying: { Flying } = {}
local highlight: Highlight? = nil
local flashUntil = 0
local decals: { Part } = {}
local lastState = -1
local stateStart = 0

local function container(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local f = Instance.new("Folder")
	f.Name = "RaidView"
	f.Parent = workspace
	folder = f
	return f
end

local function clearModel()
	if model then
		model:Destroy()
	end
	model, bossId, position = nil, nil, nil
	table.clear(parts)
	table.clear(pivots)
	for _, fly in flying do
		fly.part:Destroy()
	end
	table.clear(flying)
	shattered = false
	highlight = nil
end

local function clearAll()
	clearModel()
	for _, d in decals do
		d:Destroy()
	end
	table.clear(decals)
end

local function build(id: string)
	clearModel()
	local rig = BossRig.build(id)
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			local group = d:GetAttribute("BossGroup") :: string? or "Body"
			if group == "Shell" then
				group = "Shell:" .. ((d:GetAttribute("Follow") :: string?) or "Body")
			end
			table.insert(parts, { part = d, rest = d.CFrame, group = group })
		end
	end
	for name, value in rig:GetAttributes() do
		if string.sub(name, 1, 6) == "Pivot_" and typeof(value) == "Vector3" then
			pivots[string.sub(name, 7)] = value
		end
	end
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = rig
	highlight = h
	rig.Parent = container()
	model, bossId = rig, id
end

-- Breaks the stone shell: every plate flies off with a spin and fades out.
local function shatter(instant: boolean)
	if shattered then
		return
	end
	shattered = true
	local center = position or FighterView.toWorld(0, 2)
	for _, entry in parts do
		if string.sub(entry.group, 1, 6) == "Shell:" then
			local p = entry.part
			if instant then
				p.Transparency = 1
			else
				local out = (p.Position - center)
				local dir = Vector3.new(out.X, math.abs(out.Y) * 0.3 + 2, out.Z + 3).Unit
				table.insert(flying, {
					part = p,
					cf = p.CFrame,
					vel = dir * (28 + math.random() * 22),
					spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12,
					t = 0,
				})
			end
			entry.group = "Gone"
		end
	end
	if not instant then
		Effects.debris(center, Vector3.new(0, 1, 0.4), Color3.fromRGB(150, 146, 140), 26)
		Effects.shockwave(center, Color3.fromRGB(255, 240, 200), 60, 0.6)
		Effects.screenFlash(Color3.new(1, 1, 1), 0.35, 0.6)
		Juice.addTrauma(0.8)
		Sfx.play("heavy", 1, 0.55)
	end
end

local function groupTransform(group: string, t: number, state: number, progress: number, facing: number): CFrame
	local found: Vector3? = pivots[group]
	if found == nil then
		return CFrame.new()
	end
	local pivot = found :: Vector3
	local rot = CFrame.new()
	local breathe = math.sin(t * 1.6)
	if group == "WingL" or group == "WingR" then
		local s = if group == "WingL" then -1 else 1
		local flap = math.sin(t * 2.2) * 0.12 + (if state == 1 then progress * 0.25 else 0)
		rot = CFrame.Angles(0, s * 0.15, s * flap)
	elseif group == "ArmL" or group == "ArmR" then
		local s = if group == "ArmL" then -1 else 1
		local lead = (s == facing) -- the arm on the attack side swings
		local raise = 0.06 * breathe
		if state == 1 then
			raise = progress * (if lead then 2.2 else 0.9)
		elseif state == 2 then
			raise = math.max(0, 1 - progress * 3) * 1.6 - 0.2
		elseif state == 4 then
			raise = 1.2 + math.sin(t * 20) * 0.1
		end
		rot = CFrame.Angles(-raise * 0.8, 0, s * raise * 0.35)
	elseif group == "Head" then
		rot = CFrame.Angles(if state == 1 then -0.15 * progress else 0.04 * breathe, 0, 0)
	elseif group == "Halo" then
		rot = CFrame.Angles(0, 0, t * 0.4)
	end
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end

local function updateModel(dt: number)
	local found = RaidState.boss
	if found == nil or not RaidState.active() then
		if model then
			clearModel()
		end
		return
	end
	local boss: any = found
	if bossId ~= boss.bossId then
		build(boss.bossId)
		if boss.phase >= 2 then
			shatter(true)
		end
	end
	local current = model :: Model
	local now = os.clock()
	if boss.state ~= lastState then
		lastState = boss.state
		stateStart = now
	end
	local target = FighterView.toWorld(boss.x, boss.y)
	local pos = position or target
	pos = pos:Lerp(target, math.min(1, dt * FOLLOW))
	if (pos - target).Magnitude > 40 then
		pos = target
	end
	position = pos
	local goalYaw = boss.facing * TURN
	yaw += (goalYaw - yaw) * math.min(1, dt * 4)
	local state, progress = boss.state, boss.progress
	local bob = math.sin(now * 1.3) * 0.5
	local lean = 0
	if state == 1 then
		lean = -0.12 * progress
	elseif state == 2 then
		lean = 0.18 * math.max(0, 1 - progress * 2)
	end
	local shake = if state == 4 then Vector3.new(math.sin(now * 47), 0, math.cos(now * 39)) * 0.4 else Vector3.zero
	local sink = 0
	local tilt = 0
	if state == 5 then -- defeated: the statue crumbles down
		local u = math.min(1, (now - stateStart) / 2.5)
		sink = u * u * 6
		tilt = u * 0.35
	end
	local root = CFrame.new(pos + Vector3.new(0, bob - sink, 0) + shake)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(lean * boss.facing, 0, tilt)
	for _, entry in parts do
		if entry.group == "Gone" then
			continue
		end
		local group = entry.group
		if string.sub(group, 1, 6) == "Shell:" then
			group = string.sub(group, 7)
		end
		entry.part.CFrame = root * groupTransform(group, now, state, progress, boss.facing) * entry.rest
	end
	-- Flying shell pieces.
	local keep = {}
	for _, fly in flying do
		fly.t += dt
		fly.vel += Vector3.new(0, -60 * dt, 0)
		fly.cf = (fly.cf + fly.vel * dt) * CFrame.Angles(fly.spin.X * dt, fly.spin.Y * dt, fly.spin.Z * dt)
		fly.part.CFrame = fly.cf
		fly.part.Transparency = math.clamp((fly.t - 0.9) / 0.6, 0, 1)
		if fly.t < 1.6 then
			table.insert(keep, fly)
		else
			fly.part.Transparency = 1
		end
	end
	flying = keep
	local h = highlight
	if h then
		local left = flashUntil - now
		h.FillTransparency = if left > 0 then 1 - left / 0.12 * 0.55 else 1
	end
	current:SetAttribute("Phase", boss.phase)
end

-- Telegraph decals from the zones (boss) and mutator bombs.
local function decal(index: number): Part
	local d: Part? = decals[index]
	if d == nil then
		local p = Instance.new("Part")
		p.Name = "Telegraph"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Parent = container()
		decals[index] = p
		return p
	end
	return d :: Part
end

local function updateDecals()
	local zones = {}
	local boss = RaidState.boss
	if boss and RaidState.active() then
		for _, z in boss.zones do
			table.insert(zones, z)
		end
	end
	if MatchState.phase == "match" then
		for _, z in RaidState.hazards do
			table.insert(zones, z)
		end
	end
	local now = os.clock()
	local used = 0
	for _, z in zones do
		used += 1
		local d = decal(used)
		local width = math.max(0.3, z.x2 - z.x1) * M
		local cx = (z.x1 + z.x2) / 2
		-- Warning: dim and pulsing faster toward the end; live: bright.
		local pulse = 0.5 + 0.5 * math.sin(now * (6 + z.progress * 18))
		local transparency = if z.live then 0.35 else 0.82 - 0.25 * z.progress - 0.08 * pulse
		local color = if z.live then LIVE_COLOR else WARN_COLOR:Lerp(Color3.fromRGB(255, 160, 40), z.progress)
		d.Color = color
		d.Transparency = transparency
		d.Shape = Enum.PartType.Block
		local kind = z.kind
		if kind == 2 and z.y1 <= 0.05 then
			-- Ground disc.
			d.Shape = Enum.PartType.Cylinder
			d.Size = Vector3.new(0.25, width, math.min(width, DECAL_DEPTH * 1.4))
			d.CFrame = CFrame.new(FighterView.toWorld(cx, 0) + Vector3.new(0, 0.15, 0))
				* CFrame.Angles(0, 0, math.pi / 2)
		elseif kind == 2 then
			-- Sphere around the boss (nova).
			d.Shape = Enum.PartType.Ball
			d.Size = Vector3.one * width
			d.CFrame = CFrame.new(FighterView.toWorld(cx, (z.y1 + z.y2) / 2))
			d.Transparency = math.max(transparency, 0.7)
		elseif kind == 6 then
			-- Aim line from the boss to the target.
			local a = FighterView.toWorld(z.x1, z.y1)
			local b = FighterView.toWorld(z.x2, z.y2)
			local len = math.max(0.5, (b - a).Magnitude)
			d.Size = Vector3.new(0.25, 0.25, len)
			d.CFrame = CFrame.lookAt((a + b) / 2, b)
		else
			local h = math.max(0.15, z.y2 - z.y1) * M
			local depth = if kind == 3 then 3.5 elseif kind == 4 then 2.5 else DECAL_DEPTH
			local tall = h > 2.5 * M and kind ~= 3
			if tall and not z.live then
				-- Tall areas (rain, sweeps): a ground strip plus a faint curtain.
				d.Size = Vector3.new(width, 0.25, DECAL_DEPTH)
				d.CFrame = CFrame.new(FighterView.toWorld(cx, 0) + Vector3.new(0, 0.15, 0))
			else
				d.Size = Vector3.new(width, h, depth)
				d.CFrame = CFrame.new(FighterView.toWorld(cx, (z.y1 + z.y2) / 2))
			end
		end
	end
	for k = used + 1, #decals do
		decals[k].Transparency = 1
	end
end

function BossView.start()
	RunService.RenderStepped:Connect(function(dt)
		updateModel(dt)
		updateDecals()
	end)
	MatchState.onEvent(function(event)
		local t = event.type
		if t == "phase" and event.phase == "lobby" then
			clearAll()
		elseif t == "boss_hit" then
			flashUntil = os.clock() + 0.12
			local pos = position
			if pos then
				local boss = RaidState.boss
				local h = if boss then select(2, Bosses.raidBody(boss.bossId)) else 4
				Effects.damageNumber(
					pos + Vector3.new(0, h * M * 0.8, 3),
					event.damage or 0,
					Color3.fromRGB(255, 230, 120)
				)
			end
		elseif t == "boss_slam" then
			Juice.addTrauma(0.45)
			Sfx.play("heavy", 0.9, 0.6)
			Effects.groundRing(FighterView.toWorld(event.x or 0, 0), WARN_COLOR, (event.radius or 4) * 2 * M, 0.5)
			Effects.dust(FighterView.toWorld(event.x or 0, 0), 18, 30)
		elseif t == "boss_shatter" then
			shatter(false)
		elseif t == "boss_phase" then
			Juice.addTrauma(0.4)
			Sfx.play("metal", 1, 0.5)
		elseif t == "boss_defeated" then
			local pos = position
			if pos then
				Effects.flashBall(pos + Vector3.new(0, 8, 0), Color3.fromRGB(255, 240, 200), 40, 0.8)
				Effects.debris(pos, Vector3.new(0, 1, 0.3), Color3.fromRGB(150, 146, 140), 30)
			end
			Juice.slowmo(0.35, 1.2)
			Juice.addTrauma(0.9)
		elseif t == "hero_hit" then
			if event.target == MatchState.mySlot then
				Juice.addTrauma(if event.blocked then 0.1 else 0.3)
			end
			local part = FighterView.part(event.target, "UpperTorso")
			if part then
				Effects.impactStar(part.Position, WARN_COLOR, 4, 0.2)
				Effects.damageNumber(part.Position + Vector3.new(0, 3, 0), event.damage or 0, WARN_COLOR)
			end
			Sfx.play("slash", 0.7, 0.8)
		elseif t == "mutator_bomb_hit" or (t == "blast" and event.actor == 0) then
			Juice.addTrauma(0.3)
		end
	end)
end

return BossView
