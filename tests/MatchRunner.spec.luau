local Guard = require(Shared.Net.Guard)
local Input = require(Shared.Combat.Input)
local MatchRunner = require(Shared.Combat.MatchRunner)
local Visuals = require(Shared.Data.Visuals)

local STEP = 1 / 60

local function runner()
	return MatchRunner.new({
		slots = {
			{ userId = 100, fighterId = "ninja" },
			{ userId = nil, fighterId = "golem" },
		},
		seed = 9,
		countdown = 0,
	})
end

local function maskOf(edit: (c: any) -> ())
	local c = Input.idle()
	edit(c)
	return Input.encode(c)
end

describe("Guard", function()
	it("passes valid input and rejects wrong types, NaN and unknown remotes", function()
		local g = Guard.new()
		expect(g:allow(1, "Input", 0, { 1, 2, 0, 1 })).toBe(true)
		expect(g:allow(1, "Input", 0, { "1", 2, 0, 1 })).toBe(false)
		expect(g:allow(1, "Input", 0, { 0 / 0, 2, 0, 1 })).toBe(false)
		expect(g:allow(1, "Input", 0, { 1, 2, 0 })).toBe(false)
		expect(g:allow(1, "Snapshot", 0, {})).toBe(false)
		expect(g:allow(1, "Nope", 0, {})).toBe(false)
	end)

	it("rate-limits per player and refills over time", function()
		local g = Guard.new()
		local passed = 0
		for _ = 1, 20 do
			if g:allow(7, "SelectFighter", 0, { "ninja" }) then
				passed += 1
			end
		end
		expect(passed).toBe(4)
		expect(g:allow(8, "SelectFighter", 0, { "ninja" })).toBe(true)
		expect(g:allow(7, "SelectFighter", 0.5, { "ninja" })).toBe(true)
	end)
end)

describe("MatchRunner", function()
	it("runs exactly 60 ticks per second regardless of frame timing", function()
		local r = runner()
		local total = 0
		for _ = 1, 144 do
			local _, ticks = r:step(1 / 144)
			total += ticks
		end
		expect(total >= 59 and total <= 60).toBe(true)
	end)

	it("drops a long server hitch instead of fast-forwarding", function()
		local r = runner()
		local _, ticks = r:step(2)
		expect(ticks).toBe(MatchRunner.MAX_TICKS_PER_STEP)
	end)

	it("latches a press until a tick consumes it, exactly once", function()
		local r = runner()
		local f = r.sim.fighters[1]
		local jumpMask, axis = maskOf(function(c)
			c.jump = true
		end)
		r:setInput(1, jumpMask, axis)
		-- The next packet no longer carries the press, before any tick ran.
		local idleMask, idleAxis = Input.encode(Input.idle())
		r:setInput(1, idleMask, idleAxis)
		r:step(STEP)
		expect(f.grounded).toBe(false)
		expect(r.latched[1]).toBe(0)
	end)

	it("keeps held movement between packets", function()
		local r = runner()
		local f = r.sim.fighters[1]
		local x = f.x
		local mask, axis = maskOf(function(c)
			c.move = 1
		end)
		r:setInput(1, mask, axis)
		r:step(STEP * 20)
		expect(f.x).toBeGreaterThan(x)
	end)

	it("ignores input for bot slots and unknown slots", function()
		local r = runner()
		r:setInput(2, 4, 0)
		r:setInput(9, 4, 0)
		expect(r.held[2]).toBeNil()
		expect(r.held[9]).toBeNil()
	end)

	it("hands a leaving player's fighter to a bot", function()
		local r = runner()
		r:dropPlayer(100)
		expect(r.slots[1].userId).toBeNil()
		expect(r.sim.fighters[1].isBot).toBe(true)
		expect(r:slotOf(100)).toBeNil()
	end)

	it("encodes a snapshot the client decodes to the same values", function()
		local r = runner()
		r:step(STEP * 30)
		local decoded = MatchRunner.decode(r:snapshot())
		local f = r.sim.fighters[2]
		expect(decoded.frame).toBe(r.sim.frame)
		expect(decoded.fighters[2].x).toBeCloseTo(f.x, 2)
		expect(decoded.fighters[2].lives).toBe(f.lives)
		expect(decoded.fighters[2].grounded).toBe(f.grounded)
		expect(decoded.fighters[2].state).toBe(f.state)
	end)

	it("sends projectile positions and status flags for the renderer", function()
		local r = runner()
		r.sim.fighters[2].freezeTimer = 1
		r:setInput(
			1,
			maskOf(function(c)
				c.special = true
				c.specialHeld = true
			end),
			0
		)
		local shots = {}
		for _ = 1, 40 do
			r:step(STEP)
			shots = r:shots()
			if #shots > 0 then
				break
			end
		end
		expect(#shots % 4).toBe(0)
		expect(#shots).toBeGreaterThan(0)
		local decoded = MatchRunner.decode(r:snapshot())
		expect(bit32.btest(decoded.fighters[2].status, 1)).toBe(true)
	end)

	it("finishes a match between one idle player and a bot", function()
		local r = runner()
		for _ = 1, 60 * 200 do
			r:step(STEP)
			if r.sim.result ~= nil then
				break
			end
		end
		expect(r.sim.result).toBe(2)
	end)
end)

describe("Visuals", function()
	it("maps elements to colors by their family prefix", function()
		expect(Visuals.elementColor("fire")).toBe("#FF6A2B")
		expect(Visuals.elementColor("nine_fire")).toBe("#FF8A1F")
		expect(Visuals.elementColor("ice_breath")).toBe(Visuals.elementColor("ice"))
		expect(Visuals.elementColor("unknown")).toBe(Visuals.DEFAULT_COLOR)
	end)

	it("uses only slice fighters that exist", function()
		local Fighters = require(Shared.Data.Fighters)
		for _, id in Visuals.SLICE_FIGHTERS do
			expect(Fighters.byId[id] ~= nil).toBe(true)
		end
	end)
end)
