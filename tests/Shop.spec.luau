local Profile = require(Shared.Meta.Profile)
local Purchases = require(Shared.Meta.Purchases)
local Products = require(Shared.Data.Products)
local Cosmetics = require(Shared.Data.Cosmetics)

local NOW = 1793664000 -- 2026-11-02

local function product(id)
	return Products.byId[id]
end

describe("Profile v3 (cosmetics)", function()
	it("migrates a v2 save with empty shop fields", function()
		local p =
			Profile.migrate({ version = 2, coins = 900, level = 3, promptFighters = {}, unlocked = { dragon = true } })
		expect(p.version).toBe(3)
		expect(p.coins).toBe(900)
		expect(next(p.cosmetics)).toBe(nil)
		expect(p.equippedKo).toBe("")
		expect(p.equippedPlate).toBe("")
		expect(next(p.purchases)).toBe(nil)
		expect(p.firstSeen).toBe(0)
		expect(Profile.owns(p, "dragon")).toBe(true)
	end)

	it("drops unknown cosmetics, broken entries and equipped items the player does not own", function()
		local p = Profile.migrate({
			cosmetics = { ninja_jade = true, made_up = true, gold = "yes", ko_nova = true },
			equippedSkins = { ninja = "ninja_jade", golem = "golem_moss", valkyrie = "ninja_jade", zip = 5 },
			equippedKo = "ko_nova",
			equippedPlate = "plate_gold",
			purchases = { abc = 12, bad = "x", [3] = 4 },
			vouchers = { ["skin:400"] = 1, ["skin:800"] = 0 },
		})
		expect(p.cosmetics.ninja_jade).toBe(true)
		expect(p.cosmetics.made_up).toBe(nil)
		expect(p.cosmetics.gold).toBe(nil)
		expect(p.equippedSkins.ninja).toBe("ninja_jade")
		expect(p.equippedSkins.golem).toBe(nil) -- not owned
		expect(p.equippedSkins.valkyrie).toBe(nil) -- another fighter's skin
		expect(p.equippedKo).toBe("ko_nova")
		expect(p.equippedPlate).toBe("") -- not owned
		expect(p.purchases.abc).toBe(12)
		expect(p.purchases.bad).toBe(nil)
		expect(p.vouchers["skin:400"]).toBe(1)
		expect(p.vouchers["skin:800"]).toBe(nil)
		-- Migrating twice changes nothing.
		local again = Profile.migrate(p)
		expect(again.equippedSkins.ninja).toBe("ninja_jade")
		expect(again.purchases.abc).toBe(12)
	end)

	it("buys cosmetics with coins once and only with enough coins", function()
		local p = Profile.new()
		p.coins = 1000
		local ok, why = Profile.buyCosmetic(p, "ninja_jade")
		expect(ok).toBe(true)
		expect(p.coins).toBe(1000 - Cosmetics.skin("ninja_jade").coins)
		ok, why = Profile.buyCosmetic(p, "ninja_jade")
		expect(ok).toBe(false)
		expect(why).toBe("Hast du schon")
		expect((Profile.buyCosmetic(p, "galaxy"))).toBe(false) -- not enough coins
		expect((Profile.buyCosmetic(p, "celestial"))).toBe(false) -- earned on the path, not sold
		expect((Profile.buyCosmetic(p, "ko_classic"))).toBe(false)
	end)

	it("equips only owned, fitting cosmetics and resets to the default", function()
		local p = Profile.new()
		expect((Profile.equip(p, "skin", "ninja", "ninja_jade"))).toBe(false)
		p.cosmetics.ninja_jade = true
		p.cosmetics.gold = true
		expect((Profile.equip(p, "skin", "golem", "ninja_jade"))).toBe(false)
		expect((Profile.equip(p, "skin", "ninja", "ninja_jade"))).toBe(true)
		expect(Profile.equippedSkin(p, "ninja")).toBe("ninja_jade")
		expect((Profile.equip(p, "skin", "golem", "gold"))).toBe(true) -- material skins fit everyone
		expect((Profile.equip(p, "skin", "ninja", ""))).toBe(true)
		expect(Profile.equippedSkin(p, "ninja")).toBe(nil)
		expect((Profile.equip(p, "ko", "", "ko_void"))).toBe(false)
		expect((Profile.equip(p, "ko", "", "ko_classic"))).toBe(true)
		expect(Profile.equippedKoEffect(p)).toBe(nil)
		expect((Profile.equip(p, "plate", "", "ko_classic"))).toBe(false)
		expect((Profile.equip(p, "skin", "not_a_fighter", "gold"))).toBe(false)
		expect(Profile.view(p).equippedKo).toBe("ko_classic")
	end)

	it("shows an equipped name plate instead of the level title", function()
		local p = Profile.new()
		p.cosmetics.plate_gold = true
		Profile.equip(p, "plate", "", "plate_gold")
		local view = Profile.view(p)
		expect(view.title).toBe("Goldene Faust")
		expect(view.frame).toBe("#FFD24A")
	end)

	it("adds game pass XP and coin bonuses without doubling coins through XP", function()
		local stats = { won = true, place = 1, kos = 2, damage = 150, finishers = 0, stocksLost = 1, bestCombo = 3 }
		local plain = Profile.applyMatch(Profile.new(), "ninja", stats)
		local coinBonus, xpBonus = Purchases.passBonuses({ double_xp = true })
		local xp = Profile.applyMatch(Profile.new(), "ninja", stats, coinBonus, xpBonus)
		expect(xp.xp).toBe(plain.xp * 2)
		expect(xp.coins).toBe(plain.coins)
		local coins = Profile.applyMatch(Profile.new(), "ninja", stats, Purchases.passBonuses({ double_coins = true }))
		expect(coins.coins).toBeGreaterThan(plain.coins)
	end)
end)

