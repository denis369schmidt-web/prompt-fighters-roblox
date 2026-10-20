--!strict
-- Arenas. price = coins (0 = free). Owning an arena gives an extra vote in arena voting, never a combat edge.

local Rng = require(script.Parent.Parent.Util.Rng)

export type Arena = { id: string, name: string, price: number }

local Arenas = {}
Arenas.list = {
	{ id = "neon_alley", name = "NEON-GASSE", price = 0 },
	{ id = "moon_temple", name = "MONDTEMPEL", price = 250 },
	{ id = "holo_metropolis", name = "HOLO-METROPOLE", price = 400 },
	{ id = "warehouse", name = "LAGERHALLE", price = 300 },
	{ id = "cyber_stadium", name = "CYBER-STADION", price = 500 },
	{ id = "orbital_ring", name = "ORBITALRING", price = 900 },
	{ id = "neon_skyline", name = "NEON-SKYLINE", price = 350 },
	{ id = "colosseum", name = "KOLOSSEUM", price = 400 },
	{ id = "aurora_peak", name = "POLARLICHT-GIPFEL", price = 600 },
	{ id = "starship_hangar", name = "RAUMSCHIFF-HANGAR", price = 800 },
	{ id = "graffiti_alley", name = "GRAFFITI-GASSE", price = 300 },
	{ id = "no_mans_land", name = "NIEMANDSLAND", price = 500 },
	{ id = "sun_stadium", name = "SONNENSTADION", price = 450 },
	{ id = "rain_roof", name = "REGENDACH", price = 350 },
	{ id = "dojo", name = "DOJO", price = 450 },
	{ id = "night_market", name = "NACHTMARKT", price = 350 },
	{ id = "ruined_city", name = "RUINENSTADT", price = 550 },
	{ id = "sun_arena", name = "SONNENARENA", price = 600 },
	{ id = "storm_roof", name = "STURMDACH", price = 700 },
	{ id = "jungle_ruins", name = "DSCHUNGELRUINEN", price = 650 },
	{ id = "ice_works", name = "EISWERK", price = 700 },
	{ id = "foundry", name = "GIESSEREI", price = 750 },
	{ id = "smelter", name = "SCHMELZOFEN", price = 1000 },
} :: { Arena }

Arenas.byId = {} :: { [string]: Arena }
for _, arena in Arenas.list do
	Arenas.byId[arena.id] = arena
end

-- Votes a player casts in arena voting: 1, +1 if they own the arena, +1 with VIP; never more than 3.
function Arenas.voteWeight(ownsArena: boolean, isVip: boolean): number
	return 1 + (if ownsArena then 1 else 0) + (if isVip then 1 else 0)
end

-- `count` different arenas for a lobby vote, drawn from `pool` (default: all arenas) with a seeded generator.
function Arenas.voteOptions(seed: number, count: number, pool: { string }?): { string }
	local ids: { string } = {}
	if pool then
		for _, id in pool do
			table.insert(ids, id)
		end
	else
		for _, arena in Arenas.list do
			table.insert(ids, arena.id)
		end
	end
	local rng = Rng.new(seed)
	local out = {}
	while #out < count and #ids > 0 do
		table.insert(out, table.remove(ids, rng:int(1, #ids)) :: string)
	end
	return out
end

-- Weighted votes per option (votes maps a voter to { option index, weight }).
function Arenas.tally(options: { string }, votes: { [any]: { index: number, weight: number } }): { number }
	local totals = table.create(#options, 0)
	for _, vote in votes do
		if totals[vote.index] ~= nil then
			totals[vote.index] += vote.weight
		end
	end
	return totals
end

-- The winning option: most votes; a tie (or no votes at all) is decided by `roll` in [0, 1) among the leaders.
function Arenas.winner(options: { string }, totals: { number }, roll: number): string
	local best = -1
	local leaders = {}
	for i, total in totals do
		if total > best then
			best = total
			leaders = { i }
		elseif total == best then
			table.insert(leaders, i)
		end
	end
	return options[leaders[math.floor(roll * #leaders) + 1]]
end

return Arenas
