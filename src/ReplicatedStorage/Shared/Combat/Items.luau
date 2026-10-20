--!strict
-- Arena items (combat.gd items, weapons and power-ups): crates, rocks and barrels to pick up and throw,
-- explosive barrels that blow up when hit or thrown, weapons that change a fighter's moves until they break,
-- and power-ups that work on touch. Classic weapons and power-ups drop in every 13 to 18 seconds; shop
-- weapons never spawn here (fairness rule, see Data/Weapons).

local Arena = require(script.Parent.Arena)
local Knockback = require(script.Parent.Knockback)
local Moveset = require(script.Parent.Moveset)
local Projectiles = require(script.Parent.Projectiles)
local Weapons = require(script.Parent.Parent.Data.Weapons)

type Ability = Moveset.Ability

export type Item = {
	id: number,
	kind: string, -- light_crate, heavy_rock, barrel, explosive_barrel, a power-up or a weapon id
	name: string,
	x: number,
	y: number,
	vx: number,
	vy: number,
	startX: number,
	startY: number,
	weight: number,
	state: string, -- resting, free, carried, thrown, wielded, destroyed
	carrier: number,
	thrower: number,
	respawn: number,
	damage: number,
	push: number,
	angle: number,
	fragile: boolean,
	explosive: boolean,
	radius: number,
	power: string?, -- titan, invulnerable, speed, hammer, heal, freeze
	weapon: string?,
	noRespawn: boolean,
}

local Items = {}

local GRAVITY = 24
local PICKUP_REACH = 1.55
local TOUCH_X, TOUCH_Y = 1.15, 1.0
local MAX_ACTIVE = 6
local POWER_TIME = { titan = 12, invulnerable = 6, speed = 10, hammer = 10 }
local HEAL_PERCENT = 30

-- Every kind the renderer may see, in a fixed order (the network sends the index).
Items.KINDS = {
	"light_crate",
	"heavy_rock",
	"barrel",
	"explosive_barrel",
	"titan_mushroom",
	"invulnerable_star",
	"speed_boots",
	"smash_hammer",
	"health_heart",
	"freeze_orb",
}
for _, weapon in Weapons.classic do
	table.insert(Items.KINDS, weapon.id)
end
for _, weapon in Weapons.shop do
	table.insert(Items.KINDS, weapon.id)
end
Items.KIND_INDEX = {} :: { [string]: number }
for index, kind in Items.KINDS do
	Items.KIND_INDEX[kind] = index
end

type Def = {
	kind: string,
	name: string,
	weight: number,
	damage: number,
	push: number,
	angle: number,
	fragile: boolean,
	explosive: boolean,
	radius: number?,
	power: string?,
}

local THROWABLES: { [string]: Def } = {
	light_crate = {
		kind = "light_crate",
		name = "Leichte Kiste",
		weight = 0.6,
		damage = 14,
		push = 0.38,
		angle = 32,
		fragile = true,
		explosive = false,
	},
	heavy_rock = {
		kind = "heavy_rock",
		name = "Schwerer Stein",
		weight = 1.4,
		damage = 24,
		push = 0.58,
		angle = 45,
		fragile = false,
		explosive = false,
	},
	barrel = {
		kind = "barrel",
		name = "Holzfass",
		weight = 0.9,
		damage = 18,
		push = 0.44,
		angle = 36,
		fragile = false,
		explosive = false,
	},
	explosive_barrel = {
		kind = "explosive_barrel",
		name = "Explosiv-Fass",
		weight = 0.88,
		damage = 36,
		push = 0.75,
		angle = 52,
		fragile = true,
		explosive = true,
		radius = 3,
	},
}

