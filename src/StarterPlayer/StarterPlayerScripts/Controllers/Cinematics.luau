--!strict
-- Match cinematics around the fight, all client-side and display only:
--   Intro    letterbox, arena name card, the fighters' name plates slide in (VS), a camera sweep over the arena,
--            then 3 · 2 · 1 · KAMPF! from the server countdown (snapshot.countdown, the "go" event).
--            A rematch shows a short REVANCHE! card instead of the plates.
--   GAME!    freeze card on the server's "finish" event (the KO slow motion itself lives in Juice/Camera).
--   Victory  the camera orbits the winner, who strikes the Victory pose (the server sends state "Victory").
--   Podium   places, KOs, damage and best combo per fighter, then the reward card (MetaHud) and the
--            NOCHMAL / Zur Lobby buttons (VoteRematch). Tapping during the victory scene skips to the podium.
-- The camera override runs one render step after the fight camera and blends on top of it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arenas = require(Shared:WaitForChild("Data"):WaitForChild("Arenas"))
local Visuals = require(Shared:WaitForChild("Data"):WaitForChild("Visuals"))
local MatchRunner = require(Shared:WaitForChild("Combat"):WaitForChild("MatchRunner"))
local Bot = require(Shared:WaitForChild("Combat"):WaitForChild("Bot"))
local Announcer = require(script.Parent.Parent.UI.Announcer)
local MetaHud = require(script.Parent.Parent.UI.MetaHud)
local MatchState = require(script.Parent.Parent.State.MatchState)
local FighterView = require(script.Parent.FighterView)
local Juice = require(script.Parent.Juice)
local Sfx = require(script.Parent.Sfx)

local Cinematics = {}

local FONT = Enum.Font.GothamBlack
local GOLD = Color3.fromRGB(255, 215, 80)
local PINK = Color3.fromRGB(255, 40, 200)
local PANEL = Color3.fromRGB(16, 14, 30)
local WHITE = Color3.new(1, 1, 1)
local MEDALS = {
	Color3.fromRGB(255, 215, 80),
	Color3.fromRGB(205, 215, 230),
	Color3.fromRGB(215, 140, 80),
	Color3.fromRGB(150, 145, 170),
}
local COUNT_COLORS = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 190, 60), Color3.fromRGB(120, 255, 160) }

-- Bot personality on the CPU name plates (Combat/Bot styles).
local STYLE_LABEL: { [string]: string } = {
	rushdown = "Draufgänger",
	zoner = "Fernkämpfer",
	grappler = "Packer",
	defensive = "Konterer",
	allround = "Allrounder",
}

local GAME_SECONDS = 1.6 -- GAME! card before the victory scene
local VICTORY_SECONDS = 3.6 -- camera orbit before the podium
local PLATES_UNTIL = 3.05 -- countdown value at which the name plates leave and 3 · 2 · 1 starts

type Stat = { place: number?, kos: number, damage: number, bestCombo: number, finishers: number, stocksLost: number }

-- Camera override state.
local intro = { active = false, start = 0, length = 1 }
local orbit = { active = false, slot = 0, start = 0, settled = false }

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = FONT
	l.Text = text
	l.TextColor3 = WHITE
	l.TextStrokeTransparency = 0.3
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

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out), goal)
		:Play()
end

local function slotColor(slot: number): Color3
	return Color3.fromHex(Visuals.SLOT_COLORS[slot] or "#FFFFFF")
end

local function smooth(u: number): number
	local v = math.clamp(u, 0, 1)
	return v * v * (3 - 2 * v)
end

