--!strict
-- Everything sold for Robux. Prices are starting values (docs/ECONOMY.md explains each one).
-- assetId = 0 until the product exists in the Creator Dashboard; ShopService refuses to sell products with id 0
-- and the shop shows "Bald verfügbar" for them. comingSoon = the content is not built yet (also not sold), so
-- nobody can pay for something the game cannot deliver yet.
-- Rules enforced by tests (tests/Products.spec.luau):
--   * nothing here changes combat values (no pay-to-win)
--   * nothing is random: every product lists exactly what it grants
--   * Ranked never sees paid content that matters in a fight (start weapons are blocked there anyway)

export type Grant =
	{ kind: "coins", amount: number }
	| { kind: "skin", id: string }
	| { kind: "skinChoice", minPrice: number, maxPrice: number } -- a skin the player picks (coin price in range)
	| { kind: "fighterChoice", maxPrice: number? } -- a fighter the player picks before buying (nil = any price)
	| { kind: "bundle", id: string }
	| { kind: "seasonPremium" }
	| { kind: "seasonTiers", amount: number }
	| { kind: "adventureRevive" }
	| { kind: "gift" }

export type GamePass = {
	id: string,
	name: string,
	robux: number,
	assetId: number,
	perks: { string },
	coinBonus: number?, -- additive multiplier bonus on match coins, e.g. 1.0 = +100 %
	xpBonus: number?,
	comingSoon: boolean?,
}

export type DevProduct = {
	id: string,
	name: string,
	robux: number,
	assetId: number,
	grants: { Grant },
	oncePerAccount: boolean?,
	windowHours: number?, -- only offered this many hours after the first join
	soloOnly: boolean?,
	comingSoon: boolean?,
}

local Products = {}

Products.GAME_PASSES = {
	{
		id = "vip",
		name = "VIP",
		robux = 399,
		assetId = 0,
		coinBonus = 0.1,
		comingSoon = true,
		perks = { "goldName", "chatTag", "extraVote", "vipLounge", "vipVictoryPose" },
	},
	{ id = "double_coins", name = "Doppelte Münzen", robux = 349, assetId = 0, coinBonus = 1.0, perks = {} },
	{ id = "double_xp", name = "Doppelte XP", robux = 299, assetId = 0, xpBonus = 1.0, perks = {} },
	{
		id = "finisher_cinema",
		name = "Finisher-Kino Plus",
		robux = 249,
		assetId = 0,
		comingSoon = true,
		perks = { "altFinisherCameras", "finisherReplayClip" },
	},
	{
		id = "armory",
		name = "Waffenkammer",
		robux = 299,
		assetId = 0,
		comingSoon = true,
		perks = { "allShopWeapons" },
	},
	{
		id = "arena_collection",
		name = "Arena-Sammlung",
		robux = 499,
		assetId = 0,
		comingSoon = true,
		perks = { "allArenas" },
	},
	{
		id = "prompt_lab_plus",
		name = "Prompt-Labor Plus",
		robux = 199,
		assetId = 0,
		comingSoon = true,
		perks = { "promptSlots10", "promptColorPick", "promptCustomCardName", "promptAuraStyles" },
	},
} :: { GamePass }

