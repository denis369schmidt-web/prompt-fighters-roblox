--!strict
-- Keyboard, gamepad and touch -> one Command, sent as (mask, axis) at most 60 times per second.
-- Presses (jump, attack ...) are edge-detected here and OR-ed into the next packet, so a tap is never lost
-- even when the frame rate is above 60.
--
-- Keyboard: A/D or arrows move, W up, S down, Space jump, J attack, K special, L or Shift shield, U grab,
--           I smash (attack + direction), O dodge.
-- Gamepad:  left stick, A jump, X attack, B special, L1/R1 shield, R2 grab, L2 dodge, right stick smash.
-- Touch:    left half is a floating stick, buttons on the right (see UI/TouchButtons).
-- Dodge is a short shield tap: with a direction it rolls, without one it spot-dodges (shield + down) on the
-- ground and air-dodges in the air. Super = special with a full meter; signature moves are specials.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Input = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat"):WaitForChild("Input"))
local MatchState = require(script.Parent.Parent.State.MatchState)

local SEND_INTERVAL = 1 / 60
local STICK_DEADZONE = 0.25

local InputController = {}

-- Held state from every device; touch UI writes into `virtual`.
local virtual = {
	move = 0,
	up = false,
	down = false,
	jump = false,
	standard = false,
	special = false,
	block = false,
	grab = false,
	smash = false,
	dodge = false,
}
InputController.virtual = virtual

-- Ticks (60 Hz) a dodge holds the shield; a fresh shield press is what starts the dodge in the simulation.
local DODGE_TICKS = 5

local KEY_ACTIONS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Space] = "jump",
	[Enum.KeyCode.J] = "standard",
	[Enum.KeyCode.K] = "special",
	[Enum.KeyCode.L] = "block",
	[Enum.KeyCode.LeftShift] = "block",
	[Enum.KeyCode.U] = "grab",
	[Enum.KeyCode.I] = "smash",
	[Enum.KeyCode.O] = "dodge",
	[Enum.KeyCode.ButtonL2] = "dodge",
	[Enum.KeyCode.ButtonA] = "jump",
	[Enum.KeyCode.ButtonX] = "standard",
	[Enum.KeyCode.ButtonB] = "special",
	[Enum.KeyCode.ButtonL1] = "block",
	[Enum.KeyCode.ButtonR1] = "block",
	[Enum.KeyCode.ButtonR2] = "grab",
}

local function key(code: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(code)
end

local gamepadStick = Vector2.zero
local gamepadSmash = Vector2.zero
local pressedButtons: { [string]: boolean } = {}
local dodgeTicks = 0 -- shield held for a dodge (counts down per sent packet)
local dodgeDown = false -- this dodge is a spot dodge (adds "down")
local dodgeWasHeld = false

-- Is the local fighter on the ground (latest snapshot)?
local function grounded(): boolean
	local snap = MatchState.snapshot
	local slot = MatchState.mySlot
	local f = if snap and slot then snap.fighters[slot] else nil
	return f ~= nil and f.grounded
end

local function readHeld(): { [string]: any }
	local move = 0
	if key(Enum.KeyCode.A) or key(Enum.KeyCode.Left) then
		move -= 1
	end
	if key(Enum.KeyCode.D) or key(Enum.KeyCode.Right) then
		move += 1
	end
	if math.abs(gamepadStick.X) > STICK_DEADZONE then
		move = gamepadStick.X
	end
	if virtual.move ~= 0 then
		move = virtual.move
	end
	local held: { [string]: any } = {
		move = math.clamp(move, -1, 1),
		up = key(Enum.KeyCode.W) or key(Enum.KeyCode.Up) or gamepadStick.Y > 0.6 or virtual.up,
		down = key(Enum.KeyCode.S) or key(Enum.KeyCode.Down) or gamepadStick.Y < -0.6 or virtual.down,
		smash = gamepadSmash.Magnitude > 0.6 or virtual.smash,
	}
	for _, action in { "jump", "standard", "special", "block", "grab" } do
		held[action] = pressedButtons[action] == true or (virtual :: any)[action] == true
	end
	-- Dodge: a new press starts a short shield tap (see header).
	local dodgeHeld = pressedButtons.dodge == true or virtual.dodge
	if dodgeHeld and not dodgeWasHeld and dodgeTicks <= 0 then
		dodgeTicks = DODGE_TICKS
		dodgeDown = math.abs(held.move) < 0.6 and grounded()
	end
	dodgeWasHeld = dodgeHeld
	if dodgeTicks > 0 then
		if dodgeTicks == DODGE_TICKS and held.block then
			held.block = false -- release a held shield for one tick so the dodge gets a fresh press
		else
			held.block = true
		end
		held.down = held.down or dodgeDown
	end
	if held.smash then
		-- Right stick / smash button: attack in that direction.
		if gamepadSmash.Magnitude > 0.6 then
			held.move = if math.abs(gamepadSmash.X) > 0.4 then math.sign(gamepadSmash.X) else 0
			held.up = gamepadSmash.Y > 0.5
			held.down = gamepadSmash.Y < -0.5
		end
		held.standard = true
	end
	return held
end

function InputController.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Input") :: RemoteEvent

	UserInputService.InputBegan:Connect(function(input, processed)
		local action = KEY_ACTIONS[input.KeyCode]
		if action and not processed then
			pressedButtons[action] = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local action = KEY_ACTIONS[input.KeyCode]
		if action then
			pressedButtons[action] = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gamepadStick = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadSmash = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	local previous: { [string]: any } = {}
	local pendingPress: { [string]: boolean } =
		{ jump = false, standard = false, special = false, grab = false, smash = false }
	local sinceSend = 0
	local seq = 0
	RunService.RenderStepped:Connect(function(dt)
		if MatchState.phase ~= "match" or MatchState.mySlot == nil then
			previous = {}
			return
		end
		local held = readHeld()
		for action in pendingPress do
			if held[action] and not previous[action] then
				pendingPress[action] = true
			end
		end
		previous = held
		sinceSend += dt
		if sinceSend < SEND_INTERVAL * 0.9 then
			return
		end
		sinceSend = math.max(0, sinceSend - SEND_INTERVAL)
		if dodgeTicks > 0 then
			dodgeTicks -= 1
		end
		local cmd = Input.idle()
		cmd.move = held.move
		cmd.up, cmd.down, cmd.block = held.up, held.down, held.block
		cmd.jump, cmd.standard, cmd.special = pendingPress.jump, pendingPress.standard, pendingPress.special
		cmd.grab, cmd.smash = pendingPress.grab, pendingPress.smash
		cmd.jumpHeld, cmd.standardHeld, cmd.specialHeld = held.jump, held.standard, held.special
		for action in pendingPress do
			pendingPress[action] = false
		end
		local mask, axis = Input.encode(cmd)
		seq += 1
		remote:FireServer(mask, axis, 0, seq)
	end)
end

return InputController
