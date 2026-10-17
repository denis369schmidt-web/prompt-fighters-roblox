--!strict
-- Bosses for Boss-Raid. Numbers are imported from Godot (Generated/BossData); this module adds order and scaling.

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

return Bosses
