local ArenaBuilder = require(Server.World.ArenaBuilder)
local DecorMotion = require(Shared.Visual.DecorMotion)
local ArenaThemes = require(Shared.Data.ArenaThemes)
local Arenas = require(Shared.Data.Arenas)
local LobbyBuilder = require(Server.World.LobbyBuilder)
local Visuals = require(Shared.Data.Visuals)

-- Part budgets: arenas stay light for phones, the lobby (16 statues + the showcase fighter) a bit heavier.
local ARENA_PART_BUDGET = 700

local function count(model, class: string): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA(class) then
			n += 1
		end
	end
	return n
end

describe("Arenas", function()
	it("gives every arena a theme with valid colors", function()
		for _, arena in Arenas.list do
			local theme = ArenaThemes[arena.id]
			assert(theme, `{arena.id} has no theme`)
			assert(string.match(theme.trim, "^#%x%x%x%x%x%x$"), `{arena.id} trim`)
			assert(string.match(theme.accent, "^#%x%x%x%x%x%x$"), `{arena.id} accent`)
			assert(ArenaBuilder.hasTheme(arena.id), `{arena.id}: motif {theme.motif} is not built`)
		end
	end)

	for _, arena in Arenas.list do
		it(`builds {arena.id} with stage, platforms, backdrop and weather`, function()
			local model = ArenaBuilder.build(arena.id)
			expect(model.Parent).toBe(workspace)
			expect(model:GetAttribute("ArenaId")).toBe(arena.id)
			assert(model:FindFirstChild("Stage"), "no stage")
			assert(model:FindFirstChild("Weather"), "no weather")
			-- Decoration never collides: the Simulation owns all collision.
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					assert(not d.CanCollide, `{d.Name} collides`)
					assert(not d.CanTouch and not d.CanQuery, `{d.Name} can be touched or queried`)
					assert(d.Anchored, `{d.Name} is not anchored`)
				end
			end
			local parts = count(model, "BasePart")
			assert(parts > 60, `{arena.id} looks empty ({parts} parts)`)
			assert(parts <= ARENA_PART_BUDGET, `{arena.id} has {parts} parts (budget {ARENA_PART_BUDGET})`)
		end)
	end

	it("replaces the previous arena instead of stacking them", function()
		ArenaBuilder.build("dojo")
		ArenaBuilder.build("colosseum")
		local arenas = 0
		for _, child in workspace:GetChildren() do
			if child.Name == "Arena" then
				arenas += 1
			end
		end
		expect(arenas).toBe(1)
	end)

	it("draws three different vote options and lets the most votes win", function()
		local options = Arenas.voteOptions(42, 3)
		expect(#options).toBe(3)
		expect(options[1] ~= options[2] and options[2] ~= options[3] and options[1] ~= options[3]).toBe(true)
		expect(Arenas.voteOptions(42, 3)[2]).toBe(options[2])
		local totals = Arenas.tally(options, {
			[1] = { index = 2, weight = 1 },
			[2] = { index = 2, weight = 1 },
			[3] = { index = 3, weight = 1 },
			[4] = { index = 9, weight = 1 }, -- not an option: ignored
		})
		expect(totals[1]).toBe(0)
		expect(totals[2]).toBe(2)
		expect(Arenas.winner(options, totals, 0.99)).toBe(options[2])
	end)

	it("breaks ties and empty votes by the roll", function()
		local options = { "dojo", "foundry", "colosseum" }
		expect(Arenas.winner(options, { 0, 0, 0 }, 0)).toBe("dojo")
		expect(Arenas.winner(options, { 0, 0, 0 }, 0.99)).toBe("colosseum")
		expect(Arenas.winner(options, { 1, 0, 1 }, 0.6)).toBe("colosseum")
	end)
end)

describe("Lobby", function()
	it("builds a walkable plaza with a spawn, vote pads and all launch fighters as statues", function()
		local model = LobbyBuilder.build()
		expect(model.Parent).toBe(workspace)
		assert(model:FindFirstChild("LobbySpawn"), "no spawn")
		local floor = model:FindFirstChild("Floor")
		expect(floor.CanCollide).toBe(true)
		for _, id in Visuals.SLICE_FIGHTERS do
			assert(model:FindFirstChild("Statue_" .. id), `no statue for {id}`)
		end
		for k = 1, LobbyBuilder.PAD_COUNT do
			assert(model:FindFirstChild("VotePad" .. k), `no pad {k}`)
		end
	end)

	it("stays within its part budget and only collides where players walk", function()
		local model = LobbyBuilder.build()
		local parts = count(model, "BasePart")
		assert(parts <= LobbyBuilder.PART_BUDGET, `lobby has {parts} parts (budget {LobbyBuilder.PART_BUDGET})`)
		local solid = {
			Floor = true,
			Wall = true,
			Curb = true,
			Pedestal = true,
			BoardLeg = true,
			LampPost = true,
			GatePillar = true,
			SignPost = true,
			LeaderboardLeg = true,
			ShowcaseDais = true,
			ShowcaseStep = true,
			ShowcasePillar = true,
			Turntable = true,
			TerminalBase = true,
			TerminalConsole = true,
			DummyPost = true,
			DummyBody = true,
			DummyHead = true,
			FountainBasin = true,
			Bench = true,
		}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local name = string.gsub(d.Name, "%d+$", "")
				if d.CanCollide then
					assert(solid[name] or name == "VotePad" or name == "VotePole", `decoration {d.Name} collides`)
				end
				assert(d.Anchored, `{d.Name} is not anchored`)
				assert(not d.CanTouch, `{d.Name} can be touched`)
				if d:GetAttribute("Anim") then
					assert(not d.CanCollide, `animated {d.Name} collides`)
				end
			end
		end
	end)

	it("builds statues lighter than the full rigs and a full-detail showcase fighter", function()
		local model = LobbyBuilder.build()
		local statue = model:FindFirstChild("Statue_ninja")
		local featured = model:FindFirstChild("Featured_" .. LobbyBuilder.DEFAULT_FEATURED)
		assert(featured, "no showcase fighter")
		local statueParts, featuredParts = count(statue, "BasePart"), count(featured, "BasePart")
		assert(statueParts < 80, `statue has {statueParts} parts`)
		assert(featuredParts > statueParts, "showcase fighter should keep full detail")
		LobbyBuilder.setFeatured("golem")
		expect(LobbyBuilder.featured()).toBe("golem")
		assert(model:FindFirstChild("Featured_golem"), "showcase did not switch")
		expect(model:FindFirstChild("Featured_" .. LobbyBuilder.DEFAULT_FEATURED)).toBeNil()
	end)

	it("has a leaderboard that takes rows and a Prompt-Terminal anchor", function()
		local model = LobbyBuilder.build()
		LobbyBuilder.setLeaderboard({ { name = "Mia", value = 12 }, { name = "Ben", value = "9 Siege" } }, "TOP 8")
		local texts = {}
		for _, d in model:FindFirstChild("Leaderboard"):GetDescendants() do
			if d:IsA("TextLabel") then
				texts[d.Text] = (texts[d.Text] or 0) + 1
			end
		end
		expect(texts["Mia"]).toBe(1)
		expect(texts["12"]).toBe(1)
		expect(texts["9 Siege"]).toBe(1)
		expect(texts["TOP 8"]).toBe(1)
		expect(texts["—"]).toBe(LobbyBuilder.LEADERBOARD_ROWS - 2)
		local anchor = model:FindFirstChild("PromptTerminal")
		assert(anchor and anchor:IsA("BasePart"), "no PromptTerminal anchor")
		assert(anchor:FindFirstChild("PromptAttachment"), "no PromptAttachment")
		assert(LobbyBuilder.terminalCFrame(), "no terminal CFrame")
	end)

	it("knows which pad a player stands on", function()
		LobbyBuilder.build()
		local center = LobbyBuilder.padCenter(2)
		expect(LobbyBuilder.padAt(center + Vector3.new(2, 3, -2))).toBe(2)
		expect(LobbyBuilder.padAt(center + Vector3.new(LobbyBuilder.PAD_RADIUS + 1, 3, 0))).toBeNil()
		expect(LobbyBuilder.padAt(Visuals.LOBBY_ORIGIN + Vector3.new(0, 3, 30))).toBeNil()
	end)

	it("shows votes and status on the signs", function()
		LobbyBuilder.build()
		LobbyBuilder.setVote(1, "dojo", 2, true)
		LobbyBuilder.setStatus("KAMPF IN 5", "1/1 bereit")
		local sign = LobbyBuilder.model():FindFirstChild("VoteSign1")
		local texts = {}
		for _, d in sign:GetDescendants() do
			if d:IsA("TextLabel") then
				texts[d.Text] = true
			end
		end
		expect(texts["DOJO"]).toBe(true)
		expect(texts["2 STIMMEN"]).toBe(true)
	end)
end)

describe("Decor motion", function()
	-- Specs have no Instance/CFrame globals: attributes live on a stand-in table, and CFrames come from a built
	-- part with an unrotated CFrame (the lobby floor) shifted by a Vector3.
	local function stub()
		local attributes = {}
		return {
			SetAttribute = function(_, k, v)
				attributes[k] = v
			end,
			GetAttribute = function(_, k)
				return attributes[k]
			end,
		}
	end
	local function tagged(kind: string, spec)
		local p = stub()
		DecorMotion.tag(p, kind, spec)
		return DecorMotion.read(p)
	end
	local floor = LobbyBuilder.build():FindFirstChild("Floor").CFrame
	local IDENTITY = floor - floor.Position
	local function at(x: number, y: number, z: number)
		return IDENTITY + Vector3.new(x, y, z)
	end

	it("bobs around the rest position and loops passing props over their span", function()
		local base = at(10, 5, 0)
		local bob = tagged("bob", { amp = 2, period = 4 })
		expect(math.abs(DecorMotion.cframe(bob, base, 1).Position.Y - 7) < 1e-4).toBe(true)
		local pass = tagged("pass", { speed = 10, amp = 100 })
		local a = DecorMotion.cframe(pass, base, 0).Position.X
		local b = DecorMotion.cframe(pass, base, 10).Position.X
		expect(math.abs(a - b) < 1e-4).toBe(true) -- one full loop
		expect(a >= -40 and a <= 60).toBe(true)
	end)

	it("spins around its pivot and pulses transparency within 0..1", function()
		local spin = tagged("spin", { speed = math.pi, pivot = Vector3.new(0, 0, 0) })
		local p = DecorMotion.cframe(spin, at(5, 0, 0), 1).Position
		expect(math.abs(p.X + 5) < 1e-3 and math.abs(p.Z) < 1e-3).toBe(true)
		local pulse = tagged("pulse", { amp = 0.8, period = 2 })
		for t = 0, 2, 0.25 do
			local v = DecorMotion.transparency(pulse, 0.5, t)
			expect(v >= 0 and v <= 1).toBe(true)
		end
		expect(DecorMotion.read(stub())).toBeNil()
	end)
end)