-- Camera: intro sweep and the victory orbit, blended over the fight camera's frame.
local function cameraStep()
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		return
	end
	local now = os.clock()
	if intro.active then
		local u = (now - intro.start) / intro.length
		if u >= 1 then
			intro.active = false
			return
		end
		local w = 1 - smooth(u)
		local angle = -0.75 + u * 0.55
		local center = FighterView.toWorld(0, 2.5)
		local radius = 95 - u * 30
		local eye = center + Vector3.new(math.sin(angle) * radius, 30 - u * 18, math.cos(angle) * radius)
		local sweep = CFrame.lookAt(eye, center)
		camera.CFrame = camera.CFrame:Lerp(sweep, w)
		return
	end
	if orbit.active then
		local snap = MatchState.snapshot
		local found = if snap then snap.fighters[orbit.slot] else nil
		if not found then
			return
		end
		local f = found :: MatchRunner.NetFighter
		local t = now - orbit.start
		local target = FighterView.toWorld(f.x, f.y) + Vector3.new(0, 3.2, 0)
		local angle, radius, height
		if orbit.settled then
			-- Behind the podium: a slow, wider turn.
			angle = -0.2 + math.sin(t * 0.25) * 0.5
			radius, height = 21, 4
		else
			local u = smooth(t / VICTORY_SECONDS)
			angle = -1.0 + u * 1.3
			radius, height = 20 - u * 7, 5 - u * 2.5
		end
		local eye = target + Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)
		local goal = CFrame.lookAt(eye, target)
		local blend = math.clamp(t / 0.6, 0, 1)
		camera.CFrame = camera.CFrame:Lerp(goal, smooth(blend))
	end
end

