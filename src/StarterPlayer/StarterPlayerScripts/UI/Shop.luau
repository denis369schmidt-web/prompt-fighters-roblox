--!strict
-- The shop panel (lobby): tabs KÄMPFER / SKINS / KO-EFFEKTE / TITEL / PÄSSE. Left a big 3D preview (ViewportFrame)
-- of the selected item, right the cards. Every card shows exactly what it is and its fixed price (coins and/or
-- Robux); owned items show "Besitzt du" / "Ausrüsten". "Heute im Fokus" picks four items per UTC day from the
-- date (Data/Cosmetics.featured): the same for everyone, it only changes what is shown on top. Products without a
-- Creator Dashboard id (assetId 0) or with content still in the making show "Bald verfügbar", so the panel works
-- in Studio before real ids exist. The client only asks; the server checks and grants (Server/Shop/ShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared:WaitForChild("Data")
local Cosmetics = require(Data:WaitForChild("Cosmetics"))
local Fighters = require(Data:WaitForChild("Fighters"))
local Looks = require(Data:WaitForChild("Looks"))
local Products = require(Data:WaitForChild("Products"))
local Visuals = require(Data:WaitForChild("Visuals"))
local Purchases = require(Shared:WaitForChild("Meta"):WaitForChild("Purchases"))
local RigBuilder = require(Shared:WaitForChild("Visual"):WaitForChild("RigBuilder"))
local MatchState = require(script.Parent.Parent.State.MatchState)
local ProfileState = require(script.Parent.Parent.State.ProfileState)
local Effects = require(script.Parent.Parent.Controllers.Effects)

local Shop = {}

local FONT = Enum.Font.GothamBlack
local BODY = Enum.Font.GothamBold
local INK = Color3.fromRGB(14, 12, 28)
local PANEL = Color3.fromRGB(24, 20, 44)
local CARD = Color3.fromRGB(32, 28, 58)
local MUTED = Color3.fromRGB(150, 145, 180)
local GOLD = Color3.fromRGB(255, 215, 80)
local PINK = Color3.fromRGB(255, 40, 200)
local CYAN = Color3.fromRGB(0, 230, 255)
local GREEN = Color3.fromRGB(80, 210, 130)
local GREY = Color3.fromRGB(70, 66, 92)

local PANEL_W, PANEL_H = 940, 600
local PREVIEW_W = 300

type Tab = "fighters" | "skins" | "ko" | "plates" | "passes"
local TABS: { { id: Tab, label: string } } = {
	{ id = "fighters", label = "KÄMPFER" },
	{ id = "skins", label = "SKINS" },
	{ id = "ko", label = "KO-EFFEKTE" },
	{ id = "plates", label = "TITEL" },
	{ id = "passes", label = "PÄSSE" },
}

Shop.open = nil :: ((tab: string?) -> ())?

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
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
	pad.PaddingTop = UDim.new(0.2, 0)
	pad.PaddingBottom = UDim.new(0.2, 0)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	return b
end

local function rarityColor(rarity: string): Color3
	local r = Cosmetics.RARITIES[rarity]
	return Color3.fromHex(if r then r.color else "#FFFFFF")
end

local function rarityName(rarity: string): string
	local r = Cosmetics.RARITIES[rarity]
	return if r then r.name else ""
end

-- Places a rig in a viewport and aims the camera; full = whole body, else head and shoulders.
local function stage(viewport: ViewportFrame, fighterId: string, skinId: string?, full: boolean): (Model, number)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	local rig = RigBuilder.build(fighterId, skinId)
	rig.Parent = viewport
	local height = (rig:GetAttribute("StandHeight") :: number?) or RigBuilder.STAND_HEIGHT
	local camera: Camera = (viewport:FindFirstChildOfClass("Camera") :: any) or Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if full then
		camera.FieldOfView = 34
		camera.CFrame = CFrame.lookAt(Vector3.new(0, height * 1.15, -15.5), Vector3.new(0, height * 0.98, 0))
	else
		camera.FieldOfView = 30
		camera.CFrame = CFrame.lookAt(Vector3.new(-3.2, height * 1.55, -12.5), Vector3.new(0, height * 1.2, 0))
	end
	return rig, height
end

local function newViewport(parent: Instance, size: UDim2, position: UDim2, background: Color3): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = size
	viewport.Position = position
	viewport.BackgroundColor3 = background
	viewport.Ambient = Color3.fromRGB(170, 165, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Parent = parent
	corner(viewport, 10)
	return viewport
end

function Shop.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local coinRemote = remotes:WaitForChild("BuyWithCoins") :: RemoteFunction
	local equipRemote = remotes:WaitForChild("EquipCosmetic") :: RemoteFunction
	local purchaseRemote = remotes:WaitForChild("ShopPurchase") :: RemoteFunction
	local redeemRemote = remotes:WaitForChild("RedeemVoucher") :: RemoteFunction
	local localPlayer = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local view = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(view.X / (PANEL_W + 40), view.Y / (PANEL_H + 40)), 0.4, 1.15)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Lobby button, left under the guide.
	local openButton = button(gui, "🛒 SHOP", UDim2.fromOffset(150, 48), UDim2.fromOffset(12, 222), PINK)
	stroke(openButton, Color3.new(1, 1, 1), 2)
	openButton.Visible = false

	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = INK
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)
	local panelStroke = stroke(panel, Color3.new(1, 1, 1), 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(PINK, CYAN)
	gradient.Parent = panelStroke

	local title = text(panel, "SHOP", UDim2.fromOffset(160, 34), UDim2.fromOffset(22, 14), GOLD)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local coinsLabel = text(panel, "🪙 0", UDim2.fromOffset(200, 26), UDim2.new(1, -330, 0, 18), GOLD)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
	local voucherLabel = text(panel, "", UDim2.fromOffset(300, 16), UDim2.fromOffset(190, 24), GREEN, BODY)
	voucherLabel.TextXAlignment = Enum.TextXAlignment.Left
	local close = button(panel, "✕", UDim2.fromOffset(44, 44), UDim2.new(1, -60, 0, 10), GREY)

	local tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(1, -44, 0, 46)
	tabRow.Position = UDim2.fromOffset(22, 60)
	tabRow.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabRow
	local tabButtons: { [string]: TextButton } = {}
	for k, tab in TABS do
		local b = button(tabRow, tab.label, UDim2.new(1 / #TABS, -7, 1, 0), UDim2.new(), CARD)
		b.LayoutOrder = k
		tabButtons[tab.id] = b
	end

	local footer = text(
		panel,
		"Alles zum Festpreis · nichts Zufälliges · keine Kampfvorteile",
		UDim2.new(1, -44, 0, 16),
		UDim2.new(0, 22, 1, -24),
		MUTED,
		BODY
	)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	local status = text(panel, "", UDim2.new(0.5, 0, 0, 18), UDim2.new(0.5, -22, 1, -26), GOLD, BODY)
	status.TextXAlignment = Enum.TextXAlignment.Right

	-- Body: preview on the left, cards on the right.
	local bodyY, bodyH = 116, PANEL_H - 116 - 36
	local preview = Instance.new("Frame")
	preview.Size = UDim2.fromOffset(PREVIEW_W, bodyH)
	preview.Position = UDim2.fromOffset(22, bodyY)
	preview.BackgroundColor3 = PANEL
	preview.Parent = panel
	corner(preview, 14)
	local previewViewport = newViewport(preview, UDim2.new(1, -16, 0, 236), UDim2.fromOffset(8, 8), CARD)
	local previewArt = Instance.new("Frame") -- KO / plate / pass art instead of a rig
	previewArt.Size = previewViewport.Size
	previewArt.Position = previewViewport.Position
	previewArt.BackgroundColor3 = CARD
	previewArt.Visible = false
	previewArt.Parent = preview
	corner(previewArt, 10)
	local previewName = text(preview, "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 250))
	local previewRarity = text(preview, "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 278), MUTED, BODY)
	local previewInfo = text(preview, "", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 296), MUTED, BODY)
	previewInfo.TextWrapped = true
	local actionA = button(preview, "", UDim2.new(1, -20, 0, 46), UDim2.fromOffset(10, 336), PINK)
	local actionB = button(preview, "", UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 388), GREY)

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.fromOffset(PANEL_W - PREVIEW_W - 22 - 22 - 14, bodyH)
	content.Position = UDim2.fromOffset(22 + PREVIEW_W + 14, bodyY)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Parent = panel

	---------------------------------------------------------------------------------------------------------
	-- State

	local tab: Tab = "skins"
	local fighter = Visuals.SLICE_FIGHTERS[1]
	local selected: string? = nil -- item id in the current tab (fighter id in the fighters tab)
	local confirm: string? = nil -- coin purchase waiting for the second tap
	local open = false
	local busy = false
	local previewModel: Model? = nil
	local previewHeight = 0
	local previewKey = ""
	-- Small 3D portraits are cached and moved between rebuilt cards (building rigs is the expensive part).
	local portraits: { [string]: ViewportFrame } = {}

	local function say(message: string?, good: boolean?)
		status.Text = message or ""
		status.TextColor3 = if good then GREEN else GOLD
	end

	local function ask(remote: RemoteFunction, ...: any)
		if busy then
			return
		end
		busy = true
		local args = table.pack(...)
		task.spawn(function()
			local ok, answer = pcall(function()
				return remote:InvokeServer(table.unpack(args, 1, args.n))
			end)
			busy = false
			if not ok or type(answer) ~= "table" then
				say("Keine Antwort vom Server")
			elseif answer.message then
				say(answer.message, answer.ok)
			elseif answer.ok then
				say("")
			end
		end)
	end

	local function vouchers(): { [string]: number }
		local view = ProfileState.view
		return if view and view.vouchers then view.vouchers else {}
	end

	local function hasVoucher(kind: string, price: number): boolean
		for key, count in vouchers() do
			local k, max = string.match(key, "^(%a+):(%w+)$")
			if k == kind and count > 0 and (max == "any" or price <= (tonumber(max) or -1)) then
				return true
			end
		end
		return false
	end

	local function equippedSkin(fighterId: string): string?
		local view = ProfileState.view
		return if view and view.equippedSkins then view.equippedSkins[fighterId] else nil
	end

	---------------------------------------------------------------------------------------------------------
	-- Preview

	local function showRig(fighterId: string, skinId: string?)
		previewViewport.Visible = true
		previewArt.Visible = false
		local key = `{fighterId}|{skinId or ""}`
		if key == previewKey and previewModel then
			return
		end
		previewKey = key
		local rig, height = stage(previewViewport, fighterId, skinId, true)
		previewModel, previewHeight = rig, height
		local glow = Color3.fromHex(Looks.resolve(fighterId, skinId).glow)
		previewViewport.BackgroundColor3 = glow:Lerp(INK, 0.72)
	end

	local function showArt(build: (frame: Frame) -> ())
		previewViewport.Visible = false
		previewArt.Visible = true
		for _, child in previewArt:GetChildren() do
			if not child:IsA("UICorner") then
				child:Destroy()
			end
		end
		build(previewArt)
	end

	local function plateArt(frame: Frame, plate: Cosmetics.Plate?)
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromScale(0.86, 0.36)
		box.BackgroundColor3 = INK
		box.Parent = frame
		corner(box, 10)
		if plate then
			stroke(box, Color3.fromHex(plate.frame), 3)
		end
		text(box, localPlayer.DisplayName, UDim2.new(1, -16, 0.5, -4), UDim2.fromOffset(8, 6))
		text(
			box,
			if plate then plate.title else "Level-Titel",
			UDim2.new(1, -16, 0.34, 0),
			UDim2.new(0, 8, 0.58, 0),
			if plate then Color3.fromHex(plate.frame) else MUTED,
			BODY
		)
	end

	local function koArt(frame: Frame, ko: Cosmetics.KoEffect)
		local color = Color3.fromHex(ko.color or Looks.resolve(fighter, equippedSkin(fighter)).glow)
		local glyphs = {
			classic = "━━✦",
			confetti = "✦ ✧ ✦",
			pixel = "▦ ▦ ▦",
			nova = "◎",
			thunder = "ϟ ϟ",
			petals = "❀ ❀",
			void = "●",
		}
		local glyph =
			text(frame, glyphs[ko.style] or "✦", UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.1, 0.18), color)
		glyph.TextStrokeTransparency = 0.5
		local hint =
			text(frame, "▶ VORSCHAU in der Lobby", UDim2.fromScale(0.8, 0.1), UDim2.fromScale(0.1, 0.78), MUTED, BODY)
		hint.TextTransparency = 0.1
	end

	---------------------------------------------------------------------------------------------------------
	-- Cards

	local function clearContent()
		for _, vp in portraits do
			vp.Parent = nil
		end
		for _, child in content:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	local function section(order: number, label: string, height: number?): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, -10, 0, height or 0)
		frame.AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
		frame.LayoutOrder = order
		frame.Parent = content
		if label ~= "" then
			local l = text(frame, label, UDim2.new(1, 0, 0, 20), UDim2.new(), GOLD)
			l.TextXAlignment = Enum.TextXAlignment.Left
		end
		return frame
	end

	local function grid(parent: Frame, cell: Vector2): Frame
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.Position = UDim2.fromOffset(0, 26)
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Parent = parent
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
		layout.CellPadding = UDim2.fromOffset(10, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		local pad = Instance.new("UIPadding")
		pad.PaddingBottom = UDim.new(0, 12)
		pad.Parent = holder
		return holder
	end

	-- A card: art on top (filled by `art`), name, and a state/price line. Tapping selects it.
	local function card(
		parent: Instance,
		order: number,
		name: string,
		line: string,
		lineColor: Color3,
		rarity: string?,
		isSelected: boolean,
		onTap: () -> (),
		art: (frame: Frame) -> ()
	)
		local b = Instance.new("TextButton")
		b.Text = ""
		b.LayoutOrder = order
		b.BackgroundColor3 = CARD
		b.AutoButtonColor = true
		b.Parent = parent
		corner(b, 10)
		stroke(
			b,
			if isSelected then Color3.new(1, 1, 1) else (if rarity then rarityColor(rarity) else GREY),
			if isSelected then 3 else 1
		)
		local artFrame = Instance.new("Frame")
		artFrame.BackgroundTransparency = 1
		artFrame.Size = UDim2.new(1, -8, 1, -46)
		artFrame.Position = UDim2.fromOffset(4, 4)
		artFrame.ClipsDescendants = true
		artFrame.Parent = b
		art(artFrame)
		text(b, name, UDim2.new(1, -10, 0, 18), UDim2.new(0, 5, 1, -40))
		text(b, line, UDim2.new(1, -10, 0, 14), UDim2.new(0, 5, 1, -19), lineColor, BODY)
		b.Activated:Connect(onTap)
	end

	local function swatch(frame: Frame, look: { [string]: any }, rarity: string?)
		local colors = { look.primary, look.secondary, look.glow }
		for k, hex in colors do
			local stripe = Instance.new("Frame")
			stripe.BorderSizePixel = 0
			stripe.Size = UDim2.new(1 / 3, 0, 1, 0)
			stripe.Position = UDim2.fromScale((k - 1) / 3, 0)
			stripe.BackgroundColor3 = Color3.fromHex(hex)
			stripe.Parent = frame
		end
		corner(frame, 8)
		if rarity then
			local tag = text(
				frame,
				rarityName(rarity),
				UDim2.new(1, -8, 0, 14),
				UDim2.fromOffset(4, 4),
				rarityColor(rarity),
				BODY
			)
			tag.TextStrokeTransparency = 0.3
			tag.TextXAlignment = Enum.TextXAlignment.Left
		end
	end

	local function portrait(frame: Frame, fighterId: string, skinId: string?)
		local key = `{fighterId}|{skinId or ""}`
		local existing: ViewportFrame? = portraits[key]
		local viewport: ViewportFrame = existing or newViewport(frame, UDim2.fromScale(1, 1), UDim2.new(), CARD)
		if not existing then
			stage(viewport, fighterId, skinId, false)
			portraits[key] = viewport
		end
		viewport.BackgroundColor3 = Color3.fromHex(Looks.resolve(fighterId, skinId).glow):Lerp(INK, 0.65)
		viewport.Parent = frame
	end

	-- Price line for an item that is not owned yet.
	local function priceLine(item: Cosmetics.Item): string
		if item.coins == nil then
			return (item :: any).source or (if (item :: any).pass then "mit Game Pass" else "")
		end
		local robux = Cosmetics.robux(item)
		return if robux then `🪙 {item.coins} · R$ {robux}` else `🪙 {item.coins}`
	end

	---------------------------------------------------------------------------------------------------------
	-- Rendering per tab

	local render: () -> ()

	local function selectItem(id: string?)
		selected = id
		confirm = nil
		render()
	end

	local handlers: { [TextButton]: (() -> ())? } = {}
	local function bind(target: TextButton)
		target.Activated:Connect(function()
			local h = handlers[target]
			if h then
				h()
			end
		end)
	end
	bind(actionA)
	bind(actionB)
	-- Sets the two preview buttons (nil handler = shown but inactive).
	local function actions(a: string?, aColor: Color3?, onA: (() -> ())?, b: string?, onB: (() -> ())?)
		handlers[actionA] = onA
		handlers[actionB] = onB
		actionA.Visible = a ~= nil
		actionA.Text = a or ""
		actionA.BackgroundColor3 = aColor or PINK
		actionA.Active = onA ~= nil
		actionA.AutoButtonColor = onA ~= nil
		actionB.Visible = b ~= nil
		actionB.Text = b or ""
		actionB.Active = onB ~= nil
		actionB.AutoButtonColor = onB ~= nil
		actionB.BackgroundColor3 = if onB then CYAN:Lerp(INK, 0.35) else GREY
	end

	-- Robux button text and handler for a product (nil handler = not sellable yet).
	local function robuxAction(productId: string, choice: string): (string, (() -> ())?)
		local product = Products.byId[productId]
		if product == nil then
			return "", nil
		end
		local sellable = Purchases.sellable(product)
		if not sellable then
			return `R$ {product.robux} · {string.upper(Purchases.SOON)}`, nil
		end
		return `R$ {product.robux} KAUFEN`, function()
			ask(purchaseRemote, productId, choice)
		end
	end

	-- Buy with coins (two taps).
	local function coinAction(kind: string, id: string, price: number): (string, () -> ())
		if confirm == id then
			return `SICHER? 🪙 {price}`,
				function()
					confirm = nil
					ask(coinRemote, kind, id)
					render()
				end
		end
		return `🪙 {price} KAUFEN`, function()
			confirm = id
			render()
		end
	end

	local function cosmeticActions(item: Cosmetics.Item, equipKind: string, fighterId: string, isEquipped: boolean)
		if ProfileState.ownsCosmetic(item.id) or (item.kind == "ko" and item.id == Cosmetics.DEFAULT_KO) then
			if isEquipped then
				actions("✓ AUSGERÜSTET", GREEN, nil, "BESITZT DU", nil)
			else
				actions("AUSRÜSTEN", GREEN, function()
					ask(equipRemote, equipKind, fighterId, item.id)
				end, "BESITZT DU", nil)
			end
			return
		end
		local pass = (item :: any).pass
		if pass then
			if ProfileState.hasPass(pass) then
				actions("AUSRÜSTEN", GREEN, function()
					ask(equipRemote, equipKind, fighterId, item.id)
				end, "MIT GAME PASS", nil)
			else
				local passDef = Products.byId[pass]
				actions(`Teil von {if passDef then passDef.name else pass}`, GREY, nil, nil, nil)
			end
			return
		end
		if item.coins == nil then
			actions(string.upper((item :: any).source or "NICHT IM SHOP"), GREY, nil, nil, nil)
			return
		end
		local coins = item.coins :: number
		local aText, aHandler = coinAction("cosmetic", item.id, coins)
		if item.kind == "skin" and hasVoucher("skin", coins) then
			actions(aText, PINK, aHandler, "GUTSCHEIN EINLÖSEN", function()
				ask(redeemRemote, "skin", item.id)
			end)
			return
		end
		local _, productId = Cosmetics.robux(item)
		if productId then
			local bText, bHandler = robuxAction(productId, item.id)
			actions(aText, PINK, aHandler, bText, bHandler)
		else
			actions(aText, PINK, aHandler, nil, nil)
		end
	end

	local function describe(name: string, rarity: string?, info: string)
		previewName.Text = name
		previewRarity.Text = if rarity then `{rarityName(rarity)} · nur ein Etikett, kein Zufall` else ""
		previewRarity.TextColor3 = if rarity then rarityColor(rarity) else MUTED
		previewInfo.Text = info
	end

	local function renderFighters()
		local list = section(1, "ALLE STARTKÄMPFER")
		local holder = grid(list, Vector2.new(130, 150))
		local current = selected or fighter
		for k, id in Visuals.SLICE_FIGHTERS do
			local def = Fighters.get(id)
			local owned = ProfileState.owns(id)
			local price = if def.unlock.kind == "coins" then (def.unlock :: any).price else 0
			card(
				holder,
				k,
				def.name,
				if owned then "BESITZT DU" else `🪙 {price}`,
				if owned then GREEN else GOLD,
				nil,
				id == current,
				function()
					fighter = id
					selectItem(id)
				end,
				function(frame)
					portrait(frame, id, equippedSkin(id))
				end
			)
		end
		local def = Fighters.get(current)
		showRig(current, equippedSkin(current))
		describe(def.name, nil, `{def.element} · gleiche Werte für alle, egal wie freigeschaltet`)
		if ProfileState.owns(current) then
			actions("✓ BESITZT DU", GREEN, nil, "SKINS ANSEHEN", function()
				fighter = current
				tab = "skins"
				selected = nil
				render()
			end)
			return
		end
		local price = if def.unlock.kind == "coins" then (def.unlock :: any).price else 0
		local aText, aHandler = coinAction("fighter", current, price)
		if hasVoucher("fighter", price) then
			actions(aText, PINK, aHandler, "GUTSCHEIN EINLÖSEN", function()
				ask(redeemRemote, "fighter", current)
			end)
		else
			local bText, bHandler = robuxAction(`fighter_unlock_{price}`, current)
			actions(aText, PINK, aHandler, bText, bHandler)
		end
	end

	local function renderSkins()
		-- Today's featured items (deterministic from the date).
		local featured = section(1, "HEUTE IM FOKUS · wechselt täglich, für alle gleich")
		local strip = grid(featured, Vector2.new(130, 140))
		for k, item in Cosmetics.featured(Cosmetics.dayOf(os.time()), 4) do
			local owned = ProfileState.ownsCosmetic(item.id)
			card(
				strip,
				k,
				item.name,
				if owned then "BESITZT DU" else priceLine(item),
				if owned then GREEN else GOLD,
				item.rarity,
				item.id == selected,
				function()
					if item.kind == "ko" then
						tab = "ko"
					elseif (item :: any).fighter then
						fighter = (item :: any).fighter
					end
					selectItem(item.id)
				end,
				function(frame)
					if item.kind == "skin" then
						portrait(frame, (item :: any).fighter or fighter, item.id)
					else
						frame.BackgroundColor3 = PANEL
						frame.BackgroundTransparency = 0
						koArt(frame, item :: Cosmetics.KoEffect)
					end
				end
			)
		end

		-- Fighter chips.
		local chips = Instance.new("ScrollingFrame")
		chips.LayoutOrder = 2
		chips.Size = UDim2.new(1, -10, 0, 44)
		chips.BackgroundTransparency = 1
		chips.BorderSizePixel = 0
		chips.ScrollBarThickness = 4
		chips.ScrollingDirection = Enum.ScrollingDirection.X
		chips.AutomaticCanvasSize = Enum.AutomaticSize.X
		chips.CanvasSize = UDim2.new()
		chips.Parent = content
		local chipLayout = Instance.new("UIListLayout")
		chipLayout.FillDirection = Enum.FillDirection.Horizontal
		chipLayout.Padding = UDim.new(0, 6)
		chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
		chipLayout.Parent = chips
		for k, id in Visuals.SLICE_FIGHTERS do
			local def = Fighters.get(id)
			local chip =
				button(chips, def.name, UDim2.fromOffset(118, 36), UDim2.new(), if id == fighter then PINK else CARD)
			chip.LayoutOrder = k
			chip.Font = BODY
			chip.Activated:Connect(function()
				fighter = id
				selectItem(nil)
			end)
		end

		local def = Fighters.get(fighter)
		local list = section(3, `SKINS FÜR {def.name}`)
		local holder = grid(list, Vector2.new(130, 150))
		local equipped = equippedSkin(fighter)
		card(
			holder,
			0,
			"STANDARD",
			if equipped == nil then "✓ AUSGERÜSTET" else "BESITZT DU",
			GREEN,
			"standard",
			selected == "",
			function()
				selectItem("")
			end,
			function(frame)
				portrait(frame, fighter, nil)
			end
		)
		for k, skin in Cosmetics.skinsFor(fighter) do
			local owned = ProfileState.ownsCosmetic(skin.id)
			local line = if equipped == skin.id
				then "✓ AUSGERÜSTET"
				elseif owned then "BESITZT DU"
				else priceLine(skin)
			card(holder, k, skin.name, line, if owned then GREEN else GOLD, skin.rarity, skin.id == selected, function()
				selectItem(skin.id)
			end, function(frame)
				-- Own skins get a 3D portrait; the 14 material skins a color swatch (cheaper on phones).
				if skin.fighter then
					portrait(frame, fighter, skin.id)
				else
					swatch(frame, Looks.resolve(fighter, skin.id) :: any, skin.rarity)
				end
			end)
		end

		local skinId = selected
		local skin = if skinId and skinId ~= "" then Cosmetics.skin(skinId) else nil
		if skin and not Cosmetics.fits(skin, fighter) then
			skin = nil
		end
		if skin then
			showRig(fighter, skin.id)
			describe(skin.name, skin.rarity, skin.info)
			cosmeticActions(skin, "skin", fighter, equipped == skin.id)
		else
			showRig(fighter, if skinId == "" then nil else equipped)
			describe(def.name, nil, "Wähle einen Skin. Skins ändern nur Farben und Material.")
			if skinId == "" and equipped ~= nil then
				actions("STANDARD AUSRÜSTEN", GREEN, function()
					ask(equipRemote, "skin", fighter, "")
				end, nil, nil)
			else
				actions(nil, nil, nil, nil, nil)
			end
		end
	end

	local function equippedKo(): string
		local view = ProfileState.view
		return if view and view.equippedKo then view.equippedKo else Cosmetics.DEFAULT_KO
	end

	local function renderKo()
		local list = section(1, "KO-EFFEKTE · was deine Gegner sehen, wenn du sie aus der Arena schießt")
		local holder = grid(list, Vector2.new(130, 140))
		local current = equippedKo()
		local chosen = selected or current
		for k, ko in Cosmetics.KO_EFFECTS do
			local owned = ko.id == Cosmetics.DEFAULT_KO or ProfileState.ownsCosmetic(ko.id)
			card(
				holder,
				k,
				ko.name,
				if current == ko.id then "✓ AUSGERÜSTET" elseif owned then "BESITZT DU" else priceLine(ko),
				if owned then GREEN else GOLD,
				ko.rarity,
				ko.id == chosen,
				function()
					selectItem(ko.id)
				end,
				function(frame)
					frame.BackgroundColor3 = PANEL
					frame.BackgroundTransparency = 0
					corner(frame, 8)
					koArt(frame, ko)
				end
			)
		end
		local item = Cosmetics.get(chosen)
		if item and item.kind == "ko" then
			local ko = item :: Cosmetics.KoEffect
			showArt(function(frame)
				koArt(frame, ko)
				local play = button(frame, "▶ VORSCHAU", UDim2.fromScale(0.6, 0.18), UDim2.fromScale(0.2, 0.56), CYAN)
				play.TextColor3 = INK
				play.Activated:Connect(function()
					-- Hide the panel and blow the effect up in front of the camera (lobby world).
					local cam = workspace.CurrentCamera
					gui.Enabled = false
					local at = cam.CFrame * Vector3.new(0, -2, -48)
					local color = Color3.fromHex(Looks.resolve(fighter, equippedSkin(fighter)).glow)
					Effects.knockout(at, color, cam.CFrame.RightVector, true, ko.id)
					task.delay(1.6, function()
						gui.Enabled = true
					end)
				end)
			end)
			describe(ko.name, ko.rarity, ko.info)
			cosmeticActions(ko, "ko", "", current == ko.id)
		end
	end

	local function equippedPlate(): string
		local view = ProfileState.view
		return if view and view.equippedPlate then view.equippedPlate else ""
	end

	local function renderPlates()
		local list = section(1, "TITEL & RAHMEN · in deiner Profilleiste")
		local holder = grid(list, Vector2.new(130, 140))
		local current = equippedPlate()
		local chosen = selected or current
		card(
			holder,
			0,
			"LEVEL-TITEL",
			if current == "" then "✓ AUSGERÜSTET" else "STANDARD",
			GREEN,
			"standard",
			chosen == "",
			function()
				selectItem("")
			end,
			function(frame)
				plateArt(frame, nil)
			end
		)
		for k, plate in Cosmetics.PLATES do
			local owned = ProfileState.ownsCosmetic(plate.id)
			card(
				holder,
				k,
				plate.name,
				if current == plate.id then "✓ AUSGERÜSTET" elseif owned then "BESITZT DU" else priceLine(plate),
				if owned then GREEN else GOLD,
				plate.rarity,
				plate.id == chosen,
				function()
					selectItem(plate.id)
				end,
				function(frame)
					plateArt(frame, plate)
				end
			)
		end
		local item = Cosmetics.get(chosen)
		if item and item.kind == "plate" then
			local plate = item :: Cosmetics.Plate
			showArt(function(frame)
				plateArt(frame, plate)
			end)
			describe(plate.name, plate.rarity, `{plate.info} · Titel „{plate.title}“`)
			cosmeticActions(plate, "plate", "", current == plate.id)
		else
			showArt(function(frame)
				plateArt(frame, nil)
			end)
			describe("LEVEL-TITEL", nil, "Zeigt deinen Level-Titel (gratis)")
			if current ~= "" then
				actions("AUSRÜSTEN", GREEN, function()
					ask(equipRemote, "plate", "", "")
				end, nil, nil)
			else
				actions("✓ AUSGERÜSTET", GREEN, nil, nil, nil)
			end
		end
	end

	-- One row per product: name, exactly what it gives, price and the button.
	local function productRow(parent: Instance, order: number, product: Products.GamePass | Products.DevProduct)
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -10, 0, 74)
		row.BackgroundColor3 = CARD
		row.Parent = parent
		corner(row, 10)
		local name = text(row, product.name, UDim2.new(1, -200, 0, 24), UDim2.fromOffset(14, 8))
		name.TextXAlignment = Enum.TextXAlignment.Left
		local info =
			text(row, Purchases.describe(product), UDim2.new(1, -200, 0, 30), UDim2.fromOffset(14, 36), MUTED, BODY)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Top
		info.TextWrapped = true
		local isPass = (product :: any).grants == nil
		local owned = isPass and ProfileState.hasPass(product.id)
		local sellable = Purchases.sellable(product)
		local label = if owned
			then "✓ BESITZT DU"
			elseif not sellable then `R$ {product.robux}\n{string.upper(Purchases.SOON)}`
			else `R$ {product.robux}`
		local b = button(
			row,
			label,
			UDim2.fromOffset(170, 54),
			UDim2.new(1, -180, 0, 10),
			if owned then GREEN elseif sellable then PINK else GREY
		)
		b.AutoButtonColor = sellable and not owned
		b.Activated:Connect(function()
			if sellable and not owned then
				ask(purchaseRemote, product.id, "")
			elseif not owned then
				say(`{product.name}: {Purchases.SOON}`)
			end
		end)
	end

	local function renderPasses()
		local function list(order: number, label: string, products: { any })
			local frame = section(order, label)
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.new(1, 0, 0, 0)
			holder.Position = UDim2.fromOffset(0, 26)
			holder.AutomaticSize = Enum.AutomaticSize.Y
			holder.Parent = frame
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 8)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = holder
			local pad = Instance.new("UIPadding")
			pad.PaddingBottom = UDim.new(0, 12)
			pad.Parent = holder
			for k, product in products do
				productRow(holder, k, product)
			end
		end
		local view = ProfileState.view
		local offers = {}
		if view == nil or view.starterOffer ~= false then
			table.insert(offers, Products.byId.starter_pack)
		end
		for _, id in { "bundle_neon_nights", "bundle_heaven_hell" } do
			table.insert(offers, Products.byId[id])
		end
		list(1, "GAME PASSES · einmal kaufen, für immer", Products.GAME_PASSES)
		list(2, "MÜNZEN", {
			Products.byId.coins_s,
			Products.byId.coins_m,
			Products.byId.coins_l,
			Products.byId.coins_xl,
		})
		list(3, "ANGEBOTE · Inhalt fest, vor dem Kauf sichtbar", offers)
		showArt(function(frame)
			local l = text(frame, "R$", UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.2, 0.2), GOLD)
			l.TextStrokeTransparency = 0.5
		end)
		describe("PÄSSE & MÜNZEN", nil, "Kein Kauf ändert Kampfwerte. Jeder Kauf zeigt genau, was du bekommst.")
		actions(nil, nil, nil, nil, nil)
	end

	render = function()
		if not open then
			return
		end
		local view = ProfileState.view
		coinsLabel.Text = `🪙 {if view then Purchases.thousands(view.coins) else "…"}`
		local count = 0
		for _, n in vouchers() do
			count += n
		end
		voucherLabel.Text = if count > 0 then `🎟 {count} Gutschein(e) einlösbar` else ""
		for id, b in tabButtons do
			b.BackgroundColor3 = if id == tab then PINK else CARD
		end
		clearContent()
		local layout = content:FindFirstChildOfClass("UIListLayout")
		if layout == nil then
			local l = Instance.new("UIListLayout")
			l.Padding = UDim.new(0, 8)
			l.SortOrder = Enum.SortOrder.LayoutOrder
			l.Parent = content
		end
		if tab == "fighters" then
			renderFighters()
		elseif tab == "skins" then
			renderSkins()
		elseif tab == "ko" then
			renderKo()
		elseif tab == "plates" then
			renderPlates()
		else
			renderPasses()
		end
	end

	local function setOpen(value: boolean, toTab: string?)
		open = value
		panel.Visible = value
		backdrop.Visible = value
		openButton.Visible = not value and MatchState.phase == "lobby"
		if value then
			for _, t in TABS do
				if t.id == toTab then
					tab = t.id
				end
			end
			selected = nil
			confirm = nil
			say("")
			render()
		end
	end
	Shop.open = function(toTab: string?)
		setOpen(true, toTab)
	end

	for id, b in tabButtons do
		b.Activated:Connect(function()
			tab = id :: Tab
			selected = nil
			confirm = nil
			content.CanvasPosition = Vector2.zero
			render()
		end)
	end
	openButton.Activated:Connect(function()
		setOpen(true, nil)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	backdrop.Activated:Connect(function()
		setOpen(false)
	end)

	ProfileState.onChange(function()
		confirm = nil
		render()
	end)
	MatchState.onEvent(function(event)
		if event.type == "phase" then
			if event.phase ~= "lobby" and open then
				setOpen(false)
			end
			openButton.Visible = event.phase == "lobby" and not open
		end
	end)
	openButton.Visible = MatchState.phase == "lobby"

	-- Slow turn of the preview rig.
	RunService.RenderStepped:Connect(function()
		local model = previewModel
		if open and model and model.Parent and previewViewport.Visible then
			model:PivotTo(CFrame.new(0, previewHeight, 0) * CFrame.Angles(0, os.clock() * 0.8, 0))
		end
	end)
end

return Shop