local POWERUPS: { [string]: Def } = {
	titan_mushroom = {
		kind = "titan_mushroom",
		name = "Titan-Pilz",
		weight = 0.5,
		damage = 0,
		push = 0,
		angle = 0,
		fragile = false,
		explosive = false,
		power = "titan",
	},
	invulnerable_star = {
		kind = "invulnerable_star",
		name = "Schutzstern",
		weight = 0.5,
		damage = 0,
		push = 0,
		angle = 0,
		fragile = false,
		explosive = false,
		power = "invulnerable",
	},
	speed_boots = {
		kind = "speed_boots",
		name = "Blitz-Schuhe",
		weight = 0.5,
		damage = 0,
		push = 0,
		angle = 0,
		fragile = false,
		explosive = false,
		power = "speed",
	},
	smash_hammer = {
		kind = "smash_hammer",
		name = "Wucht-Hammer",
		weight = 0.5,
		damage = 0,
		push = 0,
		angle = 0,
		fragile = false,
		explosive = false,
		power = "hammer",
	},
	health_heart = {
		kind = "health_heart",
		name = "Herz",
		weight = 0.5,
		damage = 0,
		push = 0,
		angle = 0,
		fragile = false,
		explosive = false,
		power = "heal",
	},
	freeze_orb = {
		kind = "freeze_orb",
		name = "Frostbombe",
		weight = 0.5,
		damage = 25,
		push = 0.5,
		angle = 35,
		fragile = true,
		explosive = true,
		radius = 3.2,
		power = "freeze",
	},
}
Items.POWERUP_KINDS = {
	"titan_mushroom",
	"invulnerable_star",
	"speed_boots",
	"smash_hammer",
	"health_heart",
	"freeze_orb",
}

-- Throwables that lie in the arena from the start: platform name and spot on it (0 = left end, 1 = right end).
local START_ITEMS = {
	{ kind = "light_crate", platform = "wing_left", at = 0.67 },
	{ kind = "heavy_rock", platform = "mid_left", at = 0.5 },
	{ kind = "barrel", platform = "wing_right", at = 0.33 },
	{ kind = "explosive_barrel", platform = "apex", at = 0.5 },
}

local function emit(sim: any, event: { [string]: any })
	event.frame = sim.frame
	table.insert(sim.events, event)
end

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

local function moveToward(value: number, target: number, delta: number): number
	if value < target then
		return math.min(value + delta, target)
	end
	return math.max(value - delta, target)
end

local function add(sim: any, def: Def, x: number, y: number, weapon: string?): Item
	local item: Item = {
		id = #sim.items + 1,
		kind = def.kind,
		name = def.name,
		x = x,
		y = y,
		vx = 0,
		vy = 0,
		startX = x,
		startY = y,
		weight = def.weight,
		state = "resting",
		carrier = 0,
		thrower = 0,
		respawn = 0,
		damage = def.damage,
		push = def.push,
		angle = def.angle,
		fragile = def.fragile,
		explosive = def.explosive,
		radius = def.radius or 3,
		power = def.power,
		weapon = weapon,
		noRespawn = weapon ~= nil or def.power ~= nil,
	}
	table.insert(sim.items, item)
	emit(sim, { type = "item_spawned", id = item.id, kind = item.kind, name = item.name, x = x, y = y })
	return item
end

local function platformSpot(sim: any, name: string, at: number): (number, number)
	for _, p in sim.platforms do
		if p.name == name then
			return p.x1 + (p.x2 - p.x1) * at, p.y + 0.1
		end
	end
	return (at - 0.5) * (Arena.STAGE_RIGHT - Arena.STAGE_LEFT), 0.1
end

-- Places the start throwables of the current layout.
function Items.setup(sim: any)
	sim.items = {}
	sim.itemTimer = 15
	for _, start in START_ITEMS do
		local x, y = platformSpot(sim, start.platform, start.at)
		local item = add(sim, THROWABLES[start.kind], x, y)
		item.noRespawn = false
	end
end

