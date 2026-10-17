--!strict
-- Client entry point. Controllers (Input, Camera, HUD, VFX, Audio, Shop UI, Lobby UI) start here from Phase 1 on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Constants"))

print(`[PromptFighters] client ready, tick rate {Constants.TICK_RATE} Hz`)
