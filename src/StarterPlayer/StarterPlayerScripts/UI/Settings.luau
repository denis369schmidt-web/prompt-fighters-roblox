--!strict
-- Lobby button row under the profile bar: EINSTELLUNGEN (settings panel) and FREUNDE EINLADEN
-- (SocialService:PromptGameInvite). The panel has three switches saved in the profile (SaveSetting):
--   Kamera-Wackeln reduzieren -> the ReduceShake attribute (Juice.shakeScale multiplies by REDUCED_MOTION_SCALE)
--   Sound                     -> Sfx.ENABLED
--   Weniger Partikel          -> Effects.PARTICLE_SCALE
-- and, where Roblox allows it, a button for Experience Notifications. The opt-in prompt also shows once by
-- itself after the player's second match of the session (ExperienceNotificationService, pcall).

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Effects = require(script.Parent.Parent.Controllers.Effects)
local Sfx = require(script.Parent.Parent.Controllers.Sfx)
local MatchState = require(script.Parent.Parent.State.MatchState)
local ProfileState = require(script.Parent.Parent.State.ProfileState)
local Layout = require(script.Parent.Layout)

local Settings = {}

Settings.LOW_PARTICLES = 0.35 -- Effects.PARTICLE_SCALE with "Weniger Partikel"

local FONT = Enum.Font.GothamBlack
local BODY = Enum.Font.GothamBold
local PANEL = Color3.fromRGB(16, 14, 30)
local ON = Color3.fromRGB(120, 255, 160)
local OFF = Color3.fromRGB(70, 66, 96)

type Option = { key: string, label: string }

local OPTIONS: { Option } = {
	{ key = "reduceShake", label = "Kamera-Wackeln reduzieren" },
	{ key = "sound", label = "Sound" },
	{ key = "lowParticles", label = "Grafik: weniger Partikel" },
}

local current: { [string]: boolean } = { reduceShake = false, sound = true, lowParticles = false }

-- Applies settings on this client right away (the server copy only restores them next visit).
function Settings.apply(values: { [string]: boolean })
	for key, value in values do
		current[key] = value
	end
	-- Controllers/Juice.shakeScale() reads the attribute (same switch as Roblox "Reduced Motion").
	Players.LocalPlayer:SetAttribute("ReduceShake", current.reduceShake)
	Sfx.ENABLED = current.sound
	Effects.PARTICLE_SCALE = if current.lowParticles then Settings.LOW_PARTICLES else 1
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeButton(parent: Instance, text: string, size: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.1
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	return b
end

local function canPromptNotifications(): boolean
	local ok, can = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	return ok and can == true
end

local function promptNotifications()
	pcall(function()
		ExperienceNotificationService:PromptOptIn()
	end)
end

function Settings.start()
	local saveRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SaveSetting") :: RemoteEvent
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Button row under the profile bar (MetaHud: 280 x 54).
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(280, 44)
	row.Parent = gui
	local settingsButton = makeButton(row, "⚙ EINSTELLUNGEN", UDim2.fromOffset(124, 44), Color3.fromRGB(40, 34, 74))
	local invite = makeButton(row, "👥 FREUNDE EINLADEN", UDim2.fromOffset(148, 44), Color3.fromRGB(0, 150, 110))
	invite.Position = UDim2.fromOffset(132, 0)

	-- Settings panel.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(340, 64 + #OPTIONS * 52 + 56)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 230, 255)
	stroke.Thickness = 2
	stroke.Parent = panel
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -70, 0, 28)
	title.Position = UDim2.fromOffset(16, 14)
	title.Font = FONT
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "EINSTELLUNGEN"
	title.Parent = panel
	local close = makeButton(panel, "✕", UDim2.fromOffset(44, 44), Color3.fromRGB(40, 34, 70))
	close.Position = UDim2.new(1, -54, 0, 8)

	local switches: { [string]: TextButton } = {}
	local function refresh()
		for key, b in switches do
			local on = current[key] == true
			b.Text = if on then "AN" else "AUS"
			b.BackgroundColor3 = if on then ON else OFF
			b.TextColor3 = if on then Color3.fromRGB(10, 30, 20) else Color3.new(1, 1, 1)
		end
	end
	for k, option in OPTIONS do
		local y = 56 + (k - 1) * 52
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromOffset(220, 44)
		text.Position = UDim2.fromOffset(16, y)
		text.Font = BODY
		text.TextSize = 18
		text.TextWrapped = true
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextColor3 = Color3.fromRGB(220, 216, 240)
		text.Text = option.label
		text.Parent = panel
		local b = makeButton(panel, "", UDim2.fromOffset(80, 44), OFF)
		b.Position = UDim2.new(1, -96, 0, y)
		b.Activated:Connect(function()
			local value = not current[option.key]
			Settings.apply({ [option.key] = value })
			saveRemote:FireServer(option.key, value)
			refresh()
		end)
		switches[option.key] = b
	end
	local notify = makeButton(panel, "🔔 BENACHRICHTIGUNGEN", UDim2.new(1, -32, 0, 44), Color3.fromRGB(255, 40, 200))
	notify.Position = UDim2.new(0, 16, 1, -56)
	notify.Visible = false
	notify.Activated:Connect(promptNotifications)
	refresh()

	settingsButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			task.spawn(function()
				notify.Visible = canPromptNotifications()
			end)
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	invite.Activated:Connect(function()
		task.spawn(function()
			local ok, can = pcall(function()
				return SocialService:CanSendGameInviteAsync(player)
			end)
			if ok and can then
				pcall(function()
					SocialService:PromptGameInvite(player)
				end)
			end
		end)
	end)

	Layout.watch(function()
		local top = Layout.top(uiScale.Scale)
		row.Position = UDim2.fromOffset(12, top + 54 + 8)
		panel.Position = UDim2.fromOffset(12, top + 54 + 8 + 44 + 8)
	end)

	-- Saved settings arrive with the profile (first load and after every change).
	ProfileState.onChange(function(view)
		local saved = view.settings
		if saved then
			Settings.apply(saved)
			refresh()
		end
	end)

	-- Lobby only. After the second finished match of the session, offer notifications once.
	local finished = 0
	local offered = false
	MatchState.onEvent(function(event)
		if event.type == "results" then
			finished += 1
		elseif event.type == "phase" then
			local inLobby = event.phase == "lobby"
			row.Visible = inLobby
			if not inLobby then
				panel.Visible = false
			end
			if inLobby and finished >= 2 and not offered then
				offered = true
				task.spawn(function()
					if canPromptNotifications() then
						promptNotifications()
					end
				end)
			end
		end
	end)
end

return Settings
