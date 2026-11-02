--!strict
-- Prints the part count of every arena and the lobby (headless, under Lune): `lune run scripts/part-budget.luau`.
-- Columns: total BaseParts, parts that cast shadows, light instances, and collidable parts.

local Loader = require("../tests/runtime/Loader")

local Shared = Loader.mount("src/ReplicatedStorage/Shared")
local Server = Loader.mount("src/ServerScriptService")
Loader.provide("ReplicatedStorage", { Shared = Shared })

local ArenaBuilder = Loader.require(Server.World.ArenaBuilder)
local LobbyBuilder = Loader.require(Server.World.LobbyBuilder)
local Arenas = Loader.require(Shared.Data.Arenas)

local function stats(model: any): (number, number, number, number)
	local parts, shadows, lights, collide = 0, 0, 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d.CastShadow then
				shadows += 1
			end
			if d.CanCollide then
				collide += 1
			end
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	return parts, shadows, lights, collide
end

local function row(name: string, model: any): number
	local parts, shadows, lights, collide = stats(model)
	print(string.format("%-18s %5d parts %5d shadow %3d lights %4d collide", name, parts, shadows, lights, collide))
	return parts
end

local total = 0
for _, arena in Arenas.list do
	total += row(arena.id, ArenaBuilder.build(arena.id))
end
print(string.format("%-18s %5d parts (average %d)", "all arenas", total, total // #Arenas.list))
row("lobby", LobbyBuilder.build())
