--!strict
-- Everything sold for Robux. Prices are starting values (docs/ECONOMY.md explains each one).
-- assetId = 0 until the product exists in the Creator Dashboard; ShopService refuses to sell products with id 0.
-- Rules enforced by tests (tests/Products.spec.luau):
--   * nothing here changes combat values (no pay-to-win)
--   * nothing is random: every product lists exactly what it grants
--   * Ranked never sees paid content that matters in a fight (start weapons are blocked there anyway)

export type Grant =
	{ kind: "coins", amount: number }
	| { kind: "fighter", choice: true }
	| { kind: "skin", id: string }
	| { kind: "skinChoice", minPrice: number, maxPrice: number }
	| { kind: "fighterChoice" }
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
}

local Products = {}

Products.GAME_PASSES = {
	{
		id = "vip",
		name = "VIP",
		robux = 399,
		assetId = 0,
		coinBonus = 0.1,
		perks = { "goldName", "chatTag", "extraVote", "vipLounge", "vipVictoryPose" },
	},
	{ id = "double_coins", name = "Doppelte Münzen", robux = 349, assetId = 0, coinBonus = 1.0, perks = {} },
	{ id = "double_xp", name = "Doppelte XP", robux = 299, assetId = 0, xpBonus = 1.0, perks = {} },
	{
		id = "finisher_cinema",
		name = "Finisher-Kino Plus",
		robux = 249,
		assetId = 0,
		perks = { "altFinisherCameras", "finisherReplayClip" },
	},
	{ id = "armory", name = "Waffenkammer", robux = 299, assetId = 0, perks = { "allShopWeapons" } },
	{ id = "arena_collection", name = "Arena-Sammlung", robux = 499, assetId = 0, perks = { "allArenas" } },
	{
		id = "prompt_lab_plus",
		name = "Prompt-Labor Plus",
		robux = 199,
		assetId = 0,
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
		grants = { { kind = "fighterChoice" } },
	},
	{
		id = "fighter_unlock_900",
		name = "Kämpfer sofort (Stufe 2)",
		robux = 199,
		assetId = 0,
		grants = { { kind = "fighterChoice" } },
	},
	{
		id = "fighter_unlock_1200",
		name = "Kämpfer sofort (Stufe 3)",
		robux = 299,
		assetId = 0,
		grants = { { kind = "fighterChoice" } },
	},
	{
		id = "bundle_neon_nights",
		name = "NEON-NÄCHTE",
		robux = 399,
		assetId = 0,
		grants = { { kind = "bundle", id = "neon_nights" } },
	},
	{
		id = "bundle_heaven_hell",
		name = "HIMMEL & HÖLLE",
		robux = 599,
		assetId = 0,
		grants = { { kind = "bundle", id = "heaven_hell" } },
	},
	{
		id = "adventure_revive",
		name = "Abenteuer-Rettung",
		robux = 25,
		assetId = 0,
		soloOnly = true,
		grants = { { kind = "adventureRevive" } },
	},
	{
		id = "season_premium",
		name = "Ruhmespfad Premium",
		robux = 499,
		assetId = 0,
		grants = { { kind = "seasonPremium" } },
	},
	{
		id = "season_premium_plus",
		name = "Ruhmespfad Premium+ (inkl. 15 Stufen)",
		robux = 899,
		assetId = 0,
		grants = { { kind = "seasonPremium" }, { kind = "seasonTiers", amount = 15 } },
	},
	{
		id = "season_tiers_10",
		name = "Ruhmespfad +10 Stufen",
		robux = 199,
		assetId = 0,
		grants = { { kind = "seasonTiers", amount = 10 } },
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

Products.byId = {} :: { [string]: GamePass | DevProduct }
for _, list in { Products.GAME_PASSES, Products.DEV_PRODUCTS } :: { any } do
	for _, product in list do
		Products.byId[product.id] = product
	end
end

return Products
