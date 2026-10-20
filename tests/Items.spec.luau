local Input = require(Shared.Combat.Input)
local Items = require(Shared.Combat.Items)
local Sim = require(Shared.Combat.Simulation)
local Weapons = require(Shared.Data.Weapons)

local function cmd(edit: ((c: any) -> ())?)
	local c = Input.idle()
	if edit then
		edit(c)
	end
	return c
end

local function run(sim, frames: number, first: any?)
	local events = {}
	for frame = 1, frames do
		sim:tick({ if frame == 1 and first then first else cmd(), cmd() })
		for _, e in sim.events do
			table.insert(events, e)
		end
	end
	return events
end

local function has(events, kind: string): boolean
	for _, e in events do
		if e.type == kind then
			return true
		end
	end
	return false
end

local function duel()
	local sim = Sim.new({ fighters = { "ninja", "golem" }, countdown = 0, seed = 5, finishers = false } :: any)
	sim.fighters[1].x, sim.fighters[1].facing = -3, 1
	sim.fighters[2].x = 0
	return sim
end

-- Moves a start item to the floor right next to fighter 1.
local function itemAtFeet(sim, kind: string)
	for _, item in sim.items do
		if item.kind == kind then
			item.x, item.y = sim.fighters[1].x + 0.4, 0.1
			return item
		end
	end
	error(`no {kind}`)
end

describe("Items", function()
	it("puts a crate, a rock, a barrel and an explosive barrel into the arena", function()
		local sim = duel()
		local kinds = {}
		for _, item in sim.items do
			kinds[item.kind] = true
			expect(item.state).toBe("resting")
		end
		for _, kind in { "light_crate", "heavy_rock", "barrel", "explosive_barrel" } do
			expect(kinds[kind]).toBe(true)
		end
	end)

	it("can be switched off for modes without items", function()
		local sim = Sim.new({ fighters = { "ninja", "golem" }, countdown = 0, items = false } :: any)
		expect(#sim.items).toBe(0)
	end)

	it("lifts a crate with grab and throws it into the opponent", function()
		local sim = duel()
		local crate = itemAtFeet(sim, "light_crate")
		run(
			sim,
			5,
			cmd(function(c)
				c.grab = true
			end)
		)
		expect(crate.state).toBe("carried")
		expect(sim.fighters[1].carriedItem).toBe(crate.id)
		local events = run(
			sim,
			40,
			cmd(function(c)
				c.standard = true
			end)
		)
		expect(has(events, "item_throw")).toBe(true)
		expect(sim.fighters[2].percent).toBeGreaterThan(0)
	end)

	it("blows up an explosive barrel that gets hit and launches everyone near it", function()
		local sim = duel()
		local barrel = itemAtFeet(sim, "explosive_barrel")
		sim.fighters[2].x = barrel.x + 1
		local events = run(
			sim,
			40,
			cmd(function(c)
				c.standard = true
			end)
		)
		expect(has(events, "item_explode")).toBe(true)
		expect(barrel.state).toBe("destroyed")
		expect(sim.fighters[2].percent).toBeGreaterThan(0)
	end)

	it("arms a fighter with a weapon that adds reach and breaks after its uses", function()
		local sim = duel()
		local sword = Items.spawnWeapon(sim, "sword_hero", sim.fighters[1].x + 0.3, 0.1)
		run(
			sim,
			3,
			cmd(function(c)
				c.standard = true
			end)
		)
		local f = sim.fighters[1]
		expect(f.weapon and f.weapon.id).toBe("sword_hero")
		expect(sword.state).toBe("wielded")
		local uses = Weapons.byId.sword_hero.uses
		local broke = false
		for _ = 1, uses + 2 do
			f.cooldownStandard = 0
			local events = run(
				sim,
				40,
				cmd(function(c)
					c.standard = true
				end)
			)
			if has(events, "weapon_break") then
				broke = true
				break
			end
		end
		expect(broke).toBe(true)
		expect(f.weapon == nil).toBe(true)
	end)

	it("gives power-ups on touch: titan, heart", function()
		local sim = duel()
		local f = sim.fighters[1]
		f.percent = 50
		for _, kind in { "titan_mushroom", "health_heart" } do
			local def = { kind = kind }
			Items.spawnRandom(sim) -- advances the drop RNG like a real match
			local item = sim.items[#sim.items]
			item.kind, item.power, item.explosive =
				def.kind, if kind == "titan_mushroom" then "titan" else "heal", false
			item.x, item.y, item.state = f.x, 0.1, "resting"
			run(sim, 2)
		end
		expect(f.titanTimer).toBeGreaterThan(0)
		expect(f.percent).toBe(20)
	end)

	it("drops new weapons or power-ups during a match", function()
		local sim = duel()
		local before = #sim.items
		run(sim, 60 * 20)
		expect(#sim.items).toBeGreaterThan(before)
	end)

	it("encodes items for the renderer with kind index and holder", function()
		local sim = duel()
		local flat = Items.encode(sim)
		expect(#flat).toBe(#sim.items * 5)
		expect(Items.KINDS[flat[2]]).toBe(sim.items[1].kind)
	end)
end)
