--!strict
-- Big announcer texts over the fight: countdown numbers, KAMPF!, ERSTER KO!, LETZTER STOCK!, COMBO x5, SUDDEN DEATH,
-- 10 SEKUNDEN!, GAME! and the winner line. Calls queue up so two at once don't overwrite each other; an
-- `interrupt` call (countdown, GAME!) cuts the line. Also draws the short speech bubble when a bot taunts.
-- Display only: everything here reacts to server events and snapshots, nothing is sent back.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MatchRunner = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Combat"):WaitForChild("MatchRunner")
)
local FighterView = require(script.Parent.Parent.Controllers.FighterView)
local MatchState = require(script.Parent.Parent.State.MatchState)
local Sfx = require(script.Parent.Parent.Controllers.Sfx)

local Announcer = {}

local FONT = Enum.Font.GothamBlack
local GOLD = Color3.fromRGB(255, 215, 80)
local PINK = Color3.fromRGB(255, 60, 200)
local RED = Color3.fromRGB(255, 70, 70)
local CYAN = Color3.fromRGB(80, 230, 255)
local WHITE = Color3.new(1, 1, 1)

export type Size = "huge" | "big" | "small"
export type Options = {
	sub: string?,
	color: Color3?,
	seconds: number?,
	size: Size?,
	interrupt: boolean?,
	sound: string?,
}

type Call = { text: string, options: Options }

local HEIGHT: { [Size]: number } = { huge = 150, big = 104, small = 64 }

local queue: { Call } = {}
local busyUntil = 0
local token = 0
local holder: Frame? = nil
local main: TextLabel? = nil
local subLabel: TextLabel? = nil
local pop: UIScale? = nil

local TAUNTS = { "Zu langsam!", "Komm her!", "Das war's schon?", "Nächster!", "Hehe!", "Noch einer?" }

