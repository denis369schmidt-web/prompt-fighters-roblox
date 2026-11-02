-- Match pacing (docs/DECISIONS.md, scripts/pacing.luau): four-fighter free-for-alls should end by KOs, not by
-- the clock. A small seeded sample keeps the suite fast; the script runs the full sweep.
local Arenas = require(Shared.Data.Arenas)
local Bot = require(Shared.Combat.Bot)
local Constants = require(Shared.Data.Constants)
local MatchRunner = require(Shared.Combat.MatchRunner)
local Sim = require(Shared.Combat.Simulation)
local Visuals = require(Shared.Data.Visuals)

describe("Match pacing", function()
	it("plays duels with DEFAULT_STOCKS and free-for-alls with FFA_STOCKS", function()
		local duel = Sim.new({ fighters = { "ninja", "golem" }, countdown = 0, seed = 1 })
		expect(duel.fighters[1].lives).toBe(Constants.DEFAULT_STOCKS)
		local ffa = Sim.new({ fighters = { "ninja", "golem", "jubei" }, countdown = 0, seed = 1 })
		expect(ffa.fighters[3].lives).toBe(Constants.FFA_STOCKS)
		local explicit = Sim.new({ fighters = { "ninja", "golem", "jubei" }, countdown = 0, seed = 1, stocks = 3 })
		expect(explicit.fighters[1].lives).toBe(3)
	end)

	it("ends most seeded 4-bot matches by KOs inside the time limit", function()
		local byKo = 0
		-- Same seeds and arenas as matches 2, 3, 4 and 6 of `lune run scripts/pacing.luau`.
		local seeds = { 1074, 1111, 1148, 1222 }
		for _, seed in seeds do
			local pool = Visuals.SLICE_FIGHTERS
			local slots = {}
			for k = 1, 4 do
				slots[k] = { userId = nil, fighterId = pool[(seed + k * 3) % #pool + 1] }
			end
			local runner = MatchRunner.new({
				slots = slots,
				botLevel = 3,
				botLevels = Bot.lineup(3, 4),
				seed = seed,
				arena = Arenas.list[(seed % #Arenas.list) + 1].id,
				countdown = 0,
			})
			local frames = 0
			while runner.sim.result == nil and frames < 60 * Constants.MATCH_SECONDS do
				runner:step(1 / 60)
				frames += 1
			end
			if runner.sim.result ~= nil and frames < 60 * Constants.MATCH_SECONDS then
				byKo += 1
			end
		end
		expect(byKo >= 3).toBe(true)
	end)
end)
