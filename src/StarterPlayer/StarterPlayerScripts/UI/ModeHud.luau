--!strict
-- Mode vote and Daily Challenge on screen, display plus the VoteMode buttons:
--   lobby   a panel on the left: SCHNELLKAMPF / BOSS-RAID / TAGES-CHALLENGE buttons with their votes (same as
--           standing on the mode pads), the next raid boss and today's challenge (goal, fighter, mutators, reward;
--           "heute geschafft" once done)
--   match   in a Daily-Challenge match a banner under the top bar with the goal and both mutators.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bosses = require(Shared:WaitForChild("Data"):WaitForChild("Bosses"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local ProfileState = require(script.Parent.Parent.State.ProfileState)
local Layout = require(script.Parent.Layout)

local ModeHud = {}

local FONT = Enum.Font.GothamBlack
local PANEL = Color3.fromRGB(16, 14, 30)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 215, 80)
local GREY = Color3.fromRGB(190, 185, 210)
local MODES = {
	{ id = "quick", name = "SCHNELLKAMPF", color = Color3.fromRGB(0, 220, 255) },
	{ id = "raid", name = "BOSS-RAID", color = Color3.fromRGB(255, 80, 60) },
	{ id = "daily", name = "TAGES-CHALLENGE", color = GOLD },
}

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = FONT
	l.Text = text
	l.TextColor3 = WHITE
	l.TextSize = textSize
	l.TextStrokeTransparency = 0.4
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function ModeHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ModeHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VoteMode") :: RemoteEvent

	-- Lobby panel.
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 12, 0.56, 0)
	panel.Size = UDim2.fromOffset(270, 262)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.15
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	label(panel, "MODUS", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 6), 16).TextColor3 = GOLD
	local buttons: { [string]: TextButton } = {}
	for k, m in MODES do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -20, 0, 30)
		b.Position = UDim2.fromOffset(10, 28 + (k - 1) * 34)
		b.BackgroundColor3 = Color3.fromRGB(36, 32, 62)
		b.Font = FONT
		b.TextSize = 16
		b.TextColor3 = m.color
		b.Text = m.name
		b.Parent = panel
		corner(b, 8)
		local stroke = Instance.new("UIStroke")
		stroke.Color = m.color
		stroke.Thickness = 1
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = b
		b.Activated:Connect(function()
			remote:FireServer(m.id)
		end)
		buttons[m.id] = b
	end
	local bossLine = label(panel, "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 134), 13)
	bossLine.TextColor3 = MODES[2].color
	local dailyTitle = label(panel, "TAGES-CHALLENGE", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 156), 14)
	dailyTitle.TextColor3 = GOLD
	local dailyLines: { TextLabel } = {}
	for i = 1, 4 do
		local l = label(panel, "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 156 + i * 19), 13)
		l.TextColor3 = if i == 4 then GOLD else GREY
		l.TextTruncate = Enum.TextTruncate.AtEnd
		dailyLines[i] = l
	end

	-- Daily-Challenge banner in the match.
	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.fromOffset(520, 48)
	banner.BackgroundColor3 = PANEL
	banner.BackgroundTransparency = 0.2
	banner.Visible = false
	banner.Parent = gui
	corner(banner, 10)
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = GOLD
	bannerStroke.Thickness = 2
	bannerStroke.Parent = banner
	local bannerGoal = label(banner, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 3), 18)
	bannerGoal.TextXAlignment = Enum.TextXAlignment.Center
	bannerGoal.TextColor3 = GOLD
	local bannerMutators = label(banner, "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 27), 14)
	bannerMutators.TextXAlignment = Enum.TextXAlignment.Center

	local function place()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
		banner.Position = UDim2.new(0.5, 0, 0, Layout.top(uiScale.Scale) + 60) -- below the match clock
	end
	Layout.watch(place)

	RunService.Heartbeat:Connect(function()
		local info: any = MatchState.modeInfo
		local lobby = MatchState.phase == "lobby" and info ~= nil
		panel.Visible = lobby
		local challenge = if info then info.challenge else nil
		banner.Visible = MatchState.phase == "match" and MatchState.mode == "daily" and challenge ~= nil
		if info == nil then
			return
		end
		if lobby then
			local votes = info.votes or {}
			local best = 0
			for _, v in votes do
				best = math.max(best, v)
			end
			for k, m in MODES do
				local v = votes[k] or 0
				local b = buttons[m.id]
				b.Text = if v > 0 then `{m.name} · {v}` else m.name
				b.BackgroundColor3 = if best > 0 and v == best
					then Color3.fromRGB(70, 56, 30)
					else Color3.fromRGB(36, 32, 62)
			end
			local boss = Bosses.byId[info.boss or ""]
			bossLine.Text = if boss then `Nächster Boss: {boss.name}` else ""
		end
		if challenge then
			local mutators = {}
			for _, m in challenge.mutators do
				table.insert(mutators, `{m.icon} {m.name}`)
			end
			local view = ProfileState.view :: any
			local done = view ~= nil and view.challengeDay == challenge.day
			dailyLines[1].Text = `Ziel: {challenge.goalText}`
			dailyLines[2].Text = `{challenge.fighterName} gegen {table.concat(challenge.opponents, ", ")}`
			dailyLines[3].Text = table.concat(mutators, " + ")
			dailyLines[4].Text = if done
				then "✓ Heute geschafft"
				else `Belohnung: {challenge.rewards[1]}–{challenge.rewards[#challenge.rewards]} Münzen`
			bannerGoal.Text = `TAGES-CHALLENGE: {string.upper(challenge.goalText)}`
			bannerMutators.Text = table.concat(mutators, "   ")
		end
	end)
end

return ModeHud