local function play(call: Call)
	if not (holder and main and subLabel and pop) then
		return
	end
	local frame, label, sub, scale = holder :: Frame, main :: TextLabel, subLabel :: TextLabel, pop :: UIScale
	local o = call.options
	local size: Size = o.size or "big"
	local seconds = o.seconds or 1.2
	token += 1
	local mine = token
	busyUntil = os.clock() + seconds
	label.Text = call.text
	label.TextColor3 = o.color or GOLD
	label.Size = UDim2.new(1, 0, 0, HEIGHT[size])
	label.TextTransparency = 0
	sub.Text = o.sub or ""
	sub.Position = UDim2.new(0, 0, 0, HEIGHT[size] - 4)
	sub.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	frame.Visible = true
	scale.Scale = if size == "small" then 1.35 else 1.9
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	if o.sound then
		Sfx.play(o.sound, if size == "huge" then 1 else 0.6, if size == "huge" then 0.8 else 1.1)
	end
	task.delay(math.max(0.1, seconds - 0.22), function()
		if token ~= mine then
			return
		end
		local fade = TweenInfo.new(0.22)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(sub, fade, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
		TweenService:Create(scale, fade, { Scale = 1.15 }):Play()
	end)
end

-- Show a callout. Queued behind the current one unless `interrupt` is set.
function Announcer.show(text: string, options: Options?)
	local opts: Options = options or {}
	local call: Call = { text = text, options = opts }
	if call.options.interrupt then
		table.clear(queue)
		play(call)
	elseif os.clock() >= busyUntil and #queue == 0 then
		play(call)
	elseif #queue < 3 then
		table.insert(queue, call)
	end
end

function Announcer.clear()
	table.clear(queue)
	token += 1
	busyUntil = 0
	if holder then
		holder.Visible = false
	end
end

local function slotName(slot: number?): string
	local info = if slot then MatchState.slots[slot] else nil
	return if info then info.name else ""
end

local function isMine(slot: number?): boolean
	return slot ~= nil and slot == MatchState.mySlot
end

-- Speech bubble above a taunting bot.
local function tauntBubble(slot: number)
	local head = FighterView.part(slot, "Head")
	if head == nil then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head :: BasePart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
	label.BackgroundTransparency = 0.15
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Text = TAUNTS[math.random(1, #TAUNTS)]
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label
	gui.Parent = head :: BasePart
	task.delay(1.4, function()
		gui:Destroy()
	end)
end

function Announcer.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Announcer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / 1280, view.Y / 760), 0.6, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.36)
	frame.Size = UDim2.new(1, 0, 0, 200)
	frame.Visible = false
	frame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Text = ""
	label.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(20, 8, 40)
	stroke.Parent = label
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Font = FONT
	sub.Size = UDim2.new(1, 0, 0, 34)
	sub.TextSize = 30
	sub.TextColor3 = WHITE
	sub.TextStrokeTransparency = 0.2
	sub.Text = ""
	sub.Parent = frame
	holder, main, subLabel, pop = frame, label, sub, scale

	-- Next queued callout once the current one is done.
	RunService.Heartbeat:Connect(function()
		if #queue > 0 and os.clock() >= busyUntil then
			play(table.remove(queue, 1) :: Call)
		end
	end)

	local firstKo = false
	local comboShown: { [number]: number } = {}
	local tenSeconds = false
	MatchState.onEvent(function(event)
		local t = event.type
		if t == "phase" then
			if event.phase ~= "match" or MatchState.snapshot == nil then
				firstKo, tenSeconds = false, false
				table.clear(comboShown)
			end
			if event.phase == "lobby" then
				Announcer.clear()
			end
		elseif t == "ring_out" then
			local lives = event.lives or 0
			local name = slotName(event.actor)
			if not firstKo then
				firstKo = true
				Announcer.show(
					"ERSTER KO!",
					{ sub = `{name} fliegt raus`, color = RED, seconds = 1.3, sound = "heavy" }
				)
			elseif lives > 0 then
				Announcer.show("KO!", { sub = name, color = GOLD, seconds = 0.9, size = "small" })
			end
			if lives == 1 then
				local mine = isMine(event.actor)
				Announcer.show(if mine then "DEIN LETZTER STOCK!" else "LETZTER STOCK!", {
					sub = if mine then "Jetzt zählt jeder Treffer" else name,
					color = if mine then RED else Color3.fromRGB(255, 150, 60),
					seconds = 1.3,
				})
			end
		elseif t == "fighter_eliminated" then
			if not isMine(event.actor) then
				Announcer.show("RAUS!", { sub = slotName(event.actor), color = RED, seconds = 0.9, size = "small" })
			end
		elseif t == "hit" then
			local combo = event.combo or 0
			local actor = event.actor
			if actor and combo >= 5 and combo > (comboShown[actor] or 0) and (combo == 5 or combo % 4 == 0) then
				comboShown[actor] = combo
				local mine = isMine(actor)
				Announcer.show(`COMBO x{combo}`, {
					sub = if mine then "STARK!" else slotName(actor),
					color = if mine then CYAN else WHITE,
					seconds = 0.9,
					size = if mine then "big" else "small",
				})
			end
			if event.target and (event.combo or 0) <= 1 then
				comboShown[actor] = 0
			end
		elseif t == "sudden_death" then
			Announcer.show("SUDDEN DEATH", {
				sub = "150 % – ein Treffer entscheidet",
				color = RED,
				seconds = 2,
				interrupt = true,
				sound = "heavy",
			})
		elseif t == "one_punch_ko" then
			Announcer.show("EIN SCHLAG!", { color = RED, seconds = 1, size = "small" })
		elseif t == "shield_break" and isMine(event.actor) then
			Announcer.show("SCHILD ZERBROCHEN!", { color = CYAN, seconds = 0.9, size = "small" })
		elseif t == "parry" and isMine(event.actor) then
			Announcer.show("PARIERT!", { color = CYAN, seconds = 0.8, size = "small" })
		elseif t == "finish_him" then
			Announcer.clear() -- the HUD's finisher code banner needs the screen
		elseif t == "emote" and event.kind == "taunt" then
			tauntBubble(event.actor)
		end
	end)

	-- Time warning from the snapshot clock.
	RunService.RenderStepped:Connect(function()
		local current = MatchState.snapshot
		if not current or MatchState.phase ~= "match" then
			return
		end
		local snap = current :: MatchRunner.NetSnapshot
		if snap.countdown > 0 or snap.suddenDeath then
			return
		end
		if not tenSeconds and snap.timeLeft <= 10 and snap.timeLeft > 0 then
			tenSeconds = true
			Announcer.show("10 SEKUNDEN!", { color = PINK, seconds = 1.1, size = "big" })
		end
	end)
end

return Announcer
