--!strict
-- Pure rules for Robux purchases (Data/Products) on a Profile: what may be offered, which choice a "pick one"
-- product takes, and applying a receipt exactly once. Server/Shop/ShopService wires these to MarketplaceService;
-- tests call them directly. Nothing here is random: every grant is fixed or the player's own pick, and a pick
-- that is no longer possible when the receipt arrives turns into a voucher for the same price step.

local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Products = require(script.Parent.Parent.Data.Products)
local Visuals = require(script.Parent.Parent.Data.Visuals)
local Profile = require(script.Parent.Profile)

local Purchases = {}

-- Text the shop shows for products that cannot be bought yet (no Creator Dashboard id or content not built).
Purchases.SOON = "Bald verfügbar"

-- Can this product be sold at all right now? (Independent of the player.)
function Purchases.sellable(product: Products.GamePass | Products.DevProduct): (boolean, string?)
	if product.assetId == 0 or product.comingSoon then
		return false, Purchases.SOON
	end
	return true, nil
end

-- The grant that needs the player's pick, if any.
function Purchases.choiceGrant(product: Products.DevProduct): Products.Grant?
	for _, grant in product.grants do
		if grant.kind == "fighterChoice" or grant.kind == "skinChoice" then
			return grant
		end
	end
	return nil
end

local function fighterPrice(fighterId: string): number?
	if table.find(Visuals.SLICE_FIGHTERS, fighterId) == nil then
		return nil
	end
	return Profile.price(fighterId)
end

-- Is `choice` a valid pick for this product right now?
function Purchases.validChoice(
	profile: Profile.Profile,
	product: Products.DevProduct,
	choice: string
): (boolean, string?)
	local found = Purchases.choiceGrant(product)
	if found == nil then
		return choice == "", if choice == "" then nil else "Keine Auswahl nötig"
	end
	local grant = found :: Products.Grant
	if grant.kind == "fighterChoice" then
		local price = fighterPrice(choice)
		if price == nil then
			return false, "Kämpfer nicht im Shop"
		end
		if Profile.owns(profile, choice) then
			return false, "Hast du schon"
		end
		local maxPrice = (grant :: any).maxPrice
		if maxPrice and price > maxPrice then
			return false, "Falsche Preisstufe"
		end
		return true, nil
	end
	local g = grant :: any
	local skin = Cosmetics.skin(choice)
	if skin == nil or (skin :: Cosmetics.Skin).coins == nil then
		return false, "Skin nicht im Shop"
	end
	if Profile.ownsCosmetic(profile, choice) then
		return false, "Hast du schon"
	end
	local coins = (skin :: Cosmetics.Skin).coins :: number
	if coins < g.minPrice or coins > g.maxPrice then
		return false, "Falsche Preisstufe"
	end
	return true, nil
end

-- Player-specific limits: once per account, only in the first hours after the first join.
function Purchases.canOffer(profile: Profile.Profile, product: Products.DevProduct, now: number): (boolean, string?)
	if product.oncePerAccount and (profile.entitlements[`once:{product.id}`] or 0) > 0 then
		return false, "Schon gekauft"
	end
	local window = product.windowHours
	if window and (profile.firstSeen <= 0 or now - profile.firstSeen > window * 3600) then
		return false, "Angebot abgelaufen"
	end
	return true, nil
end

local function voucherKey(kind: string, maxPrice: number?): string
	return `{kind}:{if maxPrice then tostring(maxPrice) else "any"}`
end

local function addVoucher(profile: Profile.Profile, key: string)
	profile.vouchers[key] = (profile.vouchers[key] or 0) + 1
end

local function addEntitlement(profile: Profile.Profile, key: string, amount: number)
	profile.entitlements[key] = (profile.entitlements[key] or 0) + amount
end

