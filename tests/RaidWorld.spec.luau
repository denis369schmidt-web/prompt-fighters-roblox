local ArenaBuilder = require(Server.World.ArenaBuilder)
local Arena = require(Shared.Combat.Arena)
local LobbyBuilder = require(Server.World.LobbyBuilder)
local ModeBoard = require(Server.World.ModeBoard)
local DailyChallenge = require(Shared.Data.DailyChallenge)
local BossRig = require(Shared.Visual.BossRig)
local Bosses = require(Shared.Data.Bosses)
local Visuals = require(Shared.Data.Visuals)

local function count(model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

describe("Raid world", function()
	for _, id in { "raid_hell", "raid_heaven" } do
		it(`builds the boss arena {id} with the sanctum and an open middle`, function()
			local model = ArenaBuilder.build(id)
			assert(model:FindFirstChild("RaidSanctum"), "no sanctum")
			assert(model:FindFirstChild("Stage"), "no stage")
			expect(count(model) <= 700).toBe(true)
			for _, p in Arena.platformsFor(id) do
				expect(math.abs(p.x1) > 4 and math.abs(p.x2) > 4).toBe(true)
			end
		end)
	end

	it("puts mode pads and the challenge board into the lobby", function()
		local lobby = LobbyBuilder.build()
		local board = ModeBoard.build(lobby)
		expect(board.Parent).toBe(lobby)
		ModeBoard.setChallenge(DailyChallenge.describe(DailyChallenge.forDay(20759)))
		ModeBoard.setVotes({ 0, 2, 1 }, 2)
		ModeBoard.setBoss("AHRIMAN", "DIE LEERE HÜLLE")
		local pad = board:FindFirstChild("ModePad2")
		assert(pad, "no raid pad")
		local position = pad.CFrame.Position + Vector3.new(0, 3, 0)
		expect(ModeBoard.padAt(position)).toBe(2)
		expect(ModeBoard.padAt(Visuals.LOBBY_ORIGIN)).toBeNil()
		expect(LobbyBuilder.padAt(position)).toBeNil() -- no overlap with the arena pads
		expect(count(lobby) <= LobbyBuilder.PART_BUDGET + 120).toBe(true)
	end)

	it("builds every boss as a big rig with a shatterable shell", function()
		for _, id in Bosses.order do
			local rig = BossRig.build(id)
			local shell, total = 0, 0
			for _, d in rig:GetDescendants() do
				if d:IsA("BasePart") then
					total += 1
					if d:GetAttribute("BossGroup") == "Shell" then
						shell += 1
					end
				end
			end
			assert(shell >= 6, `{id}: shell has {shell} parts`)
			assert(total <= BossRig.PART_BUDGET, `{id}: {total} parts`)
			local _, h = Bosses.raidBody(id)
			expect(rig:GetAttribute("Height")).toBeCloseTo(h * Visuals.STUDS_PER_METER, 3)
		end
	end)
end)
