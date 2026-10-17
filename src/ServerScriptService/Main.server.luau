--!strict
-- Server entry point. Phase 0: loads all data modules so a broken table fails loudly on server start.
-- Services (MatchService, DataService, ShopService ...) are started from here from Phase 1 on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = ReplicatedStorage.Shared.Data
local Fighters = require(Data.Fighters)
local Arenas = require(Data.Arenas)
local Bosses = require(Data.Bosses)
local Weapons = require(Data.Weapons)
local Products = require(Data.Products)

print(
	`[PromptFighters] data loaded: {#Fighters.list} fighters, {#Arenas.list} arenas, {#Bosses.order} bosses, `
		.. `{#Weapons.classic + #Weapons.shop} weapons, {#Products.GAME_PASSES} game passes`
)
