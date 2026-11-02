--!strict
-- Progress on screen: level, title, XP bar and coins (lobby and results), the reward card after a match
-- (grade, XP, coins, level up, new fighter) and short toasts (daily login bonus, shop messages).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fighters = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Fighters"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local ProfileState = require(script.Parent.Parent.State.ProfileState)
local Layout = require(script.Parent.Layout)

local MetaHud = {}

-- Cinematics holds the reward card back until the podium is on screen (MetaHud.holdReward).
local rewardGate = true
local revealReward: () -> () = function() end

local FONT = Enum.Font.GothamBlack
local GOLD = Color3.fromRGB(255, 215, 80)
local PANEL = Color3.fromRGB(16, 14, 30)

local GRADE_COLORS = {
	S = Color3.fromRGB(255, 215, 80),
	A = Color3.fromRGB(120, 255, 160),
	B = Color3.fromRGB(110, 200, 255),
	C = Color3.fromRGB(230, 230, 240),
	D = Color3.fromRGB(180, 170, 190),
}

local function text(parent: Instance, value: string, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = FONT
	l.Text = value
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
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

function MetaHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MetaHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Profile bar, top left.
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromOffset(280, 54)
	bar.Position = UDim2.fromOffset(12, 14)
	bar.BackgroundColor3 = PANEL
	bar.BackgroundTransparency = 0.25
	bar.Visible = false
	bar.Parent = gui
	corner(bar, 10)
	local level = text(bar, "LV 1", UDim2.fromOffset(150, 20), UDim2.fromOffset(10, 6), 18)
	level.TextXAlignment = Enum.TextXAlignment.Left
	local coins = text(bar, "🪙 0", UDim2.fromOffset(110, 20), UDim2.new(1, -120, 0, 6), 18)
	coins.TextXAlignment = Enum.TextXAlignment.Right
	coins.TextColor3 = GOLD
	local xpBack = Instance.new("Frame")
	xpBack.Size = UDim2.new(1, -20, 0, 8)
	xpBack.Position = UDim2.fromOffset(10, 34)
	xpBack.BackgroundColor3 = Color3.fromRGB(40, 38, 64)
	xpBack.BorderSizePixel = 0
	xpBack.Parent = bar
	corner(xpBack, 4)
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack
	corner(xpFill, 4)

	-- Toast, top center.
	local toast = text(gui, "", UDim2.fromOffset(520, 40), UDim2.new(0.5, -260, 0, 60), 22)
	toast.BackgroundColor3 = PANEL
	toast.BackgroundTransparency = 0.2
	toast.TextColor3 = GOLD
	toast.Visible = false
	corner(toast, 10)
	-- Below the Roblox top bar (UI/Layout); the toast sits under the top-center prompt button.
	Layout.watch(function()
		local top = Layout.top(uiScale.Scale)
		bar.Position = UDim2.fromOffset(12, top)
		toast.Position = UDim2.new(0.5, -260, 0, top + 54)
	end)
	local toastToken = 0
	local function showToast(message: string)
		toastToken += 1
		local mine = toastToken
		toast.Text = message
		toast.Visible = true
		task.delay(3.5, function()
			if toastToken == mine then
				toast.Visible = false
			end
		end)
	end

	-- Reward card after a match.
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(360, 190)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0.55, 0)
	card.BackgroundColor3 = PANEL
	card.BackgroundTransparency = 0.1
	card.Visible = false
	card.Parent = gui
	corner(card, 14)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 2
	cardStroke.Color = GOLD
	cardStroke.Parent = card
	local grade = text(card, "A", UDim2.fromOffset(110, 110), UDim2.fromOffset(14, 14))
	local gradeCaption = text(card, "NOTE", UDim2.fromOffset(110, 20), UDim2.fromOffset(14, 124), 16)
	gradeCaption.TextColor3 = Color3.fromRGB(180, 175, 200)
	local lines: { TextLabel } = {}
	for k = 1, 4 do
		local line = text(card, "", UDim2.fromOffset(210, 30), UDim2.fromOffset(136, 10 + (k - 1) * 34), 22)
		line.TextXAlignment = Enum.TextXAlignment.Left
		lines[k] = line
	end
	local unlockLine = text(card, "", UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 1, -36), 20)
	unlockLine.TextColor3 = Color3.fromRGB(120, 255, 160)

	local pendingReward: { [string]: any }? = nil

	local function showReward()
		if pendingReward == nil or not rewardGate then
			return
		end
		local reward = pendingReward :: { [string]: any }
		pendingReward = nil
		grade.Text = reward.grade
		grade.TextColor3 = GRADE_COLORS[reward.grade] or Color3.new(1, 1, 1)
		lines[1].Text = `+{reward.xp} XP`
		lines[1].TextColor3 = Color3.fromRGB(120, 255, 160)
		lines[2].Text = `+{reward.coins} Münzen`
		lines[2].TextColor3 = GOLD
		local view = ProfileState.view
		if reward.levelAfter > reward.levelBefore then
			lines[3].Text = `LEVEL {reward.levelAfter}!`
			lines[3].TextColor3 = Color3.fromRGB(110, 200, 255)
		else
			lines[3].Text = if view then `Level {view.level}` else ""
			lines[3].TextColor3 = Color3.new(1, 1, 1)
		end
		lines[4].Text = if view and reward.unlockedFighter == nil
			then `Noch {view.winsToUnlock} Sieg(e) bis Gratis-Kämpfer`
			else ""
		lines[4].TextSize = 15
		lines[4].TextColor3 = Color3.fromRGB(180, 175, 200)
		unlockLine.Text = if reward.unlockedFighter
			then `NEUER KÄMPFER: {Fighters.get(reward.unlockedFighter).name}`
			else ""
		card.Visible = true
		card.Position = UDim2.new(0.5, 0, 0.62, 0)
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0.55, 0) })
			:Play()
	end

	revealReward = showReward

	ProfileState.onChange(function(view)
		level.Text = `LV {view.level} · {view.title}`
		coins.Text = `🪙 {view.coins}`
		xpFill:TweenSize(
			UDim2.fromScale(math.clamp(view.xp / math.max(1, view.xpNext), 0, 1), 1),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Quad,
			0.4,
			true
		)
		if view.loginCoins then
			showToast(`Täglicher Bonus, Tag {view.loginDay}: +{view.loginCoins} Münzen`)
		end
		if view.message then
			showToast(view.message)
		end
		if view.reward then
			pendingReward = view.reward
			if MatchState.phase == "results" then
				showReward()
			end
		end
	end)

	MatchState.onEvent(function(event)
		if event.type == "phase" then
			bar.Visible = event.phase ~= "match" and ProfileState.view ~= nil
			if event.phase == "results" then
				showReward()
			else
				card.Visible = false
			end
		end
	end)
	ProfileState.onChange(function()
		bar.Visible = MatchState.phase ~= "match"
	end)
end

function MetaHud.holdReward(hold: boolean)
	rewardGate = not hold
	if not hold and MatchState.phase == "results" then
		revealReward()
	end
end

return MetaHud
