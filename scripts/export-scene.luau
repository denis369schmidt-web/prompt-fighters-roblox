--!strict
-- Exports a scene built by the game code (headless, under Lune) as JSON for the preview renderer
-- (scripts/preview/render.mjs): every visible part with size, CFrame, color, material, shape and transparency,
-- text on SurfaceGuis, and the lighting the scene set.
--
--   lune run scripts/export-scene.luau arena <arenaId> out.json
--   lune run scripts/export-scene.luau lobby out.json
--   lune run scripts/export-scene.luau fighters out.json   (launch roster in a row, for portraits)
--   lune run scripts/export-scene.luau portrait ninja,golem 30 out.json   (close-up set, turned 30 degrees)
--   lune run scripts/export-scene.luau prompts "Eisgolem mit Hammer;lava ninja" 20 out.json   (prompt fighters)
--   lune run scripts/export-scene.luau poses spec.json out.json
--     (pose sheet: spec is a JSON list of { fighter, ...PoseInput fields }; rigs are posed with Visual/Pose and
--     forward kinematics through the Motor6Ds, eight per row, rows stacked upward)
--   lune run scripts/export-scene.luau scene spec.json out.json
--     (key art: an arena with posed fighters placed freely, spec = { arena, fighters = { { fighter, at, yaw?, ... } } })

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("../tests/runtime/Loader")
local CFrame = require("@lune/roblox").CFrame

local Shared = Loader.mount("src/ReplicatedStorage/Shared")
local Server = Loader.mount("src/ServerScriptService")
Loader.provide("ReplicatedStorage", { Shared = Shared })

-- Builds a fighter posed by Visual/Pose (spec = { fighter, ...PoseInput fields, joints? }) at `origin`,
-- with forward kinematics through the Motor6Ds (Lune has no joint solver).
local function posedRig(spec: any, origin: any): any
	local RigBuilder = Loader.require(Shared.Visual.RigBuilder)
	local Pose = Loader.require(Shared.Visual.Pose)
	local roblox = require("@lune/roblox")
	local rig = RigBuilder.build(spec.fighter or "ninja")
	local input: { [string]: any } = {
		state = "Ready",
		move = "",
		stage = "",
		grounded = true,
		blocking = false,
		speed = 0,
		vy = 0,
		phase = 0,
		t = 0,
	}
	for k, v in spec do
		if k ~= "fighter" and k ~= "joints" then
			input[k] = v
		end
	end
	local pose = Pose.compute(input :: any)
	-- Optional raw joint overrides for checking conventions: "joints": { "Waist": [x, y, z] }.
	for name, v in spec.joints or {} do
		pose.joints[name] = { x = v[1], y = v[2], z = v[3] }
	end
	-- Forward kinematics through the Motor6Ds (Lune has no joint solver). Keyed by part name: Lune hands out
	-- a new userdata per property read, so instances can't be table keys.
	local body: { [string]: any } = {}
	local gear: { { part: any, limb: string, rest: any } } = {}
	for _, d in rig:GetChildren() do
		if d:IsA("BasePart") then
			body[d.Name] = { part = d, rest = d.CFrame }
		end
	end
	for _, d in rig:GetDescendants() do
		local parent = d.Parent
		if d:IsA("BasePart") and parent and parent ~= rig and body[parent.Name] then
			table.insert(gear, { part = d, limb = parent.Name, rest = d.CFrame })
		end
	end
	local stand = rig:GetAttribute("StandHeight") :: number
	local look = roblox.Vector3.new(spec.facing or 1, 0, 0.35).Unit
	local base = roblox.Vector3.new(0, stand + pose.rootY, 0) + look * (pose.lunge or 0)
	local placed: { [string]: any } = {
		-- Same placement as FighterView (CFrame.lookAt toward `look`), built from a yaw because Lune's lookAt
		-- mirrors the Z axis.
		HumanoidRootPart = origin
			* roblox.CFrame.new(base)
			* roblox.CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
			* roblox.CFrame.Angles(math.rad(-pose.pitch), math.rad(pose.spin), math.rad(pose.roll)),
	}
	local motors = {}
	for _, d in rig:GetDescendants() do
		if d.ClassName == "Motor6D" then
			table.insert(motors, d)
		end
	end
	local progress = true
	while progress do
		progress = false
		for _, m in motors do
			local n0, n1 = (m :: any).Part0.Name, (m :: any).Part1.Name
			if placed[n0] and not placed[n1] then
				local a = pose.joints[m.Name]
				local turn = if a
					then roblox.CFrame.Angles(math.rad(a.x), math.rad(a.y), math.rad(a.z))
					else roblox.CFrame.new()
				placed[n1] = placed[n0] * (m :: any).C0 * turn * (m :: any).C1:Inverse()
				progress = true
			end
		end
	end
	for name, entry in body do
		entry.part.CFrame = placed[name] or entry.rest
		entry.part:SetAttribute("Posed", true)
	end
	-- Gear and face pieces sit on their limb (WeldConstraint): keep the rest offset.
	for _, g in gear do
		local limb = body[g.limb]
		g.part.CFrame = (placed[g.limb] or limb.rest) * limb.rest:Inverse() * g.rest
		g.part:SetAttribute("Posed", true)
	end
	return rig
