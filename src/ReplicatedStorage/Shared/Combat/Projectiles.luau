--!strict
-- Generic projectiles of the signature specials (combat.gd spawn_projectile_spec / _update_projectiles).
-- One spec table drives every shape: speed, gravity, homing, return, explode, pools, walls, summons that walk,
-- clouds that follow, columns from the sky. Projectile hits become contacts that the Simulation resolves
-- like any other attack, so armor, shields, counters and knockback work the same for every source.

local Arena = require(script.Parent.Arena)
local Moveset = require(script.Parent.Moveset)

type Ability = Moveset.Ability

local BODY_H = 1.8

export type Contact = {
	from: number,
	to: number,
	ability: Ability,
	special: boolean,
	pushDir: number?,
	srcX: number?,
	extra: { [string]: any }?,
	isCounter: boolean?,
}

export type Projectile = {
	id: number,
	owner: number,
	spec: { [string]: any },
	x: number,
	y: number,
	vx: number,
	vy: number,
	baseY: number,
	life: number,
	age: number,
	returning: boolean,
	hit: { [number]: boolean },
	emitT: number,
	rehitT: number,
	ability: Ability,
	sizeNow: number?,
	launched: boolean?,
	echoing: boolean?,
	echoHits: { [number]: boolean }?,
	stuck: boolean?,
	stuckTo: number?,
	pooled: boolean?,
	released: boolean?,
}

local Projectiles = {}

local function num(spec: { [string]: any }, key: string, default: number): number
	local v = spec[key]
	return if type(v) == "number" then v else default
end
Projectiles.num = num

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

local function moveToward(value: number, target: number, delta: number): number
	if value < target then
		return math.min(value + delta, target)
	end
	return math.max(value - delta, target)
end

local function emit(sim: any, event: { [string]: any })
	event.frame = sim.frame
	table.insert(sim.events, event)
end

function Projectiles.spawn(
	sim: any,
	owner: number,
	spec: { [string]: any },
	damage: number,
	x: number,
	y: number,
	vx: number,
	vy: number
): Projectile
	sim.projectileSerial += 1
	local a = Moveset.blank("projectile", tostring(spec.kind or "shot"))
	a.damage = damage
	a.push = num(spec, "push", 0.5)
	a.angle = num(spec, "angle", 35)
	a.hitstun = 0.28
	a.range = 1
	a.special = true
	if spec.freeze then
		a.freeze = spec.freeze
	end
	local pr: Projectile = {
		id = sim.projectileSerial,
		owner = owner,
		spec = spec,
		x = x,
		y = y,
		vx = vx,
		vy = vy,
		baseY = y,
		life = num(spec, "life", 1),
		age = 0,
		returning = false,
		hit = {},
		emitT = 0,
		rehitT = 0,
		ability = a,
	}
	table.insert(sim.projectiles, pr)
	emit(sim, {
		type = "projectile",
		actor = owner,
		id = pr.id,
		shape = tostring(spec.shape or ""),
		style = Projectiles.styleOf(spec),
		size = num(spec, "size", 0.5),
		color = spec.color,
	})
	return pr
end

-- Ends every projectile of `owner` whose spec has `flag` set (one wall / cloud / servant at a time).
function Projectiles.clearOwned(sim: any, owner: number, flag: string)
	for _, pr in sim.projectiles :: { Projectile } do
		if pr.owner == owner and pr.spec[flag] then
			pr.life = 0
		end
	end
end

-- How the client draws a projectile: the behaviour decides more than the shape name.
function Projectiles.styleOf(spec: { [string]: any }): string
	if spec.column then
		return "column"
	elseif spec.storm then
		return "storm"
	elseif spec.wall then
		return "wall"
	elseif spec.follow_owner then
		return "cloud"
	elseif spec.minion or spec.hound or spec.shape == "clone" or spec.echo then
		return "creature"
	elseif num(spec, "emit", 0) > 0 then
		return "turret"
	elseif spec.seal or spec.bush or spec.cage then
		return "ground"
	elseif num(spec, "explode", 0) > 0 and num(spec, "speed", 0) == 0 then
		return "mine"
	elseif spec.orbit or spec.grow then
		return "orb"
	end
	return "shot"
end

