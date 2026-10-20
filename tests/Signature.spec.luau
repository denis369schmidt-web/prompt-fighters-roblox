local Fighters = require(Shared.Data.Fighters)
local Input = require(Shared.Combat.Input)
local Signatures = require(Shared.Data.Signatures)
local SignatureParams = require(Shared.Data.Generated.SignatureParams)
local Sim = require(Shared.Combat.Simulation)

local function idle()
	return Input.idle()
end

local function special()
	local c = Input.idle()
	c.special = true
	c.specialHeld = true
	return c
end

local function has(events, kind: string): boolean
	for _, e in events do
		if e.type == kind then
			return true
		end
	end
	return false
end

-- Runs `frames` ticks; fighter 1 presses special on the frames listed in `presses`.
local function run(sim, frames: number, presses: { [number]: boolean }?)
	local events = {}
	for frame = 1, frames do
		local p1 = if presses and presses[frame] then special() else idle()
		sim:tick({ p1, idle() })
		for _, e in sim.events do
			table.insert(events, e)
		end
	end
	return events
end

local function duel(attacker: string, gap: number)
	local sim = Sim.new({ fighters = { attacker, "golem" }, countdown = 0, seed = 3, finishers = false } :: any)
	sim.fighters[1].x = -3
	sim.fighters[2].x = -3 + gap
	return sim
end

local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

describe("Signature data", function()
	it("knows every mechanic the fighters use", function()
		for id, sig in SignatureParams :: any do
			assert(Signatures.MECHANICS[sig.mech], `{id} uses unknown mechanic {sig.mech}`)
		end
	end)

	it("turns every neutral special with signature data into a signature move", function()
		for _, def in Fighters.list do
			local sim = Sim.new({ fighters = { def.id, "golem" }, countdown = 0 } :: any)
			local move = sim.fighters[1].moves.nspecial
			if (SignatureParams :: any)[def.id] then
				assert(move.sig ~= nil, `{def.id} nspecial has no signature`)
			end
		end
	end)
end)

describe("Signature mechanics", function()
	it("runs every fighter's signature for ten seconds without errors or broken numbers", function()
		local presses = {}
		for frame = 5, 600, 45 do
			presses[frame] = true
			presses[frame + 20] = true -- second press for two-stage signatures
		end
		for _, def in Fighters.list do
			local sim = duel(def.id, 3)
			local events = run(sim, 600, presses)
			if (SignatureParams :: any)[def.id] then
				assert(has(events, "signature"), `{def.id} never fired its signature`)
			end
			for _, f in sim.fighters do
				assert(finite(f.x) and finite(f.y) and finite(f.percent), `{def.id}: broken fighter numbers`)
			end
			for _, pr in sim.projectiles do
				assert(finite(pr.x) and finite(pr.y), `{def.id}: broken projectile`)
			end
		end
	end)

	it("Volt Ninja marks with the kunai and blinks to the marked opponent on the second press", function()
		local sim = duel("ninja", 4)
		local events = run(sim, 60, { [1] = true })
		expect(has(events, "marked")).toBe(true)
		expect(sim.fighters[2].markedBy).toBe(1)
		sim.fighters[1].cooldownSpecial = 0
		local before = sim.fighters[1].x
		events = run(sim, 30, { [1] = true })
		expect(has(events, "teleport")).toBe(true)
		expect(sim.fighters[1].x ~= before).toBe(true)
		expect(sim.fighters[2].markedBy).toBe(0)
	end)

	it("Magmor's lava blob lands as a burning pool", function()
		local sim = duel("golem", 9)
		local events = run(sim, 120, { [1] = true })
		expect(has(events, "pool")).toBe(true)
	end)

	it("Jubei chains three sword cuts, the last one launches", function()
		local sim = duel("jubei", 1.2)
		local f = sim.fighters[1]
		local events = {}
		-- Press special every few frames; a press only counts once the previous cut has ended.
		local stages = {}
		for frame = 1, 150 do
			local cmd = if frame % 4 == 1 then special() else idle()
			sim:tick({ cmd, idle() })
			for _, e in sim.events do
				table.insert(events, e)
				if e.type == "signature" and e.actor == 1 then
					table.insert(stages, e.mech)
				end
			end
			if #stages == 3 then
				break
			end
		end
		expect(stages[1]).toBe("tri_slash")
		expect(stages[2]).toBe("tri_slash_2")
		expect(stages[3]).toBe("tri_slash_3")
		expect(f.chainStage).toBe(0)
		expect(has(events, "hit")).toBe(true)
	end)

	it("Lepora's arrow rain drops arrows onto the opponent", function()
		local sim = duel("lepora", 5)
		local events = run(sim, 120, { [1] = true })
		local arrows = 0
		for _, e in events do
			if e.type == "projectile" and e.actor == 1 then
				arrows += 1
			end
		end
		expect(arrows).toBe(SignatureParams.lepora.count)
		expect(sim.fighters[2].percent).toBeGreaterThan(0)
	end)

	it("a shield wall sends shots back to the shooter", function()
		local sim = duel("ninja", 4)
		local wall = sim.fighters[2]
		wall.facing = -1
		wall.bulwark = 2
		local events = run(sim, 40, { [1] = true })
		expect(has(events, "reflect")).toBe(true)
		expect(wall.percent).toBe(0)
	end)

	it("frozen fighters cannot act until the ice melts", function()
		local sim = duel("ninja", 4)
		local f = sim.fighters[1]
		f.freezeTimer = 0.5
		run(sim, 10, { [1] = true })
		expect(f.pending == nil).toBe(true)
		expect(#sim.projectiles).toBe(0)
	end)
end)
