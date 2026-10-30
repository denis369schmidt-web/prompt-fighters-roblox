local GameFeel = require(Shared.Visual.GameFeel)

describe("GameFeel.impact", function()
	it("sorts hits into light, medium and heavy", function()
		expect(GameFeel.impact(3, 4).tier).toBe("light")
		expect(GameFeel.impact(9, 8).tier).toBe("medium")
		expect(GameFeel.impact(18, 16).tier).toBe("heavy")
	end)

	it("treats a strong launch as heavy even with little damage", function()
		expect(GameFeel.impact(4, 17).tier).toBe("heavy")
	end)

	it("makes super hits stronger", function()
		expect(GameFeel.strength(8, 6, true)).toBeGreaterThan(GameFeel.strength(8, 6, false))
	end)

	it("holds no picture for light hits and 50-120 ms for the rest", function()
		expect(GameFeel.impact(2, 3).hold).toBe(0)
		local medium = GameFeel.impact(9, 8).hold
		local heavy = GameFeel.impact(25, 19, false, true).hold
		expect(medium).toBeGreaterThanOrEqual(0.05)
		expect(heavy).toBeLessThanOrEqual(0.12)
		expect(heavy).toBeGreaterThan(medium)
	end)

	it("gives more trauma to stronger hits, never above 1", function()
		local light, heavy = GameFeel.impact(3, 2), GameFeel.impact(40, 30, true)
		expect(heavy.trauma).toBeGreaterThan(light.trauma)
		expect(heavy.trauma).toBeLessThanOrEqual(1)
	end)
end)

describe("GameFeel trauma and shake", function()
	it("clamps added trauma and decays to zero", function()
		expect(GameFeel.addTrauma(0.9, 0.5)).toBe(1)
		local t = 1
		for _ = 1, 120 do
			t = GameFeel.decayTrauma(t, 1 / 60)
		end
		expect(t).toBe(0)
	end)

	it("does not shake without trauma or with the shake setting off", function()
		local x, y, r = GameFeel.shake(0, 1.234, 1)
		expect(x).toBe(0)
		expect(y).toBe(0)
		expect(r).toBe(0)
		x, y, r = GameFeel.shake(1, 1.234, 0)
		expect(x + y + r).toBe(0)
	end)

	it("keeps the shake inside its limits", function()
		local tu = GameFeel.TUNING
		for k = 1, 200 do
			local x, y, r = GameFeel.shake(1, k * 0.037, 1)
			expect(math.abs(x)).toBeLessThanOrEqual(tu.shakeTranslate * 2 + 1e-6)
			expect(math.abs(y)).toBeLessThanOrEqual(tu.shakeTranslate * 2 + 1e-6)
			expect(math.abs(r)).toBeLessThanOrEqual(tu.shakeRoll * 2 + 1e-6)
		end
	end)

	it("shakes less with reduced shake", function()
		local sumFull, sumHalf = 0, 0
		for k = 1, 50 do
			local x = GameFeel.shake(0.8, k * 0.05, 1)
			local h = GameFeel.shake(0.8, k * 0.05, 0.5)
			sumFull += math.abs(x)
			sumHalf += math.abs(h)
		end
		expect(sumHalf).toBeLessThan(sumFull)
	end)
end)

describe("GameFeel.spring", function()
	it("settles a kick back to rest", function()
		local v, vel = 1, 0
		for _ = 1, 120 do
			v, vel = GameFeel.spring(v, vel, 1 / 60)
		end
		expect(math.abs(v)).toBeLessThan(0.01)
	end)

	it("stays stable on a long frame", function()
		local v, vel = GameFeel.spring(1, 0, 0.5)
		expect(math.abs(v)).toBeLessThan(1.5)
		expect(vel == vel).toBe(true)
	end)
end)

describe("GameFeel visuals", function()
	it("colors chip damage white and big damage red", function()
		local r, g, b = GameFeel.damageColor(0)
		expect(r + g + b).toBe(3)
		local r2, g2 = GameFeel.damageColor(22)
		expect(r2).toBeGreaterThan(g2 + 0.5)
		local r3, g3, b3 = GameFeel.damageColor(500)
		expect(r3).toBeLessThanOrEqual(1)
		expect(g3).toBeGreaterThanOrEqual(0)
		expect(b3).toBeGreaterThanOrEqual(0)
	end)

	it("pops big numbers bigger", function()
		expect(GameFeel.damageScale(20)).toBeGreaterThan(GameFeel.damageScale(3))
	end)

	it("names combos from two hits", function()
		expect(GameFeel.comboText(1)).toBeNil()
		expect(GameFeel.comboText(3)).toBe("3 HIT COMBO")
	end)

	it("aims the KO beam back toward the stage", function()
		local x, y = GameFeel.koDirection(16, 2)
		expect(x).toBeCloseTo(-1, 4)
		expect(y).toBeCloseTo(0, 4)
		local _, up = GameFeel.koDirection(0, -6)
		expect(up).toBeCloseTo(1, 4)
		local ux, uy = GameFeel.koDirection(-12, 13)
		expect(ux * ux + uy * uy).toBeCloseTo(1, 4)
	end)

	it("runs slow motion and eases back to normal speed", function()
		expect(GameFeel.slowScale(0.1, 1, 0.25)).toBe(0.25)
		local late = GameFeel.slowScale(0.9, 1, 0.25)
		expect(late).toBeGreaterThan(0.25)
		expect(late).toBeLessThan(1)
		expect(GameFeel.slowScale(1.2, 1, 0.25)).toBe(1)
	end)
end)
