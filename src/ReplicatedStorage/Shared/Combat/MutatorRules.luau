--!strict
-- Mutators (Data/Mutators) on a running Simulation, without touching the combat code: start effects (physics,
-- start percent, full super bar) are applied once, everything else after each tick from the tick's hit events
-- (extra damage, knockback scaling, energy drain) and on timers (place swap, bomb rain, item rain).
-- Used by the Daily Challenge (Data/DailyChallenge) and any mode that turns mutators on. Deterministic.
--
-- RIESEN / WINZLINGE change power and knockback here; their body size is not drawn yet, so the Daily Challenge
-- does not roll them (Data/DailyChallenge.MUTATOR_POOL).

local Arena = require(script.Parent.Arena)
local Items = require(script.Parent.Items)
local Knockback = require(script.Parent.Knockback)
local Simulation = require(script.Parent.Simulation)
local Constants = require(script.Parent.Parent.Data.Constants)
local Mutators = require(script.Parent.Parent.Data.Mutators)
local Rng = require(script.Parent.Parent.Util.Rng)

type Simulation = Simulation.Simulation

local STEP = 1 / Constants.TICK_RATE

local MutatorRules = {}

MutatorRules.SWAP_SECONDS = 15
MutatorRules.BOMB_SECONDS = 3.2
MutatorRules.BOMB_WARN = 1.3
MutatorRules.BOMB_RADIUS = 1.7
MutatorRules.BOMB_DAMAGE = 13
MutatorRules.ITEM_SECONDS = 5
MutatorRules.ESCALATION_SECONDS = 60
MutatorRules.ENERGY_SHARE = 0.4

export type Bomb = { id: number, x: number, warn: number, warnTotal: number }

export type State = {
	ids: { string },
	power: number,
	kb: number,
	escalation: boolean,
	vampire: boolean,
	swap: boolean,
	bombs: boolean,
	itemRain: boolean,
	swapT: number,
	bombT: number,
	itemT: number,
	pending: { Bomb },
	serial: number,
	rng: Rng.Rng,
	elapsed: number,
}

local PHYS_KEYS = { "gravity", "fast_fall", "jump", "air", "run" }

-- Applies the start effects of `ids` and returns the state for afterTick. Unknown ids are ignored.
function MutatorRules.apply(sim: Simulation, ids: { string }, seed: number?): State
	local state: State = {
		ids = {},
		power = 1,
		kb = 1,
		escalation = false,
		vampire = false,
		swap = false,
		bombs = false,
		itemRain = false,
		swapT = MutatorRules.SWAP_SECONDS,
		bombT = MutatorRules.BOMB_SECONDS,
		itemT = MutatorRules.ITEM_SECONDS,
		pending = {},
		serial = 0,
		rng = Rng.new((seed or 1) * 17 + 401),
		elapsed = 0,
	}
	for _, id in ids do
		local m = Mutators.byId[id]
		if m == nil then
			continue
		end
		table.insert(state.ids, id)
		state.power *= m.power or 1
		state.kb *= m.kb or 1
		for _, f in sim.fighters do
			if m.phys then
				for _, key in PHYS_KEYS do
					local mult = m.phys[key]
					if mult and f.phys[key] then
						f.phys[key] *= mult
					end
				end
				if m.phys.run then
					f.runSpeed *= m.phys.run
				end
			end
			if m.damage then
				f.percent = math.max(f.percent, m.damage)
			end
			if m.super then
				f.super = Constants.MAX_SUPER
			end
		end
		local rule = m.rule
		if rule == "escalation" then
			state.escalation = true
		elseif rule == "vampire" then
			state.vampire = true
		elseif rule == "swap" then
			state.swap = true
		elseif rule == "bomb_rain" then
			state.bombs = true
		elseif rule == "item_rain" then
			state.itemRain = true
		end
	end
	return state
end

-- The damage multiplier right now (power mutators and escalation).
function MutatorRules.damageMult(state: State): number
	local mult = state.power
	if state.escalation then
		mult *= 1 + math.clamp(state.elapsed / MutatorRules.ESCALATION_SECONDS, 0, 1)
	end
	return mult
end

local function alive(f: any): boolean
	return f.state ~= "Defeated" and f.state ~= "Dazed" and f.lives > 0
end

