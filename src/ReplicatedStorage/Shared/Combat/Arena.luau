--!strict
-- Stage geometry in meters (combat.gd). The main stage spans STAGE_LEFT..STAGE_RIGHT at y = 0; floating
-- platforms are pass-through from below and can be dropped through with down.

export type Platform = { name: string, x1: number, x2: number, y: number }

local Arena = {
	STAGE_LEFT = -9.5,
	STAGE_RIGHT = 9.5,
	BLAST_LEFT = -16.0,
	BLAST_RIGHT = 16.0,
	BLAST_BOTTOM = -6.0,
	BLAST_TOP = 13.0,
	LEDGE_HANG_Y = -1.0,
	SPAWN_X = { -6.2, 6.2, -2.5, 2.5 },
	SPAWN_FACING = { 1, -1, 1, -1 },
	RESPAWN_X = { -5.0, 5.0, -1.8, 1.8 },
	RESPAWN_Y = 4.2,
}

local function p(name: string, x1: number, x2: number, y: number): Platform
	return { name = name, x1 = x1, x2 = x2, y = y }
end

Arena.LAYOUTS = {
	classic = {
		p("wing_left", -8.5, -5.5, 1.45),
		p("wing_right", 5.5, 8.5, 1.45),
		p("mid_left", -4.2, -1.8, 2.5),
		p("mid_right", 1.8, 4.2, 2.5),
		p("center", -1.5, 1.5, 3.65),
		p("apex", -1.0, 1.0, 5.2),
		p("perch_left", -9.2, -7.2, 3.4),
		p("perch_right", 7.2, 9.2, 3.4),
	},
	towers = {
		p("wing_left", -8.6, -6.0, 1.3),
		p("wing_right", 6.0, 8.6, 1.3),
		p("mid_left", -7.4, -5.0, 2.5),
		p("mid_right", 5.0, 7.4, 2.5),
		p("center", -1.6, 1.6, 1.9),
		p("apex", -1.1, 1.1, 3.2),
		p("perch_left", -8.8, -6.6, 3.7),
		p("perch_right", 6.6, 8.8, 3.7),
	},
	bridge = {
		p("wing_left", -8.8, -6.4, 1.2),
		p("wing_right", 6.4, 8.8, 1.2),
		p("mid_left", -5.6, -3.4, 2.3),
		p("mid_right", 3.4, 5.6, 2.3),
		p("center", -3.0, 3.0, 3.4),
		p("apex", -0.8, 0.8, 4.6),
		p("perch_left", -9.2, -7.6, 2.4),
		p("perch_right", 7.6, 9.2, 2.4),
	},
	low = {
		p("wing_left", -7.0, -4.0, 1.5),
		p("wing_right", 4.0, 7.0, 1.5),
		p("mid_left", -9.0, -7.2, 2.6),
		p("mid_right", 7.2, 9.0, 2.6),
		p("center", -1.3, 1.3, 1.5),
		p("apex", -2.0, 2.0, 2.7),
		p("perch_left", -5.6, -3.8, 2.8),
		p("perch_right", 3.8, 5.6, 2.8),
	},
} :: { [string]: { Platform } }

-- Layout per arena id (Data/Arenas); every other arena plays "classic".
Arena.ARENA_LAYOUT = {
	colosseum = "towers",
	sun_arena = "towers",
	sun_stadium = "towers",
	cyber_stadium = "towers",
	warehouse = "towers",
	foundry = "towers",
	aurora_peak = "bridge",
	orbital_ring = "bridge",
	starship_hangar = "bridge",
	ice_works = "bridge",
	smelter = "bridge",
	no_mans_land = "bridge",
	neon_skyline = "low",
	graffiti_alley = "low",
	rain_roof = "low",
	storm_roof = "low",
	ruined_city = "low",
} :: { [string]: string }

function Arena.platformsFor(arenaId: string): { Platform }
	return Arena.LAYOUTS[Arena.ARENA_LAYOUT[arenaId] or "classic"]
end

function Arena.isOutOfBounds(x: number, y: number): boolean
	return x < Arena.BLAST_LEFT or x > Arena.BLAST_RIGHT or y < Arena.BLAST_BOTTOM or y > Arena.BLAST_TOP
end

return Arena