describe("Purchases (ProcessReceipt rules)", function()
	it("grants a receipt exactly once, also when Roblox calls twice", function()
		local p = Profile.new()
		local bag = product("coins_m")
		local first = Purchases.applyReceipt(p, bag, "receipt-1", NOW)
		local second = Purchases.applyReceipt(p, bag, "receipt-1", NOW + 5)
		expect(first).toBe(true)
		expect(second).toBe(false)
		expect(p.coins).toBe(Profile.START_COINS + 1700)
		expect(p.purchases["receipt-1"]).toBe(NOW)
		Purchases.applyReceipt(p, bag, "receipt-2", NOW)
		expect(p.coins).toBe(Profile.START_COINS + 3400)
	end)

	it("gives the picked skin, or a voucher of the same step if the pick is gone", function()
		local p = Profile.new()
		local tier = product("skin_robux_199")
		expect((Purchases.choose(p, tier, "ninja_jade"))).toBe(true) -- 700 coins
		expect((Purchases.choose(p, tier, "ninja_bloodmoon"))).toBe(false) -- 400: other step
		Purchases.applyReceipt(p, tier, "r1", NOW)
		expect(p.cosmetics.ninja_jade).toBe(true)
		expect(p.choices.skin_robux_199).toBe(nil)
		-- Pick something, then own it before the receipt arrives: voucher instead.
		Purchases.choose(p, tier, "golem_glacier")
		p.cosmetics.golem_glacier = true
		Purchases.applyReceipt(p, tier, "r2", NOW)
		expect(p.vouchers["skin:800"]).toBe(1)
		expect((Purchases.redeem(p, "skin", "galaxy"))).toBe(false) -- 1500 > 800
		expect((Purchases.redeem(p, "skin", "kairo_storm"))).toBe(true)
		expect(p.cosmetics.kairo_storm).toBe(true)
		expect(p.vouchers["skin:800"]).toBe(nil)
	end)

	it("unlocks the picked fighter of the right price step", function()
		local p = Profile.new()
		local unlock = product("fighter_unlock_600")
		local locked = Profile.nextLocked(p)
		expect((Purchases.choose(p, unlock, locked))).toBe(true)
		Purchases.applyReceipt(p, unlock, "f1", NOW)
		expect(Profile.owns(p, locked)).toBe(true)
		expect((Purchases.choose(p, unlock, "ninja"))).toBe(false) -- starter, owned
	end)

	it("sells the starter pack once, in the first 72 hours, with a voucher if nothing was picked", function()
		local p = Profile.new()
		local starter = product("starter_pack")
		expect((Purchases.canOffer(p, starter, NOW))).toBe(false) -- first join unknown
		p.firstSeen = NOW
		expect((Purchases.canOffer(p, starter, NOW + 71 * 3600))).toBe(true)
		expect((Purchases.canOffer(p, starter, NOW + 73 * 3600))).toBe(false)
		expect((Purchases.choose(p, starter, ""))).toBe(true)
		Purchases.applyReceipt(p, starter, "s1", NOW + 3600)
		expect(p.coins).toBe(Profile.START_COINS + 1000)
		expect(p.cosmetics.chrome).toBe(true)
		expect(p.vouchers["fighter:any"]).toBe(1)
		expect((Purchases.canOffer(p, starter, NOW + 7200))).toBe(false)
		local fighter = Profile.nextLocked(p)
		expect((Purchases.redeem(p, "fighter", fighter))).toBe(true)
		expect(Profile.owns(p, fighter)).toBe(true)
	end)

	it("keeps the receipt list bounded, oldest first out", function()
		local p = Profile.new()
		for k = 1, Profile.MAX_PURCHASES + 10 do
			Purchases.applyReceipt(p, product("coins_s"), `r{k}`, NOW + k)
		end
		local count = 0
		for _ in p.purchases do
			count += 1
		end
		expect(count).toBe(Profile.MAX_PURCHASES)
		expect(p.purchases.r1).toBe(nil)
		expect(p.purchases[`r{Profile.MAX_PURCHASES + 10}`]).toBe(NOW + Profile.MAX_PURCHASES + 10)
	end)
end)
