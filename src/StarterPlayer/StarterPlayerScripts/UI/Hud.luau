--!strict
-- Fight HUD (damage %, stocks, super bar, timer), center banners (3-2-1, LOS!, FINISHER, SUDDEN DEATH, winner),
-- the lobby fighter picker and touch buttons. Built in code for Phase 1; Phase 4 swaps in designed UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Data"):WaitForChild("Constants"))
local Fighters = require(Shared:WaitForChild("Data"):WaitForChild("Fighters"))
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local MatchRunner = require(Shared:WaitForChild("Combat"):WaitForChild("MatchRunner"))
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MatchState = require(script.Parent.Parent.State.MatchState)

local Hud = {}

local FONT = Enum.Font.GothamBlack

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = FONT
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	if textSize then
		l.TextSize = textSize
	else
		l.TextScaled = true
	end
	l.Parent = parent
	return l
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Damage color goes white -> yellow -> orange -> red as the percent rises (kill range reads at a glance).
local function percentColor(percent: number): Color3
	local t = math.clamp(percent / 150, 0, 1)
	return Color3.new(1, 1 - t * 0.85, 1 - math.min(t * 2, 1))
end

type Card = { frame: Frame, percent: TextLabel, stocks: TextLabel, super: Frame, name: TextLabel }