end

local kind = process.args[1]
local root: any
if kind == "arena" then
	root = Loader.require(Server.World.ArenaBuilder).build(process.args[2])
	-- Four fighters on their spawn points, as at the start of a match.
	local RigBuilder = Loader.require(Shared.Visual.RigBuilder)
	local Arena = Loader.require(Shared.Combat.Arena)
	local Visuals = Loader.require(Shared.Data.Visuals)
	local roblox = require("@lune/roblox")
	local picks = { "ninja", "steel_knight", "phoenix", "golem" }
	for i, id in picks do
		local rig = RigBuilder.build(id)
		local place = roblox.CFrame.new(Arena.SPAWN_X[i] * Visuals.STUDS_PER_METER, Visuals.STAGE_Y, 0)
			* roblox.CFrame.Angles(0, if Arena.SPAWN_FACING[i] > 0 then -math.pi / 2 else math.pi / 2, 0)
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = place * d.CFrame
			end
		end
		rig.Parent = root
	end
elseif kind == "lobby" then
	local ArenaBuilder = Loader.require(Server.World.ArenaBuilder)
	ArenaBuilder.applyLighting(Loader.require(Shared.Data.ArenaThemes).neon_alley)
	root = Loader.require(Server.World.LobbyBuilder).build()
elseif kind == "fighters" then
	local RigBuilder = Loader.require(Shared.Visual.RigBuilder)
	local Visuals = Loader.require(Shared.Data.Visuals)
	local roblox = require("@lune/roblox")
	root = roblox.Instance.new("Model")
	for i, id in Visuals.SLICE_FIGHTERS do
		local rig = RigBuilder.build(id)
		local x = ((i - 1) % 8 - 3.5) * 7.5 + (if i <= 8 then 0 else 3.75)
		local z = if i <= 8 then 0 else 12
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = roblox.CFrame.new(x, 0, z) * d.CFrame
			end
		end
		rig.Parent = root
	end
