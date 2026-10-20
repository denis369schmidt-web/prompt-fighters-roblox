local Fighters = require(Shared.Data.Fighters)
local Looks = require(Shared.Data.Looks)
local Pose = require(Shared.Visual.Pose)

local STATES = {
	"Ready",
	"Attack",
	"Charge",
	"Dodge",
	"Grab",
	"Grabbed",
	"Carrying",
	"Throw",
	"HitStun",
	"ShieldBreak",
	"Dazed",
	"Ledge",
	"Defeated",
}
local MOVES = { "", "jab", "ftilt", "utilt", "dtilt", "dash_attack", "fsmash", "usmash", "dsmash" }
for key in Pose.MOVE_KIND do
	table.insert(MOVES, key)
end
local STAGES = { "", "windup", "active", "recovery" }

local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

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

describe("Pose", function()
	it("returns finite angles for every state, move, stage and air/ground combination", function()
		local checked = 0
		for _, state in STATES do
			for _, move in MOVES do
				for _, stage in STAGES do
					for _, grounded in { true, false } do
						local p = Pose.compute(input({
							state = state,
							move = move,
							stage = stage,
							grounded = grounded,
							speed = 5,
							vy = if grounded then 0 else -3,
							phase = 2.1,
						}))
						for _, name in Pose.JOINTS do
							local a = p.joints[name]
							assert(a, `{state}/{move}/{stage}: joint {name} missing`)
							assert(
								finite(a.x) and finite(a.y) and finite(a.z),
								`{state}/{move}/{stage}: {name} not finite`
							)
							assert(math.abs(a.x) <= 180 and math.abs(a.z) <= 180, `{state}/{move}: {name} out of range`)
						end
						assert(finite(p.rootY) and finite(p.pitch) and finite(p.roll) and finite(p.spin))
						checked += 1
					end
				end
			end
		end
		expect(checked).toBeGreaterThan(500)
	end)

	it("throws the right arm forward on an active jab and pulls it back in windup", function()
		local strike = Pose.compute(input({ state = "Attack", move = "jab", stage = "active" }))
		local windup = Pose.compute(input({ state = "Attack", move = "jab", stage = "windup" }))
		expect(strike.joints.RightShoulder.x).toBeGreaterThan(80)
		expect(strike.joints.RightElbow.x).toBeLessThan(10)
		expect(windup.joints.RightElbow.x).toBeGreaterThan(100)
		expect(strike.snappy).toBe(true)
	end)

	it("swings the legs in opposite directions while running", function()
		local p = Pose.compute(input({ speed = 6, phase = math.pi / 2 }))
		expect(p.joints.LeftHip.x).toBeGreaterThan(20)
		expect(p.joints.RightHip.x).toBeLessThan(-20)
	end)

	it("crouches behind the shield and hangs with raised arms on a ledge", function()
		local shield = Pose.compute(input({ blocking = true }))
		expect(shield.rootY).toBeLessThan(-0.3)
		local ledge = Pose.compute(input({ state = "Ledge" }))
		expect(ledge.joints.LeftShoulder.x).toBeGreaterThan(150)
	end)

	it("spins during an active neutral aerial", function()
		local a = Pose.compute(input({ move = "nair", stage = "active", grounded = false, t = 0.1 }))
		local b = Pose.compute(input({ move = "nair", stage = "active", grounded = false, t = 0.2 }))
		expect(a.spin ~= b.spin).toBe(true)
	end)
end)

describe("Looks", function()
	it("gives every roster fighter a complete look with valid colors", function()
		for _, def in Fighters.list do
			local look = Looks.get(def.id)
			for _, key in { "skin", "primary", "secondary", "glow" } do
				local hex = (look :: any)[key]
				assert(string.match(hex, "^#%x%x%x%x%x%x$"), `{def.id}.{key} = {hex}`)
			end
			assert(look.scale.height > 0.7 and look.scale.height < 1.4, `{def.id} height`)
			assert(#look.gear >= 1, `{def.id} has no gear`)
		end
	end)

	it("hand-designs the four slice fighters", function()
		for _, id in { "ninja", "golem", "jubei", "lepora" } do
			expect(Looks.BY_ID[id] ~= nil).toBe(true)
		end
	end)

	it("shades colors without leaving the 0..255 range", function()
		expect(Looks.shade("#808080", 0.5)).toBe("#404040")
		expect(Looks.shade("#F0F0F0", 2)).toBe("#FFFFFF")
	end)
end)
