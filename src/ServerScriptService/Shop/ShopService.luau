--!strict
-- The shop on the server: Robux purchases (ProcessReceipt for developer products, game passes), coin purchases,
-- equipping cosmetics and redeeming vouchers. Rules live in Shared/Meta/Purchases and Shared/Meta/Profile; this
-- module only talks to Roblox. The client never grants anything: it asks, the server checks and opens the
-- Roblox purchase dialog, and only ProcessReceipt / pass ownership changes what a player has.
--
-- ProcessReceipt (docs/SPEC.md 10.7):
--   * profile not loaded, temporary (DataStore down) or player gone -> NotProcessedYet (Roblox retries later)
--   * the PurchaseId is written into the profile together with the grant, then the profile is saved right away;
--     PurchaseGranted only after that save succeeded, otherwise NotProcessedYet
--   * a repeated callback for a recorded PurchaseId grants nothing again, it only retries the save

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Data.Cosmetics)
local Fighters = require(ReplicatedStorage.Shared.Data.Fighters)
local Products = require(ReplicatedStorage.Shared.Data.Products)
local Profile = require(ReplicatedStorage.Shared.Meta.Profile)
local Purchases = require(ReplicatedStorage.Shared.Meta.Purchases)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local RemoteHub = require(script.Parent.Parent.Net.RemoteHub)

local ShopService = {}

type Answer = { ok: boolean, message: string? }

-- Session state: owned game passes per player (read at join, updated on purchase).
local passes: { [number]: { [string]: boolean } } = {}

local productsByAsset: { [number]: Products.DevProduct } = {}
local passesByAsset: { [number]: Products.GamePass } = {}
for _, product in Products.DEV_PRODUCTS do
	if product.assetId ~= 0 then
		productsByAsset[product.assetId] = product
	end
end
for _, pass in Products.GAME_PASSES do
	if pass.assetId ~= 0 then
		passesByAsset[pass.assetId] = pass
	end
end

-- Fires (player, productId, summary) after a purchase was granted and saved (analytics can listen).
local granted = Instance.new("BindableEvent")
ShopService.granted = granted.Event

function ShopService.hasPass(player: Player, passId: string): boolean
	local owned = passes[player.UserId]
	return owned ~= nil and owned[passId] == true
end

-- Additive coin bonuses and XP bonus from the player's game passes (for Profile.applyMatch).
function ShopService.matchBonuses(player: Player): ({ number }, number)
	return Purchases.passBonuses(passes[player.UserId] or {})
end

local function ownedPasses(player: Player): { [string]: boolean }
	return passes[player.UserId] or {}
end