Products.DEV_PRODUCTS = {
	{ id = "coins_s", name = "Münzbeutel S", robux = 49, assetId = 0, grants = { { kind = "coins", amount = 500 } } },
	{
		id = "coins_m",
		name = "Münzbeutel M",
		robux = 149,
		assetId = 0,
		grants = { { kind = "coins", amount = 1700 } },
	},
	{
		id = "coins_l",
		name = "Münzbeutel L",
		robux = 399,
		assetId = 0,
		grants = { { kind = "coins", amount = 5000 } },
	},
	{
		id = "coins_xl",
		name = "Münzbeutel XL",
		robux = 899,
		assetId = 0,
		grants = { { kind = "coins", amount = 12000 } },
	},
	{
		id = "starter_pack",
		name = "Startpaket",
		robux = 99,
		assetId = 0,
		oncePerAccount = true,
		windowHours = 72,
		grants = { { kind = "fighterChoice" }, { kind = "coins", amount = 1000 }, { kind = "skin", id = "chrome" } },
	},
	{
		id = "fighter_unlock_600",
		name = "Kämpfer sofort (Stufe 1)",
		robux = 149,
		assetId = 0,
		grants = { { kind = "fighterChoice", maxPrice = 600 } },
	},
	{
		id = "fighter_unlock_900",
		name = "Kämpfer sofort (Stufe 2)",
		robux = 199,
		assetId = 0,
		grants = { { kind = "fighterChoice", maxPrice = 900 } },
	},
	{
		id = "fighter_unlock_1200",
		name = "Kämpfer sofort (Stufe 3)",
		robux = 299,
		assetId = 0,
		grants = { { kind = "fighterChoice", maxPrice = 1200 } },
	},
	{
		id = "bundle_neon_nights",
		name = "NEON-NÄCHTE",
		robux = 399,
		assetId = 0,
		comingSoon = true,
		grants = { { kind = "bundle", id = "neon_nights" } },
	},
	{
		id = "bundle_heaven_hell",
		name = "HIMMEL & HÖLLE",
		robux = 599,
		assetId = 0,
		comingSoon = true,
		grants = { { kind = "bundle", id = "heaven_hell" } },
	},
	{
		id = "adventure_revive",
		name = "Abenteuer-Rettung",
		robux = 25,
		assetId = 0,
		comingSoon = true,
		soloOnly = true,
		grants = { { kind = "adventureRevive" } },
	},
	{
		id = "season_premium",
		name = "Ruhmespfad Premium",
		robux = 499,
		assetId = 0,
		comingSoon = true,
		grants = { { kind = "seasonPremium" } },
	},
	{
		id = "season_premium_plus",
		name = "Ruhmespfad Premium+ (inkl. 15 Stufen)",
		robux = 899,
		assetId = 0,
		comingSoon = true,
		grants = { { kind = "seasonPremium" }, { kind = "seasonTiers", amount = 15 } },
	},
	{
		id = "season_tiers_10",
		name = "Ruhmespfad +10 Stufen",
		robux = 199,
		assetId = 0,
		comingSoon = true,
		grants = { { kind = "seasonTiers", amount = 10 } },
	},
	-- Skin direkt: one product per Robux price step; the player picks the skin before the purchase dialog opens
	-- (the choice is stored in the profile). If the choice is gone when the receipt arrives (owned by then), the
	-- player gets a voucher for any skin up to that coin price instead. Prices follow Products.skinRobux.
	{
		id = "skin_robux_99",
		name = "Skin direkt (bis 400 Münzen)",
		robux = 99,
		assetId = 0,
		grants = { { kind = "skinChoice", minPrice = 1, maxPrice = 400 } },
	},
	{
		id = "skin_robux_199",
		name = "Skin direkt (bis 800 Münzen)",
		robux = 199,
		assetId = 0,
		grants = { { kind = "skinChoice", minPrice = 401, maxPrice = 800 } },
	},
	{
		id = "skin_robux_299",
		name = "Skin direkt (bis 1 200 Münzen)",
		robux = 299,
		assetId = 0,
		grants = { { kind = "skinChoice", minPrice = 801, maxPrice = 1200 } },
	},
	{
		id = "skin_robux_449",
		name = "Skin direkt (über 1 200 Münzen)",
		robux = 449,
		assetId = 0,
		grants = { { kind = "skinChoice", minPrice = 1201, maxPrice = 100000 } },
	},
} :: { DevProduct }

-- Bundles: fixed contents, shown in full before purchase.
Products.BUNDLES = {
	neon_nights = {
		arenas = { "neon_skyline", "holo_metropolis", "cyber_stadium", "graffiti_alley", "night_market" },
		skins = { "neon", "galaxy" },
	},
	heaven_hell = { skins = { "marble", "obsidian", "ghost", "lava" }, weapons = { "soul_scythe", "dragon_lance" } },
}

-- Robux price of the direct skin purchase by coin price (rotation shop).
function Products.skinRobux(coinPrice: number): number
	if coinPrice <= 400 then
		return 99
	elseif coinPrice <= 800 then
		return 199
	elseif coinPrice <= 1200 then
		return 299
	end
	return 449
end

Products.SUBSCRIPTION = {
	id = "arena_patron",
	name = "Arena-Gönner",
	priceTier = "4.99 EUR",
	dailyCoins = 150,
	monthlySkin = true,
	perks = { "patronFrame", "dailyQuestReroll", "supporterTitle" },
}

Products.PRIVATE_SERVER_ROBUX_PER_MONTH = 100

-- Combat-relevant fields a product may never touch. Tests scan every product for them.
Products.FORBIDDEN_PERKS = { "damage", "knockback", "defense", "speed", "health", "superGain", "rankedWeapon" }

-- The "Skin direkt" product for a skin's coin price.
function Products.skinProductId(coinPrice: number): string
	return `skin_robux_{Products.skinRobux(coinPrice)}`
end

-- What each game-pass perk does, as the shop shows it (German, player-facing).
Products.PERK_TEXT = {
	goldName = "Goldener Name",
	chatTag = "Chat-Tag [VIP]",
	extraVote = "+1 Arena-Stimme (max. 3)",
	vipLounge = "VIP-Lounge in der Lobby",
	vipVictoryPose = "Exklusive Siegerpose",
	altFinisherCameras = "Alternative Finisher-Kameras",
	finisherReplayClip = "Finisher-Replay als Clip",
	allShopWeapons = "Alle 8 Shop-Waffen (nicht in Ranked)",
	allArenas = "Alle 22 Zusatz-Arenen",
	promptSlots10 = "10 statt 3 Prompt-Slots",
	promptColorPick = "Farbwahl für Prompt-Kämpfer",
	promptCustomCardName = "Eigener Kartenname",
	promptAuraStyles = "Aura-Stile",
} :: { [string]: string }

Products.byId = {} :: { [string]: GamePass | DevProduct }
for _, list in { Products.GAME_PASSES, Products.DEV_PRODUCTS } :: { any } do
	for _, product in list do
		Products.byId[product.id] = product
	end
end

return Products