local function randomSpot(sim: any): (number, number)
	local rng = sim.rng
	if rng:next() < 0.35 then
		return rng:range(Arena.STAGE_LEFT + 1, Arena.STAGE_RIGHT - 1), 0.15
	end
	local p = sim.platforms[rng:int(1, #sim.platforms)]
	return rng:range(p.x1 + 0.3, p.x2 - 0.3), p.y + 0.15
end

function Items.spawnWeapon(sim: any, weaponId: string, x: number?, y: number?): Item
	local w = Weapons.byId[weaponId]
	local px, py = x, y
	if px == nil or py == nil then
		px, py = randomSpot(sim)
	end
	return add(sim, {
		kind = weaponId,
		name = w.name,
		weight = 0.7,
		damage = 12,
		push = 0.5,
		angle = 40,
		fragile = false,
		explosive = false,
	}, px :: number, py :: number, weaponId)
end

function Items.spawnRandom(sim: any)
	local rng = sim.rng
	if rng:next() < 0.6 then
		local pool = Weapons.classic
		Items.spawnWeapon(sim, pool[rng:int(1, #pool)].id)
		return
	end
	local kind = Items.POWERUP_KINDS[rng:int(1, #Items.POWERUP_KINDS)]
	local p = sim.platforms[rng:int(1, #sim.platforms)]
	add(sim, POWERUPS[kind], rng:range(p.x1 + 0.3, p.x2 - 0.3), p.y + 0.2)
end

local function applyPower(sim: any, i: number, item: Item)
	local f = sim.fighters[i]
	local power = item.power :: string
	if power == "invulnerable" then
		f.invulnerable = math.max(f.invulnerable, POWER_TIME.invulnerable)
	elseif power == "titan" then
		f.titanTimer = POWER_TIME.titan
	elseif power == "speed" then
		f.speedTimer = POWER_TIME.speed
	elseif power == "hammer" then
		f.hammerTimer = POWER_TIME.hammer
	elseif power == "heal" then
		f.percent = math.max(0, f.percent - HEAL_PERCENT)
	end
	item.state = "destroyed"
	emit(sim, { type = "powerup", actor = i, id = item.id, power = power, name = item.name })
end

function Items.equipWeapon(sim: any, i: number, item: Item)
	local f = sim.fighters[i]
	local w = Weapons.byId[item.weapon :: string]
	item.state = "wielded"
	item.carrier = i
	f.weapon = { id = w.id, uses = w.uses, item = item.id }
	emit(sim, { type = "weapon_pickup", actor = i, id = item.id, weapon = w.id, name = w.name })
end

-- Removes the weapon from a fighter: thrown, dropped or broken.
function Items.dropWeapon(sim: any, i: number, how: string)
	local f = sim.fighters[i]
	local held = f.weapon
	if held == nil then
		return
	end
	f.weapon = nil
	local item = sim.items[held.item] :: Item
	item.carrier = 0
	if how == "throw" then
		item.state = "thrown"
		item.thrower = i
		item.x, item.y = f.x + f.facing * 0.7, f.y + 1
		item.vx, item.vy = f.facing * 15, 3.5
		item.damage = 16
		emit(sim, { type = "item_throw", actor = i, id = item.id })
	elseif how == "break" then
		item.state = "destroyed"
		emit(sim, { type = "weapon_break", actor = i, id = item.id, name = item.name })
	else
		item.state = "free"
		item.x, item.y = f.x, f.y + 0.5
		item.vx, item.vy = 0, 2
	end
end

-- Grab near an item: power-ups work, weapons are taken, anything else is lifted. True if something happened.
function Items.tryPickup(sim: any, i: number): boolean
	local f = sim.fighters[i]
	if f.carriedItem ~= 0 then
		Items.throwCarried(sim, i)
		return true
	end
	if f.weapon then
		Items.dropWeapon(sim, i, "throw")
		return true
	end
	local best: Item? = nil
	local bestDist = PICKUP_REACH
	for _, item in sim.items :: { Item } do
		if item.state == "resting" or item.state == "free" then
			local dx, dy = item.x - f.x, item.y - f.y
			local d = math.sqrt(dx * dx + dy * dy)
			if d < bestDist then
				best, bestDist = item, d
			end
		end
	end
	if best == nil then
		return false
	end
	local item = best :: Item
	if item.power and not item.explosive then
		applyPower(sim, i, item)
	elseif item.weapon then
		Items.equipWeapon(sim, i, item)
	else
		item.state = "carried"
		item.carrier = i
		item.vx, item.vy = 0, 0
		f.carriedItem = item.id
		emit(sim, { type = "item_pickup", actor = i, id = item.id, name = item.name })
	end
	return true
end

-- Standing on a weapon: attack picks it up. True if it did.
function Items.pickupWeaponUnderfoot(sim: any, i: number): boolean
	local f = sim.fighters[i]
	if not f.grounded or f.weapon or f.carriedItem ~= 0 then
		return false
	end
	for _, item in sim.items :: { Item } do
		if
			item.weapon
			and (item.state == "resting" or item.state == "free")
			and math.abs(item.x - f.x) < 0.9
			and math.abs(item.y - f.y) < 0.8
		then
			Items.equipWeapon(sim, i, item)
			return true
		end
	end
	return false
end

function Items.throwCarried(sim: any, i: number)
	local f = sim.fighters[i]
	if f.carriedItem == 0 then
		return
	end
	local item = sim.items[f.carriedItem] :: Item
	item.state = "thrown"
	item.carrier = 0
	item.thrower = i
	item.x, item.y = f.x + f.facing * 0.75, f.y + 0.8
	item.vx = f.facing * 14 / math.max(0.5, item.weight)
	item.vy = 4.5
	f.carriedItem = 0
	emit(sim, { type = "item_throw", actor = i, id = item.id, name = item.name })
end

-- A fighter who gets hit lets the lifted item fall.
function Items.dropCarried(sim: any, i: number)
	local f = sim.fighters[i]
	if f.carriedItem == 0 then
		return
	end
	local item = sim.items[f.carriedItem] :: Item
	item.state = "free"
	item.carrier = 0
	item.vx, item.vy = 0, 1
	f.carriedItem = 0
end

-- Lets go of everything a fighter holds (ring out).
function Items.release(sim: any, i: number)
	local f = sim.fighters[i]
	if f.weapon then
		Items.dropWeapon(sim, i, "break")
	end
	if f.carriedItem ~= 0 then
		local item = sim.items[f.carriedItem] :: Item
		item.state = "free"
		item.carrier = 0
		item.vx, item.vy = 0, 1
		f.carriedItem = 0
	end
end

-- Turns a move into its weapon version; special becomes the weapon ability. Uses wear the weapon down.
function Items.weaponAbility(sim: any, i: number, a: Ability): Ability
	local f = sim.fighters[i]
	local w = Weapons.byId[f.weapon.id]
	local b = table.clone(a)
	b.weapon = w.id
	b.sig = nil
	if a.special then
		local kind = w.special
		b = Moveset.blank("nspecial", `{w.name}`)
		b.special, b.weapon = true, w.id
		b.damage, b.range, b.windup, b.active, b.recovery = 12, 1.2, 0.12, 0.12, 0.3
		b.push, b.angle, b.hitstun, b.cooldown = 0.9, 55, 0.3, 1
		if Weapons.projectiles[kind] then
			b.spawnShot, b.noHit = kind, true
		elseif kind == "quake" then
			b.allAround, b.xMin, b.range, b.yMin, b.yMax = true, -2.6, 2.6, -0.3, 1.4
			b.damage, b.angle, b.push, b.windup = 16, 70, 1.3, 0.2
		elseif kind == "frost_nova" then
			b.allAround, b.xMin, b.range, b.yMin, b.yMax = true, -2.4, 2.4, -0.5, 2.4
			b.damage, b.angle, b.push, b.freeze = 9, 50, 0.6, 1.2
		end
	elseif w.shoot then
		b.spawnShot, b.noHit = w.shoot, true
		b.windup = math.max(0.04, a.windup + w.windup)
	else
		b.range = a.range + w.reach
		b.damage = a.damage * w.dmg
		b.push = a.push * w.kb
		b.windup = math.max(0.03, a.windup + w.windup)
		if w.freeze then
			b.freeze = w.freeze
		end
	end
	f.weapon.uses -= 1
	if f.weapon.uses <= 0 then
		b.breaksWeapon = true
	end
	return b
end

-- The power hammer replaces the jab while it lasts.
function Items.hammerAbility(): Ability
	local a = Moveset.blank("jab", "Wucht-Hammer")
	a.damage, a.range, a.windup, a.active, a.recovery = 42, 1.6, 0.15, 0.15, 0.22
	a.push, a.angle, a.cooldown, a.hitstun = 1.6, 42, 0.35, 0.45
	return a
end

-- Start of a weapon move's active frames: fire its shot, break it if it was the last use.
function Items.onActiveStart(sim: any, i: number, a: Ability)
	local f = sim.fighters[i]
	local kind = a.spawnShot
	if kind then
		local spec = table.clone(Weapons.projectiles[kind])
		spec.kind = kind
		spec.shape = spec.shape or kind
		if f.weapon then
			spec.color = Weapons.byId[f.weapon.id].color
		end
		Projectiles.spawn(sim, i, spec, spec.damage, f.x + f.facing * 0.7, f.y + 1.1, f.facing * spec.speed, 0)
	end
	if a.breaksWeapon and f.weapon then
		Items.dropWeapon(sim, i, "break")
	end
end

-- Hits on explosive items when an attack goes active near them.
function Items.attackReach(sim: any, i: number, a: Ability)
	local f = sim.fighters[i]
	for k, item in sim.items :: { Item } do
		if item.state ~= "destroyed" and item.state ~= "carried" and item.state ~= "wielded" and item.explosive then
			local forward = (item.x - f.x) * f.facing
			local reach = a.range + 0.4
			local inReach = if a.allAround then math.abs(forward) <= reach else forward >= -0.35 and forward <= reach
			if inReach and math.abs(item.y - f.y) <= 1.4 then
				item.thrower = i
				Items.explode(sim, k)
			end
		end
	end
end

-- Explosion of a barrel or frost bomb: falloff damage and launch for everyone in range.
function Items.explode(sim: any, index: number)
	local item = sim.items[index] :: Item
	if item.state == "destroyed" then
		return
	end
	item.state = "destroyed"
	item.respawn = 9
	local freeze = item.power == "freeze"
	emit(sim, {
		type = "item_explode",
		id = item.id,
		x = item.x,
		y = item.y,
		radius = item.radius,
		freeze = freeze,
		actor = item.thrower,
	})
	for fi, f in sim.fighters do
		if f.state == "Defeated" or f.state == "Dazed" or f.invulnerable > 0 then
			continue
		end
		local dx, dy = f.x - item.x, f.y + 0.75 - item.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist > item.radius then
			continue
		end
		f.pending = nil
		f.blocking = false
		f.grounded = false
		f.dropThrough = 0.15
		f.state = "HitStun"
		if freeze then
			f.freezeTimer = 2.5
			f.stun = 2.5
			f.vx, f.vy = 0, 0
			emit(sim, { type = "freeze_hit", actor = item.thrower, target = fi, duration = 2.5 })
			continue
		end
		local falloff = math.clamp(1 - dist / item.radius, 0.35, 1)
		local damage = item.damage * falloff * math.clamp(1 - f.stats.defense * 0.01, 0.55, 0.9)
		f.percent = math.clamp(f.percent + damage, 0, 999)
		local weight = math.clamp(f.weight, 0.85, 1.35)
		local impulse = item.push * 4.25 * falloff * Knockback.launchScale(f.percent) / weight
		local dir = if math.abs(dx) > 0.05 then sign(dx) else (if fi % 2 == 0 then 1 else -1)
		f.vx = dir * impulse * 0.85
		f.vy = math.max(impulse * 0.5, 1.8)
		f.stun = Knockback.hitstun(f.percent)
		f.airControlLock = f.stun * 0.6
		if item.thrower ~= 0 and item.thrower ~= fi then
			sim._lastHitBy[fi] = item.thrower
		end
		emit(sim, {
			type = "hit",
			actor = if item.thrower ~= 0 then item.thrower else fi,
			target = fi,
			damage = damage,
			special = true,
			superHit = true,
			impulse = impulse,
			percent = f.percent,
		})
	end
end

-- Power-up timers and touching power-ups on the floor.
function Items.tickFighter(sim: any, i: number, f: any, dt: number)
	f.titanTimer = math.max(0, f.titanTimer - dt)
	f.speedTimer = math.max(0, f.speedTimer - dt)
	f.hammerTimer = math.max(0, f.hammerTimer - dt)
	if f.state == "Defeated" then
		return
	end
	for _, item in sim.items :: { Item } do
		if
			item.power
			and not item.explosive
			and (item.state == "resting" or item.state == "free")
			and math.abs(item.x - f.x) < TOUCH_X
			and math.abs(item.y - f.y) < TOUCH_Y
		then
			applyPower(sim, i, item)
		end
	end
end

-- Item physics, thrown hits, respawns and new drops. Runs once per tick after the fighters moved.
function Items.update(sim: any, dt: number)
	sim.itemTimer -= dt
	if sim.itemTimer <= 0 then
		sim.itemTimer = sim.rng:range(13, 18)
		local active = 0
		for _, item in sim.items :: { Item } do
			if item.state ~= "destroyed" then
				active += 1
			end
		end
		if active < MAX_ACTIVE then
			Items.spawnRandom(sim)
		end
	end

	for index, item in sim.items :: { Item } do
		if item.state == "wielded" or item.state == "carried" then
			local c = sim.fighters[item.carrier]
			if c then
				item.x = c.x + (if item.state == "carried" then c.facing * 0.65 else 0)
				item.y = c.y + (if item.state == "carried" then 0.8 else 1)
			end
			continue
		end
		if item.state == "destroyed" then
			if not item.noRespawn then
				item.respawn -= dt
				if item.respawn <= 0 then
					item.state = "resting"
					item.x, item.y, item.vx, item.vy = item.startX, item.startY, 0, 0
					item.carrier, item.thrower = 0, 0
					emit(sim, {
						type = "item_spawned",
						id = item.id,
						kind = item.kind,
						name = item.name,
						x = item.x,
						y = item.y,
					})
				end
			end
			continue
		end
		if item.state ~= "thrown" and item.state ~= "free" then
			continue
		end
		item.vy -= GRAVITY * dt * 0.85
		item.x += item.vx * dt
		item.y += item.vy * dt
		local landed = false
		if item.vy <= 0 then
			for _, p in sim.platforms do
				if item.x >= p.x1 and item.x <= p.x2 and item.y <= p.y + 0.1 and item.y >= p.y - 0.2 then
					item.y = p.y + 0.1
					landed = true
					break
				end
			end
			if not landed and item.x >= Arena.STAGE_LEFT and item.x <= Arena.STAGE_RIGHT and item.y <= 0.1 then
				item.y = 0.1
				landed = true
			end
		end
		local wasThrown = item.state == "thrown"
		if landed then
			item.vy = 0
			item.vx = moveToward(item.vx, 0, 18 * dt)
			item.state = "resting"
			if item.explosive and (wasThrown or math.abs(item.vx) > 2) then
				Items.explode(sim, index)
				continue
			end
		end
		if wasThrown then
			for fi, t in sim.fighters do
				if fi == item.thrower or (item.thrower ~= 0 and sim:isAlly(item.thrower, fi)) then
					continue
				end
				if t.state == "Defeated" or t.state == "Dazed" or t.invulnerable > 0 then
					continue
				end
				if math.abs(item.x - t.x) < 1.25 and math.abs(item.y - (t.y + 0.75)) < 1.35 then
					if item.explosive then
						Items.explode(sim, index)
						break
					end
					local damage = item.damage * math.clamp(1 - t.stats.defense * 0.01, 0.6, 0.92)
					t.percent = math.clamp(t.percent + damage, 0, 999)
					local weight = math.clamp(t.weight, 0.85, 1.35)
					local impulse = item.push * 5 * (1 + t.percent * 0.022 + t.percent * damage * 0.0015) / weight
					local dir = if math.abs(item.vx) > 0.1 then sign(item.vx) else 1
					t.vx = dir * impulse * math.cos(math.rad(item.angle))
					t.vy = impulse * math.sin(math.rad(item.angle))
					t.grounded = false
					t.dropThrough = 0.15
					t.stun = math.clamp(0.32 + t.percent * 0.003, 0.2, 0.85)
					t.state = "HitStun"
					t.pending = nil
					t.blocking = false
					if item.thrower ~= 0 then
						sim._lastHitBy[fi] = item.thrower
					end
					emit(sim, {
						type = "hit",
						actor = if item.thrower ~= 0 then item.thrower else fi,
						target = fi,
						damage = damage,
						impulse = impulse,
						percent = t.percent,
						item = item.id,
					})
					if item.fragile then
						item.state = "destroyed"
						item.respawn = 7
						emit(sim, { type = "item_break", id = item.id, x = item.x, y = item.y })
					else
						item.vx *= -0.3
						item.vy = 2.5
						item.state = "free"
					end
					break
				end
			end
		end
		if
			item.state ~= "destroyed"
			and (item.y < Arena.BLAST_BOTTOM or item.x < Arena.BLAST_LEFT or item.x > Arena.BLAST_RIGHT)
		then
			item.state = "destroyed"
			item.respawn = 6
		end
	end
end

-- Network state of the items: flat { id, kindIndex, x, y, state, ... } for everything not destroyed.
-- state: 1 lying, 2 flying, 10 + fighter carried, 20 + fighter wielded.
function Items.encode(sim: any): { number }
	local out = {}
	for _, item in sim.items :: { Item } do
		if item.state == "destroyed" then
			continue
		end
		local state = if item.state == "carried"
			then 10 + item.carrier
			elseif item.state == "wielded" then 20 + item.carrier
			elseif item.state == "thrown" then 2
			else 1
		table.insert(out, item.id)
		table.insert(out, Items.KIND_INDEX[item.kind] or 0)
		table.insert(out, math.round(item.x * 100) / 100)
		table.insert(out, math.round(item.y * 100) / 100)
		table.insert(out, state)
	end
	return out
end

return Items
