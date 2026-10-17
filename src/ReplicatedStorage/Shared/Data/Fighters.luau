--!strict
-- Fighter definitions: the roster joined with the imported Godot numbers (preset stats, kit, signature).
-- Logic reads fighters only through this module: Fighters.get(id) / Fighters.list.

local Roster = require(script.Parent.Roster)
local Presets = require(script.Parent.Generated.FighterPresets)
local Kits = require(script.Parent.Generated.FighterKits)
local Signatures = require(script.Parent.Generated.SignatureParams)

export type Stats = { vitality: number, power: number, defense: number, speed: number, technique: number }
export type Move = {
	name: string,
	dmg: number,
	windup: number,
	active: number,
	recovery: number,
	xMin: number,
	xMax: number,
	yMin: number,
	yMax: number,
	angle: number,
	kb: number,
	extras: { [string]: any },
}
export type Physics = {
	jump: number,
	gravity: number,
	fast_fall: number,
	air: number,
	air_jumps: number,
	run: number,
	shield: number,
	[string]: number,
}
export type Finisher = { name: string, code: { string }, kind: string }
export type Fighter = Roster.RosterEntry & {
	element: string,
	weight: number,
	runSpeed: number,
	stats: Stats,
	health: number,
	phys: Physics,
	standardName: string,
	specialName: string,
	moves: { [string]: Move },
	signatureParams: { [string]: any },
	finisher: Finisher,
	gear: { string },
}

local Fighters = {}
Fighters.list = {} :: { Fighter }
Fighters.byId = {} :: { [string]: Fighter }

for _, entry in Roster do
	local preset = (Presets :: any)[entry.id]
	local kit = (Kits.kits :: any)[entry.id]
	local sig = (Signatures :: any)[entry.id]
	assert(preset and kit and sig, `missing Godot data for fighter {entry.id}`)

	local phys = table.clone(Kits.defaultPhys) :: any
	for key, value in kit.phys or {} do
		phys[key] = value
	end

	local fighter = table.clone(entry) :: any
	fighter.element = preset.element
	fighter.weight = kit.weight or preset.weight
	fighter.runSpeed = kit.speed
	fighter.stats = preset.stats
	-- Health for boss and adventure modes (prompt_interpreter.gd: 90 + vitality * 1.6).
	fighter.health = 90 + preset.stats.vitality * 1.6
	fighter.phys = phys
	fighter.standardName = kit.standard_name or preset.standard.name
	fighter.specialName = kit.special_name or preset.special.name
	fighter.moves = kit.moves
	fighter.signatureParams = sig
	fighter.finisher = kit.finisher
	fighter.gear = preset.gear

	table.insert(Fighters.list, fighter)
	Fighters.byId[entry.id] = fighter
end

function Fighters.get(id: string): Fighter
	local fighter = Fighters.byId[id]
	assert(fighter, `unknown fighter {id}`)
	return fighter
end

function Fighters.starters(): { Fighter }
	local result = {}
	for _, fighter in Fighters.list do
		if fighter.unlock.kind == "starter" then
			table.insert(result, fighter)
		end
	end
	return result
end

return Fighters