local function checkPasses(player: Player)
	local owned: { [string]: boolean } = {}
	for _, pass in Products.GAME_PASSES do
		if pass.assetId ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.assetId)
			end)
			if ok and has then
				owned[pass.id] = true
			elseif not ok then
				warn(`[ShopService] pass check failed for {player.UserId} / {pass.id}: {has}`)
			end
		end
	end
	if player.Parent == nil then
		return
	end
	passes[player.UserId] = owned
	PlayerData.refresh(player)
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if player == nil or PlayerData.get(player) == nil or not PlayerData.canSave(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = productsByAsset[info.ProductId]
	if product == nil then
		warn(`[ShopService] receipt for unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	local summary = ""
	local fresh = false
	PlayerData.update(player, function(profile)
		fresh, summary = Purchases.applyReceipt(profile, product, purchaseId, os.time())
	end, nil)
	-- Saved now or never granted: a crash before this point loses nothing, Roblox simply asks again.
	if not PlayerData.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if fresh then
		PlayerData.refresh(player, { message = `Danke! {summary}` })
		granted:Fire(player, product.id, summary)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function buyWithCoins(player: Player, kind: string, id: string): Answer
	if PlayerData.get(player) == nil then
		return { ok = false, message = "Profil lädt noch" }
	end
	local answer: Answer = { ok = false, message = "Unbekannt" }
	local extra: { [string]: any } = {}
	PlayerData.update(player, function(profile)
		local ok, reason
		if kind == "fighter" then
			ok, reason = Profile.buyFighter(profile, id)
			extra.bought = if ok then id else nil
		elseif kind == "cosmetic" then
			ok, reason = Profile.buyCosmetic(profile, id)
		else
			ok, reason = false, "Unbekannt"
		end
		local name = if kind == "fighter" and Fighters.byId[id]
			then Fighters.byId[id].name
			elseif Cosmetics.byId[id] then (Cosmetics.byId[id] :: any).name
			else id
		answer = { ok = ok, message = if ok then `{name} gekauft!` else reason }
		extra.message = answer.message
	end, extra)
	return answer
end

local function equip(player: Player, kind: string, fighterId: string, id: string): Answer
	if PlayerData.get(player) == nil then
		return { ok = false, message = "Profil lädt noch" }
	end
	local answer: Answer = { ok = false }
	PlayerData.update(player, function(profile)
		local ok, reason = Profile.equip(profile, kind, fighterId, id, ownedPasses(player))
		answer = { ok = ok, message = reason }
	end)
	return answer
end

local function redeem(player: Player, kind: string, id: string): Answer
	if PlayerData.get(player) == nil then
		return { ok = false, message = "Profil lädt noch" }
	end
	local answer: Answer = { ok = false }
	PlayerData.update(player, function(profile)
		local ok, reason = Purchases.redeem(profile, kind, id)
		answer = { ok = ok, message = if ok then "Gutschein eingelöst!" else reason }
	end, nil)
	return answer
end

local function startPurchase(player: Player, id: string, choice: string): Answer
	local profile = PlayerData.get(player)
	if profile == nil then
		return { ok = false, message = "Profil lädt noch" }
	end
	local product = Products.byId[id]
	if product == nil then
		return { ok = false, message = "Unbekannt" }
	end
	local sellable, why = Purchases.sellable(product)
	if not sellable then
		return { ok = false, message = why }
	end
	if not PlayerData.canSave(player) then
		-- A purchase on a temporary profile could not be stored; Roblox would retry it, but don't even start.
		return { ok = false, message = "Speichern gerade nicht möglich, bitte später" }
	end
	if (product :: any).grants == nil then
		local pass = product :: Products.GamePass
		if ShopService.hasPass(player, pass.id) then
			return { ok = false, message = "Hast du schon" }
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.assetId)
		return { ok = true }
	end
	local devProduct = product :: Products.DevProduct
	local offer, reason = Purchases.canOffer(profile :: Profile.Profile, devProduct, os.time())
	if not offer then
		return { ok = false, message = reason }
	end
	local chosen, chooseReason = true, nil
	PlayerData.update(player, function(p)
		chosen, chooseReason = Purchases.choose(p, devProduct, choice)
	end)
	if not chosen then
		return { ok = false, message = chooseReason }
	end
	MarketplaceService:PromptProductPurchase(player, devProduct.assetId)
	return { ok = true }
end

local function decorate(player: Player, view: { [string]: any })
	local owned = {}
	for passId in ownedPasses(player) do
		table.insert(owned, passId)
	end
	table.sort(owned)
	view.passes = owned
	local profile = PlayerData.get(player)
	local starter = Products.byId.starter_pack :: Products.DevProduct
	view.starterOffer = profile ~= nil and (Purchases.canOffer(profile, starter, os.time()))
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt :: any
	PlayerData.decorate = decorate
	Players.PlayerAdded:Connect(checkPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passes[player.UserId] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, assetId, purchased)
		local pass = passesByAsset[assetId]
		if not purchased or pass == nil then
			return
		end
		local owned: { [string]: boolean } = passes[player.UserId] or {}
		owned[pass.id] = true
		passes[player.UserId] = owned
		PlayerData.refresh(player, { message = `{pass.name} freigeschaltet!` })
		granted:Fire(player, pass.id, pass.name)
	end)

	RemoteHub.handle("BuyWithCoins", buyWithCoins, { ok = false })
	RemoteHub.handle("EquipCosmetic", equip, { ok = false })
	RemoteHub.handle("RedeemVoucher", redeem, { ok = false })
	RemoteHub.handle("ShopPurchase", startPurchase, { ok = false, message = "Zu schnell, kurz warten" })
end

return ShopService