local function explode(sim: any, pr: Projectile, contacts: { Contact })
	local radius = num(pr.spec, "explode", 0)
	if pr.sizeNow then
		radius *= (pr.sizeNow :: number) / num(pr.spec, "size", 1) -- grown orbs blow up bigger
	end
	emit(sim, { type = "blast", actor = pr.owner, x = pr.x, y = pr.y, radius = radius, color = pr.spec.color })
	if pr.spec.flash then
		emit(sim, { type = "flashbang", actor = pr.owner, x = pr.x, y = pr.y })
	end
	for ti, t in sim.fighters do
		if ti ~= pr.owner and not sim:isAlly(pr.owner, ti) and t.state ~= "Defeated" and t.state ~= "Dazed" then
			local dx, dy = t.x - pr.x, t.y + BODY_H * 0.45 - pr.y
			if math.sqrt(dx * dx + dy * dy) <= radius then
				table.insert(contacts, {
					from = pr.owner,
					to = ti,
					ability = pr.ability,
					special = true,
					pushDir = if math.abs(dx) > 0.05 then sign(dx) else 1,
					srcX = pr.x,
				})
			end
		end
	end
end

local function nearestTo(sim: any, owner: number): any?
	local k = sim:nearestOpponent(owner)
	return if k then sim.fighters[k] else nil
end

