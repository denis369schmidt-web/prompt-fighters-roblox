--!strict
-- Client entry point: match state from the server, then input, rendering, camera and HUD.

local MatchState = require(script.Parent.State.MatchState)
local InputController = require(script.Parent.Controllers.InputController)
local FighterView = require(script.Parent.Controllers.FighterView)
local ProjectileView = require(script.Parent.Controllers.ProjectileView)
local CameraController = require(script.Parent.Controllers.CameraController)
local Hud = require(script.Parent.UI.Hud)

MatchState.start()
InputController.start()
FighterView.start()
ProjectileView.start()
CameraController.start()
Hud.start()