-- Applies one grant. Returns a short line for the player.
local function applyGrant(profile: Profile.Profile, product: Products.DevProduct, grant: Products.Grant): string
	local g = grant :: any
	if grant.kind == "coins" then
		profile.coins += g.amount
		return `+{g.amount} Münzen`
	elseif grant.kind == "skin" then
		local skin = Cosmetics.skin(g.id)
		if skin == nil then
			return ""
		end
		profile.cosmetics[g.id] = true
		return `Skin {(skin :: Cosmetics.Skin).name}`
	elseif grant.kind == "fighterChoice" then
		local choice = profile.choices[product.id]
		if choice and Purchases.validChoice(profile, product, choice) then
			profile.unlocked[choice] = true
			return `Kämpfer freigeschaltet`
		end
		addVoucher(profile, voucherKey("fighter", g.maxPrice))
		return "Kämpfer-Gutschein"
	elseif grant.kind == "skinChoice" then
		local choice = profile.choices[product.id]
		if choice and Purchases.validChoice(profile, product, choice) then
			profile.cosmetics[choice] = true
			return `Skin {(Cosmetics.skin(choice) :: Cosmetics.Skin).name}`
		end
		addVoucher(profile, voucherKey("skin", g.maxPrice))
		return "Skin-Gutschein"
	elseif grant.kind == "bundle" then
		local bundle = (Products.BUNDLES :: any)[g.id]
		if bundle == nil then
			return ""
		end
		for _, id in bundle.skins or {} do
			if Cosmetics.skin(id) then
				profile.cosmetics[id] = true
			end
		end
		for _, id in bundle.arenas or {} do
			profile.items[`arena:{id}`] = true
		end
		for _, id in bundle.weapons or {} do
			profile.items[`weapon:{id}`] = true
		end
		return "Paket"
	elseif grant.kind == "seasonPremium" then
		addEntitlement(profile, "seasonPremium", 1)
		return "Ruhmespfad Premium"
	elseif grant.kind == "seasonTiers" then
		addEntitlement(profile, "seasonTiers", g.amount)
		return `+{g.amount} Stufen`
	elseif grant.kind == "adventureRevive" then
		addEntitlement(profile, "adventureRevive", 1)
		return "Abenteuer-Rettung"
	end
	return ""
end

-- Drops the oldest receipt ids above Profile.MAX_PURCHASES.
local function prune(profile: Profile.Profile)
	local list: { { id: string, at: number } } = {}
	for id, at in profile.purchases do
		table.insert(list, { id = id, at = at })
	end
	if #list <= Profile.MAX_PURCHASES then
		return
	end
	table.sort(list, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.id < b.id
	end)
	for k = 1, #list - Profile.MAX_PURCHASES do
		profile.purchases[list[k].id] = nil
	end
end

-- Applies a receipt once: the PurchaseId is recorded first, so a second callback for the same receipt (Roblox
-- retries until it gets PurchaseGranted) changes nothing. Returns false if the receipt was already applied.
function Purchases.applyReceipt(
	profile: Profile.Profile,
	product: Products.DevProduct,
	purchaseId: string,
	now: number
): (boolean, string)
	if profile.purchases[purchaseId] ~= nil then
		return false, ""
	end
	profile.purchases[purchaseId] = now
	local lines: { string } = {}
	for _, grant in product.grants do
		local line = applyGrant(profile, product, grant)
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	profile.choices[product.id] = nil
	if product.oncePerAccount then
		addEntitlement(profile, `once:{product.id}`, 1)
	end
	prune(profile)
	return true, `{product.name}: {table.concat(lines, ", ")}`
end

-- Remembers the player's pick for a choice product (validated), right before the purchase dialog opens.
-- An empty pick on a choice product is allowed: the purchase then gives a voucher to redeem later.
function Purchases.choose(profile: Profile.Profile, product: Products.DevProduct, choice: string): (boolean, string?)
	if choice == "" and Purchases.choiceGrant(product) then
		profile.choices[product.id] = nil
		return true, nil
	end
	local ok, reason = Purchases.validChoice(profile, product, choice)
	if not ok then
		return false, reason
	end
	if Purchases.choiceGrant(product) then
		profile.choices[product.id] = choice
	end
	return true, nil
end

-- The cheapest voucher of `kind` that covers `price` (key), or nil.
function Purchases.voucherFor(profile: Profile.Profile, kind: string, price: number): string?
	local best, bestMax = nil, math.huge
	for key, count in profile.vouchers do
		local k, max = string.match(key, "^(%a+):(%w+)$")
		if k == kind and count > 0 and max then
			local limit = if max == "any" then math.huge else tonumber(max) or -1
			if price <= limit and (best == nil or limit < bestMax) then
				best, bestMax = key, limit
			end
		end
	end
	return best
end

