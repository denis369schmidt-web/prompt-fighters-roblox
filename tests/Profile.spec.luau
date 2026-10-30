local Profile = require(Shared.Meta.Profile)
local Progression = require(Shared.Data.Progression)

local function stats(edit: ((s: any) -> ())?)
	local s = { won = false, place = 3, kos = 0, damage = 0, finishers = 0, stocksLost = 3, bestCombo = 0 }
	if edit then
		edit(s)
	end
	return s
end

describe("Profile", function()
	it("starts with coins, level 1 and the starter fighters", function()
		local p = Profile.new()
		expect(p.level).toBe(1)
		expect(p.coins).toBe(Profile.START_COINS)
		expect(Profile.owns(p, "ninja")).toBe(true)
		expect(Profile.owns(p, "dragon")).toBe(false)
		expect(Profile.owns(p, "does_not_exist")).toBe(false)
	end)

	it("repairs old or broken saves instead of failing", function()
		local p = Profile.migrate({ coins = "lots", level = 4, unlocked = { dragon = true }, extra = 1 })
		expect(p.coins).toBe(Profile.START_COINS)
		expect(p.level).toBe(4)
		expect(Profile.owns(p, "dragon")).toBe(true)
		expect(Profile.migrate(nil).level).toBe(1)
	end)

	it("pays more for a good win than for a quick loss", function()
		local loss = Profile.applyMatch(Profile.new(), "ninja", stats())
		local win = Profile.applyMatch(
			Profile.new(),
			"ninja",
			stats(function(s)
				s.won, s.place, s.kos, s.damage, s.finishers, s.stocksLost = true, 1, 4, 320, 1, 1
			end)
		)
		expect(loss.xp).toBeGreaterThan(0)
		expect(loss.coins).toBeGreaterThan(0)
		expect(win.xp).toBeGreaterThan(loss.xp)
		expect(win.coins).toBeGreaterThan(loss.coins)
		expect(win.grade).toBe("S")
		expect(loss.grade).toBe("D")
	end)

	it("levels up and carries the extra XP over", function()
		local p = Profile.new()
		Profile.addXp(p, Progression.xpToNext(1) + 10)
		expect(p.level).toBe(2)
		expect(p.xp).toBe(10)
	end)

	it("unlocks the cheapest locked fighter every third win", function()
		local p = Profile.new()
		local won = stats(function(s)
			s.won, s.place = true, 1
		end)
		expect(Profile.applyMatch(p, "ninja", won).unlockedFighter).toBeNil()
		expect(Profile.applyMatch(p, "ninja", won).unlockedFighter).toBeNil()
		local third = Profile.applyMatch(p, "ninja", won)
		expect(third.unlockedFighter ~= nil).toBe(true)
		expect(Profile.owns(p, third.unlockedFighter)).toBe(true)
		expect(Profile.price(third.unlockedFighter)).toBe(600)
	end)

	it("buys a fighter only with enough coins", function()
		local p = Profile.new()
		local ok, reason = Profile.buyFighter(p, "dragon")
		expect(ok).toBe(false)
		assert(string.find(reason, "fehlen"), reason)
		p.coins = 1000
		expect((Profile.buyFighter(p, "dragon"))).toBe(true)
		expect(p.coins).toBe(400)
		expect(Profile.owns(p, "dragon")).toBe(true)
		expect((Profile.buyFighter(p, "dragon"))).toBe(false)
		expect((Profile.buyFighter(p, "ninja"))).toBe(false)
	end)

	it("pays the login calendar once a day and restarts after a missed day", function()
		local p = Profile.new()
		local coins, day = Profile.dailyLogin(p, 100)
		expect(day).toBe(1)
		expect(coins).toBe(Progression.LOGIN_CALENDAR[1])
		expect((Profile.dailyLogin(p, 100))).toBe(0)
		local _, day2 = Profile.dailyLogin(p, 101)
		expect(day2).toBe(2)
		local _, day3 = Profile.dailyLogin(p, 105)
		expect(day3).toBe(1)
	end)

	it("shows owned launch fighters and the wins left to the next free unlock", function()
		local view = Profile.view(Profile.new())
		expect(#view.owned).toBe(10)
		expect(view.winsToUnlock).toBe(Progression.WINS_PER_FIGHTER_UNLOCK)
	end)
end)
