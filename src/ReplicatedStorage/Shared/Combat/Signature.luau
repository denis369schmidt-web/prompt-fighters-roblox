--!strict
-- Runtime of the signature specials (combat.gd _sig_activate, _sig_followup and the signature parts of the
-- tick). Moveset.signatureAbility shapes the move; this module runs what happens when it goes active, the
-- second press of two-stage signatures, timed states (turbo, eagle, volley, iaido ...) and on-hit effects.
-- Fighters and the simulation are passed untyped to avoid a require cycle with Simulation.

local Arena = require(script.Parent.Arena)
local Moveset = require(script.Parent.Moveset)
local Projectiles = require(script.Parent.Projectiles)

type Ability = Moveset.Ability
type Contact = Projectiles.Contact

local Signature = {}

Signature.MARK_TIME = 3.5
Signature.HEAT_MAX = 100

local num = Projectiles.num

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

local function emit(sim: any, event: { [string]: any })
	event.frame = sim.frame
	table.insert(sim.events, event)
end

local function spawn(
	sim: any,
	owner: number,
	spec: { [string]: any },
	damage: number,
	x: number,
	y: number,
	vx: number,
	vy: number
)
	return Projectiles.spawn(sim, owner, spec, damage, x, y, vx, vy)
end

local function merged(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

-- Opponent near enough to aim a targeted signature at (meteor, arrow rain ...), or nil.
local function targetWithin(sim: any, i: number, reach: number): any?
	local f = sim.fighters[i]
	local k = sim:nearestOpponent(i)
	if k and math.abs(sim.fighters[k].x - f.x) < reach then
		return sim.fighters[k]
	end
	return nil
end

local function onStage(f: any): boolean
	return f.grounded and math.abs(f.y) < 0.01
end

-- Opponent currently carrying fighter i's mark, or nil.
function Signature.markedTarget(sim: any, i: number): number?
	for ti, t in sim.fighters do
		if ti ~= i and t.markedBy == i and t.markTimer > 0 and t.state ~= "Defeated" then
			return ti
		end
	end
	return nil
end

-- Clears every signature state of a fighter (ring out, respawn).
function Signature.reset(f: any)
	f.slam = false
	f.dive = 0
	f.bulwark = 0
	f.iai = 0
	f.turbo = 0
	f.eagle = 0
	f.volley = 0
	f.hoverT = 0
	f.chainStage = 0
	f.chainTimer = 0
	f.markedBy = 0
	f.markTimer = 0
	f.freezeTimer = 0
	f.hexT = 0
	f.leashT = 0
	f.heat = 0
end

-- Called when a move starts (combat.gd _begin_pending).
function Signature.onBegin(f: any, a: Ability)
	local sig = a.sig
	if sig and sig.mech == "bulwark" then
		f.bulwark = a.windup
	end
	if a.charge then
		f.sigCharge = 0
	end
end

-- Second press of two-stage signatures: tri slash cuts, the mark strike, spear recall, foxfire release and
-- the meltdown at full heat. Nil when nothing is ready.
function Signature.followup(sim: any, i: number): Ability?
	local f = sim.fighters[i]
	local sig = f.sigParams
	if sig == nil or f.weapon then
		return nil
	end
	local base = f.moves.nspecial :: Ability
	local spDamage = f.specialDamage
	local push = f.specialPush
	local mech = sig.mech
	local function make(name: string, mechName: string): Ability
		local a = Moveset.blank("nspecial", name)
		a.special = true
		a.windup = 0.05
		a.cooldown = base.cooldown
		a.push = push
		a.sig = merged(sig, { mech = mechName })
		return a
	end
	if mech == "tri_slash" and (f.chainStage == 1 or f.chainStage == 2) and f.chainTimer > 0 then
		local stage = f.chainStage + 1
		local a = make(if stage == 2 then "Zweiter Schnitt" else "Drei-Welten-Schnitt", `tri_slash_{stage}`)
		a.damage = spDamage * num(sig, "dmg", 1) * (if stage == 2 then 1 else 1.5)
		Moveset.triSlashCut(a, push, sig, stage)
		return a
	elseif mech == "mark" and Signature.markedTarget(sim, i) then
		local a = make("Blitzschlag", "mark_strike")
		a.damage = spDamage * 1.25
		a.windup, a.active, a.recovery = 0.06, 0.14, 0.26
		a.xMin, a.range, a.yMin, a.yMax = -0.4, 1.6, -0.3, 2.1
		a.angle, a.push, a.hitstun = 50, push * 1.4, 0.5
		return a
	elseif mech == "javelin" then
		for _, pr in sim.projectiles :: { Projectiles.Projectile } do
			if pr.owner == i and pr.stuck then
				local a = make("Speer-Rückruf", "recall")
				a.damage = spDamage * 0.8
				a.active, a.recovery, a.noHit, a.cooldown = 0.1, 0.16, true, 0.3
				return a
			end
		end
	elseif mech == "fox_orbit" then
		for _, pr in sim.projectiles :: { Projectiles.Projectile } do
			if pr.owner == i and pr.spec.orbit and not pr.released then
				local a = make("Fuchsfeuer-Flug", "fox_release")
				a.damage = spDamage
				a.active, a.recovery, a.noHit = 0.1, 0.16, true
				return a
			end
		end
	elseif mech == "magma" and f.heat >= Signature.HEAT_MAX then
		local a = make("KERNSCHMELZE", "meltdown")
		a.damage = spDamage * 1.7
		a.windup, a.active, a.recovery = 0.3, 0.2, 0.4
		a.xMin, a.range, a.yMin, a.yMax, a.allAround = -3, 3, -0.5, 3.2, true
		a.angle, a.push, a.hitstun, a.armor, a.noHeat = 55, push * 2.3, 0.5, 99, true
		return a
	end
	return nil
end

-- One shot of a ki volley, aimed at the nearest opponent in a forward cone; the last one explodes.
local function fireVolley(sim: any, i: number)
	local f = sim.fighters[i]
	local sig = f.sigParams
	f.volley -= 1
	f.volleyT = num(sig, "interval", 0.1)
	local last = f.volley <= 0
	local fx = f.facing
	local dx, dy = fx, 0
	local k = sim:nearestOpponent(i)
	if k then
		local t = sim.fighters[k]
		dx, dy = t.x - f.x, t.y + 1 - (f.y + 1.2)
		local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
		dx, dy = dx / len, dy / len
	end
	if dx * fx < 0.3 then
		dx, dy = fx, math.clamp(dy, -0.7, 0.7)
		local len = math.sqrt(dx * dx + dy * dy)
		dx, dy = dx / len, dy / len
	end
	local spec = merged(sig, { kind = f.fighterId })
	local dmg = f.specialDamage * num(sig, "dmg", 0.16)
	if last then
		spec.size = 0.55
		spec.explode = num(sig, "final_explode", 2)
		dmg *= num(sig, "final_mult", 2.5)
	end
	local speed = num(sig, "speed", 15)
	spawn(sim, i, spec, dmg, f.x + fx * 0.7, f.y + 1.2, dx * speed, dy * speed)
end

local function teleportNextTo(sim: any, f: any, o: any)
	local side = if math.abs(o.x - f.x) > 0.05 then sign(o.x - f.x) else f.facing
	emit(sim, { type = "teleport", actor = f.index, fromX = f.x, fromY = f.y })
	f.x = o.x + side * 0.9
	f.y = o.y
	f.facing = -side
	f.grounded = o.grounded
end

-- Runs a signature at the start of its active frames.
function Signature.activate(sim: any, i: number, a: Ability)
	local f = sim.fighters[i]
	local sig = a.sig :: { [string]: any }
	local dmg = a.damage
	local fx = f.facing
	local spec = merged(sig, { kind = f.fighterId })
	local mech = sig.mech
	emit(sim, { type = "signature", actor = i, mech = mech, color = sig.color, name = a.name })

	if
		mech == "projectile"
		or mech == "mark"
		or mech == "javelin"
		or mech == "magma"
		or mech == "board"
		or mech == "soul_weigh"
		or mech == "hex"
		or mech == "flashbang"
		or mech == "time_bomb"
		or mech == "phase_swap"
		or mech == "chain_leash"
		or mech == "crescent"
		or mech == "lasso"
		or mech == "anchor_chain"
	then
		local count = num(sig, "count", 1)
		local spread = num(sig, "spread", 0.18)
		for k = 0, count - 1 do
			local ang = (k - (count - 1) * 0.5) * spread * fx
			local speed = num(sig, "speed", 12)
			local vx0, vy0 = fx * speed, num(sig, "rise", 0)
			local c, s = math.cos(ang), math.sin(ang)
			spawn(
				sim,
				i,
				spec,
				dmg / math.max(1, count * 0.7),
				f.x + fx * 0.7,
				f.y + 1.15,
				vx0 * c - vy0 * s,
				vx0 * s + vy0 * c
			)
		end
	elseif mech == "clone" then
		spec = merged(spec, { shape = "clone", life = 0.65, size = 0.7, pierce = true, push = 0.7, angle = 40 })
		spawn(sim, i, spec, dmg, f.x + fx * 0.5, f.y + 0.9, fx * num(sig, "speed", 10), 0)
	elseif mech == "eruption" then
		spec = merged(spec, {
			shape = sig.shape or "pillar",
			life = 0.2 + 0.18 * num(sig, "count", 3),
			size = 0.65,
			pierce = true,
			push = 0.8,
			angle = 80,
		})
		spawn(sim, i, spec, dmg, f.x + fx * 0.9, f.y + 0.4, fx * num(sig, "speed", 8), 0)
	elseif mech == "meteor" then
		local t = targetWithin(sim, i, 7)
		local tx = if t then t.x else f.x + fx * 3
		spec = merged(spec, { shape = "meteor", life = 2, gravity = 14, size = num(sig, "size", 0.8) })
		spawn(sim, i, spec, dmg, tx - fx * 2, f.y + 9, fx * 2.5, -6)
	elseif mech == "mine" then
		spec = merged(spec, {
			shape = sig.shape or "mine",
			life = num(sig, "fuse", 9),
			size = 0.6,
			explode = num(sig, "explode", 2),
			push = 0.9,
			angle = 70,
		})
		spawn(sim, i, spec, dmg, f.x + fx, f.y + 0.2, 0, 0)
	elseif mech == "turret" then
		spec = merged(spec, { shape = sig.shape or "turret", life = 3.6, size = 0, emit = 0.45, pierce = true })
		spawn(sim, i, spec, dmg, f.x + fx, f.y + 0.6, 0, 0)
	elseif mech == "teleport" then
		local t = targetWithin(sim, i, 9)
		if t then
			teleportNextTo(sim, f, t)
		end
	elseif mech == "counter" then
		f.counter = 0.45
	elseif mech == "rage" then
		f.rageTimer = num(sig, "time", 6)
	elseif mech == "mark_strike" then
		local mt = Signature.markedTarget(sim, i)
		if mt then
			local mo = sim.fighters[mt]
			teleportNextTo(sim, f, mo)
			mo.markedBy = 0
			mo.markTimer = 0
		end
	elseif mech == "recall" then
		for _, pr in sim.projectiles :: { Projectiles.Projectile } do
			if pr.owner == i and pr.stuck then
				pr.stuck = false
				pr.spec = merged(pr.spec, { turn = 0.01, speed = 20, gravity = 0, pierce = true })
				pr.age = 0.02
				pr.life = 2.5
				pr.hit = {}
				pr.ability = table.clone(pr.ability)
				pr.ability.damage = dmg
				emit(sim, { type = "recall", actor = i, id = pr.id })
			end
		end
	elseif mech == "meltdown" then
		f.heat = 0
	elseif mech == "cannon" then
		local fromX = math.clamp(f.x - fx * 11, Arena.BLAST_LEFT + 1, Arena.BLAST_RIGHT - 1)
		spec = merged(spec, { shape = "cannonball", life = 2.2, size = 0.5, explode = 1.8, push = 0.8, angle = 45 })
		spawn(sim, i, spec, dmg, fromX, f.y + 1, fx * 19, 0)
	elseif mech == "iai" then
		f.iai = a.active
	elseif mech == "volley" then
		f.volley = num(sig, "count", 6)
		f.volleyT = 0
	elseif mech == "nova" then
		spec = merged(spec, { shape = sig.shape or "orb", fuse = 0.01, base_dmg = dmg })
		spawn(sim, i, spec, dmg, f.x, f.y + 2.6, 0, 0)
	elseif mech == "shadow_clone" then
		Projectiles.clearOwned(sim, i, "echo")
		spec = merged(spec, {
			shape = "clone",
			life = num(sig, "life", 5),
			size = 0.7,
			pierce = true,
			push = 0.7,
			angle = 40,
			echo = true,
		})
		spawn(sim, i, spec, dmg, f.x + fx * 0.5, f.y + 0.9, fx * num(sig, "speed", 10), 0)
	elseif mech == "trail_dash" then
		f.trailLastX = f.x
	elseif mech == "tri_slash" or mech == "tri_slash_2" or mech == "tri_slash_3" then
		local stage = if mech == "tri_slash" then 1 elseif mech == "tri_slash_2" then 2 else 3
		if stage < 3 then
			f.chainStage = stage
			f.chainTimer = num(sig, "window", 0.9) + a.active + a.recovery
		else
			f.chainStage = 0
			f.chainTimer = 0
			f.vy = 9
			f.grounded = false
		end
	elseif mech == "star_seal" then
		Projectiles.clearOwned(sim, i, "seal")
		spec = merged(spec, { life = num(sig, "life", 5), pierce = true, push = 0.15, angle = 80, seal = true })
		spawn(sim, i, spec, dmg, f.x, f.y + 0.1, 0, 0)
	elseif mech == "ice_decoy" then
		for _, pr in sim.projectiles :: { Projectiles.Projectile } do
			if pr.owner == i and pr.spec.shape == "ice_decoy" then
				pr.life = 0
			end
		end
		spawn(sim, i, merged(spec, { push = 0.2, angle = 60 }), dmg, f.x, f.y + 0.9, 0, 0)
		emit(sim, { type = "decoy", actor = i, fromX = f.x, fromY = f.y })
		f.x -= fx * num(sig, "blink", 2.6)
		if onStage(f) then
			f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
		end
		f.intangible = math.max(f.intangible, 0.3)
	elseif mech == "turbo" then
		f.turbo = num(sig, "time", 4)
		f.turboHitT = 0
	elseif mech == "eagle" then
		f.eagle = num(sig, "time", 6.5)
		f.eagleStrikeT = 0.45
		f.vy = math.max(f.vy, 7.5)
		if f.grounded then
			f.grounded = false
			f.y += 0.05
		end
		f.airJumps = f.phys.air_jumps
		emit(sim, { type = "eagle_summon", actor = i })
	elseif mech == "breath" then
		-- In the air the fighter hovers while breathing.
		if not f.grounded then
			f.vy = math.max(f.vy, num(sig, "hover", 2.5))
		end
		f.hoverT = num(sig, "time", 0.9)
	elseif mech == "rebirth" then
		local heal = math.min(num(sig, "heal", 12) + f.percent * num(sig, "heal_share", 0.15), f.percent)
		f.percent -= heal
		emit(sim, { type = "rebirth_heal", actor = i, amount = heal })
		f.cooldownSpecial = math.max(f.cooldownSpecial, num(sig, "cooldown", 10))
	elseif mech == "war_horn" then
		f.armorTimer = math.max(f.armorTimer, num(sig, "armor", 3))
		emit(sim, { type = "war_horn", actor = i })
	elseif mech == "fox_orbit" then
		Projectiles.clearOwned(sim, i, "orbit")
		local count = num(sig, "count", 3)
		for k = 0, count - 1 do
			local orb = merged(spec, {
				orbit = true,
				phase = math.pi * 2 * k / count,
				pierce = true,
				homing = 0,
				push = 0.35,
				angle = 50,
			})
			spawn(sim, i, orb, dmg * 0.6, f.x, f.y + 1.1, 0, 0)
		end
	elseif mech == "fox_release" then
		local fsig = f.sigParams
		for _, pr in sim.projectiles :: { Projectiles.Projectile } do
			if pr.owner == i and pr.spec.orbit and not pr.released then
				pr.released = true
				pr.spec = merged(pr.spec, { homing = num(fsig, "homing", 6), pierce = false, rehit = 0 })
				local ax, ay = fx, 0
				local k = sim:nearestOpponent(i)
				if k then
					ax, ay = sim.fighters[k].x - pr.x, sim.fighters[k].y + 1 - pr.y
				end
				local len = math.max(0.001, math.sqrt(ax * ax + ay * ay))
				local speed = num(fsig, "speed", 12)
				pr.vx, pr.vy = ax / len * speed, ay / len * speed
				pr.life = 1.6
				pr.hit = {}
				pr.ability = table.clone(pr.ability)
				pr.ability.damage *= 1.6
				pr.ability.push = 0.6
			end
		end
	elseif mech == "missile_salvo" then
		for k = 0, num(sig, "count", 4) - 1 do
			spawn(sim, i, spec, dmg, f.x - fx * 0.2, f.y + 1.9, fx * (1 + k * 0.9), 9 - k * 0.7)
		end
	elseif mech == "blizzard" then
		Projectiles.clearOwned(sim, i, "storm")
		local t = targetWithin(sim, i, 9)
		local bx, by = f.x + fx * 3, f.y
		if t then
			bx, by = t.x, t.y
		end
		spawn(sim, i, merged(spec, { storm = true, pierce = true }), dmg, bx, by + num(sig, "height", 3.2), 0, 0)
	elseif mech == "arrow_rain" then
		local t = targetWithin(sim, i, 10)
		local ax, ay = f.x + fx * 4, f.y
		if t then
			ax, ay = t.x, t.y
		end
		local count = num(sig, "count", 7)
		local width = num(sig, "width", 2.1)
		local speed = num(sig, "speed", 16)
		for k = 0, count - 1 do
			local px = ax - width * 0.5 + width * k / math.max(1, count - 1)
			local py = ay + num(sig, "height", 7) + (k % 3) * 1.2 + k * 0.25
			-- each arrow ends where it hits the floor
			spawn(sim, i, merged(spec, { life = (py - ay) / speed }), dmg, px, py, 0, -speed)
		end
	elseif mech == "bramble" then
		Projectiles.clearOwned(sim, i, "bush")
		spec = merged(spec, { bush = true, pierce = true })
		for k = 0, num(sig, "count", 3) - 1 do
			local bx = f.x + fx * (1.2 + k * num(sig, "gap", 1))
			if onStage(f) then
				bx = math.clamp(bx, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
			end
			spawn(sim, i, spec, dmg, bx, f.y + 0.35, 0, 0)
		end
	elseif mech == "root_snare" then
		local t = targetWithin(sim, i, 8)
		local rx, ry = f.x + fx * 3, f.y
		if t then
			rx, ry = t.x, t.y
		end
		spawn(sim, i, merged(spec, { pierce = true }), dmg, rx, ry + 0.5, 0, 0)
	elseif mech == "stampede" then
		f.armorTimer = math.max(f.armorTimer, num(sig, "time", 0.9) + 0.1)
	elseif mech == "bone_prison" then
		local k = sim:nearestOpponent(i)
		if k and math.abs(sim.fighters[k].x - f.x) < 8 then
			local t = sim.fighters[k]
			spawn(sim, i, merged(spec, { cage = k, fuse = 0.01, nohit = true }), dmg, t.x, t.y + 1, 0, 0)
		end
	elseif mech == "toxic_cloud" then
		Projectiles.clearOwned(sim, i, "follow_owner")
		spawn(sim, i, merged(spec, { follow_owner = true, pierce = true }), dmg, f.x, f.y + 1, 0, 0)
	elseif mech == "bat_form" then
		f.hoverT = num(sig, "time", 1)
		if not f.grounded then
			f.vy = math.max(f.vy, 1.5)
		end
	elseif mech == "orbital_strike" then
		local t = targetWithin(sim, i, 10)
		local sx, sy = f.x + fx * 4, f.y
		if t then
			sx, sy = t.x, t.y
		end
		spawn(sim, i, merged(spec, { column = true, pierce = true }), dmg, sx, sy + 0.1, 0, 0)
	elseif mech == "revenant" then
		Projectiles.clearOwned(sim, i, "minion")
		local rx = f.x + fx
		if onStage(f) then
			rx = math.clamp(rx, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
		end
		spawn(sim, i, merged(spec, { minion = true, pierce = true }), dmg, rx, f.y + 0.9, 0, 0)
	elseif mech == "flame_wall" then
		Projectiles.clearOwned(sim, i, "wall")
		spec = merged(spec, { life = num(sig, "life", 3), pierce = true, push = 0.55, angle = 65, wall = true })
		spawn(sim, i, spec, dmg, f.x + fx * 1.5, f.y + 0.9, 0, 0)
	elseif mech == "singularity" then
		spec = merged(spec, {
			shape = "singularity",
			life = num(sig, "fuse", 1.6),
			fuse = 0.01,
			size = 0.4,
			nohit = true,
			push = 0.95,
			angle = 50,
		})
		spawn(sim, i, spec, dmg, f.x + fx * 2.5, f.y + 1.2, fx * 1.2, 0)
	elseif mech == "crown_shift" then
		-- Frost: every hit freezes for a moment. Glut: every hit hurts more.
		f.crown = if f.crown == "frost" then "glut" else "frost"
		emit(sim, { type = "crown_shift", actor = i, mode = f.crown })
	elseif mech == "pack_hound" then
		Projectiles.clearOwned(sim, i, "hound")
		local hx = math.clamp(f.x + fx, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
		spawn(sim, i, merged(spec, { hound = true, pierce = true }), dmg, hx, f.y + 0.5, 0, 0)
	elseif mech == "anvil" then
		local t = targetWithin(sim, i, 7)
		local ax = if t then t.x else f.x + fx * 3
		spawn(sim, i, merged(spec, { life = 2.2 }), dmg, ax, f.y + num(sig, "height", 7), 0, -2)
	elseif mech == "bridge_dive" then
		-- Straight up, then head first straight down; the splash throws everyone up.
		f.vy = num(sig, "rise", 13)
		f.y += 0.05
		f.grounded = false
		f.slam = true
		f.slamVx = fx * 1.2
		f.vx = f.slamVx
		f.slamDmg = dmg
		f.dive = num(sig, "dive", 24)
	elseif mech == "leap_slam" then
		local t = targetWithin(sim, i, 9)
		local tx = if t then t.x else f.x + fx * 3
		tx = math.clamp(tx, Arena.STAGE_LEFT + 0.6, Arena.STAGE_RIGHT - 0.6)
		local rise = num(sig, "rise", 11.5)
		local flight = 2 * rise / math.max(1, f.phys.gravity)
		f.vy = rise
		f.y += 0.05
		f.grounded = false
		f.slam = true
		f.slamVx = (tx - f.x) / flight
		f.vx = f.slamVx
		f.slamDmg = dmg
		f.armorTimer = math.max(f.armorTimer, flight + 0.2)
		if math.abs(tx - f.x) > 0.1 then
			f.facing = if tx > f.x then 1 else -1
		end
	end
end

-- Signature timers of one fighter, once per tick before its controls.
function Signature.tick(sim: any, i: number, f: any, dt: number)
	f.bulwark = math.max(0, f.bulwark - dt)
	f.turbo = math.max(0, f.turbo - dt)
	f.turboHitT = math.max(0, f.turboHitT - dt)
	if f.eagle > 0 then
		f.eagle = math.max(0, f.eagle - dt)
		f.eagleStrikeT = math.max(0, f.eagleStrikeT - dt)
		if f.eagle <= 0 then
			emit(sim, { type = "eagle_leave", actor = i })
		end
	end
	if f.chainTimer > 0 then
		f.chainTimer = math.max(0, f.chainTimer - dt)
		if f.chainTimer <= 0 then
			f.chainStage = 0
		end
	end
	if f.markTimer > 0 then
		f.markTimer = math.max(0, f.markTimer - dt)
		if f.markTimer <= 0 then
			f.markedBy = 0
		end
	end
	if f.hexT > 0 then
		f.hexT = math.max(0, f.hexT - dt)
	end
	if f.volley > 0 then
		f.volleyT -= dt
		if f.volleyT <= 0 then
			fireVolley(sim, i)
		end
	end
	if f.leashT > 0 then
		-- Soul chain: the leashed fighter cannot get further away than the chain allows.
		f.leashT = math.max(0, f.leashT - dt)
		local by = sim.fighters[f.leashBy]
		if by and by.state ~= "Defeated" then
			local dx = f.x - by.x
			if math.abs(dx) > f.leashLen then
				f.x = by.x + sign(dx) * f.leashLen
				f.vx = 0
			end
		end
	end
end

-- Movement while a signature state is on: speed multiplier for walking and running.
function Signature.speedScale(f: any): number
	local scale = 1
	local sig = f.sigParams
	if f.turbo > 0 then
		scale *= num(sig, "boost", 1.6)
	end
	if f.eagle > 0 and not f.grounded then
		scale *= num(sig, "boost", 1.3)
	end
	return scale
end

-- Eagle flight: jump rises, down sinks, otherwise it glides. Returns the gravity multiplier.
function Signature.flight(f: any, jump: boolean, up: boolean, down: boolean, dt: number): number
	if f.eagle > 0 and not f.grounded and f.state ~= "Grabbed" and f.state ~= "HitStun" then
		if jump then
			f.vy = math.max(f.vy, 4.5)
		elseif up then
			f.vy = math.min(f.vy + 30 * dt, 6)
		elseif down then
			f.vy = math.max(f.vy - 30 * dt, -7)
		else
			f.vy = if f.vy > 0 then math.max(0, f.vy - 16 * dt) else math.min(0, f.vy + 16 * dt)
		end
		if f.y > 5 then
			f.vy = math.min(f.vy, 0)
		end
		f.airJumps = f.phys.air_jumps
		return num(f.sigParams, "lift", 0.12)
	end
	return 1
end

-- After gravity: diving and hovering.
function Signature.afterGravity(f: any, dt: number)
	if f.slam and f.dive > 0 and f.vy < 0 then
		f.vy = -f.dive
		f.intangible = math.max(f.intangible, 0.1)
		f.dropThrough = 0.1 -- head first through the platforms
	end
	if f.hoverT > 0 then
		f.hoverT -= dt
		f.vy = math.max(f.vy, -0.8)
	end
	if f.slam then
		f.vx = f.slamVx
	end
end

-- Landing of a leap slam or dive: a quake that hits grounded opponents in range, harder up close.
function Signature.onLand(sim: any, i: number, f: any): boolean
	if not f.slam then
		return false
	end
	f.slam = false
	f.dive = 0
	f.vx = 0
	local sig = f.sigParams or {}
	local radius = num(sig, "radius", 6)
	emit(sim, { type = "slam", actor = i, x = f.x, y = f.y, radius = radius, color = sig.color })
	for ti, t in sim.fighters do
		if ti == i or sim:isAlly(i, ti) or t.state == "Defeated" or t.state == "Dazed" or t.state == "Ledge" then
			continue
		end
		local dist = math.abs(t.x - f.x)
		if dist > radius or t.y - f.y > 0.8 or t.y < f.y - 1 then
			continue
		end
		local near = 1 - dist / radius
		local a = Moveset.blank("slam", "Erdbeben")
		a.damage = f.slamDmg * (0.45 + 0.55 * near)
		a.push = 0.35 + 0.7 * near
		a.angle = 80
		a.hitstun = 0.3 + 0.2 * near
		a.range = radius
		a.special = true
		table.insert(sim.queued, {
			from = i,
			to = ti,
			ability = a,
			special = true,
			pushDir = if dist > 0.05 then sign(t.x - f.x) else f.facing,
		})
	end
	return true
end

-- Charging signatures (charge beam, sling fist): the windup waits while special is held.
function Signature.holdCharge(f: any, pending: any, specialHeld: boolean, dt: number)
	local a = pending.ability
	if pending.stage == "windup" and a.charge and specialHeld and a.sig and f.sigCharge < num(a.sig, "charge", 1.4) then
		f.sigCharge += dt
		pending.remaining = math.max(pending.remaining, dt)
	end
end

-- Applies a finished charge at the active start: longer reach, more damage and push.
function Signature.applyCharge(f: any, a: Ability)
	if not a.charge or a.sig == nil then
		return
	end
	local sig = a.sig :: { [string]: any }
	local ch = math.clamp(f.sigCharge / num(sig, "charge", 1.4), 0, 1)
	local length = num(sig, "length", 5)
	a.range = length + (num(sig, "max_length", 14) - length) * ch
	a.damage *= 0.7 + 0.9 * ch
	a.push *= 0.8 + 0.8 * ch
	if sig.mech == "sling_fist" then
		-- only the fist at the end of the stretched arm hits
		a.xMin = math.max(0.3, a.range - num(sig, "tip", 1.5))
	end
end

-- Start of a move's active frames: charge, signature effect, fresh hit lists for shadow clones.
function Signature.onActiveStart(sim: any, i: number, a: Ability)
	local f = sim.fighters[i]
	Signature.applyCharge(f, a)
	for _, pr in sim.projectiles :: { Projectiles.Projectile } do
		if pr.owner == i and pr.echoing then
			pr.echoHits = {}
		end
	end
	if a.sig then
		Signature.activate(sim, i, a)
	end
end

-- Every tick of a running move's active frames.
function Signature.whileActive(sim: any, i: number, f: any, pending: any, contacts: { Contact })
	local a = pending.ability :: Ability
	local pull = a.pullForce
	if pull then
		for ti, t in sim.fighters do
			if
				ti ~= i
				and not sim:isAlly(i, ti)
				and t.state ~= "Defeated"
				and t.state ~= "Dazed"
				and t.state ~= "Ledge"
				and t.intangible <= 0
			then
				local dx = f.x - t.x
				if math.abs(dx) < a.range + 1 and math.abs(t.y - f.y) < 2.5 and math.abs(dx) > 0.5 then
					t.x += sign(dx) * pull * sim.STEP
				end
			end
		end
	end
	if a.sustainVx then
		f.vx = f.facing * a.sustainVx -- stampede keeps running
	end
	if a.sig == nil then
		return
	end
	local sig = a.sig :: { [string]: any }
	if f.iai > 0 and sig.mech == "iai" then
		-- Iaido stance: the first opponent to step into reach is cut down in one flash.
		f.iai = math.max(0, f.iai - sim.STEP)
		local reach = num(sig, "range", 3.8)
		for ti, t in sim.fighters do
			if
				ti == i
				or sim:isAlly(i, ti)
				or t.state == "Defeated"
				or t.state == "Dazed"
				or t.intangible > 0
				or t.invulnerable > 0
			then
				continue
			end
			local fwd = (t.x - f.x) * f.facing
			if fwd > -0.2 and fwd <= reach and math.abs(t.y - f.y) < 1.4 then
				local fromX = f.x
				local orig = f.facing
				f.x = t.x + orig * 1.1
				if onStage(f) then
					f.x = math.clamp(f.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
				end
				f.facing = -orig
				local cut = Moveset.blank("iai", "Iaido-Schnitt")
				cut.damage, cut.push, cut.angle, cut.hitstun, cut.special = a.damage, a.push * 2, 35, 0.5, true
				table.insert(contacts, { from = i, to = ti, ability = cut, special = true, pushDir = -orig })
				emit(sim, { type = "iai_cut", actor = i, target = ti, fromX = fromX, y = f.y })
				f.iai = 0
				pending.remaining = 0
				break
			end
		end
	end
	if sig.mech == "trail_dash" and math.abs(f.x - f.trailLastX) >= 0.7 then
		-- Thunder path: the dash leaves sparks that shock anyone standing in them.
		f.trailLastX = f.x
		spawn(sim, i, {
			kind = "trail",
			shape = "spark_trail",
			color = sig.color,
			life = num(sig, "trail_life", 2),
			size = 0.45,
			rehit = 0.45,
			pierce = true,
			push = 0.12,
			angle = 75,
		}, f.specialDamage * num(sig, "trail_dmg", 0.18), f.x, f.y + 0.15, 0, 0)
	end
end

-- Shadow clones copy the owner's normal attacks from where they stand.
function Signature.echoStrike(
	sim: any,
	i: number,
	a: Ability,
	touches: (x: number, y: number, facing: number, target: any, a: Ability) -> boolean,
	contacts: { Contact }
)
	for _, pr in sim.projectiles :: { Projectiles.Projectile } do
		if pr.owner ~= i or not pr.echoing or pr.echoHits == nil then
			continue
		end
		local hits = pr.echoHits :: { [number]: boolean }
		local k = sim:nearestOpponent(i)
		local facing = if k and sim.fighters[k].x < pr.x then -1 else 1
		for ti, t in sim.fighters do
			if ti == i or sim:isAlly(i, ti) or t.state == "Defeated" or t.state == "Dazed" or hits[ti] then
				continue
			end
			if touches(pr.x, pr.y - 0.9, facing, t, a) then
				hits[ti] = true
				local echo = table.clone(a)
				echo.damage *= num(pr.spec, "echo_mult", 0.5)
				table.insert(
					contacts,
					{ from = i, to = ti, ability = echo, special = false, pushDir = facing, srcX = pr.x }
				)
				emit(sim, { type = "echo_strike", actor = i, x = pr.x, y = pr.y, facing = facing })
			end
		end
	end
end

-- Hits that come from timed states: turbo rams and the eagle's dives.
function Signature.stateContacts(sim: any, contacts: { Contact })
	for i, f in sim.fighters do
		if f.state == "Defeated" then
			continue
		end
		local sig = f.sigParams
		if f.turbo > 0 and f.turboHitT <= 0 and f.grounded and math.abs(f.walkV) >= num(sig, "min_speed", 4.5) then
			for ti, t in sim.fighters do
				if ti == i or sim:isAlly(i, ti) or t.state == "Defeated" or t.state == "Dazed" then
					continue
				end
				if math.abs(t.x - f.x) < 0.95 and math.abs(t.y - f.y) < 1.4 then
					local ram = Moveset.blank("turbo", "Turbo-Rammstoß")
					ram.damage, ram.push, ram.angle, ram.hitstun = f.specialDamage * num(sig, "dmg", 0.45), 0.7, 40, 0.3
					table.insert(
						contacts,
						{ from = i, to = ti, ability = ram, special = true, pushDir = sign(f.walkV) }
					)
					emit(sim, { type = "turbo_ram", actor = i, target = ti })
					f.turboHitT = num(sig, "rehit", 0.6)
					break
				end
			end
		end
		if f.eagle > 0 and f.eagleStrikeT <= 0 then
			local best, bestD = nil, num(sig, "reach", 3.4)
			for ti, t in sim.fighters do
				if ti == i or sim:isAlly(i, ti) or t.state == "Defeated" or t.invulnerable > 0 then
					continue
				end
				local dx, dy = t.x - f.x, (t.y - f.y) * 0.7
				local dd = math.sqrt(dx * dx + dy * dy)
				if dd < bestD then
					best, bestD = ti, dd
				end
			end
			if best then
				local t = sim.fighters[best]
				local claw = Moveset.blank("eagle", "Adlerklauen")
				claw.damage, claw.push, claw.angle, claw.hitstun =
					f.specialDamage * num(sig, "dmg", 0.55), 0.62, 55, 0.32
				table.insert(contacts, {
					from = i,
					to = best,
					ability = claw,
					special = true,
					pushDir = if math.abs(t.x - f.x) > 0.01 then sign(t.x - f.x) else f.facing,
				})
				emit(sim, { type = "eagle_strike", actor = i, target = best, x = t.x, y = t.y })
				f.eagleStrikeT = num(sig, "rehit", 1)
			end
		end
	end
end

-- Damage multiplier of a hit from signature states: curses and the glowing crown.
function Signature.damageMult(attacker: any, target: any): number
	local m = 1
	if target.hexT > 0 then
		m *= target.hexMult
	end
	if attacker.crown == "glut" then
		m *= num(attacker.sigParams, "glut_mult", 1.25)
	end
	return m
end

-- Heat gauge (fighters with phys.heat): heats up when hitting and more when hit.
function Signature.gainHeat(sim: any, attackerIndex: number, targetIndex: number, damage: number)
	for _, pair in { { attackerIndex, 1.2 }, { targetIndex, 1.6 } } do
		local who = sim.fighters[pair[1]]
		if (who.phys :: any).heat and who.heat < Signature.HEAT_MAX then
			who.heat = math.min(Signature.HEAT_MAX, who.heat + damage * pair[2])
			if who.heat >= Signature.HEAT_MAX then
				emit(sim, { type = "heat_full", actor = pair[1] })
			end
		end
	end
end

-- Effects of a landed hit beyond damage and launch (pull, lasso, curse, chain, swap, mark, hook, freeze).
function Signature.onHit(sim: any, contact: Contact, damage: number)
	local attacker = sim.fighters[contact.from]
	local target = sim.fighters[contact.to]
	local a = contact.ability
	local extra: { [string]: any } = contact.extra or {}
	target.iai = 0
	target.bulwark = 0
	target.slam = false
	target.volley = 0
	if extra.pull then
		local toward = if math.abs(attacker.x - target.x) > 0.05 then sign(attacker.x - target.x) else attacker.facing
		target.vx, target.vy = toward * 9, 3.5
	end
	if extra.lasso then
		-- Roped in, swung over the head and thrown behind the thrower.
		local side = attacker.facing
		target.x, target.y = attacker.x - side * 1.1, attacker.y + 0.6
		target.vx, target.vy = -side * 8.5, 6
		emit(sim, { type = "lasso", actor = contact.from, target = contact.to })
	end
	if extra.hex then
		target.hexT, target.hexMult = extra.hex[1], extra.hex[2]
		emit(sim, { type = "hexed", actor = contact.from, target = contact.to, duration = extra.hex[1] })
	end
	if extra.leash then
		target.leashBy, target.leashT, target.leashLen = contact.from, extra.leash[1], extra.leash[2]
		emit(sim, { type = "leashed", actor = contact.from, target = contact.to, duration = extra.leash[1] })
	end
	if extra.swap then
		attacker.x, target.x = target.x, attacker.x
		attacker.y, target.y = target.y, attacker.y
		attacker.intangible = math.max(attacker.intangible, 0.4)
		emit(sim, { type = "swap", actor = contact.from, target = contact.to })
	end
	local steal = extra.lifesteal or a.lifesteal
	if steal then
		attacker.percent = math.max(0, attacker.percent - damage * steal)
	end
	if extra.mark then
		target.markedBy = contact.from
		target.markTimer = Signature.MARK_TIME
		emit(sim, { type = "marked", actor = contact.from, target = contact.to })
	end
	if extra.yank then
		-- Boarding hook: the attacker is pulled to the target and follows up with a kick.
		local side = if math.abs(attacker.x - target.x) > 0.05 then sign(attacker.x - target.x) else -attacker.facing
		local fromX = attacker.x
		attacker.x, attacker.y = target.x + side * 0.9, target.y
		attacker.vx, attacker.vy = 0, 0
		attacker.grounded = false
		attacker.facing = -side
		target.vx, target.vy = 0, 0
		local kick = Moveset.blank("yank", "Enterstiefel")
		kick.damage, kick.push, kick.angle, kick.hitstun, kick.special = a.damage * 2, 0.85, 42, 0.4, true
		table.insert(
			sim.queued,
			{ from = contact.from, to = contact.to, ability = kick, special = true, pushDir = -side }
		)
		emit(sim, { type = "yank", actor = contact.from, target = contact.to, fromX = fromX })
	end
	if a.freeze then
		target.freezeTimer = a.freeze
		emit(sim, { type = "freeze_hit", actor = contact.from, target = contact.to, duration = a.freeze })
	elseif attacker.crown == "frost" then
		target.freezeTimer = math.max(target.freezeTimer, num(attacker.sigParams, "frost_freeze", 0.18))
	end
	if not a.noHeat then
		Signature.gainHeat(sim, contact.from, contact.to, damage)
	end
end

return Signature
