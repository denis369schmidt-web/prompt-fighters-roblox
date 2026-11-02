--!strict
-- Boss-Raid HUD, display only:
--   * boss bar under the top bar: name and title, HP bar with a lagging damage chip and the phase-2 marker at 50 %,
--     phase label, the enrage clock (WUT IN 1:20 / WÜTEND! ZEIT 0:45) and the team's shared lives;
--   * the boss name card during the intro countdown (name, title, intro line from Data/Bosses);
--   * phase-2 cinematic (PHASE 2 banner, camera focus), enrage callout, downs and respawns;
--   * victory / defeat screen before the podium, and the boss title or challenge news from the reward.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bosses = require(Shared:WaitForChild("Data"):WaitForChild("Bosses"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local RaidState = require(script.Parent.Parent.State.RaidState)
local Announcer = require(script.Parent.Announcer)
local Layout = require(script.Parent.Layout)
local FighterView = require(script.Parent.Parent.Controllers.FighterView)
local Juice = require(script.Parent.Parent.Controllers.Juice)

local BossHud = {}

local FONT = Enum.Font.GothamBlack
local PANEL = Color3.fromRGB(16, 14, 30)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 215, 80)
local RED = Color3.fromRGB(255, 70, 70)
local GREY = Color3.fromRGB(190, 185, 210)
local BAR_WIDTH = 560
local CARD_UNTIL = 3.05 -- countdown value at which the name card leaves (as the Cinematics plates)

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

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function BossHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BossHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- Boss bar.
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Size = UDim2.fromOffset(BAR_WIDTH + 24, 74)
	bar.BackgroundColor3 = PANEL
	bar.BackgroundTransparency = 0.15
	bar.Visible = false
	bar.Parent = gui
	corner(bar, 12)
	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 2
	barStroke.Color = RED
	barStroke.Parent = bar
	local nameLabel = label(bar, "", UDim2.fromOffset(300, 24), UDim2.fromOffset(12, 4), 22)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local titleLabel = label(bar, "", UDim2.fromOffset(260, 14), UDim2.new(1, -272, 0, 9), 13)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Right
	titleLabel.TextColor3 = GREY
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(BAR_WIDTH, 18)
	back.Position = UDim2.fromOffset(12, 30)
	back.BackgroundColor3 = Color3.fromRGB(40, 30, 50)
	back.BorderSizePixel = 0
	back.Parent = bar
	corner(back, 6)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromScale(1, 1)
	chip.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	chip.BorderSizePixel = 0
	chip.Parent = back
	corner(chip, 6)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = RED
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 6)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	gradient.Rotation = 90
	gradient.Parent = fill
	-- Phase-2 marker at 50 %.
	local marker = Instance.new("Frame")
	marker.Size = UDim2.fromOffset(3, 26)
	marker.Position = UDim2.new(Bosses.PHASE_TWO_AT, -1, 0, -4)
	marker.BackgroundColor3 = GOLD
	marker.BorderSizePixel = 0
	marker.ZIndex = 3
	marker.Parent = back
	local markerTag = label(back, "II", UDim2.fromOffset(20, 12), UDim2.new(Bosses.PHASE_TWO_AT, -10, 0, -16), 11)
	markerTag.TextColor3 = GOLD
	local hpLabel = label(back, "", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 13)
	hpLabel.ZIndex = 4
	local phaseLabel = label(bar, "", UDim2.fromOffset(120, 18), UDim2.fromOffset(12, 51), 15)
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
	local livesLabel = label(bar, "", UDim2.fromOffset(200, 18), UDim2.new(0.5, -100, 0, 51), 15)
	local timerLabel = label(bar, "", UDim2.fromOffset(200, 18), UDim2.new(1, -212, 0, 51), 15)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Name card for the intro.
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromOffset(640, 210)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = PANEL
	card.BackgroundTransparency = 0.1
	card.Visible = false
	card.ZIndex = 5
	card.Parent = gui
	corner(card, 16)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 3
	cardStroke.Parent = card
	local cardCaption = label(card, "BOSS-RAID", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 12), 20)
	cardCaption.TextColor3 = RED
	local cardName = label(card, "", UDim2.new(1, -40, 0, 74), UDim2.fromOffset(20, 38))
	local cardTitle = label(card, "", UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 114), 24)
	cardTitle.TextColor3 = GOLD
	local cardIntro = label(card, "", UDim2.new(1, -60, 0, 50), UDim2.fromOffset(30, 148), 18)
	cardIntro.TextColor3 = GREY
	cardIntro.TextWrapped = true
	cardIntro.Font = Enum.Font.GothamMedium

	-- Victory / defeat screen.
	local outcome = Instance.new("Frame")
	outcome.AnchorPoint = Vector2.new(0.5, 0.5)
	outcome.Size = UDim2.fromOffset(620, 170)
	outcome.Position = UDim2.fromScale(0.5, 0.42)
	outcome.BackgroundColor3 = PANEL
	outcome.BackgroundTransparency = 0.08
	outcome.Visible = false
	outcome.ZIndex = 6
	outcome.Parent = gui
	corner(outcome, 16)
	local outcomeStroke = Instance.new("UIStroke")
	outcomeStroke.Thickness = 3
	outcomeStroke.Parent = outcome
	local outcomeTitle = label(outcome, "", UDim2.new(1, -40, 0, 78), UDim2.fromOffset(20, 14))
	local outcomeSub = label(outcome, "", UDim2.new(1, -40, 0, 30), UDim2.fromOffset(20, 98), 24)
	outcomeSub.TextColor3 = GREY
	local outcomeStats = label(outcome, "", UDim2.new(1, -40, 0, 22), UDim2.fromOffset(20, 132), 18)
	outcomeStats.TextColor3 = GOLD

	local function place()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
		bar.Position = UDim2.new(0.5, 0, 0, Layout.top(uiScale.Scale))
	end
	Layout.watch(place)

	local shownHp = 1
	local chipHp = 1
	local chipHold = 0
	local cardOut = false
	local currentBoss: string? = nil

	local function showCard(bossId: string)
		local def = Bosses.byId[bossId]
		if def == nil then
			return
		end
		local color = Color3.fromHex(def.color)
		cardName.Text = def.name
		cardName.TextColor3 = color
		cardStroke.Color = color
		cardTitle.Text = def.title
		cardIntro.Text = def.intro or ""
		card.Visible = true
		cardOut = false
		local scale = card:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = card
		scale.Scale = 1.6
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	local function hideCard()
		if card.Visible and not cardOut then
			cardOut = true
			local scale = card:FindFirstChildOfClass("UIScale")
			if scale then
				TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0.01 }):Play()
			end
			task.delay(0.26, function()
				if cardOut then
					card.Visible = false
				end
			end)
		end
	end

	local function showOutcome(victory: boolean, reason: string?)
		local boss = RaidState.boss
		local def = if boss then Bosses.byId[boss.bossId] else nil
		local name = if def then def.name else "BOSS"
		outcomeTitle.Text = if victory then "BOSS BESIEGT!" else "RAID GESCHEITERT"
		outcomeTitle.TextColor3 = if victory then GOLD else RED
		outcomeStroke.Color = outcomeTitle.TextColor3
		outcomeSub.Text = if victory
			then `{name} ist gefallen`
			elseif reason == "time" then "Die Zeit ist abgelaufen"
			else "Alle Helden sind gefallen"
		if boss then
			local fought = Bosses.RAID.TIME_LIMIT - boss.timeLeft
			outcomeStats.Text = if victory
				then `Zeit {clock(fought)} · Team-Leben übrig: {boss.lives}`
				else `{name} hatte noch {math.ceil(boss.hp / math.max(1, boss.maxHp) * 100)} % LP`
		else
			outcomeStats.Text = ""
		end
		outcome.Visible = true
		local scale = outcome:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = outcome
		scale.Scale = 1.8
		TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		task.delay(3.2, function()
			outcome.Visible = false
		end)
	end

	MatchState.onEvent(function(event)
		local t = event.type
		if t == "phase" then
			if event.phase == "match" and event.mode == "raid" then
				local info = event.modeInfo
				local id = if info then info.boss else nil
				if id and (MatchState.snapshot == nil or currentBoss ~= id) then
					currentBoss = id
					showCard(id)
					outcome.Visible = false
					shownHp, chipHp = 1, 1
				end
			elseif event.phase == "lobby" then
				card.Visible = false
				outcome.Visible = false
				currentBoss = nil
			end
		elseif MatchState.mode ~= "raid" then
			return
		elseif t == "go" then
			hideCard()
			local boss = RaidState.boss
			Announcer.show("BOSS-RAID!", {
				sub = if boss then `Besiegt {Bosses.byId[boss.bossId].name}!` else nil,
				color = RED,
				seconds = 1,
				size = "huge",
				interrupt = true,
				sound = "heavy",
			})
		elseif t == "boss_phase" then
			local boss = RaidState.boss
			Announcer.show("PHASE 2", {
				sub = "Die Steinhülle zerbricht!",
				color = GOLD,
				seconds = 2,
				size = "huge",
				interrupt = true,
				sound = "heavy",
			})
			if boss then
				Juice.focus(FighterView.toWorld(boss.x, boss.y + 2.5), 1.6, 0.25)
			end
		elseif t == "boss_enrage" then
			Announcer.show(
				"WÜTEND!",
				{ sub = "Der Boss schlägt härter zu", color = RED, seconds = 1.6, size = "big" }
			)
		elseif t == "hero_down" then
			local mine = event.actor == MatchState.mySlot
			local info = MatchState.slots[event.actor]
			if mine then
				Announcer.show(if event.out then "RAUS!" else "AM BODEN!", {
					sub = if event.out
						then "Keine Team-Leben mehr"
						else `Zurück in {Bosses.RAID.RESPAWN_SECONDS} s · Team-Leben: {event.lives}`,
					color = RED,
					seconds = 1.4,
				})
			elseif info then
				Announcer.show(`{info.name} fällt`, {
					sub = `Team-Leben: {event.lives}`,
					color = Color3.fromRGB(255, 150, 60),
					seconds = 0.9,
					size = "small",
				})
			end
		elseif t == "finish" and event.raid then
			task.delay(0.15, function()
				showOutcome(event.victory == true, event.reason)
			end)
		end
	end)

	-- Reward news: a new boss title, the daily challenge.
	local profileRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Profile") :: RemoteEvent
	profileRemote.OnClientEvent:Connect(function(view: any)
		local raid = view.raid
		if raid and raid.title then
			task.delay(4, function()
				Announcer.show("NEUER TITEL!", { sub = raid.title, color = GOLD, seconds = 2.2, size = "big" })
			end)
		end
		local challenge = view.challenge
		if challenge and challenge.done and (challenge.coins or 0) > 0 then
			task.delay(4, function()
				Announcer.show("TAGES-CHALLENGE GESCHAFFT!", {
					sub = `+{challenge.coins} Münzen · Serie Tag {challenge.streak}`,
					color = GOLD,
					seconds = 2.2,
					size = "big",
				})
			end)
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local boss: any = RaidState.boss
		local active = boss ~= nil and MatchState.mode == "raid" and MatchState.phase == "match"
		bar.Visible = active
		local snap = MatchState.snapshot
		if card.Visible and snap and snap.countdown <= CARD_UNTIL then
			hideCard()
		end
		if not active or boss == nil then
			return
		end
		local def = Bosses.byId[boss.bossId]
		local color = Color3.fromHex(def.color)
		nameLabel.Text = def.name
		nameLabel.TextColor3 = color:Lerp(WHITE, 0.3)
		titleLabel.Text = def.title
		local frac = math.clamp(boss.hp / math.max(1, boss.maxHp), 0, 1)
		shownHp += (frac - shownHp) * math.min(1, dt * 12)
		if frac < chipHp then
			chipHold += dt
			if chipHold > 0.5 then
				chipHp += (frac - chipHp) * math.min(1, dt * 4)
			end
		else
			chipHp, chipHold = frac, 0
		end
		fill.Size = UDim2.fromScale(shownHp, 1)
		chip.Size = UDim2.fromScale(chipHp, 1)
		fill.BackgroundColor3 = if boss.phase >= 2 then Color3.fromRGB(255, 120, 40) else RED
		hpLabel.Text = `{math.max(0, math.ceil(boss.hp))} / {boss.maxHp}`
		phaseLabel.Text = if boss.state == 4 then "VERWANDLUNG" else `PHASE {boss.phase}`
		phaseLabel.TextColor3 = if boss.phase >= 2 then GOLD else WHITE
		livesLabel.Text =
			`TEAM-LEBEN {string.rep("●", math.min(boss.lives, 8))}{if boss.lives == 0 then "–" else ""}`
		local toEnrage = Bosses.RAID.ENRAGE_SECONDS - (Bosses.RAID.TIME_LIMIT - boss.timeLeft)
		if boss.enraged then
			timerLabel.Text = `WÜTEND! ZEIT {clock(boss.timeLeft)}`
			timerLabel.TextColor3 = RED
			barStroke.Color = if math.floor(os.clock() * 4) % 2 == 0 then RED else GOLD
		else
			timerLabel.Text = `WUT IN {clock(toEnrage)}`
			timerLabel.TextColor3 = GREY
			barStroke.Color = color
		end
	end)
end

return BossHud