-- Redeems a voucher: kind "fighter" (unlocks the fighter) or "skin" (owns the skin).
function Purchases.redeem(profile: Profile.Profile, kind: string, id: string): (boolean, string?)
	local price: number?
	if kind == "fighter" then
		price = fighterPrice(id)
		if price == nil then
			return false, "Kämpfer nicht im Shop"
		end
		if Profile.owns(profile, id) then
			return false, "Hast du schon"
		end
	elseif kind == "skin" then
		local skin = Cosmetics.skin(id)
		if skin == nil or (skin :: Cosmetics.Skin).coins == nil then
			return false, "Skin nicht im Shop"
		end
		if Profile.ownsCosmetic(profile, id) then
			return false, "Hast du schon"
		end
		price = (skin :: Cosmetics.Skin).coins
	else
		return false, "Unbekannt"
	end
	local found = Purchases.voucherFor(profile, kind, price :: number)
	if found == nil then
		return false, "Kein passender Gutschein"
	end
	local key = found :: string
	local left = (profile.vouchers[key] :: number) - 1;
	(profile.vouchers :: any)[key] = if left > 0 then left else nil
	if kind == "fighter" then
		profile.unlocked[id] = true
	else
		profile.cosmetics[id] = true
	end
	return true, nil
end

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end
Purchases.thousands = thousands

-- Exactly what a product gives, as the shop shows it (German). Every grant kind has a line (tests check it).
function Purchases.describe(product: Products.GamePass | Products.DevProduct): string
	local grants = (product :: any).grants
	if grants == nil then
		local pass = product :: Products.GamePass
		local lines: { string } = {}
		for _, perk in pass.perks do
			table.insert(lines, Products.PERK_TEXT[perk] or perk)
		end
		if pass.coinBonus then
			table.insert(lines, `+{math.floor(pass.coinBonus * 100 + 0.5)} % Münzen aus Kämpfen`)
		end
		if pass.xpBonus then
			table.insert(lines, `+{math.floor(pass.xpBonus * 100 + 0.5)} % XP aus Kämpfen`)
		end
		return table.concat(lines, " · ")
	end
	local lines: { string } = {}
	for _, grant in grants :: { Products.Grant } do
		local g = grant :: any
		if grant.kind == "coins" then
			table.insert(lines, `{thousands(g.amount)} Münzen`)
		elseif grant.kind == "skin" then
			local skin = Cosmetics.skin(g.id)
			table.insert(lines, `Skin {if skin then skin.name else g.id}`)
		elseif grant.kind == "fighterChoice" then
			table.insert(
				lines,
				if g.maxPrice
					then `1 Kämpfer deiner Wahl (Münzpreis {thousands(g.maxPrice)})`
					else "1 Kämpfer deiner Wahl"
			)
		elseif grant.kind == "skinChoice" then
			table.insert(lines, "1 Skin deiner Wahl aus dieser Preisstufe")
		elseif grant.kind == "bundle" then
			local bundle = (Products.BUNDLES :: any)[g.id] or {}
			local names: { string } = {}
			for _, id in bundle.skins or {} do
				local skin = Cosmetics.skin(id)
				table.insert(names, if skin then skin.name else id)
			end
			if bundle.arenas then
				table.insert(names, `{#bundle.arenas} Arenen`)
			end
			if bundle.weapons then
				table.insert(names, `{#bundle.weapons} Waffen`)
			end
			table.insert(lines, table.concat(names, ", "))
		elseif grant.kind == "seasonPremium" then
			table.insert(lines, "Premium-Spur der Saison")
		elseif grant.kind == "seasonTiers" then
			table.insert(lines, `{g.amount} Ruhmespfad-Stufen`)
		elseif grant.kind == "adventureRevive" then
			table.insert(lines, "1× Weiterspielen im Solo-Abenteuer")
		end
	end
	local dev = product :: Products.DevProduct
	if dev.oncePerAccount then
		table.insert(lines, "einmal pro Konto")
	end
	if dev.windowHours then
		table.insert(lines, `nur in den ersten {dev.windowHours} h`)
	end
	return table.concat(lines, " + ")
end

-- Additive match bonuses from owned game passes (Progression.matchCoins adds them up).
function Purchases.passBonuses(owned: { [string]: boolean }): ({ number }, number)
	local coins: { number } = {}
	local xp = 0
	for _, pass in Products.GAME_PASSES do
		if owned[pass.id] then
			if pass.coinBonus then
				table.insert(coins, pass.coinBonus)
			end
			xp += pass.xpBonus or 0
		end
	end
	return coins, xp
end

return Purchases
