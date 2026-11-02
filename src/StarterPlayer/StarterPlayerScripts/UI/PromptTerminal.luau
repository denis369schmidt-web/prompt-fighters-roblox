--!strict
-- The prompt terminal: the first thing a player sees in the lobby (docs/GROWTH.md section 2). Type a description
-- ("Beschreibe deinen Kämpfer …") or tap one of three suggestion chips, or enter a friend's share code. The server
-- filters the text and answers with the fighter; then the REVEAL plays: light burst, the fighter spinning in a
-- ViewportFrame, name, title, stat bars and signature fading in, the share code, and "Mit diesem Kämpfer spielen"
-- (picks it through UI/Hud like a tap in the picker). The fighter itself is rebuilt here from its id
-- (Prompt/Registry), so the client never needs more than the server's summary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared:WaitForChild("Prompt"):WaitForChild("Registry"))
local Interpreter = require(Shared:WaitForChild("Prompt"):WaitForChild("Interpreter"))
local RigBuilder = require(Shared:WaitForChild("Visual"):WaitForChild("RigBuilder"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local Hud = require(script.Parent.Hud)

local PromptTerminal = {}

local FONT = Enum.Font.GothamBlack
local BODY_FONT = Enum.Font.GothamBold
local PINK = Color3.fromRGB(255, 40, 200)
local CYAN = Color3.fromRGB(0, 230, 255)
local INK = Color3.fromRGB(14, 12, 28)
local SUGGESTIONS = { "Lavagolem mit Hammer", "Eisninja", "Sternendrache" }
local STAT_LABELS = {
	{ "vitality", "VITALITÄT" },
	{ "power", "KRAFT" },
	{ "defense", "VERTEIDIGUNG" },
	{ "speed", "TEMPO" },
	{ "technique", "TECHNIK" },
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(
	parent: Instance,
	value: string,
	size: UDim2,
	position: UDim2,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = font or FONT
	l.TextScaled = true
	l.Text = value
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Parent = parent
	return l
end

local function button(parent: Instance, value: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = value
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	return b
end

local function neonStroke(parent: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = Color3.new(1, 1, 1)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(PINK, CYAN)
	gradient.Parent = stroke
end

local function textBox(parent: Instance, placeholder: string, size: UDim2, position: UDim2): TextBox
	local box = Instance.new("TextBox")
	box.Size = size
	box.Position = position
	box.BackgroundColor3 = Color3.fromRGB(28, 24, 52)
	box.Font = BODY_FONT
	box.TextSize = 22
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(150, 145, 180)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = parent
	corner(box, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = box
	return box
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, delay: number?)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0)
	TweenService:Create(instance, info, goal):Play()
end

-- Keeps a TextBox at most `limit` characters (UTF-8 aware).
local function limit(box: TextBox, chars: number)
	local len = utf8.len(box.Text)
	if len == nil then
		box.Text = ""
	elseif len > chars then
		box.Text = string.sub(box.Text, 1, (utf8.offset(box.Text, chars + 1) :: number) - 1)
	end
end

function PromptTerminal.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local submitRemote = remotes:WaitForChild("SubmitPrompt") :: RemoteFunction
	local codeRemote = remotes:WaitForChild("LoadPromptCode") :: RemoteFunction

	local gui = Instance.new("ScreenGui")
	gui.Name = "PromptTerminal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1000, view.Y / 720), 0.55, 1.1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	---------------------------------------------------------------------------------------------------------
	-- Terminal panel

	local panel = Instance.new("Frame")
	panel.Name = "Terminal"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 64)
	panel.Size = UDim2.fromOffset(600, 318)
	panel.BackgroundColor3 = INK
	panel.BackgroundTransparency = 0.06
	panel.Parent = gui
	corner(panel, 18)
	neonStroke(panel, 3)

	text(
		panel,
		"✦ PROMPT-KÄMPFER",
		UDim2.fromOffset(300, 18),
		UDim2.fromOffset(24, 16),
		Color3.fromRGB(255, 225, 70)
	).TextXAlignment =
		Enum.TextXAlignment.Left
	local headline = text(panel, "Beschreibe deinen Kämpfer", UDim2.new(1, -110, 0, 38), UDim2.fromOffset(24, 38))
	headline.TextXAlignment = Enum.TextXAlignment.Left
	local close = button(panel, "✕", UDim2.fromOffset(40, 40), UDim2.new(1, -54, 0, 14), Color3.fromRGB(40, 34, 70))

	local input = textBox(panel, "Beschreibe deinen Kämpfer …", UDim2.new(1, -48, 0, 54), UDim2.fromOffset(24, 90))
	local counter = text(
		panel,
		`0/{Interpreter.MAX_CHARS}`,
		UDim2.fromOffset(70, 14),
		UDim2.new(1, -94, 0, 147),
		Color3.fromRGB(150, 145, 180),
		BODY_FONT
	)
	counter.TextXAlignment = Enum.TextXAlignment.Right

	local create = button(panel, "ERSCHAFFEN ✦", UDim2.new(1, -48, 0, 56), UDim2.fromOffset(24, 166), PINK)

	local chipRow = Instance.new("Frame")
	chipRow.BackgroundTransparency = 1
	chipRow.Size = UDim2.new(1, -48, 0, 40)
	chipRow.Position = UDim2.fromOffset(24, 232)
	chipRow.Parent = panel
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.Parent = chipRow
	local chips: { TextButton } = {}
	for k, suggestion in SUGGESTIONS do
		local chip = button(chipRow, suggestion, UDim2.new(1 / 3, -6, 1, 0), UDim2.new(), Color3.fromRGB(40, 34, 74))
		chip.Font = BODY_FONT
		chip.LayoutOrder = k
		local stroke = Instance.new("UIStroke")
		stroke.Color = CYAN
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = chip
		chips[k] = chip
	end

	-- Code entry (replaces the chips while open).
	local codeRow = Instance.new("Frame")
	codeRow.BackgroundTransparency = 1
	codeRow.Size = UDim2.new(1, -48, 0, 40)
	codeRow.Position = UDim2.fromOffset(24, 232)
	codeRow.Visible = false
	codeRow.Parent = panel
	local codeBox = textBox(codeRow, "Code, z. B. 7KQ2XM", UDim2.new(0.62, 0, 1, 0), UDim2.new())
	codeBox.Font = FONT
	local loadCode = button(codeRow, "LADEN", UDim2.new(0.36, 0, 1, 0), UDim2.new(0.64, 0, 0, 0), CYAN)
	loadCode.TextColor3 = INK

	local status =
		text(panel, "", UDim2.new(1, -48, 0, 18), UDim2.fromOffset(24, 284), Color3.fromRGB(255, 120, 140), BODY_FONT)
	local codeToggle =
		button(panel, "CODE EINGEBEN", UDim2.fromOffset(170, 30), UDim2.new(0, 24, 1, 6), Color3.fromRGB(40, 34, 74))
	codeToggle.Font = BODY_FONT
	local rosterButton = button(
		panel,
		"ROSTER-KÄMPFER",
		UDim2.fromOffset(170, 30),
		UDim2.new(1, -194, 1, 6),
		Color3.fromRGB(40, 34, 74)
	)
	rosterButton.Font = BODY_FONT

	-- Small button that brings the terminal back.
	local reopen = button(gui, "✦ NEUER PROMPT", UDim2.fromOffset(200, 44), UDim2.new(0.5, -100, 0, 14), PINK)
	reopen.Visible = false

	---------------------------------------------------------------------------------------------------------
	-- Reveal overlay

	local overlay = Instance.new("Frame")
	overlay.Name = "Reveal"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(6, 4, 14)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = gui

	local rays = Instance.new("Frame")
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(10, 10)
	rays.BackgroundTransparency = 1
	rays.ZIndex = 10
	rays.Parent = overlay
	local rayFrames: { Frame } = {}
	for k = 1, 12 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(1400, if k % 2 == 0 then 70 else 36)
		ray.Rotation = k * 15
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Color3.new(1, 1, 1)
		ray.BackgroundTransparency = 1
		ray.ZIndex = 10
		ray.Parent = rays
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ray
		rayFrames[k] = ray
	end

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(760, 460)
	card.BackgroundColor3 = INK
	card.BackgroundTransparency = 0.04
	card.ZIndex = 11
	card.Parent = overlay
	corner(card, 20)
	neonStroke(card, 3)

	local stage = Instance.new("Frame")
	stage.Size = UDim2.fromOffset(300, 420)
	stage.Position = UDim2.fromOffset(20, 20)
	stage.BackgroundColor3 = Color3.fromRGB(24, 20, 44)
	stage.ZIndex = 11
	stage.ClipsDescendants = true
	stage.Parent = card
	corner(stage, 14)
	local pillar = Instance.new("Frame")
	pillar.AnchorPoint = Vector2.new(0.5, 0)
	pillar.Position = UDim2.fromScale(0.5, 0)
	pillar.Size = UDim2.fromScale(0.5, 1)
	pillar.BorderSizePixel = 0
	pillar.BackgroundColor3 = Color3.new(1, 1, 1)
	pillar.ZIndex = 11
	pillar.Parent = stage
	local pillarGradient = Instance.new("UIGradient")
	pillarGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	pillarGradient.Parent = pillar
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 165, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = 12
	viewport.Parent = stage
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local info = Instance.new("Frame")
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -364, 1, -40)
	info.Position = UDim2.fromOffset(344, 20)
	info.ZIndex = 11
	info.Parent = card
	local fading: { GuiObject } = {}
	local function infoText(value: string, y: number, h: number, color: Color3?, font: Enum.Font?): TextLabel
		local l = text(info, value, UDim2.new(1, 0, 0, h), UDim2.fromOffset(0, y), color, font)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.ZIndex = 12
		table.insert(fading, l)
		return l
	end
	infoText("DEIN KÄMPFER", 0, 16, Color3.fromRGB(255, 225, 70))
	local nameLabel = infoText("", 20, 50)
	local titleLabel = infoText("", 74, 22, Color3.fromRGB(225, 222, 240), BODY_FONT)
	local metaLabel = infoText("", 100, 16, Color3.fromRGB(160, 155, 190), BODY_FONT)
	local bars: { Frame } = {}
	for k, entry in STAT_LABELS do
		local y = 126 + (k - 1) * 24
		infoText(entry[2], y, 14, Color3.fromRGB(200, 196, 220), BODY_FONT).Size = UDim2.fromOffset(120, 14)
		local back = Instance.new("Frame")
		back.Position = UDim2.fromOffset(126, y + 2)
		back.Size = UDim2.new(1, -126, 0, 10)
		back.BackgroundColor3 = Color3.fromRGB(40, 36, 66)
		back.BorderSizePixel = 0
		back.ZIndex = 12
		back.Parent = info
		corner(back, 5)
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(0, 1)
		bar.BorderSizePixel = 0
		bar.ZIndex = 13
		bar.Parent = back
		corner(bar, 5)
		bars[k] = bar
	end
	local sigLabel = infoText("", 252, 22, Color3.new(1, 1, 1))
	local sigInfo = infoText("", 276, 30, Color3.fromRGB(180, 176, 205), BODY_FONT)
	sigInfo.TextWrapped = true
	local codeLabel = infoText("", 312, 22, CYAN)
	infoText(
		"Teile den Code: Freunde spielen genau diesen Kämpfer.",
		336,
		14,
		Color3.fromRGB(150, 145, 180),
		BODY_FONT
	)
	local play = button(info, "MIT DIESEM KÄMPFER SPIELEN", UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, 362), PINK)
	play.ZIndex = 12
	local againBottom =
		button(card, "NEUER PROMPT", UDim2.fromOffset(170, 34), UDim2.new(0.5, -85, 1, 10), Color3.fromRGB(40, 34, 74))
	againBottom.ZIndex = 11
	againBottom.Font = BODY_FONT
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 20
	flash.Parent = gui

	---------------------------------------------------------------------------------------------------------
	-- State

	local open = true
	local busy = false
	local revealing = false
	local current: { [string]: any }? = nil
	local spin = 0
	local center = Vector3.new(0, 3, 0)

	local function inLobby(): boolean
		return MatchState.phase == "lobby"
	end

	local function refresh()
		local lobby = inLobby()
		panel.Visible = lobby and open and not revealing
		reopen.Visible = lobby and not open and not revealing
		overlay.Visible = lobby and revealing
	end

	local function setOpen(value: boolean)
		open = value
		refresh()
	end
	Hud.isTerminalOpen = function(): boolean
		return open or revealing
	end
	Hud.onNewPrompt = function()
		revealing = false
		setOpen(true)
		input:CaptureFocus()
	end

	local function setBusy(value: boolean, message: string?)
		busy = value
		create.Text = if value then "ERSCHAFFE …" else "ERSCHAFFEN ✦"
		create.AutoButtonColor = not value
		status.TextColor3 = if value then Color3.fromRGB(200, 196, 230) else Color3.fromRGB(255, 120, 140)
		status.Text = message or ""
	end

	local function reveal(summary: { [string]: any })
		local found = Registry.get(summary.id)
		if found == nil then
			setBusy(false, "Kämpfer konnte nicht geladen werden")
			return
		end
		local result = found :: Interpreter.Result
		current = summary
		local glow = Color3.fromHex(result.look.glow)
		-- Fighter on the stage.
		for _, child in viewport:GetChildren() do
			if child:IsA("Model") then
				child:Destroy()
			end
		end
		local rig = RigBuilder.build(result.id)
		rig.Parent = viewport
		local height = (rig:GetAttribute("StandHeight") :: number?) or RigBuilder.STAND_HEIGHT
		center = Vector3.new(0, height * 1.1, 0)
		spin = 0
		stage.BackgroundColor3 = glow:Lerp(Color3.fromRGB(16, 14, 30), 0.72)
		pillar.BackgroundColor3 = glow
		for _, ray in rayFrames do
			ray.BackgroundColor3 = glow
			ray.BackgroundTransparency = 1
		end
		nameLabel.Text = result.fighter.name
		nameLabel.TextColor3 = glow
		titleLabel.Text = summary.title
		metaLabel.Text = `{summary.element} · {summary.archetype}`
		sigLabel.Text = `SIGNATUR: {summary.signature}`
		sigInfo.Text = summary.signatureInfo
		codeLabel.Text = `CODE: {summary.code}`
		for _, l in fading do
			(l :: TextLabel).TextTransparency = 1
		end
		for _, bar in bars do
			bar.Size = UDim2.fromScale(0, 1)
			bar.BackgroundColor3 = glow
		end
		play.Visible = false
		-- Light burst, then the card, then the details one after another.
		revealing = true
		refresh()
		overlay.BackgroundTransparency = 1
		tween(overlay, 0.35, { BackgroundTransparency = 0.25 })
		flash.BackgroundTransparency = 0.1
		tween(flash, 0.6, { BackgroundTransparency = 1 })
		card.Size = UDim2.fromOffset(380, 230)
		tween(card, 0.45, { Size = UDim2.fromOffset(760, 460) })
		for k, ray in rayFrames do
			tween(ray, 0.5, { BackgroundTransparency = 0.25 + (k % 3) * 0.12 }, 0.05)
		end
		local delayAt = 0.35
		for _, l in fading do
			tween(l, 0.35, { TextTransparency = 0 }, delayAt)
			delayAt += 0.06
		end
		for k, entry in STAT_LABELS do
			local value = summary.stats[entry[1]] or 0
			tween(
				bars[k],
				0.5,
				{ Size = UDim2.fromScale(math.clamp(value / Interpreter.STAT_MAX, 0.05, 1), 1) },
				0.6 + k * 0.08
			)
		end
		task.delay(1.1, function()
			if current == summary then
				play.Visible = true
			end
		end)
		setBusy(false)
		input.Text = ""
	end

	local function handle(ok: boolean, response: any)
		if not ok or type(response) ~= "table" then
			setBusy(false, "Keine Verbindung zum Server. Versuch es nochmal.")
		elseif response.ok and type(response.fighter) == "table" then
			reveal(response.fighter)
		else
			setBusy(false, if type(response.message) == "string" then response.message else "Das hat nicht geklappt")
		end
	end

	local function submit(value: string)
		if busy then
			return
		end
		local cleaned = Interpreter.clean(value)
		if cleaned == "" then
			setBusy(false, "Beschreibe zuerst deinen Kämpfer")
			return
		end
		setBusy(true, "Dein Kämpfer entsteht …")
		task.spawn(function()
			handle(pcall(submitRemote.InvokeServer, submitRemote, cleaned))
		end)
	end

	local function submitCode()
		if busy then
			return
		end
		setBusy(true, "Code wird geladen …")
		local value = codeBox.Text
		task.spawn(function()
			handle(pcall(codeRemote.InvokeServer, codeRemote, string.sub(value, 1, 16)))
		end)
	end

	input:GetPropertyChangedSignal("Text"):Connect(function()
		limit(input, Interpreter.MAX_CHARS)
		counter.Text = `{utf8.len(input.Text) or 0}/{Interpreter.MAX_CHARS}`
	end)
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		limit(codeBox, 8)
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit(input.Text)
		end
	end)
	codeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitCode()
		end
	end)
	create.Activated:Connect(function()
		submit(input.Text)
	end)
	for k, chip in chips do
		chip.Activated:Connect(function()
			input.Text = SUGGESTIONS[k]
			submit(SUGGESTIONS[k])
		end)
	end
	loadCode.Activated:Connect(submitCode)
	codeToggle.Activated:Connect(function()
		codeRow.Visible = not codeRow.Visible
		chipRow.Visible = not codeRow.Visible
		codeToggle.Text = if codeRow.Visible then "VORSCHLÄGE" else "CODE EINGEBEN"
		if codeRow.Visible then
			codeBox:CaptureFocus()
		end
	end)
	rosterButton.Activated:Connect(function()
		setOpen(false)
		if Hud.openPicker then
			Hud.openPicker()
		end
	end)
	close.Activated:Connect(function()
		setOpen(false)
		if Hud.openPicker then
			Hud.openPicker()
		end
	end)
	reopen.Activated:Connect(function()
		setOpen(true)
	end)
	play.Activated:Connect(function()
		local chosen = current
		if chosen and Hud.choose then
			Hud.choose(chosen.id)
		end
		revealing = false
		setOpen(false)
	end)
	againBottom.Activated:Connect(function()
		revealing = false
		setOpen(true)
		input:CaptureFocus()
	end)

	-- Orbit camera and slowly turning light rays while the reveal is up.
	RunService.RenderStepped:Connect(function(dt: number)
		if not overlay.Visible then
			return
		end
		spin += dt * 0.9
		local r = 13
		camera.CFrame = CFrame.lookAt(
			center + Vector3.new(math.sin(spin) * r, 1.6, -math.cos(spin) * r),
			center + Vector3.new(0, 0.2, 0)
		)
		rays.Rotation = (rays.Rotation + dt * 12) % 360
	end)

	MatchState.onEvent(function(event)
		if event.type == "phase" then
			if event.phase ~= "lobby" then
				revealing = false
			end
			refresh()
		end
	end)
	refresh()
end

return PromptTerminal
