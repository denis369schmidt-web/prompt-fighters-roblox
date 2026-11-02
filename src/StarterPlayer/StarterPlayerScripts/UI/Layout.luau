--!strict
-- Shared HUD layout rules: everything starts below Roblox's top bar (GuiService.TopbarInset, which differs per
-- device and grows on phones), and a slot at the top right stays free for the shop button (UI/Shop).
-- ScreenGuis here use IgnoreGuiInset = true plus a UIScale, so offsets are divided by the scale.

local GuiService = game:GetService("GuiService")

local Layout = {}

Layout.MARGIN = 8
-- Reserved top-right area (unscaled pixels below the top bar) for the shop button; lobby panels start below it.
Layout.SHOP_SLOT = { width = 240, height = 60 }
-- Fallback top bar height when TopbarInset is not known yet (current Roblox top bar: 58 px).
Layout.TOPBAR_FALLBACK = 58

-- Pixels from the screen top to the first free row below the Roblox top bar.
function Layout.topPixels(): number
	local height = 0
	pcall(function()
		height = GuiService.TopbarInset.Max.Y
	end)
	if height <= 0 then
		height = Layout.TOPBAR_FALLBACK
	end
	return height + Layout.MARGIN
end

-- Same in the offset units of a ScreenGui scaled by `scale` (its UIScale).
function Layout.top(scale: number): number
	return Layout.topPixels() / math.max(scale, 0.01)
end

-- Calls `callback` now and whenever the top bar or the screen size changes.
function Layout.watch(callback: () -> ())
	callback()
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(callback)
	end)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		task.defer(callback) -- after the UIScale of the gui updated
	end)
end

return Layout
