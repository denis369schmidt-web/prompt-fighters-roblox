--!strict
-- Fight HUD (damage %, stocks, super bar, timer), center banners (3-2-1, LOS!, FINISHER, SUDDEN DEATH, winner),
-- the lobby fighter picker and touch buttons. Built in code for Phase 1; Phase 4 swaps in designed UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arenas = require(Shared:WaitForChild("Data"):WaitForChild("Arenas"))
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

	local timer = label(gui, "", UDim2.fromOffset(120, 34), UDim2.new(0.5, -60, 0, 14))
	local banner = label(gui, "", UDim2.new(1, 0, 0, 110), UDim2.new(0, 0, 0.32, 0))
	banner.TextColor3 = Color3.fromRGB(255, 225, 70)
	local subBanner = label(gui, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0.32, 112))

	-- Everything shrinks on small screens (phones) so the fight stays visible.
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Damage cards: one slim row along the bottom edge, below the stage.
	local cardRow = Instance.new("Frame")
	cardRow.BackgroundTransparency = 1
	cardRow.Size = UDim2.new(1, 0, 0, 58)
	cardRow.Position = UDim2.new(0, 0, 1, -64)
	cardRow.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = cardRow

	local cards: { Card } = {}

	local function buildCards()
		for _, card in cards do
			card.frame:Destroy()
		end
		table.clear(cards)
		for i, slot in MatchState.slots do
			local mine = i == MatchState.mySlot
			local slotColor = Color3.fromHex(Visuals.SLOT_COLORS[i] or "#FFFFFF")
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromOffset(if mine then 168 else 148, 54)
			frame.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
			frame.BackgroundTransparency = if mine then 0.15 else 0.4
			frame.LayoutOrder = i
			frame.Parent = cardRow
			corner(frame, 8)
			local stroke = Instance.new("UIStroke")
			stroke.Color = slotColor
			stroke.Thickness = if mine then 3 else 1.5
			stroke.Parent = frame
			local name = label(
				frame,
				(if mine then "DU · " elseif slot.userId then "" else "CPU · ") .. slot.name,
				UDim2.new(1, -12, 0, 14),
				UDim2.fromOffset(6, 3),
				13
			)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextColor3 = slotColor
			local percent = label(frame, "0%", UDim2.new(0.6, 0, 0, 30), UDim2.fromOffset(6, 17), 28)
			percent.TextXAlignment = Enum.TextXAlignment.Left
			local stocks = label(frame, "", UDim2.new(0.4, -6, 0, 30), UDim2.new(0.6, 0, 0, 17), 14)
			stocks.TextXAlignment = Enum.TextXAlignment.Right
			stocks.TextColor3 = slotColor
			local barBack = Instance.new("Frame")
			barBack.Size = UDim2.new(1, -12, 0, 4)
			barBack.Position = UDim2.new(0, 6, 1, -7)
			barBack.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
			barBack.BorderSizePixel = 0
			barBack.Parent = frame
			corner(barBack, 2)
			local bar = Instance.new("Frame")
			bar.Size = UDim2.fromScale(0, 1)
			bar.BackgroundColor3 = Color3.fromRGB(0, 230, 255)
			bar.BorderSizePixel = 0
			bar.Parent = barBack
			corner(bar, 2)
			cards[i] = { frame = frame, percent = percent, stocks = stocks, super = bar, name = name }
		end
	end

	local setPickerOpen: (open: boolean) -> ()

	-- Lobby: pick one of the launch fighters (8 x 2 grid that shrinks to the screen width).
	local picker = Instance.new("Frame")
	picker.Size = UDim2.new(0.96, 0, 0, 236)
	picker.AnchorPoint = Vector2.new(0.5, 0)
	picker.Position = UDim2.new(0.5, 0, 1, -256)
	picker.BackgroundTransparency = 1
	picker.Parent = gui
	local pickerLayout = Instance.new("UIGridLayout")
	pickerLayout.CellSize = UDim2.new(0.115, 0, 0.47, 0)
	pickerLayout.CellPadding = UDim2.new(0.01, 0, 0.04, 0)
	pickerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Parent = picker
	local pickerTitle = label(gui, "WÄHLE DEINEN KÄMPFER", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 1, -306))
	local selectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SelectFighter") :: RemoteEvent
	local chosen: string? = nil
	local pickButtons: { [string]: TextButton } = {}
	for _, fighterId in Visuals.SLICE_FIGHTERS do
		local def = Fighters.get(fighterId)
		local button = Instance.new("TextButton")
		button.LayoutOrder = #picker:GetChildren()
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
			-- Close the picker so the lobby is free to walk around in.
			setPickerOpen(false)
		end)
		pickButtons[fighterId] = button
	end

	-- Lobby: arena vote buttons (same as standing on a pad) and the button that reopens the picker.
	local votedByButton = false
	local voteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VoteArena") :: RemoteEvent
	local voteRow = Instance.new("Frame")
	voteRow.BackgroundTransparency = 1
	voteRow.Size = UDim2.fromOffset(220, 3 * 48)
	voteRow.AnchorPoint = Vector2.new(1, 0)
	voteRow.Position = UDim2.new(1, -12, 0, 80)
	voteRow.Parent = gui
	local voteLayout = Instance.new("UIListLayout")
	voteLayout.Padding = UDim.new(0, 6)
	voteLayout.SortOrder = Enum.SortOrder.LayoutOrder
	voteLayout.Parent = voteRow
	local voteTitle = label(gui, "ARENA WÄHLEN", UDim2.fromOffset(220, 26), UDim2.new(1, -232, 0, 50))
	local voteButtons: { TextButton } = {}
	for k = 1, 3 do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, 42)
		b.LayoutOrder = k
		b.BackgroundColor3 = Color3.fromRGB(24, 20, 44)
		b.BackgroundTransparency = 0.15
		b.Font = FONT
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = ""
		b.Parent = voteRow
		corner(b, 8)
		b.Activated:Connect(function()
			local id = MatchState.options[k]
			if id then
				voteRemote:FireServer(id)
				votedByButton = true
			end
		end)
		voteButtons[k] = b
	end

	local pickerToggle = Instance.new("TextButton")
	pickerToggle.Size = UDim2.fromOffset(220, 54)
	pickerToggle.AnchorPoint = Vector2.new(0.5, 1)
	pickerToggle.Position = UDim2.new(0.5, 0, 1, -16)
	pickerToggle.BackgroundColor3 = Color3.fromRGB(255, 40, 200)
	pickerToggle.Font = FONT
	pickerToggle.TextScaled = true
	pickerToggle.TextColor3 = Color3.new(1, 1, 1)
	pickerToggle.Text = "KÄMPFER WÄHLEN"
	pickerToggle.Visible = false
	pickerToggle.Parent = gui
	corner(pickerToggle, 12)
	pickerToggle.Activated:Connect(function()
		setPickerOpen(true)
	end)

	setPickerOpen = function(open: boolean)
		local inLobby = MatchState.phase == "lobby"
		picker.Visible = inLobby and open
		pickerTitle.Visible = inLobby and open
		pickerToggle.Visible = inLobby and not open
		pickerToggle.Text = if chosen then `{Fighters.get(chosen :: string).name} · ÄNDERN` else "KÄMPFER WÄHLEN"
	end

	-- Lobby guide: three steps on the left that tick off as the player does them.
	local guide = Instance.new("Frame")
	guide.Size = UDim2.fromOffset(280, 132)
	guide.Position = UDim2.fromOffset(12, 80)
	guide.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
	guide.BackgroundTransparency = 0.25
	guide.Parent = gui
	corner(guide, 10)
	local guideTitle = label(guide, "SO GEHT'S", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 8), 18)
	guideTitle.TextXAlignment = Enum.TextXAlignment.Left
	guideTitle.TextColor3 = Color3.fromRGB(255, 225, 70)
	local steps: { TextLabel } = {}
	for k = 1, 3 do
		local step = label(guide, "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 6 + k * 30), 17)
		step.TextXAlignment = Enum.TextXAlignment.Left
		steps[k] = step
	end

	local function onPad(): boolean
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local lobby = workspace:FindFirstChild("Lobby")
		if root == nil or not root:IsA("BasePart") or lobby == nil then
			return false
		end
		for k = 1, 3 do
			local pad = lobby:FindFirstChild("VotePad" .. k)
			if pad and pad:IsA("BasePart") then
				local d = pad.Position - root.Position
				if Vector2.new(d.X, d.Z).Magnitude <= pad.Size.Y / 2 then
					return true
				end
			end
		end
		return false
	end

	local function updateGuide()
		local inLobby = MatchState.phase == "lobby"
		guide.Visible = inLobby
		if not inLobby then
			return
		end
		local picked = chosen ~= nil
		local voted = votedByButton or onPad()
		steps[1].Text = (if picked then "✓  " else "1  ") .. "Kämpfer wählen"
		steps[2].Text = (if voted then "✓  " else "2  ") .. "Auf ein Arena-Feld stellen"
		steps[3].Text = if picked
			then `3  Kampf startet in {math.max(0, math.ceil(MatchState.timer))} s`
			else "3  Warten auf den Start"
		steps[1].TextColor3 = if picked then Color3.fromRGB(120, 255, 160) else Color3.new(1, 1, 1)
		steps[2].TextColor3 = if voted then Color3.fromRGB(120, 255, 160) else Color3.new(1, 1, 1)
	end
	task.spawn(function()
		while gui.Parent do
			updateGuide()
			task.wait(0.25)
		end
	end)

	local function showVotes()
		local inLobby = MatchState.phase == "lobby" and #MatchState.options > 0
		voteRow.Visible = inLobby
		voteTitle.Visible = inLobby
		for k, b in voteButtons do
			local id = MatchState.options[k]
			local info = if id then Arenas.byId[id] else nil
			local count = MatchState.votes[k] or 0
			b.Visible = id ~= nil
			b.Text = if info then `{info.name}  ·  {count}` else ""
		end
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

	local lastPhase = ""
	MatchState.onEvent(function(event)
		local t = event.type
		if t == "phase" then
			local inLobby = event.phase == "lobby"
			-- Fewer Roblox menus over the fight: no backpack ever, player list only in the lobby.
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, inLobby)
			end)
			-- The picker opens by itself only while no fighter is chosen.
			setPickerOpen(inLobby and (chosen == nil or picker.Visible))
			showVotes()
			cardRow.Visible = not inLobby
			touch.Visible = event.phase == "match" and MatchState.mySlot ~= nil and UserInputService.TouchEnabled
			if event.phase == "match" and lastPhase ~= "match" then
				buildCards()
				local info = Arenas.byId[event.arena or ""]
				if info then
					showBanner(info.name, "ARENA", 1.6)
				end
			end
			if inLobby then
				timer.Text = "" -- the lobby guide shows the countdown
				if lastPhase ~= "lobby" then
					votedByButton = false
				end
			end
			lastPhase = event.phase
		elseif t == "go" then
			showBanner("LOS!", nil, 0.8)
		elseif t == "ring_out" and event.lives > 0 then
			local slot = MatchState.slots[event.actor]
			showBanner("KO!", if slot then slot.name else nil, 0.9)
		elseif t == "finish_him" then
			showBanner("FINISHER!", "Code: " .. table.concat(event.code, " "), 5)
		elseif t == "finisher" then
			showBanner(event.name, "FINISHER", 2.5)
		elseif t == "fighter_eliminated" and event.actor == MatchState.mySlot then
			showBanner("DU BIST RAUS", "Zuschauen – nächste Runde gleich", 3)
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
				card.percent.Text = if f.state == "Defeated" then "RAUS" else `{math.floor(f.percent)}%`
				card.percent.TextColor3 = percentColor(f.percent)
				card.stocks.Text = string.rep("●", f.lives)
				card.super.Size = UDim2.fromScale(math.clamp(f.super / Constants.MAX_SUPER, 0, 1), 1)
			end
		end
	end)
end

return Hud