function Hud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FightHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local timer = label(gui, "", UDim2.fromOffset(160, 50), UDim2.new(0.5, -80, 0, 18))
	local banner = label(gui, "", UDim2.new(1, 0, 0, 110), UDim2.new(0, 0, 0.32, 0))
	banner.TextColor3 = Color3.fromRGB(255, 225, 70)
	local subBanner = label(gui, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0.32, 112))

	local cardRow = Instance.new("Frame")
	cardRow.BackgroundTransparency = 1
	cardRow.Size = UDim2.new(1, 0, 0, 92)
	cardRow.Position = UDim2.new(0, 0, 1, -104)
	cardRow.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = cardRow

	local cards: { Card } = {}

	local function buildCards()
		for _, card in cards do
			card.frame:Destroy()
		end
		table.clear(cards)
		for i, slot in MatchState.slots do
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromOffset(170, 88)
			frame.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
			frame.BackgroundTransparency = 0.15
			frame.LayoutOrder = i
			frame.Parent = cardRow
			corner(frame, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromHex(Visuals.SLOT_COLORS[i] or "#FFFFFF")
			stroke.Thickness = 3
			stroke.Parent = frame
			local name = label(
				frame,
				(if slot.userId then `P{i} ` else "CPU ") .. slot.name,
				UDim2.new(1, -12, 0, 18),
				UDim2.fromOffset(6, 4)
			)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local percent = label(frame, "0%", UDim2.new(1, -12, 0, 40), UDim2.fromOffset(6, 22))
			percent.TextXAlignment = Enum.TextXAlignment.Left
			local stocks = label(frame, "", UDim2.new(0.5, 0, 0, 18), UDim2.new(0.5, -6, 0, 30))
			stocks.TextXAlignment = Enum.TextXAlignment.Right
			local barBack = Instance.new("Frame")
			barBack.Size = UDim2.new(1, -12, 0, 8)
			barBack.Position = UDim2.fromOffset(6, 70)
			barBack.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
			barBack.Parent = frame
			corner(barBack, 4)
			local bar = Instance.new("Frame")
			bar.Size = UDim2.fromScale(0, 1)
			bar.BackgroundColor3 = Color3.fromRGB(0, 230, 255)
			bar.Parent = barBack
			corner(bar, 4)
			cards[i] = { frame = frame, percent = percent, stocks = stocks, super = bar, name = name }
		end
	end

	-- Lobby: pick one of the slice fighters.
	local picker = Instance.new("Frame")
	picker.Size = UDim2.new(1, 0, 0, 170)
	picker.Position = UDim2.new(0, 0, 1, -200)
	picker.BackgroundTransparency = 1
	picker.Parent = gui
	local pickerLayout = layout:Clone()
	pickerLayout.Parent = picker
	local pickerTitle = label(gui, "WÄHLE DEINEN KÄMPFER", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 1, -250))
	local selectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SelectFighter") :: RemoteEvent
	local chosen: string? = nil
	local pickButtons: { [string]: TextButton } = {}
	for _, fighterId in Visuals.SLICE_FIGHTERS do
		local def = Fighters.get(fighterId)
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(150, 150)
		button.BackgroundColor3 = Color3.fromHex(Visuals.elementColor(def.element))
		button.Font = FONT
		button.TextScaled = true
		button.Text = def.name
		button.TextColor3 = Color3.fromRGB(16, 14, 30)
		button.Parent = picker
		corner(button, 14)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 0
		stroke.Color = Color3.new(1, 1, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		button.Activated:Connect(function()
			chosen = fighterId
			selectRemote:FireServer(fighterId)
			for id, b in pickButtons do
				(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = if id == fighterId then 5 else 0
			end
		end)
		pickButtons[fighterId] = button
	end

	-- Touch: big buttons on the right, a floating stick on the left half.
	local touch = Instance.new("Frame")
	touch.BackgroundTransparency = 1
	touch.Size = UDim2.fromScale(1, 1)
	touch.Visible = false
	touch.Parent = gui
	local function touchButton(text: string, action: string, position: UDim2, size: number)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(size, size)
		b.Position = position
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.BackgroundColor3 = Color3.fromRGB(30, 26, 60)
		b.BackgroundTransparency = 0.25
		b.Font = FONT
		b.TextScaled = true
		b.Text = text
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = touch
		corner(b, size // 2)
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				(InputController.virtual :: any)[action] = true
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				(InputController.virtual :: any)[action] = false
			end
		end)
	end
	touchButton("ANGRIFF", "standard", UDim2.new(1, -150, 1, -110), 96)
	touchButton("SPEZIAL", "special", UDim2.new(1, -60, 1, -200), 84)
	touchButton("SPRUNG", "jump", UDim2.new(1, -60, 1, -90), 84)
	touchButton("SCHILD", "block", UDim2.new(1, -250, 1, -70), 70)
	touchButton("GREIFEN", "grab", UDim2.new(1, -150, 1, -220), 70)
	touchButton("SMASH", "smash", UDim2.new(1, -250, 1, -170), 70)

	local stickOrigin: Vector2? = nil
	local stickInput: InputObject? = nil
	UserInputService.TouchStarted:Connect(function(input, processed)
		local viewport = workspace.CurrentCamera.ViewportSize
		if not processed and input.Position.X < viewport.X * 0.45 and stickInput == nil then
			stickInput = input
			stickOrigin = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.TouchMoved:Connect(function(input)
		local origin = stickOrigin
		if input == stickInput and origin then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - origin
			local v = InputController.virtual
			v.move = if math.abs(delta.X) > 18 then math.clamp(delta.X / 70, -1, 1) else 0
			v.up = delta.Y < -45
			v.down = delta.Y > 45
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == stickInput then
			stickInput, stickOrigin = nil, nil
			local v = InputController.virtual
			v.move, v.up, v.down = 0, false, false
		end
	end)

	local function showBanner(text: string, sub: string?, seconds: number?)
		banner.Text = text
		subBanner.Text = sub or ""
		banner.TextTransparency = 0
		subBanner.TextTransparency = 0
		banner.Size = UDim2.new(1, 0, 0, 150)
		TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.new(1, 0, 0, 110) })
			:Play()
		local token = text
		task.delay(seconds or 1.4, function()
			if banner.Text == token then
				banner.Text = ""
				subBanner.Text = ""
			end
		end)
	end

	MatchState.onEvent(function(event)
		local t = event.type
		if t == "phase" then
			local inLobby = event.phase == "lobby"
			picker.Visible = inLobby
			pickerTitle.Visible = inLobby
			cardRow.Visible = not inLobby
			touch.Visible = event.phase == "match" and MatchState.mySlot ~= nil and UserInputService.TouchEnabled
			if event.phase == "match" then
				buildCards()
			end
			if inLobby then
				timer.Text = if chosen then `START IN {math.ceil(event.timer)}` else ""
			end
		elseif t == "go" then
			showBanner("LOS!", nil, 0.8)
		elseif t == "ring_out" and event.lives > 0 then
			local slot = MatchState.slots[event.actor]
			showBanner("KO!", if slot then slot.name else nil, 0.9)
		elseif t == "finish_him" then
			showBanner("FINISHER!", "Code: " .. table.concat(event.code, " "), 5)
		elseif t == "finisher" then
			showBanner(event.name, "FINISHER", 2.5)
		elseif t == "sudden_death" then
			showBanner("SUDDEN DEATH", "150 % – ein Treffer entscheidet", 2)
		elseif t == "results" then
			local winner = MatchState.slots[event.winner]
			if winner then
				local you = event.winner == MatchState.mySlot
				showBanner(if you then "SIEG!" else `{winner.name} GEWINNT`, if you then "Nochmal?" else nil, 6)
			else
				showBanner("UNENTSCHIEDEN", nil, 6)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if MatchState.snapshot == nil or MatchState.phase == "lobby" then
			return
		end
		local snap = MatchState.snapshot :: MatchRunner.NetSnapshot
		if snap.countdown > 0 then
			timer.Text = tostring(math.ceil(snap.countdown))
		elseif snap.finishPhase then
			timer.Text = string.format("%.1f", math.max(0, snap.finishTimer))
		else
			local s = math.ceil(snap.timeLeft)
			timer.Text = string.format("%d:%02d", s // 60, s % 60)
		end
		for i, f in snap.fighters do
			local card = cards[i]
			if card then
				card.percent.Text = if f.state == "Defeated" then "—" else `{math.floor(f.percent)}%`
				card.percent.TextColor3 = percentColor(f.percent)
				card.stocks.Text = string.rep("●", f.lives)
				card.super.Size = UDim2.fromScale(math.clamp(f.super / Constants.MAX_SUPER, 0, 1), 1)
			end
		end
	end)
end

return Hud
