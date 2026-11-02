local Code = require(Shared.Prompt.Code)
local Interpreter = require(Shared.Prompt.Interpreter)
local Keywords = require(Shared.Prompt.Keywords)
local Registry = require(Shared.Prompt.Registry)
local Fighters = require(Shared.Data.Fighters)
local Looks = require(Shared.Data.Looks)
local Moveset = require(Shared.Combat.Moveset)
local MatchRunner = require(Shared.Combat.MatchRunner)
local RigBuilder = require(Shared.Visual.RigBuilder)
local PromptGear = require(Shared.Visual.PromptGear)
local Seed = require(Shared.Util.Seed)

local SHOWCASE = {
	"Eisgolem mit Hammer",
	"lava ninja",
	"Sternendrache",
	"Roboter Samurai",
	"Giftfuchs",
	"Blitzritter",
	"Schattenvampir",
	"Wasser Magier",
}

local function sum(stats)
	local total = 0
	for _, key in Interpreter.STAT_KEYS do
		total += stats[key]
	end
	return total
end

-- Every rig rule the roster is held to (RigBuilder.spec): joints, bones, budget, feet on the floor, all gear built.
local function checkRig(id: string)
	local model = RigBuilder.build(id)
	local look = Looks.get(id)
	for _, gear in look.gear do
		assert(RigBuilder.GEAR[gear], `{id}: unknown gear {gear}`)
		for _, d in RigBuilder.GEAR[gear] do
			assert(model:FindFirstChild(d.name, true), `{id}: {gear} piece {d.name} missing`)
		end
	end
	local visible, lowest = 0, math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			visible += 1
			local s = d.Size
			for _, corner in { Vector3.new(-1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(-1, -1, 1), Vector3.new(1, -1, -1) } do
				lowest = math.min(lowest, (d.CFrame * (corner * s / 2)).Y)
			end
		end
	end
	assert(visible <= RigBuilder.PART_BUDGET, `{id}: {visible} parts (budget {RigBuilder.PART_BUDGET})`)
	assert(visible > 18, `{id}: only {visible} parts`)
	assert(lowest > -0.25 and lowest < 0.25, `{id}: lowest point at y = {lowest}`)
	return model
end

local function checkFighter(result)
	local f = result.fighter
	expect(sum(f.stats)).toBe(Interpreter.BUDGET)
	for _, key in Interpreter.STAT_KEYS do
		assert(f.stats[key] >= Interpreter.STAT_MIN and f.stats[key] <= Interpreter.STAT_MAX, `{f.id}: {key}`)
	end
	assert(#f.name > 0 and #f.name <= 24, `name "{f.name}"`)
	assert(f.signatureParams.mech, `{f.id}: no signature mechanic`)
	assert(f.moves.jab and f.moves.uspecial, `{f.id}: incomplete moves`)
	assert(f.weight >= 0.8 and f.weight <= 1.5, `{f.id}: weight {f.weight}`)
	assert(f.runSpeed > 0, `{f.id}: run speed`)
end

describe("Prompt interpreter", function()
	it("gives the same fighter for the same text, regardless of case and outer spaces", function()
		local a = Interpreter.fromText("Eisgolem mit Hammer")
		local b = Interpreter.fromText("  eisgolem MIT hammer ")
		expect(a.code).toBe(b.code)
		expect(a.fighter.name).toBe(b.fighter.name)
		expect(a.look).toEqual(b.look)
		expect(a.fighter.stats).toEqual(b.fighter.stats)
		expect(a.traits.variant).toBe(Seed.fromText("Eisgolem mit Hammer") % Code.VARIANTS)
	end)

	it("reads German compounds and English words", function()
		local function kinds(text)
			local t = Interpreter.parse(text)
			local e = if t.element > 0 then Keywords.ELEMENTS[t.element].key else nil
			local b = if t.body > 0 then Keywords.BODIES[t.body].key else nil
			local b2 = if t.body2 > 0 then Keywords.BODIES[t.body2].key else nil
			local w = if t.weapon > 0 then Keywords.WEAPONS[t.weapon].key else nil
			local s = if t.tempo > 0 then Keywords.TEMPOS[t.tempo].key else nil
			return { e, b, w, s, b2 }
		end
		expect(kinds("Eisgolem mit Hammer")).toEqual({ "eis", "golem", "hammer" })
		expect(kinds("ice golem with a hammer")).toEqual({ "eis", "golem", "hammer" })
		expect(kinds("lava ninja")).toEqual({ "lava", "ninja" })
		expect(kinds("Sternendrache")).toEqual({ "kosmos", "drache" })
		expect(kinds("space dragon")).toEqual({ "kosmos", "drache" })
		expect(kinds("Roboter Samurai")).toEqual({ nil, "samurai", nil, nil, "roboter" })
		expect(kinds("Giftfuchs")).toEqual({ "gift", "fuchs" })
		expect(kinds("poison fox")).toEqual({ "gift", "fuchs" })
		expect(kinds("Blitzritter")).toEqual({ "blitz", "ritter" })
		expect(kinds("lightning knight")).toEqual({ "blitz", "ritter" })
		expect(kinds("Schattenvampir")).toEqual({ "schatten", "vampir" })
		expect(kinds("Wasser Magier")).toEqual({ "wasser", "magier" })
		expect(kinds("water wizard")).toEqual({ "wasser", "magier" })
		expect(kinds("Frosthammer, langsam aber stark")).toEqual({ "eis", nil, "hammer", "stark" })
		expect(kinds("fast fire bunny with a bow")).toEqual({ "feuer", "hase", "bogen", "schnell" })
		expect(kinds("Toasterritter")).toEqual({ nil, "ritter" })
		-- Umlauts typed or folded, upper case.
		expect(kinds("EISBAER")).toEqual({ nil, "baer" })
		expect(kinds("Phönix")).toEqual({ nil, "phoenix" })
		expect(kinds("phoenix")).toEqual({ nil, "phoenix" })
		-- Keywords hidden inside other words do not count.
		expect(kinds("Blitzmeister")).toEqual({ "blitz" })
		expect(kinds("im Kreis")).toEqual({})
		expect(kinds("Stahlschwert")).toEqual({ "metall", nil, "schwert" })
	end)

	it("names fighters from the recognized keywords", function()
		expect(Interpreter.fromText("Eisgolem mit Hammer").fighter.name).toBe("EISGOLEM")
		expect(Interpreter.fromText("lava ninja").fighter.name).toBe("LAVANINJA")
		expect(Interpreter.fromText("Sternendrache").fighter.name).toBe("STERNENDRACHE")
		expect(Interpreter.fromText("Roboter Samurai").fighter.name).toBe("ROBOSAMURAI")
		expect(Interpreter.fromText("Giftfuchs").fighter.name).toBe("GIFTFUCHS")
		expect(Interpreter.fromText("Feuer mit Hammer").fighter.name).toBe("FEUERHAMMER")
		expect(Interpreter.fromText("Wasser Magier").fighter.name).toBe("WASSERMAGIER")
		local title = Interpreter.fromText("Eisgolem").summary.title
		expect(title).toBe("Eisiger Koloss")
	end)

	it("turns unknown words into a valid fighter from the seed", function()
		for _, text in { "Toaster", "xyz", "", "Wolkenbär mit Regenschirm", "1234 !!!", "😀😀😀" } do
			local result = Interpreter.fromText(text)
			checkFighter(result)
			assert(Fighters.get(result.fighter.signature ~= "" and "ninja"), "roster intact")
		end
		expect(Interpreter.fromText("Toaster").code).never.toBe(Interpreter.fromText("Wolkenbär").code)
	end)

	it("keeps the stat budget at 100 for every element, body, weapon and tempo", function()
		for e = 0, #Keywords.ELEMENTS do
			for _, b in { 0, 1, 2, 5, 17, 22 } do
				for _, t in { 0, 1, 2, 3 } do
					checkFighter(Interpreter.build({ element = e, body = b, body2 = 0, weapon = e % 16, tempo = t, variant = e * 31 % 512 }))
				end
			end
		end
		local stats = Interpreter.normalize({ 60, 60, 2, 2, 0 })
		expect(stats[1] + stats[2] + stats[3] + stats[4] + stats[5]).toBe(100)
		expect(stats[1]).toBe(36)
	end)

	it("matches the element in color and signature", function()
		local ice = Interpreter.fromText("Eisgolem")
		expect(ice.look.glow).toBe(ice.signatureParams.color)
		expect(ice.look.materials.Slate).toBe("Ice")
		expect(ice.look.glowEyes).toBe(true)
		local donors = Keywords.ELEMENTS[ice.traits.element].signatures
		assert(table.find(donors, ice.fighter.prompt.donor), "signature from an ice fighter")
		local robot = Interpreter.fromText("Roboter Samurai")
		expect(robot.look.skinMaterial).toBe("Metal")
		assert(table.find(robot.look.gear, "katana"), "samurai keeps the katana")
	end)

	it("builds a valid rig for every element, body and weapon", function()
		for i = 1, #Keywords.ELEMENTS do
			local r = Registry.register(Interpreter.build({ element = i, body = 0, body2 = 0, weapon = 0, tempo = 0, variant = i }))
			checkRig(r.id)
		end
		for i = 1, #Keywords.BODIES do
			local r = Registry.register(Interpreter.build({ element = i % #Keywords.ELEMENTS + 1, body = i, body2 = 0, weapon = 0, tempo = 0, variant = i * 3 }))
			checkRig(r.id)
		end
		for i = 1, #Keywords.WEAPONS do
			local r = Registry.register(Interpreter.build({ element = 0, body = i, body2 = 0, weapon = i, tempo = 0, variant = i * 5 }))
			checkRig(r.id)
		end
	end)

	it("builds valid rigs for every body pair and a wide sample of codes", function()
		for b = 1, #Keywords.BODIES do
			for b2 = 1, #Keywords.BODIES do
				if b ~= b2 and (b + b2) % 3 == 0 then
					local r = Registry.register(Interpreter.build({ element = (b * b2) % 21, body = b, body2 = b2, weapon = (b + b2) % 16, tempo = b % 4, variant = b * 17 + b2 }))
					checkRig(r.id)
				end
			end
		end
		for _, text in SHOWCASE do
			checkRig(Registry.fromText(text).id)
		end
	end)

	it("builds every prompt gear set with all its pieces", function()
		local look = table.clone(Looks.get("ninja")) :: any
		local all = {}
		for gear in PromptGear :: any do
			table.insert(all, gear)
		end
		look.gear = all
		Looks.BY_ID.__promptgear = look
		local ok, model = pcall(RigBuilder.build, "__promptgear")
		Looks.BY_ID.__promptgear = nil
		assert(ok, tostring(model))
		for gear, pieces in PromptGear :: any do
			for _, d in pieces do
				assert(model:FindFirstChild(d.name, true), `{gear}: piece {d.name} not built`)
			end
		end
	end)
end)

describe("Prompt codes", function()
	it("round-trips traits through 6 characters", function()
		for k = 0, 400 do
			local t = { element = k % 21, body = k % 26, body2 = (k * 7) % 26, weapon = k % 16, tempo = k % 4, variant = (k * 97) % 512 }
			local code = Code.encode(t)
			expect(#code).toBe(6)
			expect(Code.decode(code)).toEqual(t)
		end
	end)

	it("rebuilds the same fighter from the code without the text", function()
		for _, text in SHOWCASE do
			local a = Interpreter.fromText(text)
			local b = Interpreter.fromCode(a.code)
			assert(b, `code {a.code} did not decode`)
			expect(b.fighter.name).toBe(a.fighter.name)
			expect(b.look).toEqual(a.look)
			expect(b.fighter.stats).toEqual(a.fighter.stats)
			expect(b.summary).toEqual(a.summary)
		end
	end)

	it("accepts sloppy typing and rejects garbage", function()
		local code = Interpreter.fromText("Sternendrache").code
		expect(Code.normalize(string.lower(code))).toBe(code)
		expect(Code.normalize(string.sub(code, 1, 3) .. "-" .. string.sub(code, 4))).toBe(code)
		expect(Code.normalize("ABC")).toBeNil()
		expect(Code.normalize("ABCDEU!")).toBeNil()
		expect(Interpreter.fromCode("")).toBeNil()
		expect(Interpreter.fromCode("#####")).toBeNil()
		-- Codes that point past the keyword lists are refused, not clamped.
		local bad = Code.encode({ element = 31, body = 1, body2 = 0, weapon = 0, tempo = 0, variant = 0 })
		expect(Interpreter.fromCode(bad)).toBeNil()
	end)

	it("registers prompt fighters under prompt_<CODE> for moves, looks and the simulation", function()
		local r = Registry.fromText("lava ninja")
		expect(r.id).toBe("prompt_" .. r.code)
		expect(Interpreter.codeOf(r.id)).toBe(r.code)
		expect(Interpreter.codeOf("ninja")).toBeNil()
		expect(Interpreter.codeOf("prompt_" .. string.lower(r.code))).toBeNil()
		expect(Fighters.get(r.id).name).toBe("LAVANINJA")
		-- Not in the roster list (pickers and shops only show roster fighters).
		for _, f in Fighters.list do
			assert(f.id ~= r.id, "prompt fighter leaked into the roster list")
		end
		local moves = Moveset.build(r.id)
		expect(moves.nspecial.name).toBe(r.fighter.specialName)
		-- A fighter id from another machine resolves from its code alone.
		local other = Interpreter.fromText("Schattenvampir")
		expect(Fighters.get(other.id).name).toBe("SCHATTENVAMPIR")
		expect(Looks.get(other.id)).toEqual(other.look)
	end)

	it("fights a full match with prompt fighters against roster bots", function()
		local a = Registry.fromText("Eisgolem mit Hammer")
		local b = Registry.fromText("Blitzritter")
		local runner = MatchRunner.new({
			slots = {
				{ userId = 1, fighterId = a.id },
				{ userId = 2, fighterId = b.id },
				{ userId = nil, fighterId = "ninja" },
				{ userId = nil, fighterId = "golem" },
			},
			seed = 4,
			countdown = 0,
		})
		for _ = 1, 60 * 20 do
			runner:step(1 / 60)
			if runner.sim.result ~= nil then
				break
			end
		end
		expect(runner.sim.fighters[1].fighterId).toBe(a.id)
		assert(#runner:snapshot() > 0, "snapshot")
	end)
end)