function Cinematics.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cinematics"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Letterbox bars (scale-sized, so they ignore UIScale).
	local bars: { Frame } = {}
	for k = 1, 2 do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, 0)
		bar.AnchorPoint = Vector2.new(0, if k == 1 then 0 else 1)
		bar.Position = UDim2.fromScale(0, if k == 1 then 0 else 1)
		bar.ZIndex = 1
		bar.Parent = gui
		bars[k] = bar
	end
	local function letterbox(on: boolean)
		for _, bar in bars do
			tween(bar, 0.45, { Size = UDim2.fromScale(1, if on then 0.09 else 0) })
		end
	end

	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 0
	flash.Parent = gui

	-- Intro: arena card and name plates.
	local introLayer = Instance.new("Frame")
	introLayer.BackgroundTransparency = 1
	introLayer.Size = UDim2.fromScale(1, 1)
	introLayer.Visible = false
	introLayer.ZIndex = 2
	introLayer.Parent = gui
	local arenaCard = Instance.new("Frame")
	arenaCard.AnchorPoint = Vector2.new(0.5, 0)
	arenaCard.Size = UDim2.fromOffset(560, 96)
	arenaCard.Position = UDim2.new(0.5, 0, 0, 70)
	arenaCard.BackgroundColor3 = PANEL
	arenaCard.BackgroundTransparency = 0.15
	arenaCard.Parent = introLayer
	corner(arenaCard, 14)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = PINK
	cardStroke.Thickness = 3
	cardStroke.Parent = arenaCard
	local arenaCaption = label(arenaCard, "ARENA", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 8), 18)
	arenaCaption.TextColor3 = PINK
	local arenaName = label(arenaCard, "", UDim2.new(1, -24, 0, 54), UDim2.fromOffset(12, 32))
	arenaName.TextColor3 = GOLD
	local versus = label(introLayer, "VS", UDim2.fromOffset(160, 110), UDim2.new(0.5, -80, 0.5, -40))
	versus.TextColor3 = PINK
	local versusStroke = Instance.new("UIStroke")
	versusStroke.Thickness = 4
	versusStroke.Color = Color3.fromRGB(20, 8, 40)
	versusStroke.Parent = versus
	local plates: { Frame } = {}

	local function clearPlates()
		for _, plate in plates do
			plate:Destroy()
		end
		table.clear(plates)
	end

	local function plateTarget(slot: number): (UDim2, UDim2)
		local left = slot % 2 == 1
		local row = (slot - 1) // 2
		local y = UDim2.new(0, 0, 0.5, -60 + row * 96)
		local on = if left then UDim2.new(0, 40, y.Y.Scale, y.Y.Offset) else UDim2.new(1, -380, y.Y.Scale, y.Y.Offset)
		local off = if left then UDim2.new(0, -420, y.Y.Scale, y.Y.Offset) else UDim2.new(1, 60, y.Y.Scale, y.Y.Offset)
		return on, off
	end

	local function buildPlates()
		clearPlates()
		for i, slot in MatchState.slots do
			local color = slotColor(i)
			local mine = i == MatchState.mySlot
			local plate = Instance.new("Frame")
			plate.Size = UDim2.fromOffset(340, 80)
			plate.BackgroundColor3 = PANEL
			plate.BackgroundTransparency = 0.1
			plate.Parent = introLayer
			corner(plate, 12)
			local stroke = Instance.new("UIStroke")
			stroke.Color = color
			stroke.Thickness = if mine then 4 else 2
			stroke.Parent = plate
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 10, 1, -16)
			stripe.Position = UDim2.fromOffset(8, 8)
			stripe.BackgroundColor3 = color
			stripe.BorderSizePixel = 0
			stripe.Parent = plate
			corner(stripe, 4)
			local name = label(plate, slot.name, UDim2.new(1, -40, 0, 42), UDim2.fromOffset(28, 6))
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextColor3 = color
			local who = if mine
				then "DU"
				elseif slot.player then slot.player
				else `CPU · {STYLE_LABEL[Bot.styleOf(slot.fighterId)] or ""}`
			local sub = label(plate, who, UDim2.new(1, -40, 0, 22), UDim2.fromOffset(28, 50), 20)
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = if mine then GOLD else Color3.fromRGB(200, 195, 220)
			local on, off = plateTarget(i)
			plate.Position = off
			task.delay(0.15 + i * 0.12, function()
				if plate.Parent then
					tween(plate, 0.4, { Position = on }, Enum.EasingStyle.Back)
				end
			end)
			plates[i] = plate
		end
	end

	local function hidePlates()
		for i, plate in plates do
			local _, off = plateTarget(i)
			tween(plate, 0.3, { Position = off })
		end
		tween(arenaCard, 0.3, { Position = UDim2.new(0.5, 0, 0, -140) })
		tween(versus, 0.2, { TextTransparency = 1 })
		tween(versusStroke, 0.2, { Transparency = 1 })
		task.delay(0.35, function()
			introLayer.Visible = false
		end)
	end

	local introToken = 0
	local platesOut = false
	local lastCount = 0
	local function startIntro(rematch: boolean)
		introToken += 1
		platesOut = false
		lastCount = 0
		local info = Arenas.byId[MatchState.arena]
		-- Modes: the raid shows its boss card (UI/BossHud) instead of the VS plates.
		local raid = MatchState.mode == "raid"
		arenaName.Text = if rematch then "REVANCHE!" elseif info then info.name else MatchState.arena
		arenaCaption.Text = if rematch then "GLEICHE KÄMPFER · GLEICHE ARENA" elseif raid then "BOSS-RAID" else "ARENA"
		arenaCard.Position = UDim2.new(0.5, 0, 0, -140)
		tween(arenaCard, 0.45, { Position = UDim2.new(0.5, 0, 0, 70) }, Enum.EasingStyle.Back)
		versus.TextTransparency = 1
		versusStroke.Transparency = 1
		introLayer.Visible = true
		letterbox(true)
		if rematch or raid then
			clearPlates()
		else
			buildPlates()
			task.delay(0.6, function()
				tween(versus, 0.3, { TextTransparency = 0 })
				tween(versusStroke, 0.3, { Transparency = 0 })
			end)
		end
		intro.active = not rematch
		intro.start = os.clock()
		intro.length = 1.7
	end

	-- Results: podium rows, rematch buttons.
	local results = Instance.new("Frame")
	results.BackgroundTransparency = 1
	results.Size = UDim2.fromScale(1, 1)
	results.Visible = false
	results.ZIndex = 3
	results.Parent = gui
	local podium = Instance.new("Frame")
	podium.AnchorPoint = Vector2.new(0.5, 0)
	podium.Size = UDim2.fromOffset(560, 262)
	podium.Position = UDim2.new(0.5, 0, 0, 56)
	podium.BackgroundColor3 = PANEL
	podium.BackgroundTransparency = 0.12
	podium.Parent = results
	corner(podium, 14)
	local podiumStroke = Instance.new("UIStroke")
	podiumStroke.Color = GOLD
	podiumStroke.Thickness = 2
	podiumStroke.Parent = podium
	local podiumTitle = label(podium, "ERGEBNIS", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 8))
	podiumTitle.TextColor3 = GOLD
	-- Stat columns, right-aligned from the row's right edge: offset from the right and width.
	local COLUMNS = {
		{ title = "KOs", right = 214, width = 60 },
		{ title = "SCHADEN", right = 110, width = 100 },
		{ title = "COMBO", right = 14, width = 90 },
	}
	local function column(parent: Instance, text: string, k: number, y: number, height: number, size: number)
		local c = COLUMNS[k]
		local l = label(parent, text, UDim2.fromOffset(c.width, height), UDim2.new(1, -c.right - c.width, 0, y), size)
		l.TextXAlignment = Enum.TextXAlignment.Right
		return l
	end
	for k in COLUMNS do
		local head = column(podium, COLUMNS[k].title, k, 46, 16, 14)
		head.Position += UDim2.fromOffset(-14, 0)
		head.TextColor3 = Color3.fromRGB(170, 165, 195)
	end
	local rows: { Frame } = {}

	local buttonRow = Instance.new("Frame")
	buttonRow.BackgroundTransparency = 1
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Size = UDim2.fromOffset(500, 96)
	buttonRow.Position = UDim2.new(0.5, 0, 1, -14)
	buttonRow.Parent = results
	local again = Instance.new("TextButton")
	again.Size = UDim2.fromOffset(290, 66)
	again.Position = UDim2.fromOffset(0, 0)
	again.BackgroundColor3 = PINK
	again.Font = FONT
	again.TextScaled = true
	again.TextColor3 = WHITE
	again.Text = "NOCHMAL"
	again.Parent = buttonRow
	corner(again, 14)
	local againPad = Instance.new("UIPadding")
	againPad.PaddingTop = UDim.new(0, 10)
	againPad.PaddingBottom = UDim.new(0, 10)
	againPad.Parent = again
	local lobby = Instance.new("TextButton")
	lobby.Size = UDim2.fromOffset(190, 54)
	lobby.Position = UDim2.fromOffset(310, 6)
	lobby.BackgroundColor3 = Color3.fromRGB(40, 36, 70)
	lobby.Font = FONT
	lobby.TextScaled = true
	lobby.TextColor3 = WHITE
	lobby.Text = "Zur Lobby"
	lobby.Parent = buttonRow
	corner(lobby, 12)
	local lobbyPad = Instance.new("UIPadding")
	lobbyPad.PaddingTop = UDim.new(0, 12)
	lobbyPad.PaddingBottom = UDim.new(0, 12)
	lobbyPad.Parent = lobby
	local voteLine = label(buttonRow, "", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 72), 18)
	voteLine.TextColor3 = Color3.fromRGB(200, 195, 220)

	local skip = Instance.new("TextButton")
	skip.BackgroundTransparency = 1
	skip.Text = ""
	skip.Size = UDim2.fromScale(1, 1)
	skip.Visible = false
	skip.ZIndex = 6
	skip.Parent = gui
	local skipHint = label(skip, "Tippen zum Überspringen", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 1, -40), 18)
	skipHint.TextColor3 = Color3.fromRGB(200, 195, 220)
	skipHint.ZIndex = 6

	local rematchRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VoteRematch") :: RemoteEvent
	local myVote: boolean? = nil
	local resultsEnd = 0

	local function refreshVotes()
		local tally = MatchState.rematch
		local inMatch = MatchState.mySlot ~= nil
		again.Visible = inMatch
		lobby.Visible = inMatch
		again.Text = if myVote == true then "✓ NOCHMAL" else "NOCHMAL"
		again.AutoButtonColor = myVote == nil
		lobby.Text = if myVote == false then "✓ Lobby" else "Zur Lobby"
		local left = math.max(0, math.ceil(resultsEnd - os.clock()))
		local count = if tally and tally.total > 1 then ` · Nochmal: {tally.yes}/{tally.total}` else ""
		voteLine.Text = if inMatch then `Weiter in {left} s{count}` else `Nächste Runde in {left} s`
	end
	again.Activated:Connect(function()
		if myVote == nil then
			myVote = true
			rematchRemote:FireServer(true)
			refreshVotes()
		end
	end)
	lobby.Activated:Connect(function()
		if myVote == nil then
			myVote = false
			rematchRemote:FireServer(false)
			refreshVotes()
		end
	end)

	local resultStats: { [number]: Stat } = {}
	local finisherName: string? = nil
	local winnerSlot = 0
	local sceneToken = 0
	local podiumShown = false

	local function buildRows()
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)
		local order = {}
		for i in MatchState.slots do
			table.insert(order, i)
		end
		table.sort(order, function(a, b)
			local pa = (resultStats[a] and resultStats[a].place) or a + 10
			local pb = (resultStats[b] and resultStats[b].place) or b + 10
			return pa < pb
		end)
		for rank, i in order do
			local slot = MatchState.slots[i]
			local stat = resultStats[i]
			local place = (stat and stat.place) or rank
			local mine = i == MatchState.mySlot
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -28, 0, 44)
			row.Position = UDim2.new(0, 14 + 40, 0, 66 + (rank - 1) * 48)
			row.BackgroundColor3 = if mine then Color3.fromRGB(60, 30, 80) else Color3.fromRGB(28, 24, 50)
			row.BackgroundTransparency = 1
			row.Parent = podium
			corner(row, 10)
			local medal = label(row, `{place}.`, UDim2.fromOffset(46, 36), UDim2.fromOffset(6, 4))
			medal.TextColor3 = MEDALS[math.clamp(place, 1, 4)]
			local who = if mine then "DU" elseif slot.player then slot.player else "CPU"
			local name = label(row, `{slot.name}`, UDim2.fromOffset(200, 24), UDim2.fromOffset(58, 3), 22)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextColor3 = slotColor(i)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local whoLabel = label(row, who, UDim2.fromOffset(200, 14), UDim2.fromOffset(58, 27), 13)
			whoLabel.TextXAlignment = Enum.TextXAlignment.Left
			whoLabel.TextColor3 = if mine then GOLD else Color3.fromRGB(180, 175, 200)
			if stat then
				column(row, tostring(stat.kos), 1, 0, 44, 22)
				column(row, `{stat.damage} %`, 2, 0, 44, 22)
				column(row, tostring(stat.bestCombo), 3, 0, 44, 22)
			end
			if place == 1 then
				local crown = label(row, "SIEGER", UDim2.fromOffset(70, 14), UDim2.new(0, 190, 0, 27), 12)
				crown.TextColor3 = GOLD
			end
			-- Slide in one after the other.
			task.delay(0.08 * rank, function()
				if row.Parent then
					tween(
						row,
						0.35,
						{ Position = UDim2.new(0, 14, 0, 66 + (rank - 1) * 48), BackgroundTransparency = 0.2 }
					)
				end
			end)
			rows[rank] = row
		end
	end

	local function showPodium()
		if podiumShown then
			return
		end
		podiumShown = true
		skip.Visible = false
		orbit.settled = true
		letterbox(false)
		buildRows()
		results.Visible = true
		podium.Position = UDim2.new(0.5, 0, 0, -300)
		tween(podium, 0.45, { Position = UDim2.new(0.5, 0, 0, 56) }, Enum.EasingStyle.Back)
		buttonRow.Position = UDim2.new(0.5, 0, 1, 120)
		tween(buttonRow, 0.45, { Position = UDim2.new(0.5, 0, 1, -14) }, Enum.EasingStyle.Back)
		refreshVotes()
		MetaHud.holdReward(false)
	end
	skip.Activated:Connect(showPodium)

	local function victoryScene(token: number)
		if token ~= sceneToken then
			return
		end
		if winnerSlot <= 0 or MatchState.slots[winnerSlot] == nil then
			showPodium()
			return
		end
		orbit.active = true
		orbit.slot = winnerSlot
		orbit.start = os.clock()
		orbit.settled = false
		letterbox(true)
		skip.Visible = true
		local mine = winnerSlot == MatchState.mySlot
		local slot = MatchState.slots[winnerSlot]
		local raid = MatchState.mode == "raid"
		Announcer.show(if raid then "SIEG IM TEAM!" elseif mine then "SIEG!" else `{slot.name} GEWINNT!`, {
			sub = if raid
				then (if mine then "Du hast den meisten Schaden gemacht" else `MVP: {slot.name}`)
				elseif mine then "Du bist der Champion"
				elseif slot.player then slot.player
				else nil,
			color = if mine then GOLD else slotColor(winnerSlot),
			seconds = VICTORY_SECONDS - 0.4,
			size = "huge",
			interrupt = true,
		})
		task.delay(VICTORY_SECONDS, function()
			if token == sceneToken then
				showPodium()
			end
		end)
	end

	local function resetAll()
		sceneToken += 1
		introToken += 1
		intro.active = false
		orbit.active = false
		orbit.settled = false
		podiumShown = false
		results.Visible = false
		skip.Visible = false
		introLayer.Visible = false
		myVote = nil
		letterbox(false)
		MetaHud.holdReward(false)
	end

	local lastPhase = MatchState.phase
	MatchState.onEvent(function(event)
		local t = event.type
		if t == "phase" then
			local phase = event.phase
			if phase == "match" and lastPhase ~= "match" then
				local rematch = lastPhase == "results"
				resetAll()
				startIntro(rematch)
			elseif phase == "results" then
				if lastPhase == "match" then
					Juice.hold(0.3) -- GAME! freeze (after the camera's phase reset)
				end
				resultsEnd = os.clock() + (event.timer or 0)
				refreshVotes()
			elseif phase == "lobby" then
				resetAll()
				clearPlates()
			end
			lastPhase = phase
		elseif t == "go" then
			if introLayer.Visible then
				hidePlates()
			end
			letterbox(false)
			Announcer.show("KAMPF!", { color = PINK, seconds = 0.9, size = "huge", interrupt = true, sound = "heavy" })
		elseif t == "finisher" then
			finisherName = event.name
		elseif t == "finish" then
			sceneToken += 1
			local token = sceneToken
			winnerSlot = event.winner or -1
			local executed = event.finisher == true and finisherName ~= nil
			local delay = if executed then GAME_SECONDS + 1.2 else GAME_SECONDS
			if executed then
				-- The finisher's name first, GAME! right behind it (Announcer queues it).
				Announcer.show(finisherName :: string, {
					sub = "FINISHER",
					color = Color3.fromRGB(255, 120, 60),
					seconds = 1.2,
					size = "huge",
					interrupt = true,
					sound = "heavy",
				})
			end
			finisherName = nil
			MetaHud.holdReward(true)
			Juice.addTrauma(0.5)
			flash.BackgroundTransparency = 0.3
			tween(flash, 0.5, { BackgroundTransparency = 1 })
			Sfx.play("metal", 1, 0.7)
			local gameText = if winnerSlot > 0 then "GAME!" else "UNENTSCHIEDEN"
			if event.raid then
				gameText = if event.victory then "BOSS BESIEGT!" else "NIEDERLAGE" -- Modes: Boss-Raid
			end
			Announcer.show(gameText, {
				color = GOLD,
				seconds = GAME_SECONDS,
				size = "huge",
				interrupt = not executed,
				sound = "heavy",
			})
			task.delay(delay, function()
				victoryScene(token)
			end)
		elseif t == "results" then
			resultStats = event.stats or {}
			winnerSlot = event.winner or winnerSlot
			if podiumShown then
				buildRows()
			end
		end
	end)

	-- Countdown numbers and the moment the plates leave, from the server clock in the snapshot.
	RunService.RenderStepped:Connect(function()
		if MatchState.phase == "results" and results.Visible then
			refreshVotes()
		end
		local current = MatchState.snapshot
		if not current or MatchState.phase ~= "match" then
			return
		end
		local snap = current :: MatchRunner.NetSnapshot
		if not platesOut and snap.countdown <= PLATES_UNTIL then
			platesOut = true
			hidePlates()
			if snap.countdown <= 0 then
				letterbox(false) -- joined a running match: no countdown to show
			end
		end
		if snap.countdown <= 0 then
			return
		end
		local n = math.ceil(snap.countdown)
		if n <= 3 and n >= 1 and n ~= lastCount and snap.countdown <= PLATES_UNTIL then
			lastCount = n
			Announcer.show(tostring(n), {
				color = COUNT_COLORS[n],
				seconds = 0.85,
				size = "huge",
				interrupt = true,
				sound = "heavy",
			})
		end
	end)

	RunService:BindToRenderStep("Cinematics", Enum.RenderPriority.Camera.Value + 2, cameraStep)
end

return Cinematics
