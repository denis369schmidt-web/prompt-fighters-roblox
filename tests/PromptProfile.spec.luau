local Guard = require(Shared.Net.Guard)
local Interpreter = require(Shared.Prompt.Interpreter)
local Profile = require(Shared.Meta.Profile)
local Registry = require(Shared.Prompt.Registry)

describe("Prompt fighters in the profile", function()
	it("migrates v1 saves to an empty prompt history and drops broken codes", function()
		local p = Profile.migrate({ version = 1, coins = 300, level = 3 })
		expect(p.version).toBe(Profile.VERSION)
		expect(p.promptFighters).toEqual({})
		expect(p.coins).toBe(300)
		local code = Interpreter.fromText("Giftfuchs").code
		local q = Profile.migrate({ promptFighters = { "bad", code, 5, "abcdef", code, code, code } })
		expect(q.promptFighters[1]).toBe(code)
		for _, c in q.promptFighters do
			expect(c).toBe(code)
		end
		expect(#q.promptFighters <= Profile.PROMPT_HISTORY).toBe(true)
		expect(Profile.migrate({ promptFighters = "x" }).promptFighters).toEqual({})
	end)

	it("keeps the last three prompt fighters, newest first, without duplicates", function()
		local p = Profile.new()
		local codes = {}
		for _, text in { "a golem", "b ninja", "c drache", "d ritter" } do
			local code = Interpreter.fromText(text).code
			table.insert(codes, code)
			expect(Profile.addPromptFighter(p, code)).toBe(true)
		end
		expect(p.promptFighters).toEqual({ codes[4], codes[3], codes[2] })
		Profile.addPromptFighter(p, codes[2])
		expect(p.promptFighters).toEqual({ codes[2], codes[4], codes[3] })
		expect(Profile.addPromptFighter(p, "nope")).toBe(false)
		expect(Profile.view(p).prompts).toEqual(p.promptFighters)
	end)

	it("gives prompt fighters no mastery XP and never treats them as owned roster fighters", function()
		local r = Registry.fromText("Blitzritter")
		local p = Profile.new()
		Profile.applyMatch(
			p,
			r.id,
			{ won = true, place = 1, kos = 2, damage = 100, finishers = 0, stocksLost = 0, bestCombo = 3 }
		)
		expect(p.fighterXp[r.id]).toBeNil()
		expect(Profile.owns(p, r.id)).toBe(false)
		expect((Profile.buyFighter(p, r.id))).toBe(false)
	end)
end)

describe("Prompt remotes", function()
	it("accepts prompts up to 120 characters (umlauts count once) and refuses longer or broken text", function()
		local g = Guard.new()
		expect(g:allow(1, "SubmitPrompt", 0, { "Eisgolem mit Hammer" })).toBe(true)
		expect(g:allow(2, "SubmitPrompt", 0, { string.rep("ü", 120) })).toBe(true)
		expect(g:allow(3, "SubmitPrompt", 0, { string.rep("a", 121) })).toBe(false)
		expect(g:allow(4, "SubmitPrompt", 0, { string.char(255, 254) })).toBe(false)
		expect(g:allow(5, "SubmitPrompt", 0, { 42 })).toBe(false)
		expect(g:allow(6, "SubmitPrompt", 0, { "a", "b" })).toBe(false)
	end)

	it("rate-limits prompts to one every two seconds and codes to one per second", function()
		local g = Guard.new()
		expect(g:allow(9, "SubmitPrompt", 0, { "Sternendrache" })).toBe(true)
		expect(g:allow(9, "SubmitPrompt", 0.5, { "Sternendrache" })).toBe(false)
		expect(g:allow(9, "SubmitPrompt", 2.6, { "Sternendrache" })).toBe(true)
		expect(g:allow(9, "LoadPromptCode", 0, { "7KQ2XM" })).toBe(true)
		expect(g:allow(9, "LoadPromptCode", 0.2, { "7KQ2XM" })).toBe(false)
		expect(g:allow(10, "LoadPromptCode", 0, { string.rep("A", 17) })).toBe(false)
	end)
end)
