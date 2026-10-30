local Pose = require(Shared.Visual.Pose)
local Fighters = require(Shared.Data.Fighters)
local Moveset = require(Shared.Combat.Moveset)

local function input(overrides: { [string]: any })
	local base = {
		state = "Ready",
		move = "",
		stage = "",
		grounded = true,
		blocking = false,
		speed = 0,
		vy = 0,
		phase = 0,
		t = 1.3,
	}
	for k, v in overrides do
		(base :: any)[k] = v
	end
	return base :: any
end

local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function check(p: any, label: string)
	for _, name in Pose.JOINTS do
		local j = p.joints[name]
		assert(j, `{label}: {name} missing`)
		assert(finite(j.x) and finite(j.y) and finite(j.z), `{label}: {name} not finite`)
		assert(math.abs(j.x) <= 180 and math.abs(j.y) <= 180 and math.abs(j.z) <= 180, `{label}: {name} range`)
	end
	for _, key in { "rootY", "pitch", "roll", "spin", "lunge", "stiffness", "damping" } do
		assert(finite(p[key]), `{label}: {key} not finite`)
	end
	assert(p.stiffness > 0 and p.damping > 0, `{label}: spring hints`)
end

describe("Pose keyframes", function()
	it("has a complete keyframe set for every motion and maps every move to one", function()
		for move, kind in Pose.MOTION_KIND do
			assert(Pose.MOVES[kind], `{move} -> {kind} has no keyframes`)
		end
		for kind, def in Pose.MOVES do
			assert(def.wind and def.hit, `{kind} lacks wind/hit`)
			if def.alt then
				assert(Pose.MOVES[def.alt], `{kind}.alt {def.alt} missing`)
			end
		end
		-- Coarse families for the slash arcs stay on the old names.
		local families = { punch = true, heavy = true, upper = true, low = true, stomp = true }
		for _, extra in { "spin", "kick", "backkick", "blast" } do
			families[extra] = true
		end
		for move, family in Pose.MOVE_KIND do
			assert(families[family], `{move} family {family}`)
		end
	end)

	it("stays finite and in range across every move, stage, weapon and time", function()
		local checked = 0
		for move in Pose.MOTION_KIND do
			for _, weapon in { "", "blade", "polearm", "heavy", "gun" } do
				for _, stage in { "windup", "active", "recovery" } do
					for _, st in { 0, 0.03, 0.08, 0.2, 0.6, 2 } do
						for variant = 0, 1 do
							local p = Pose.compute(input({
								state = "Attack",
								move = move,
								stage = stage,
								stageTime = st,
								stageLength = 0.12,
								weapon = weapon,
								variant = variant,
								grounded = variant == 0,
								vy = -2,
							}))
							check(p, `{move}/{weapon}/{stage}/{st}`)
							checked += 1
						end
					end
				end
			end
		end
		expect(checked).toBeGreaterThan(5000)
	end)

	it("winds back, snaps past the strike and settles toward it (overshoot)", function()
		local function shoulder(stage: string, st: number): number
			return Pose.compute(input({ state = "Attack", move = "jab", stage = stage, stageTime = st })).joints.RightShoulder.x
		end
		local wind = shoulder("windup", 0.1)
		local early = shoulder("active", 0.02)
		local peak = -math.huge
		for k = 1, 20 do
			peak = math.max(peak, shoulder("active", k * 0.005))
		end
		local held = shoulder("active", 0.12)
		expect(wind).toBeLessThan(50)
		expect(early).toBeGreaterThan(wind)
		expect(peak).toBeGreaterThan(held + 1)
		expect(held).toBeGreaterThan(80)
		-- Recovery eases back toward the stance.
		local late = shoulder("recovery", 0.22)
		expect(late).toBeLessThan(held)
	end)

	it("alternates hands on a 1-2 and keeps weapons in the right hand", function()
		local one = Pose.compute(input({ state = "Attack", move = "jab", stage = "active", variant = 0 }))
		local two = Pose.compute(input({ state = "Attack", move = "jab", stage = "active", variant = 1 }))
		expect(one.joints.RightElbow.x).toBeLessThan(10)
		expect(two.joints.LeftElbow.x).toBeLessThan(10)
		expect(Pose.kindOf("jab", "blade", 0)).toBe("hslash")
		expect(Pose.kindOf("jab", "blade", 1)).toBe("hslash2")
		expect(Pose.kindOf("fsmash", "polearm", 0)).toBe("chop")
		expect(Pose.kindOf("ftilt", "gun", 0)).toBe("aim")
		expect(Pose.kindOf("", "blade", 0)).toBeNil()
	end)

	it("winds the smash back further than the jab and lunges further on the hit", function()
		local smashWind = Pose.compute(input({ state = "Attack", move = "fsmash", stage = "windup", stageTime = 0.2 }))
		local smashHit = Pose.compute(input({ state = "Attack", move = "fsmash", stage = "active", stageTime = 0.1 }))
		local jabHit = Pose.compute(input({ state = "Attack", move = "jab", stage = "active", stageTime = 0.1 }))
		expect(smashWind.lunge).toBeLessThan(-0.2)
		expect(smashWind.rootY).toBeLessThan(-0.5)
		expect(smashHit.lunge).toBeGreaterThan(jabHit.lunge)
	end)

	it("flips through a full turn on forward and back aerials", function()
		local function pitchAt(move: string, stage: string, st: number): number
			return Pose.compute(input({
				state = "Attack",
				move = move,
				stage = stage,
				stageTime = st,
				stageLength = 0.1,
				grounded = false,
			})).pitch
		end
		expect(pitchAt("fair", "recovery", 1)).toBeCloseTo(360, 0)
		expect(pitchAt("bair", "recovery", 1)).toBeCloseTo(-360, 0)
		expect(pitchAt("fair", "active", 0.05)).toBeGreaterThan(90)
	end)
end)

