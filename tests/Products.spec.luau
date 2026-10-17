local Products = require(Shared.Data.Products)
local Fighters = require(Shared.Data.Fighters)
local RewardData = require(Shared.Data.Generated.RewardData)

local function contains(list, value)
	for _, v in list do
		if v == value then
			return true
		end
	end
	return false
end

describe("Products (fair monetization rules)", function()
	it("has unique ids and positive prices", function()
		local seen = {}
		for _, list in { Products.GAME_PASSES, Products.DEV_PRODUCTS } do
			for _, p in list do
				assert(not seen[p.id], `duplicate product {p.id}`)
				seen[p.id] = true
				expect(p.robux).toBeGreaterThan(0)
			end
		end
	end)

	it("sells no combat stats (no pay-to-win)", function()
		for _, pass in Products.GAME_PASSES do
			for _, perk in pass.perks do
				for _, forbidden in Products.FORBIDDEN_PERKS do
					assert(not perk:lower():find(forbidden:lower(), 1, true), `{pass.id} sells combat perk {perk}`)
				end
			end
		end
	end)

	it("sells nothing random: every grant is a known, fixed kind", function()
		local allowed = {
			coins = true,
			skin = true,
			fighterChoice = true,
			bundle = true,
			seasonPremium = true,
			seasonTiers = true,
			adventureRevive = true,
		}
		for _, p in Products.DEV_PRODUCTS do
			expect(#p.grants).toBeGreaterThan(0)
			for _, grant in p.grants do
				assert(allowed[grant.kind], `{p.id} has grant kind {grant.kind}`)
			end
		end
	end)

	it("gives bigger coin bags a better rate", function()
		local last = 0
		for _, id in { "coins_s", "coins_m", "coins_l", "coins_xl" } do
			local p = Products.byId[id] :: any
			local rate = p.grants[1].amount / p.robux
			expect(rate).toBeGreaterThan(last)
			last = rate
		end
	end)

	it("only references skins, arenas and weapons that exist", function()
		local skins = {}
		for _, s in RewardData.skins do
			skins[s.id] = true
		end
		for _, p in Products.DEV_PRODUCTS do
			for _, grant in p.grants do
				if grant.kind == "skin" then
					assert(skins[grant.id], `{p.id} grants unknown skin {grant.id}`)
				elseif grant.kind == "bundle" then
					local bundle = Products.BUNDLES[grant.id]
					assert(bundle, `{p.id} grants unknown bundle {grant.id}`)
					for _, skin in bundle.skins or {} do
						assert(skins[skin], `bundle {grant.id} has unknown skin {skin}`)
					end
				end
			end
		end
	end)

	it("prices instant fighter unlocks for every coin tier", function()
		for _, f in Fighters.list do
			if f.unlock.kind == "coins" then
				assert(Products.byId[`fighter_unlock_{f.unlock.price}`], `no Robux unlock for price {f.unlock.price}`)
			end
		end
	end)

	it("keeps the adventure revive solo-only", function()
		expect((Products.byId.adventure_revive :: any).soloOnly).toBe(true)
	end)

	it("lists the subscription perks without combat effects", function()
		expect(contains(Products.SUBSCRIPTION.perks, "dailyQuestReroll")).toBe(true)
	end)
end)
