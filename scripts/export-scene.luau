--!strict
-- Exports a scene built by the game code (headless, under Lune) as JSON for the preview renderer
-- (scripts/preview/render.mjs): every visible part with size, CFrame, color, material, shape and transparency,
-- text on SurfaceGuis, and the lighting the scene set.
--
--   lune run scripts/export-scene.luau arena <arenaId> out.json
--   lune run scripts/export-scene.luau lobby out.json
--   lune run scripts/export-scene.luau fighters out.json   (launch roster in a row, for portraits)
--   lune run scripts/export-scene.luau portrait ninja,golem 30 out.json   (close-up set, turned 30 degrees)

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("../tests/runtime/Loader")
local CFrame = require("@lune/roblox").CFrame

local Shared = Loader.mount("src/ReplicatedStorage/Shared")
local Server = Loader.mount("src/ServerScriptService")
Loader.provide("ReplicatedStorage", { Shared = Shared })

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
else
	error("usage: export-scene.luau arena <id> | lobby | fighters | portrait <id,id,...> <yawDeg> <out.json>")
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
		local cframe = if hasPosition then CFrame.new(position) else d.CFrame
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