describe("Pose locomotion and reactions", function()
	it("sprints with a bigger stride and lean than it walks", function()
		local walk = Pose.compute(input({ speed = 1.5, phase = math.pi / 2 }))
		local run = Pose.compute(input({ speed = 7, phase = math.pi / 2 }))
		expect(run.joints.LeftHip.x).toBeGreaterThan(walk.joints.LeftHip.x)
		expect(run.pitch).toBeGreaterThan(walk.pitch)
		-- Arms swing against the legs.
		expect(run.joints.LeftShoulder.x).toBeLessThan(0)
		expect(run.joints.RightShoulder.x).toBeGreaterThan(30)
	end)

	it("stands heavier and wider for heavy fighters, bounces light ones", function()
		local heavy = Pose.style("golem", 1.34, 1)
		local light = Pose.style("ninja", 0.88, 2)
		expect(heavy.weight).toBeGreaterThan(light.weight)
		expect(light.bounce).toBeGreaterThan(heavy.bounce)
		local h = Pose.compute(input({ style = heavy }))
		local l = Pose.compute(input({ style = light }))
		expect(h.joints.RightHip.z).toBeGreaterThan(l.joints.RightHip.z)
		-- Bounce moves the light fighter over time.
		local l2 = Pose.compute(input({ style = light, t = 1.6 }))
		expect(math.abs(l.rootY - l2.rootY)).toBeGreaterThan(0.02)
		for _, def in Fighters.list do
			local s = Pose.style(def.id, def.weight, 1)
			assert(s.weight >= 0 and s.weight <= 1 and finite(s.seed), def.id)
		end
	end)

	it("squashes on landing and recovers", function()
		local hit = Pose.compute(input({ landTime = 0.05, landImpact = 1 }))
		local later = Pose.compute(input({ landTime = 0.5, landImpact = 1 }))
		expect(hit.rootY).toBeLessThan(later.rootY - 0.4)
	end)

	it("front flips on an air jump and tucks while rising", function()
		local mid = Pose.compute(input({ grounded = false, vy = 5, airTime = 0.5, flipTime = 0.21 }))
		expect(mid.pitch).toBeGreaterThan(120)
		local rise = Pose.compute(input({ grounded = false, vy = 6, airTime = 0.5 }))
		local fall = Pose.compute(input({ grounded = false, vy = -6, airTime = 0.5 }))
		expect(rise.joints.RightKnee.x).toBeLessThan(fall.joints.RightKnee.x)
	end)

	it("flinches away from the hit and tumbles when launched hard", function()
		local back = Pose.compute(input({ state = "HitStun", stateTime = 0.02, vx = -4, facing = 1 }))
		local front = Pose.compute(input({ state = "HitStun", stateTime = 0.02, vx = 4, facing = 1 }))
		expect(back.pitch).toBeLessThan(0)
		expect(front.pitch).toBeGreaterThan(0)
		local a = Pose.compute(input({ state = "HitStun", stateTime = 0.2, vx = -20, vy = 8, grounded = false }))
		local b = Pose.compute(input({ state = "HitStun", stateTime = 0.4, vx = -20, vy = 8, grounded = false }))
		expect(math.abs(a.pitch - b.pitch)).toBeGreaterThan(60)
	end)

	it("rolls a full turn through a dodge roll", function()
		local done = Pose.compute(input({ state = "Dodge", stateTime = 0.34, vx = 7, facing = 1 }))
		local mid = Pose.compute(input({ state = "Dodge", stateTime = 0.17, vx = 7, facing = 1 }))
		expect(done.pitch).toBeCloseTo(360, 0)
		expect(mid.rootY).toBeLessThan(-1)
		local backward = Pose.compute(input({ state = "Dodge", stateTime = 0.34, vx = -7, facing = 1 }))
		expect(backward.pitch).toBeCloseTo(-360, 0)
	end)

	it("covers every move the launch fighters can send", function()
		for _, def in Fighters.list do
			for key, ability in Moveset.build(def.id) do
				local name = if ability.sig then ability.sig.mech else key
				assert(Pose.MOTION_KIND[name], `{def.id}: {name} has no motion`)
			end
		end
	end)
end)