elseif kind == "portrait" then
	-- A few fighters side by side, 5 studs apart, turned by <yaw> degrees (0 = facing the camera at -Z).
	local RigBuilder = Loader.require(Shared.Visual.RigBuilder)
	local roblox = require("@lune/roblox")
	local ids = string.split(process.args[2], ",")
	local yaw = math.rad(tonumber(process.args[3]) or 0)
	root = roblox.Instance.new("Model")
	for i, id in ids do
		local rig = RigBuilder.build(id)
		local x = ((#ids + 1) / 2 - i) * 5.5
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = roblox.CFrame.new(x, 0, 0) * roblox.CFrame.Angles(0, yaw, 0) * d.CFrame
			end
		end
		rig.Parent = root
	end
elseif kind == "prompts" then
	-- Prompt fighters (Shared/Prompt) from texts separated by ";", in an idle pose, side by side on small plinths.
	local Registry = Loader.require(Shared.Prompt.Registry)
	local roblox = require("@lune/roblox")
	local texts = string.split(process.args[2], ";")
	local yaw = tonumber(process.args[3]) or 0
	root = roblox.Instance.new("Model")
	for i, text in texts do
		local result = Registry.fromText(text)
		print(
			`{text} -> {result.fighter.name} ({result.summary.title}) code {result.code}: {table.concat(
				result.look.gear,
				", "
			)}`
		)
		local x = ((#texts + 1) / 2 - i) * 6
		local origin = roblox.CFrame.new(x, 0, 0)
		local plinth = roblox.Instance.new("Part")
		plinth.Size = roblox.Vector3.new(5, 0.4, 5)
		plinth.CFrame = origin * roblox.CFrame.new(0, -0.2, 0)
		plinth.Color = roblox.Color3.fromHex(result.look.glow):Lerp(roblox.Color3.fromRGB(30, 28, 44), 0.75)
		plinth.Parent = root
		-- Name plate in front: name, then title and share code (the prompt itself is not shown).
		local plate = roblox.Instance.new("Part")
		plate.Size = roblox.Vector3.new(5.6, 1.5, 0.2)
		plate.CFrame = origin * roblox.CFrame.new(0, -1.2, -2.7)
		plate.Color = roblox.Color3.fromRGB(18, 16, 30)
		plate.Parent = plate.Parent or root
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Front
		gui.Parent = plate
		local lines = {
			{ result.fighter.name, roblox.Color3.fromHex(result.look.glow), 0.06, 0.5 },
			{ `{result.summary.title} · {result.code}`, roblox.Color3.fromRGB(225, 225, 235), 0.6, 0.3 },
		}
		for _, line in lines do
			local label = roblox.Instance.new("TextLabel")
			label.Text = line[1]
			label.TextColor3 = line[2]
			label.Position = roblox.UDim2.fromScale(0, line[3])
			label.Size = roblox.UDim2.fromScale(1, line[4])
			label.Parent = gui
		end
		-- Idle pose, turned from the fight's side view toward the camera (at -Z).
		posedRig({ fighter = result.id, t = 0.3, phase = 0.3 }, origin * roblox.CFrame.Angles(0, math.rad(90 + yaw), 0)).Parent =
			root
	end
elseif kind == "poses" then
	local roblox = require("@lune/roblox")
	local specs = serde.decode("json", fs.readFile(process.args[2]))
	root = roblox.Instance.new("Model")
	local PER_ROW, DX, DY = 8, 8, 10
	for i, spec in specs do
		local col, row = (i - 1) % PER_ROW, (i - 1) // PER_ROW
		local origin = roblox.CFrame.new((col - (PER_ROW - 1) / 2) * DX, row * DY, 0)
		local floor = roblox.Instance.new("Part")
		floor.Size = roblox.Vector3.new(DX - 1, 0.2, 4)
		floor.CFrame = origin * roblox.CFrame.new(0, -0.1, 0)
		floor.Color = roblox.Color3.fromRGB(70, 70, 80)
		floor.Parent = root
		posedRig(spec, origin).Parent = root
	end
elseif kind == "scene" then
	-- An arena with posed fighters placed freely, for key art: { arena, fighters = { { fighter, at = {x, y, z}, ... } } }.
	local roblox = require("@lune/roblox")
	local spec = serde.decode("json", fs.readFile(process.args[2]))
	root = Loader.require(Server.World.ArenaBuilder).build(spec.arena)
	for _, f in spec.fighters do
		local at = f.at or { 0, 0, 0 }
		posedRig(f, roblox.CFrame.new(at[1], at[2], at[3]) * roblox.CFrame.Angles(0, math.rad(f.yaw or 0), 0)).Parent =
			root
	end
else
	error(
		"usage: export-scene.luau arena <id> | lobby | fighters | portrait <id,id,...> <yawDeg> | prompts <a;b> <yawDeg> | poses <spec.json> | scene <spec.json> <out.json>"
	)
end
local out = process.args[#process.args]

local parts = {}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		local shape = "Block"
		if d.ClassName == "WedgePart" then
			shape = "Wedge"
		elseif d.ClassName == "Part" then
			shape = d.Shape.Name
		end
		local texts = {}
		for _, gui in d:GetChildren() do
			if gui.ClassName == "SurfaceGui" then
				for _, label in gui:GetDescendants() do
					if label.ClassName == "TextLabel" and label.Text ~= "" then
						local p, s = label.Position, label.Size
						table.insert(texts, {
							text = label.Text,
							color = { label.TextColor3.R, label.TextColor3.G, label.TextColor3.B },
							box = { p.X.Scale, p.Y.Scale, s.X.Scale, s.Y.Scale },
							face = gui.Face.Name,
						})
					end
				end
			end
		end
		local c = d.Color
		-- Lune stores Position and CFrame separately; builders set one of them.
		local hasPosition, position = pcall(function()
			return d.Position
		end)
		local cframe = if hasPosition and d:GetAttribute("Posed") == nil then CFrame.new(position) else d.CFrame
		table.insert(parts, {
			size = { d.Size.X, d.Size.Y, d.Size.Z },
			cf = { cframe:GetComponents() },
			color = { c.R, c.G, c.B },
			material = d.Material.Name,
			shape = shape,
			transparency = d.Transparency,
			texts = if #texts > 0 then texts else nil,
		})
	end
end

local Lighting = Loader.game:GetService("Lighting")
local function rgb(c: any)
	return { c.R, c.G, c.B }
end
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local lit, lighting = pcall(function()
	return {
		clock = Lighting.ClockTime,
		ambient = rgb(Lighting.OutdoorAmbient),
		exposure = Lighting.ExposureCompensation,
		fog = if atmosphere then rgb(atmosphere.Color) else nil,
		density = if atmosphere then atmosphere.Density else 0,
	}
end)
fs.writeFile(
	out,
	serde.encode("json", {
		parts = parts,
		lighting = if lit then lighting else { clock = 14, ambient = { 0.6, 0.6, 0.65 }, exposure = 0, density = 0 },
	})
)
print(`{kind}: {#parts} parts -> {out}`)
