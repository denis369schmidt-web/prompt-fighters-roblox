--!strict
-- Server entry point: loads all data modules (a broken table fails loudly on start) and starts the services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = ReplicatedStorage.Shared.Data
local Fighters = require(Data.Fighters)
local Arenas = require(Data.Arenas)
local Bosses = require(Data.Bosses)
local Weapons = require(Data.Weapons)
local Products = require(Data.Products)
local MatchService = require(script.Parent.Match.MatchService)

print(
	`[PromptFighters] data loaded: {#Fighters.list} fighters, {#Arenas.list} arenas, {#Bosses.order} bosses, `
		.. `{#Weapons.classic + #Weapons.shop} weapons, {#Products.GAME_PASSES} game passes`
)

MatchService.start()
