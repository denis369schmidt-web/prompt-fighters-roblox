local Seed = require(Shared.Util.Seed)

describe("Seed", function()
	it("matches the Godot prompt hash", function()
		expect(Seed.fromText("Eisgolem mit Frosthammer")).toBe(1473011350)
		expect(Seed.fromText("")).toBe(2166136261)
	end)

	it("is case-insensitive, including German umlauts", function()
		expect(Seed.fromText("ÄÖÜ Drache")).toBe(316673014)
		expect(Seed.fromText("äöü drache")).toBe(316673014)
	end)

	it("gives everyone the same daily seed", function()
		expect(Seed.fromDate(2026, 10, 17)).toBe(1333742450)
	end)
end)