local function explode(state: State, sim: Simulation, bomb: Bomb)
	table.insert(sim.events, { type = "blast", actor = 0, x = bomb.x, y = 0.3, radius = MutatorRules.BOMB_RADIUS })
	for i, f in sim.fighters do
		if alive(f) and f.invulnerable <= 0 and f.intangible <= 0 then
			local dx = f.x - bomb.x
			if math.abs(dx) <= MutatorRules.BOMB_RADIUS + 0.3 and f.y < 2.2 then
				local damage = MutatorRules.BOMB_DAMAGE * MutatorRules.damageMult(state)
				f.percent = math.clamp(f.percent + damage, 0, Constants.MAX_PERCENT)
				local dir = if math.abs(dx) > 0.05 then (if dx > 0 then 1 else -1) else 1
				local launch = Knockback.attack(
					damage,
					1.3,
					55,
					false,
					0.4,
					f.percent,
					f.weight,
					f.stats.vitality,
					dir,
					true,
					false,
					f.grounded,
					f.inX,
					f.inY
				)
				f.vx, f.vy = launch.vx * state.kb, launch.vy * state.kb
				f.grounded = false
				f.state = "HitStun"
				f.stun = launch.hitstun
				f.pending = nil
				table.insert(sim.events, { type = "mutator_bomb_hit", target = i, damage = damage })
			end
		end
	end
end

-- After each Simulation tick: scales this tick's hits and runs the timed rules.
function MutatorRules.afterTick(state: State, sim: Simulation)
	if sim.countdown > 0 or sim.result ~= nil then
		return
	end
	state.elapsed += STEP
	local mult = MutatorRules.damageMult(state)
	for _, e in sim.events do
		if e.type ~= "hit" or e.target == nil then
			continue
		end
		local target = sim.fighters[e.target]
		local attacker = sim.fighters[e.actor]
		local damage = e.damage or 0
		if target and mult ~= 1 then
			local extra = damage * (mult - 1)
			target.percent = math.clamp(target.percent + extra, 0, Constants.MAX_PERCENT)
			if attacker then
				attacker.damageDealt += extra
			end
		end
		if target and state.kb ~= 1 and not e.armored then
			target.vx *= state.kb
			target.vy *= state.kb
		end
		if attacker and state.vampire then
			attacker.super = math.min(Constants.MAX_SUPER, attacker.super + damage * mult * MutatorRules.ENERGY_SHARE)
		end
	end

	if state.swap then
		state.swapT -= STEP
		if state.swapT <= 0 then
			state.swapT = MutatorRules.SWAP_SECONDS
			local list = {}
			for i, f in sim.fighters do
				if alive(f) and f.state ~= "Ledge" and f.state ~= "Grabbed" then
					table.insert(list, i)
				end
			end
			if #list >= 2 then
				-- Everyone moves one place along: 1 -> 2 -> ... -> n -> 1.
				local first = sim.fighters[list[1]]
				local fx, fy = first.x, first.y
				for k = 1, #list - 1 do
					local a, b = sim.fighters[list[k]], sim.fighters[list[k + 1]]
					a.x, a.y = b.x, b.y
				end
				local last = sim.fighters[list[#list]]
				last.x, last.y = fx, fy
				for _, k in list do
					local f = sim.fighters[k]
					f.vx, f.vy = 0, 0
					f.grounded = f.y <= 0.01
				end
				table.insert(sim.events, { type = "mutator_swap", fighters = list })
			end
		end
	end

	if state.bombs then
		state.bombT -= STEP
		if state.bombT <= 0 then
			state.bombT = MutatorRules.BOMB_SECONDS
			local list = {}
			for _, f in sim.fighters do
				if alive(f) then
					table.insert(list, f)
				end
			end
			if #list > 0 then
				local f = list[state.rng:int(1, #list)]
				state.serial += 1
				local x = math.clamp(f.x + state.rng:range(-1.5, 1.5), Arena.STAGE_LEFT + 0.5, Arena.STAGE_RIGHT - 0.5)
				table.insert(state.pending, {
					id = state.serial,
					x = x,
					warn = MutatorRules.BOMB_WARN,
					warnTotal = MutatorRules.BOMB_WARN,
				})
				table.insert(sim.events, { type = "mutator_bomb", x = x, warn = MutatorRules.BOMB_WARN })
			end
		end
		local keep = {}
		for _, bomb in state.pending do
			bomb.warn -= STEP
			if bomb.warn <= 0 then
				explode(state, sim, bomb)
			else
				table.insert(keep, bomb)
			end
		end
		state.pending = keep
	end

	if state.itemRain and sim.itemsEnabled then
		state.itemT -= STEP
		if state.itemT <= 0 then
			state.itemT = MutatorRules.ITEM_SECONDS
			Items.spawnRandom(sim)
		end
	end
end

-- Bomb warnings as telegraph zones in the BossFight zone format (kind 2 = circle): kind, x1, x2, y1, y2, progress.
function MutatorRules.zones(state: State): { number }
	local out = {}
	for _, bomb in state.pending do
		local r = MutatorRules.BOMB_RADIUS
		for _, v in { 2, bomb.x - r, bomb.x + r, 0, 1.5, 1 - bomb.warn / bomb.warnTotal } do
			table.insert(out, math.round(v * 100) / 100)
		end
	end
	return out
end

return MutatorRules
