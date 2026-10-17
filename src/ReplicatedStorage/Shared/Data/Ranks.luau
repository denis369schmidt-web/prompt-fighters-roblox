--!strict
-- Ranked leagues: points needed and first-reach reward. Season lasts 8 weeks.

local Ranks = {}

Ranks.SEASON_WEEKS = 8
Ranks.LEAGUES = {
	{ id = "bronze", name = "BRONZE", points = 0, coins = 0, chests = 0 },
	{ id = "silver", name = "SILBER", points = 100, coins = 200, chests = 0 },
	{ id = "gold", name = "GOLD", points = 250, coins = 300, chests = 1 },
	{ id = "platinum", name = "PLATIN", points = 450, coins = 500, chests = 1 },
	{ id = "diamond", name = "DIAMANT", points = 700, coins = 800, chests = 1 },
	{ id = "master", name = "MEISTER", points = 1000, coins = 1200, chests = 2 },
	{ id = "champion", name = "CHAMPION", points = 1400, coins = 2000, chests = 3 },
}

function Ranks.leagueFor(points: number)
	local league = Ranks.LEAGUES[1]
	for _, entry in Ranks.LEAGUES do
		if points >= entry.points then
			league = entry
		end
	end
	return league
end

return Ranks
