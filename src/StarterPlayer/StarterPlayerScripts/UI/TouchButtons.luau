--!strict
-- Touch controls for phones and tablets (shown during a match when the device has a touch screen):
--   left 45 % of the screen: floating stick (appears where the thumb lands; flick = F/B and D for finisher codes)
--   right side: ANGRIFF (big), SPRUNG, SPEZIAL (turns into SUPER! with a full meter) on the main arc,
--               SCHILD, GREIFEN, SMASH and AUSWEICHEN on the outer arc.
-- Button sizes follow the short screen edge in real pixels (no UIScale), never below MIN_BUTTON, and stay
-- inside the device safe area. Writes held state into InputController.virtual; the controller sends it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Constants"))
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MatchState = require(script.Parent.Parent.State.MatchState)

local TouchButtons = {}

TouchButtons.MIN_BUTTON = 56 -- px, smallest button (Roblox and platform guidance: >= 44)
TouchButtons.STICK_ZONE = 0.45 -- left share of the screen that starts the stick
TouchButtons.STICK_RANGE = 70 -- px of thumb travel for full speed
TouchButtons.STICK_DEAD = 14 -- px before the fighter walks
TouchButtons.STICK_VERTICAL = 42 -- px up/down for "up" / "down"

local FONT = Enum.Font.GothamBlack
local SUPER_GOLD = Color3.fromRGB(255, 205, 60)
local BASE = Color3.fromRGB(30, 26, 60)

type ButtonDef = {
	text: string,
	action: string,
	size: number, -- times the unit
	angle: number, -- degrees around the corner pivot (0 = left of it, 90 = above it)
	radius: number, -- times the unit from the pivot
	color: Color3?,
}

-- Main arc around ANGRIFF, outer arc for the rarer actions. Pivot sits near the bottom-right corner.
local BUTTONS: { ButtonDef } = {
	{ text = "ANGRIFF", action = "standard", size = 1.25, angle = 0, radius = 0, color = Color3.fromRGB(255, 60, 120) },
	{ text = "SPRUNG", action = "jump", size = 1.0, angle = 8, radius = 1.3 },
	{ text = "SPEZIAL", action = "special", size = 1.0, angle = 52, radius = 1.3, color = Color3.fromRGB(0, 170, 220) },
	{ text = "SCHILD", action = "block", size = 0.85, angle = 92, radius = 1.3 },
	{ text = "GREIFEN", action = "grab", size = 0.8, angle = 30, radius = 2.4 },
	{ text = "SMASH", action = "smash", size = 0.8, angle = 62, radius = 2.4 },
	{ text = "AUSWEICHEN", action = "dodge", size = 0.8, angle = 0, radius = 2.45 },
}

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

