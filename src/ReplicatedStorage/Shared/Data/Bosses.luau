--!strict
-- Bosses for Boss-Raid. Numbers are imported from Godot (Generated/BossData); this module adds order, scaling,
-- the raid rules (Combat/BossFight) and rewards.

local BossData = require(script.Parent.Generated.BossData)

local Bosses = {}
Bosses.byId = BossData.bosses :: { [string]: any }
Bosses.patterns = BossData.patterns :: { [string]: any }

-- Raid order from the template: hell circle by circle, then heaven.
Bosses.order = {
	"ahriman",
	"lilith",
	"asmodeus",
	"beelzebub",
	"mammon",
	"baphomet",
	"belphegor",
	"bel_marduk",
	"leviathan",
	"lucifer",
	"angelus",
	"michael",
	"principatus",
	"potestas",
	"virtus",
	"dominatio",
	"ophan",
	"cherub",
	"seraph",
}

Bosses.PHASE_TWO_AT = 0.5

-- Godot hp values are tuned for two heroes: hp * (0.5 + 0.25 * heroes), as in bosses.gd profile().
function Bosses.scaledHp(id: string, heroCount: number): number
	local boss = Bosses.byId[id]
	assert(boss, `unknown boss {id}`)
	return boss.hp * (0.5 + 0.25 * math.max(1, heroCount))
end

function Bosses.phase(hp: number, maxHp: number): number
	return if hp <= maxHp * Bosses.PHASE_TWO_AT then 2 else 1
end

-- Boss-Raid rules (Combat/BossFight). Sizes are Godot meters scaled up: a raid boss stands about three fighters tall.
Bosses.RAID = {
	SCALE = 1.5, -- Godot body size -> raid body size
	WIDTH = 1.6, -- hurtbox width = body_w * SCALE * WIDTH
	HEROES = 4, -- players plus bot helpers
	LIVES_PER_HERO = 1.5, -- shared team lives pool: floor(heroes * this)
	RESPAWN_SECONDS = 3.0,
	RESPAWN_INVULNERABLE = 2.0,
	ENRAGE_SECONDS = 150, -- after this the boss hits harder and attacks faster
	TIME_LIMIT = 210, -- the raid is lost when the boss still stands here
	TRANSFORM_SECONDS = 2.6, -- phase-2 transformation (invulnerable)
	DAMAGE_TAKEN = 0.85, -- hero damage (percent points) -> boss HP
	HP_MULT = 2.2, -- on top of scaledHp: a raid of four takes about 1-2.5 minutes
	PHASE_TWO_SPEED = 1.2,
	PHASE_TWO_DAMAGE = 1.15,
	ENRAGE_DAMAGE = 1.5,
	ENRAGE_TEMPO = 0.65, -- multiplier on gaps and wind-ups once enraged
	BLOCK_DAMAGE = 0.3,
	HIT_MERCY = 0.35, -- seconds a hero can't be hit again by the same source kind
	GAP = { 1.5, 2.2 }, -- seconds between patterns (phase 1); phase 2 uses 75 %
	-- Wind-up (telegraph) per pattern type, seconds; sweeps bring their own.
	WINDUP = {
		emit = 0.8,
		beam = 1.15,
		charge = 0.95,
		gale = 0.75,
		ring = 0.85,
		dive = 1.1,
		nova = 1.05,
		pillars = 1.15,
		slow = 0.85,
		sweep = 0.8,
	} :: { [string]: number },
	-- Knockback speed (m/s) a hit gives a hero, per pattern type.
	PUSH = {
		emit = 3.5,
		beam = 8,
		charge = 10,
		gale = 2.5,
		ring = 7,
		dive = 10.5,
		nova = 10,
		pillars = 8.5,
		slow = 0,
		sweep = 9.5,
		contact = 6,
	} :: { [string]: number },
}

-- Rewards for one raid (data-driven): later bosses pay more; the first victory over a boss adds a bonus and a title.
Bosses.REWARD = {
	winXp = 140,
	winCoins = 70,
	coinsPerOrder = 6, -- + this many coins per place in Bosses.order
	lossXp = 50,
	lossCoins = 15,
	lossPerPhaseCoins = 10, -- a lost raid that reached phase 2 pays a little more
	firstWinCoins = 150,
}

export type RaidReward = { xp: number, coins: number, firstWin: boolean, title: string? }

function Bosses.reward(id: string, won: boolean, phaseReached: number, firstWin: boolean): RaidReward
	local boss = Bosses.byId[id]
	assert(boss, `unknown boss {id}`)
	local r = Bosses.REWARD
	if not won then
		return {
			xp = r.lossXp,
			coins = r.lossCoins + (if phaseReached >= 2 then r.lossPerPhaseCoins else 0),
			firstWin = false,
		}
	end
	local order = table.find(Bosses.order, id) or 1
	return {
		xp = r.winXp,
		coins = r.winCoins + (order - 1) * r.coinsPerOrder + (if firstWin then r.firstWinCoins else 0),
		firstWin = firstWin,
		title = if firstWin then Bosses.titleFor(id) else nil,
	}
end

-- The title a player earns with the first victory over a boss.
function Bosses.titleFor(id: string): string
	local boss = Bosses.byId[id]
	return `BEZWINGER: {if boss then boss.name else string.upper(id)}`
end

-- The raid boss for a round: the template order, one after the other.
function Bosses.forRound(round: number): string
	return Bosses.order[(math.max(1, math.floor(round)) - 1) % #Bosses.order + 1]
end

-- Size of the raid body in meters: width, height, hover height of the feet.
function Bosses.raidBody(id: string): (number, number, number)
	local boss = Bosses.byId[id]
	assert(boss, `unknown boss {id}`)
	local s = Bosses.RAID.SCALE
	local h = (boss.height or boss.body_h or 3.3) * s
	local w = (boss.body_w or 1.1) * s * Bosses.RAID.WIDTH
	return w, h, (boss.hover or 0.3) * s
end

-- Boss arena for a realm (Data/ArenaThemes raid_hell / raid_heaven, Combat/Arena layout "raid").
function Bosses.arenaFor(id: string): string
	local boss = Bosses.byId[id]
	return if boss and boss.realm == "heaven" then "raid_heaven" else "raid_hell"
end

return Bosses
