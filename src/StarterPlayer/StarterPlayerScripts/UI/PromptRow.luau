--!strict
-- The "DEINE PROMPT-KÄMPFER" row in the lobby picker (UI/Hud): the player's last three prompt fighters as small
-- 3D cards, rebuilt from their share codes (Prompt/Registry), plus a "+ NEUER PROMPT" card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared:WaitForChild("Prompt"):WaitForChild("Registry"))
local RigBuilder = require(Shared:WaitForChild("Visual"):WaitForChild("RigBuilder"))
local ProfileState = require(script.Parent.Parent.State.ProfileState)

local PromptRow = {}

local FONT = Enum.Font.GothamBlack
local CARD_W, CARD_H = 112, 88

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, value: string, size: UDim2, position: UDim2, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = FONT
	l.TextScaled = true
	l.Text = value
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.3
	l.Parent = parent
	return l
end

-- A small spinning-free portrait of a fighter (for cards and the reveal). Returns the viewport.
function PromptRow.portrait(parent: Instance, fighterId: string, background: Color3): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundColor3 = background
	viewport.Ambient = Color3.fromRGB(170, 165, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Parent = parent
	local ok, rig = pcall(RigBuilder.build, fighterId)
	if ok then
		rig.Parent = viewport
		local height = (rig:GetAttribute("StandHeight") :: number?) or RigBuilder.STAND_HEIGHT
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.CFrame = CFrame.lookAt(Vector3.new(-3.2, height * 1.55, -12.5), Vector3.new(0, height * 1.2, 0))
		cam.Parent = viewport
		viewport.CurrentCamera = cam
	end
	return viewport
end

-- Builds the row (centered at `position`, bottom-anchored). onPick(fighterId) on a tap, onNew() for a new prompt.
function PromptRow.build(parent: Instance, position: UDim2, onPick: (fighterId: string) -> (), onNew: () -> ()): Frame
	local row = Instance.new("Frame")
	row.Name = "PromptRow"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = position
	row.Size = UDim2.fromOffset(4 * (CARD_W + 8) + 180, CARD_H)
	row.Visible = false
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	local caption =
		text(row, "DEINE PROMPT-\nKÄMPFER", UDim2.fromOffset(150, 44), UDim2.new(), Color3.fromRGB(255, 225, 70))
	caption.LayoutOrder = 0

	local cards: { [string]: TextButton } = {}
	local shown = ""

	local function card(order: number): TextButton
		local b = Instance.new("TextButton")
		b.LayoutOrder = order
		b.Size = UDim2.fromOffset(CARD_W, CARD_H)
		b.BackgroundColor3 = Color3.fromRGB(22, 18, 40)
		b.Text = ""
		b.AutoButtonColor = true
		b.Parent = row
		corner(b, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 0
		stroke.Color = Color3.new(1, 1, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = b
		return b
	end

	local newCard = card(10)
	newCard.BackgroundColor3 = Color3.fromRGB(255, 40, 200)
	text(newCard, "+ NEUER\nPROMPT", UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6), Color3.new(1, 1, 1))
	newCard.Activated:Connect(onNew)

	local function refresh(codes: { string })
		local key = table.concat(codes, ",")
		if key == shown then
			return
		end
		shown = key
		for _, b in cards do
			b:Destroy()
		end
		table.clear(cards)
		for i, code in codes do
			local result = Registry.get("prompt_" .. code)
			if result then
				local glow = Color3.fromHex(result.look.glow)
				local b = card(i)
				local viewport = PromptRow.portrait(b, result.id, glow:Lerp(Color3.fromRGB(16, 14, 30), 0.65))
				viewport.Size = UDim2.fromScale(1, 0.74)
				corner(viewport, 10)
				text(b, result.fighter.name, UDim2.new(1, -8, 0.24, 0), UDim2.new(0, 4, 0.75, 0), glow)
				b.Activated:Connect(function()
					onPick(result.id)
				end)
				b:SetAttribute("FighterId", result.id)
				if row:GetAttribute("Chosen") == result.id then
					(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 4
				end
				cards[result.id] = b
			end
		end
	end
	ProfileState.onChange(function(view)
		refresh(view.prompts or {})
	end)
	row:SetAttribute("Chosen", "")
	return row
end

-- Outlines the chosen prompt fighter's card (none when a roster fighter is chosen).
function PromptRow.setChosen(row: Frame, fighterId: string)
	row:SetAttribute("Chosen", fighterId)
	for _, child in row:GetChildren() do
		if child:IsA("TextButton") then
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = 0
			end
		end
	end
	for _, child in row:GetChildren() do
		if child:IsA("TextButton") and child:GetAttribute("FighterId") == fighterId then
			(child:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 4
		end
	end
end

return PromptRow
