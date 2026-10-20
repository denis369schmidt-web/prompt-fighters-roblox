--!strict
-- Weapon items (numbers imported from combat.gd) plus shop prices (rewards.gd).
-- reach 0 = projectile weapon (see `shoot`). dmg/kb are multipliers; uses = attacks until it breaks.
-- Fairness rule: Ranked spawns only the 8 classic items and allows no start weapon.

local WeaponData = require(script.Parent.Generated.WeaponData)
local RewardData = require(script.Parent.Generated.RewardData)

export type Weapon = {
	id: string,
	name: string,
	reach: number,
	dmg: number,
	kb: number,
	windup: number,
	uses: number,
	special: string,
	shoot: string?,
	freeze: number?,
	shop: boolean?,
	color: string?,
	price: number?,
	rarity: string?,
}

local Weapons = {}
Weapons.byId = {} :: { [string]: Weapon }
Weapons.classic = {} :: { Weapon }
Weapons.shop = {} :: { Weapon }
Weapons.projectiles = WeaponData.projectiles :: { [string]: any }

for id, def in WeaponData.weapons :: { [string]: any } do
	local weapon = table.clone(def)
	weapon.id = id
	Weapons.byId[id] = weapon
end
for _, offer in RewardData.shopWeapons do
	local weapon = Weapons.byId[offer.id] :: any
	assert(weapon, `shop weapon {offer.id} has no combat definition`)
	weapon.price = offer.price
	weapon.rarity = offer.rarity
	table.insert(Weapons.shop, weapon)
end
for _, weapon in Weapons.byId do
	if not weapon.shop then
		table.insert(Weapons.classic, weapon)
	end
end
table.sort(Weapons.classic, function(a, b)
	return a.id < b.id
end)

-- Weapons allowed to spawn in a mode: classic items, plus owned shop weapons outside Ranked.
function Weapons.spawnPool(mode: string, owned: { [string]: boolean }?): { Weapon }
	local pool = table.clone(Weapons.classic)
	if mode ~= "ranked" and owned then
		for _, weapon in Weapons.shop do
			if owned[weapon.id] then
				table.insert(pool, weapon)
			end
		end
	end
	return pool
end

function Weapons.startWeaponAllowed(mode: string): boolean
	return mode ~= "ranked"
end

return Weapons
