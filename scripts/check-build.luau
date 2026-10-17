--!strict
-- Verifies the place that `rojo build` produced: `lune run scripts/check-build.luau build/PromptFighters.rbxl`.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "build/PromptFighters.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local expected = {
	{ "ReplicatedStorage.Shared.Data.Fighters", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Data.Generated.FighterKits", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Data.Products", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Combat.Knockback", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Combat.Simulation", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Combat.Bot", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Combat.MatchRunner", "ModuleScript" },
	{ "ServerScriptService.Server.Match.MatchService", "ModuleScript" },
	{ "ServerScriptService.Server.Net.RemoteHub", "ModuleScript" },
	{ "StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController", "ModuleScript" },
	{ "StarterPlayer.StarterPlayerScripts.Client.UI.Hud", "ModuleScript" },
	{ "ServerScriptService.Server.Main", "Script" },
	{ "StarterPlayer.StarterPlayerScripts.Client.Main", "LocalScript" },
}

local missing = 0
for _, item in expected do
	local current: any = game
	for part in item[1]:gmatch("[^%.]+") do
		current = current and current:FindFirstChild(part)
	end
	if not current or current.ClassName ~= item[2] then
		print(`missing {item[2]} {item[1]}`)
		missing += 1
	end
end

local modules = 0
for _, inst in game:GetDescendants() do
	if inst:IsA("LuaSourceContainer") then
		modules += 1
	end
end
print(`{path}: {modules} scripts, {missing} missing`)
process.exit(if missing == 0 then 0 else 1)