-- Moves every projectile one step and appends its hits to `contacts`.
function Projectiles.update(sim: any, dt: number, contacts: { Contact })
	local keep: { Projectile } = {}
	for _, pr in sim.projectiles :: { Projectile } do
		local d = pr.spec
		pr.age += dt
		pr.life -= dt
		if pr.stuck then
			-- A thrown spear stuck in the floor waits to be recalled.
			if pr.life > 0 then
				table.insert(keep, pr)
			else
				emit(sim, { type = "projectile_end", id = pr.id })
			end
			continue
		end
		local owner = sim.fighters[pr.owner]
		local speed = num(d, "speed", 10)

		if d.grow then
			-- Nova orb: grows above the owner's head, then is hurled at the nearest opponent.
			local base = num(d, "size", 0.3)
			pr.sizeNow = math.min(num(d, "max_size", 1), base + d.grow * pr.age)
			if not pr.launched then
				if pr.age < num(d, "hold", 1) and owner.state ~= "HitStun" and owner.state ~= "Defeated" then
					pr.x, pr.y, pr.vx, pr.vy = owner.x, owner.y + 2.6, 0, 0
				else
					pr.launched = true
					local ax, ay = owner.facing, -0.3
					local t = nearestTo(sim, pr.owner)
					if t then
						ax, ay = t.x - pr.x, t.y + 1 - pr.y
					end
					local len = math.max(0.001, math.sqrt(ax * ax + ay * ay))
					pr.vx, pr.vy = ax / len * speed, ay / len * speed
					local grown = (pr.sizeNow :: number) / base
					pr.ability = table.clone(pr.ability)
					pr.ability.damage = num(d, "base_dmg", pr.ability.damage) * (0.6 + 0.4 * grown)
					emit(sim, { type = "nova_launch", actor = pr.owner, id = pr.id, size = pr.sizeNow })
				end
			end
		end
		if d.echo and not pr.echoing and pr.age >= num(d, "dash_time", 0.45) then
			-- Shadow clone: after its dash it stays and copies the owner's attacks.
			pr.echoing = true
			pr.vx, pr.vy = 0, 0
			pr.echoHits = {}
			emit(sim, { type = "clone_ready", actor = pr.owner, id = pr.id, x = pr.x })
		end
		if d.seal then
			-- Star seal: its owner standing inside is enraged.
			if
				math.abs(owner.x - pr.x) <= num(d, "size", 1.7)
				and math.abs(owner.y - pr.y) < 1.5
				and owner.state ~= "Defeated"
			then
				owner.rageTimer = math.max(owner.rageTimer, 0.15)
			end
		end
		if math.abs(pr.vx) + math.abs(pr.vy) > 0.5 and not d.echo then
			-- Fire walls stop enemy shots.
			local blocked = false
			for _, w in sim.projectiles :: { Projectile } do
				if
					w.spec.wall
					and w.owner ~= pr.owner
					and not sim:isAlly(w.owner, pr.owner)
					and w.life > 0
					and math.abs(w.x - pr.x) < 0.7
					and math.abs(w.y - pr.y) < 1.4
				then
					blocked = true
					emit(sim, { type = "wall_block", actor = w.owner, x = pr.x, y = pr.y })
					break
				end
			end
			if blocked then
				emit(sim, { type = "projectile_end", id = pr.id })
				continue
			end
		end
		if num(d, "gravity_pull", 0) > 0 then
			-- Singularity: drags opponents towards its core.
			for ti, t in sim.fighters do
				if
					ti ~= pr.owner
					and not sim:isAlly(pr.owner, ti)
					and t.state ~= "Defeated"
					and t.state ~= "Dazed"
					and t.state ~= "Ledge"
					and t.intangible <= 0
				then
					local cx, cy = pr.x - t.x, pr.y - (t.y + 0.9)
					local dist = math.sqrt(cx * cx + cy * cy)
					if dist < num(d, "pull_radius", 4) and dist > 0.35 then
						t.x += sign(cx) * d.gravity_pull * dt
						if not t.grounded then
							t.vy = moveToward(t.vy, sign(cy) * 3, 20 * dt)
						end
					end
				end
			end
		end
		local turn = num(d, "turn", -1)
		if turn > 0 and pr.age >= turn then
			-- Returning projectiles fly back to their owner.
			local tx, ty = owner.x - pr.x, owner.y + 1.1 - pr.y
			local len = math.sqrt(tx * tx + ty * ty)
			if len < 0.7 and pr.age > turn + 0.1 then
				if d.javelin then
					owner.cooldownSpecial = 0 -- catching the spear readies the next throw
					emit(sim, { type = "catch", actor = pr.owner })
				end
				emit(sim, { type = "projectile_end", id = pr.id })
				continue
			end
			len = math.max(len, 0.001)
			pr.vx, pr.vy = tx / len * speed, ty / len * speed
			if not pr.returning then
				pr.hit = {}
			end
			pr.returning = true
		end
		if num(d, "homing", 0) > 0 and pr.age >= num(d, "home_delay", 0) then
			local t = nearestTo(sim, pr.owner)
			if t then
				local wx, wy = t.x - pr.x, t.y + 1 - pr.y
				local len = math.max(0.001, math.sqrt(wx * wx + wy * wy))
				wx, wy = wx / len * speed, wy / len * speed
				local ddx, ddy = wx - pr.vx, wy - pr.vy
				local dl = math.sqrt(ddx * ddx + ddy * ddy)
				local step = d.homing * speed * dt
				if dl <= step then
					pr.vx, pr.vy = wx, wy
				else
					pr.vx += ddx / dl * step
					pr.vy += ddy / dl * step
				end
			end
		end
		pr.vy -= num(d, "gravity", 0) * dt
		pr.x += pr.vx * dt
		pr.y += pr.vy * dt
		if num(d, "wave", 0) > 0 then
			pr.y = pr.baseY + math.sin(pr.age * 9) * 0.5 * d.wave
		end
		if d.hound then
			-- Star hound: runs to the opponent and keeps biting; it leaps after airborne targets.
			pr.vx = 0
			local t = nearestTo(sim, pr.owner)
			if t then
				if math.abs(t.x - pr.x) > 0.3 then
					pr.vx = sign(t.x - pr.x) * num(d, "walk", 7.5)
				end
				pr.y = moveToward(pr.y, t.y + 0.5, 7 * dt)
			end
			pr.x = math.clamp(pr.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
		end
		if d.minion then
			-- Skeleton servant: walks to the nearest opponent.
			pr.vx = 0
			local t = nearestTo(sim, pr.owner)
			if t and math.abs(t.x - pr.x) > 0.5 then
				pr.vx = sign(t.x - pr.x) * num(d, "walk", 3)
			end
			pr.x = math.clamp(pr.x, Arena.STAGE_LEFT, Arena.STAGE_RIGHT)
		end
		if pr.stuckTo then
			-- Time bomb: rides along on its victim.
			local sb = sim.fighters[pr.stuckTo :: number]
			pr.x, pr.y = sb.x, sb.y + 1.2
		end
		if d.follow_owner then
			-- Poison cloud: stays around its owner.
			pr.x, pr.y = owner.x, owner.y + 1
		end
		if d.cage then
			-- Bone prison: the caged opponent cannot get out.
			local ct = sim.fighters[d.cage]
			if ct and ct.state ~= "Defeated" then
				ct.x = math.clamp(ct.x, pr.x - 0.8, pr.x + 0.8)
				if ct.y > pr.y + 1.2 then
					ct.y = pr.y + 1.2
					ct.vy = math.min(ct.vy, 0)
				end
			end
		end
		if d.orbit and not pr.released then
			-- Foxfire ring: circles its owner until it is hurled.
			local ang = num(d, "phase", 0) + pr.age * num(d, "spin", 4)
			local r = num(d, "radius", 1.3)
			pr.x, pr.y = owner.x + math.cos(ang) * r, owner.y + 1.1 + math.sin(ang) * r * 0.8
			pr.vx, pr.vy = 0, 0
		end
		if d.storm then
			-- Blizzard: the snow cloud drifts after the nearest opponent.
			local t = nearestTo(sim, pr.owner)
			if t then
				pr.x = moveToward(pr.x, t.x, num(d, "follow", 2.2) * dt)
			end
		end
		if num(d, "emit", 0) > 0 then
			-- Turret: fires bolts at the nearest opponent.
			pr.emitT += dt
			if pr.emitT >= d.emit then
				pr.emitT = 0
				local t = nearestTo(sim, pr.owner)
				local dir = if t then sign(t.x - pr.x) else 1
				Projectiles.spawn(sim, pr.owner, {
					kind = "bolt",
					shape = "bolt",
					color = d.color,
					speed = 20,
					life = 0.6,
					size = 0.3,
					push = 0.25,
					angle = 20,
				}, pr.ability.damage, pr.x + dir * 0.4, pr.y + 0.2, dir * 20, 0)
			end
		end

		-- Landing: arcs explode on the floor, pools spread, spears stick, others stop falling.
		local gone = false
		if pr.y <= 0.15 and pr.x >= Arena.STAGE_LEFT and pr.x <= Arena.STAGE_RIGHT and num(d, "gravity", 0) > 0 then
			pr.y = 0.15
			if d.pool and not pr.pooled then
				-- Lava blob: turns into a burning pool on the floor.
				local pool = d.pool
				pr.pooled = true
				local spec = table.clone(d)
				spec.shape = "lava_pool"
				spec.gravity = 0
				spec.size = num(pool, "size", 1.2)
				spec.rehit = num(pool, "rehit", 0.5)
				spec.pierce = true
				pr.spec = spec
				d = spec
				pr.vx, pr.vy = 0, 0
				pr.life = num(pool, "life", 4)
				pr.hit = {}
				pr.ability = table.clone(pr.ability)
				pr.ability.damage *= num(pool, "dmg", 0.35)
				pr.ability.push = 0.3
				pr.ability.angle = 80
				pr.ability.hitstun = 0.2
				emit(sim, { type = "pool", actor = pr.owner, id = pr.id, x = pr.x })
			elseif d.sticky then
				pr.vx, pr.vy = 0, 0 -- the time bomb lies ticking on the floor
			elseif num(d, "explode", 0) > 0 then
				explode(sim, pr, contacts)
				gone = true
			elseif d.javelin and not pr.returning then
				pr.stuck = true
				pr.vx, pr.vy = 0, 0
				pr.life = 6
				emit(sim, { type = "stuck", actor = pr.owner, id = pr.id })
			else
				pr.vy = 0
			end
		end
		if num(d, "rehit", 0) > 0 then
			pr.rehitT += dt
			if pr.rehitT >= d.rehit then
				pr.rehitT = 0
				pr.hit = {}
			end
		end

		local size = pr.sizeNow or num(d, "size", 0.5)
		local inert = pr.age < num(d, "delay", 0) or d.nohit or pr.echoing or (d.grow and not pr.launched)
		if not gone and not inert then
			for ti, t in sim.fighters do
				if
					ti == pr.owner
					or sim:isAlly(pr.owner, ti)
					or pr.hit[ti]
					or t.state == "Defeated"
					or t.state == "Dazed"
				then
					continue
				end
				local touch = math.abs(t.x - pr.x) <= size
					and pr.y >= t.y - 0.3 - size * 0.5
					and pr.y <= t.y + BODY_H + size * 0.5
				if d.column then
					-- Orbital strike: the beam hits everything standing in its column.
					touch = math.abs(t.x - pr.x) <= size and t.y >= pr.y - 0.6 and t.y <= pr.y + num(d, "height", 9)
				elseif d.storm then
					-- The hail falls in a column below the cloud.
					touch = math.abs(t.x - pr.x) <= size and t.y <= pr.y and t.y >= pr.y - num(d, "height", 3.2) - 0.6
				end
				if not touch then
					continue
				end
				if d.sticky and not pr.stuckTo then
					-- Time bomb: clings to whoever it hits and keeps ticking.
					pr.stuckTo = ti
					local spec = table.clone(d)
					spec.gravity = 0
					spec.nohit = true
					pr.spec = spec
					pr.life = num(d, "stick_fuse", 1.4)
					pr.vx, pr.vy = 0, 0
					emit(sim, { type = "bomb_stuck", actor = pr.owner, target = ti })
					break
				end
				if t.bulwark > 0 and sign(pr.x - t.x) == t.facing and not pr.pooled then
					-- Shield wall: the shot flies back and now belongs to the defender.
					pr.owner = ti
					pr.vx = -pr.vx * 1.1
					pr.vy = math.abs(pr.vy) * 0.3
					pr.x = t.x + t.facing * (size + 0.4)
					pr.hit = {}
					pr.returning = false
					emit(sim, { type = "reflect", actor = ti, x = pr.x, y = pr.y })
					break
				end
				pr.hit[ti] = true
				if num(d, "explode", 0) > 0 then
					explode(sim, pr, contacts)
					gone = true
					break
				end
				local ability = pr.ability
				local extra: { [string]: any } = {}
				if num(d, "weigh", 0) > 0 then
					-- Weighing of the heart: the heavier the opponent's damage, the harder the verdict.
					local mult = 1 + t.percent / d.weigh
					ability = table.clone(ability)
					ability.damage *= mult
					emit(sim, { type = "soul_weigh", actor = pr.owner, target = ti, mult = mult })
				end
				for _, key in { "pull", "lasso", "mark", "yank", "swap" } do
					if d[key] then
						extra[key] = true
					end
				end
				if num(d, "hex", 0) > 0 then
					extra.hex = { d.hex, num(d, "hex_mult", 1.3) }
				end
				if num(d, "leash", 0) > 0 then
					extra.leash = { d.leash, num(d, "leash_len", 2.5) }
				end
				if num(d, "lifesteal", 0) > 0 then
					extra.lifesteal = d.lifesteal
				end
				table.insert(contacts, {
					from = pr.owner,
					to = ti,
					ability = ability,
					special = false,
					pushDir = if math.abs(pr.vx) > 0.1 then sign(pr.vx) else 1,
					srcX = pr.x,
					extra = extra,
				})
				if not d.pierce then
					gone = true
					break
				end
			end
		end
		if not gone and pr.life <= 0 and d.anchor and next(pr.hit) == nil and owner.state ~= "Defeated" then
			-- Chain anchor: nothing caught, so the anchor bites into the air and its owner zips to it.
			local zx, zy = pr.x - owner.x, pr.y - (owner.y + 1)
			local len = math.sqrt(zx * zx + zy * zy)
			if len > 0.3 then
				local zip = num(d, "zip", 15)
				owner.vx = zx / len * zip
				owner.vy = math.max(zy / len * zip, 4)
				owner.grounded = false
				owner.airDashUsed = false
				emit(sim, { type = "anchor_zip", actor = pr.owner, x = pr.x, y = pr.y })
			end
		end
		if not gone and pr.life <= 0 and num(d, "fuse", 0) > 0 then
			explode(sim, pr, contacts)
			gone = true
		end
		if gone or pr.life <= 0 or pr.x < Arena.BLAST_LEFT or pr.x > Arena.BLAST_RIGHT or pr.y < Arena.BLAST_BOTTOM then
			emit(sim, { type = "projectile_end", id = pr.id })
			continue
		end
		table.insert(keep, pr)
	end
	sim.projectiles = keep
end

return Projectiles
