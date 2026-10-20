local ArenaBuilder = require(Server.World.ArenaBuilder)
local ArenaThemes = require(Shared.Data.ArenaThemes)
local Arenas = require(Shared.Data.Arenas)
local LobbyBuilder = require(Server.World.LobbyBuilder)
local Visuals = require(Shared.Data.Visuals)

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
				end
			end
			assert(count(model, "BasePart") > 60, `{arena.id} looks empty ({count(model, "BasePart")} parts)`)
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