function TouchButtons.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Enabled = false
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local virtual = InputController.virtual :: any
	local holding: { [InputObject]: string } = {} -- touch -> action it holds
	local buttons: { [string]: { button: TextButton, def: ButtonDef } } = {}

	local function release(input: InputObject)
		local action = holding[input]
		if action then
			holding[input] = nil
			for _, other in holding do
				if other == action then
					return -- another finger still holds it
				end
			end
			virtual[action] = false
			local entry = buttons[action]
			if entry then
				entry.button.BackgroundTransparency = 0.25
			end
		end
	end

	for _, def in BUTTONS do
		local b = Instance.new("TextButton")
		b.Name = def.action
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.BackgroundColor3 = def.color or BASE
		b.BackgroundTransparency = 0.25
		b.AutoButtonColor = false
		b.Font = FONT
		b.TextScaled = true
		b.Text = def.text
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = gui
		corner(b, UDim.new(0.5, 0))
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.14, 0)
		pad.PaddingRight = UDim.new(0.14, 0)
		pad.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 0.6
		stroke.Thickness = 2
		stroke.Parent = b
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				holding[input] = def.action
				virtual[def.action] = true
				b.BackgroundTransparency = 0.05
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				release(input)
			end
		end)
		buttons[def.action] = { button = b, def = def }
	end

	-- Floating stick: a ring where the thumb landed and a knob that follows it.
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundColor3 = Color3.new(1, 1, 1)
	ring.BackgroundTransparency = 0.85
	ring.Visible = false
	ring.Parent = gui
	corner(ring, UDim.new(0.5, 0))
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.45
	knob.Visible = false
	knob.Parent = gui
	corner(knob, UDim.new(0.5, 0))

	-- Finisher hint for touch players: what the code letters mean here.
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -84)
	hint.Size = UDim2.fromOffset(520, 26)
	hint.BackgroundTransparency = 0.35
	hint.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
	hint.Font = FONT
	hint.TextScaled = true
	hint.TextColor3 = SUPER_GOLD
	hint.Text = "F/B = Stick zum/weg vom Gegner · U = SPRUNG · D = Stick ↓ · A = ANGRIFF · S = SPEZIAL"
	hint.Visible = false
	hint.Parent = gui
	corner(hint, UDim.new(0, 8))

	local unit = 64
	local function layout()
		-- The gui covers the device safe area; fall back to the viewport before it has a size.
		local view = if gui.AbsoluteSize.X > 0 then gui.AbsoluteSize else workspace.CurrentCamera.ViewportSize
		local short = math.min(view.X, view.Y)
		unit = math.max(TouchButtons.MIN_BUTTON / 0.8, math.clamp(short * 0.15, 60, 104))
		-- Pivot (center of ANGRIFF) near the bottom-right corner, clear of the damage cards' row.
		local pivot = Vector2.new(view.X - unit * 1.05, view.Y - unit * 1.05)
		for _, entry in buttons do
			local def = entry.def
			local size = math.max(TouchButtons.MIN_BUTTON, unit * def.size)
			local rad = math.rad(def.angle)
			local p = pivot + Vector2.new(-math.cos(rad), -math.sin(rad)) * unit * def.radius
			entry.button.Size = UDim2.fromOffset(size, size)
			entry.button.Position = UDim2.fromOffset(p.X, p.Y)
		end
		ring.Size = UDim2.fromOffset(TouchButtons.STICK_RANGE * 2, TouchButtons.STICK_RANGE * 2)
		knob.Size = UDim2.fromOffset(unit * 0.6, unit * 0.6)
		hint.Size = UDim2.fromOffset(math.min(view.X - 32, 620), math.max(20, unit * 0.32))
	end
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	-- Touch positions -> offsets inside this gui (input and Absolute* share one space).
	local function local2(input: InputObject): Vector2
		return Vector2.new(input.Position.X, input.Position.Y) - gui.AbsolutePosition
	end

	local stickOrigin: Vector2? = nil
	local stickInput: InputObject? = nil
	local function resetStick()
		stickInput, stickOrigin = nil, nil
		virtual.move, virtual.up, virtual.down = 0, false, false
		ring.Visible, knob.Visible = false, false
	end
	UserInputService.TouchStarted:Connect(function(input, processed)
		if not gui.Enabled then
			return
		end
		local origin = local2(input)
		if not processed and origin.X < gui.AbsoluteSize.X * TouchButtons.STICK_ZONE and stickInput == nil then
			stickInput = input
			stickOrigin = origin
			ring.Position = UDim2.fromOffset(origin.X, origin.Y)
			knob.Position = ring.Position
			ring.Visible, knob.Visible = true, true
		end
	end)
	UserInputService.TouchMoved:Connect(function(input)
		local origin = stickOrigin
		if input == stickInput and origin then
			local delta = local2(input) - origin
			virtual.move = if math.abs(delta.X) > TouchButtons.STICK_DEAD
				then math.clamp(delta.X / TouchButtons.STICK_RANGE, -1, 1)
				else 0
			virtual.up = delta.Y < -TouchButtons.STICK_VERTICAL
			virtual.down = delta.Y > TouchButtons.STICK_VERTICAL
			local clamped = if delta.Magnitude > TouchButtons.STICK_RANGE
				then delta.Unit * TouchButtons.STICK_RANGE
				else delta
			knob.Position = UDim2.fromOffset(origin.X + clamped.X, origin.Y + clamped.Y)
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == stickInput then
			resetStick()
		end
		-- A finger that slid off its button still lets go of it.
		release(input)
	end)

	local function releaseAll()
		for input in holding do
			release(input)
		end
		for _, def in BUTTONS do
			virtual[def.action] = false
		end
		resetStick()
	end

	local function refresh()
		local show = MatchState.phase == "match" and MatchState.mySlot ~= nil and UserInputService.TouchEnabled
		if gui.Enabled and not show then
			releaseAll()
		end
		gui.Enabled = show
	end
	MatchState.onEvent(function(event)
		if event.type == "phase" then
			refresh()
		elseif event.type == "finish_him" then
			hint.Visible = event.actor == MatchState.mySlot
		elseif event.type == "finisher" or event.type == "finish" then
			hint.Visible = false
		end
	end)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refresh)

	-- SPEZIAL shows SUPER! while the meter is full (the next special is a super hit).
	local special = buttons.special
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local snap = MatchState.snapshot
		local slot = MatchState.mySlot
		local f = if snap and slot then snap.fighters[slot] else nil
		local full = f ~= nil and f.super >= Constants.MAX_SUPER
		special.button.Text = if full then "SUPER!" else special.def.text
		special.button.BackgroundColor3 = if full then SUPER_GOLD else special.def.color or BASE
		if snap and not snap.finishPhase then
			hint.Visible = false
		end
	end)
end

return TouchButtons
