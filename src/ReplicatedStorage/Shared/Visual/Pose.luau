--!strict
-- Procedural animation: target joint angles for an R15 rig from what the snapshot says a fighter is doing.
-- Pure math (no Instances), so every state and move is covered by tests. The client eases the joints toward
-- these targets each frame, which gives smooth motion without animation assets.
--
-- Angles are degrees per Motor6D (rotation in joint space): +x swings a limb forward, knees bend with -x,
-- elbows with +x, +z lifts the right arm/leg outward (-z for the left side).

export type Angles = { x: number, y: number, z: number }
export type PoseInput = {
	state: string,
	move: string, -- "" when no move is running
	stage: string, -- "windup" | "active" | "recovery" | ""
	grounded: boolean,
	blocking: boolean,
	speed: number, -- horizontal speed in m/s (absolute)
	vy: number, -- vertical speed in m/s
	phase: number, -- run cycle phase in radians (client advances it with distance)
	t: number, -- seconds, for idle breathing and wobbles
}
export type PoseOutput = {
	joints: { [string]: Angles },
	rootY: number, -- studs added to the standing height (negative = crouch)
	pitch: number, -- degrees, + leans forward
	roll: number, -- degrees, sideways sway
	spin: number, -- degrees of extra yaw (spinning aerials)
	snappy: boolean, -- true during strikes: the client eases faster so hits read crisp
}

local Pose = {}

Pose.JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
}

-- Which body motion each move uses.
Pose.MOVE_KIND = {
	jab = "punch",
	ftilt = "punch",
	dash_attack = "punch",
	fsmash = "heavy",
	utilt = "upper",
	usmash = "upper",
	uair = "upper",
	uspecial = "upper",
	dtilt = "low",
	dsmash = "low",
	dair = "stomp",
	nair = "spin",
	fair = "kick",
	bair = "backkick",
	nspecial = "blast",
	dspecial = "blast",
} :: { [string]: string }

local function a(x: number, y: number?, z: number?): Angles
	return { x = x, y = y or 0, z = z or 0 }
end

local function out(): PoseOutput
	local joints = {}
	for _, name in Pose.JOINTS do
		joints[name] = a(0)
	end
	return { joints = joints, rootY = 0, pitch = 0, roll = 0, spin = 0, snappy = false }
end

local function set(p: PoseOutput, values: { [string]: Angles })
	for name, angles in values do
		p.joints[name] = angles
	end
end

local function guard(p: PoseOutput, t: number)
	local breathe = math.sin(t * 2.2)
	set(p, {
		Waist = a(6 + breathe * 2),
		Neck = a(-4),
		RightShoulder = a(45, 0, 8),
		RightElbow = a(85),
		LeftShoulder = a(60, 0, -8),
		LeftElbow = a(90),
		LeftHip = a(18, 0, -4),
		LeftKnee = a(-28),
		RightHip = a(-8, 0, 4),
		RightKnee = a(-22),
	})
	p.rootY = -0.25 + breathe * 0.06
end

local function run(p: PoseOutput, phase: number, speed: number)
	local s = math.sin(phase)
	local amount = math.clamp(speed / 6, 0.4, 1)
	set(p, {
		Waist = a(14 * amount),
		Neck = a(-10 * amount),
		LeftHip = a(45 * s * amount),
		RightHip = a(-45 * s * amount),
		LeftKnee = a(-20 - 55 * math.max(0, -s) * amount),
		RightKnee = a(-20 - 55 * math.max(0, s) * amount),
		LeftShoulder = a(-40 * s * amount, 0, -6),
		RightShoulder = a(40 * s * amount, 0, 6),
		LeftElbow = a(70),
		RightElbow = a(70),
	})
	p.rootY = math.abs(math.cos(phase)) * 0.3 * amount - 0.1
	p.pitch = 8 * amount
end

local function air(p: PoseOutput, vy: number)
	if vy > 1 then
		set(p, {
			LeftHip = a(55),
			RightHip = a(35),
			LeftKnee = a(-80),
			RightKnee = a(-60),
			LeftShoulder = a(-25, 0, -35),
			RightShoulder = a(-25, 0, 35),
			LeftElbow = a(40),
			RightElbow = a(40),
		})
	else
		set(p, {
			LeftHip = a(15),
			RightHip = a(-5),
			LeftKnee = a(-25),
			RightKnee = a(-15),
			LeftShoulder = a(30, 0, -60),
			RightShoulder = a(30, 0, 60),
			LeftElbow = a(20),
			RightElbow = a(20),
		})
	end
end

local function attack(p: PoseOutput, kind: string, stage: string, t: number)
	local strike = stage == "active"
	if kind == "punch" then
		if strike then
			set(p, {
				Waist = a(10, 30),
				RightShoulder = a(92, 0, 4),
				RightElbow = a(0),
				LeftShoulder = a(45, 0, -10),
				LeftElbow = a(95),
				LeftHip = a(30),
				LeftKnee = a(-35),
			})
			p.pitch = 10
		else
			set(p, { Waist = a(4, -25), RightShoulder = a(20), RightElbow = a(115) })
		end
	elseif kind == "heavy" then
		if strike then
			set(p, {
				Waist = a(18, 40),
				RightShoulder = a(100, 0, 6),
				RightElbow = a(0),
				LeftShoulder = a(80, 0, -10),
				LeftElbow = a(20),
				LeftHip = a(50),
				LeftKnee = a(-40),
				RightHip = a(-25),
			})
			p.pitch = 16
		else
			set(p, { Waist = a(-8, -45), RightShoulder = a(-60, 0, 20), RightElbow = a(45) })
			p.rootY = -0.4
		end
	elseif kind == "upper" then
		if strike then
			set(p, {
				Waist = a(-15),
				Neck = a(-25),
				RightShoulder = a(170, 0, 5),
				RightElbow = a(10),
				LeftShoulder = a(20, 0, -30),
				RightHip = a(20),
				RightKnee = a(-40),
			})
			p.rootY = 0.3
		else
			set(p, { Waist = a(20), RightShoulder = a(-10), RightElbow = a(100) })
			p.rootY = -0.6
		end
	elseif kind == "low" then
		set(p, {
			LeftHip = a(65),
			LeftKnee = a(-100),
			RightHip = if strike then a(80, 0, 10) else a(30),
			RightKnee = if strike then a(-5) else a(-70),
			Waist = a(25),
			LeftShoulder = a(30, 0, -40),
			RightShoulder = a(-20, 0, 30),
		})
		p.rootY = -0.9
	elseif kind == "kick" then
		set(p, {
			RightHip = if strike then a(95) else a(60),
			RightKnee = if strike then a(-5) else a(-90),
			LeftHip = a(-10),
			LeftKnee = a(-30),
			Waist = a(-15),
			LeftShoulder = a(10, 0, -55),
			RightShoulder = a(10, 0, 55),
		})
	elseif kind == "backkick" then
		set(p, {
			RightHip = if strike then a(-85) else a(-30),
			RightKnee = if strike then a(-10) else a(-80),
			LeftHip = a(30),
			LeftKnee = a(-50),
			Waist = a(28),
			Neck = a(-25),
		})
	elseif kind == "spin" then
		set(p, {
			LeftShoulder = a(0, 0, -90),
			RightShoulder = a(0, 0, 90),
			LeftHip = a(40, 0, -20),
			RightHip = a(40, 0, 20),
			LeftKnee = a(-60),
			RightKnee = a(-60),
		})
		if strike then
			p.spin = (t * 900) % 360
		end
	elseif kind == "stomp" then
		set(p, {
			LeftHip = if strike then a(-10) else a(70),
			RightHip = if strike then a(-10) else a(70),
			LeftKnee = if strike then a(0) else a(-110),
			RightKnee = if strike then a(0) else a(-110),
			LeftShoulder = a(150, 0, -20),
			RightShoulder = a(150, 0, 20),
		})
	elseif kind == "blast" then
		if strike then
			set(p, {
				Waist = a(12),
				LeftShoulder = a(90, 0, -4),
				RightShoulder = a(90, 0, 4),
				LeftElbow = a(0),
				RightElbow = a(0),
				LeftHip = a(35),
				LeftKnee = a(-40),
				RightHip = a(-20),
			})
			p.pitch = 8
		else
			set(p, {
				Waist = a(-5, -20),
				LeftShoulder = a(-30, 0, -10),
				RightShoulder = a(-30, 0, 10),
				LeftElbow = a(95),
				RightElbow = a(95),
			})
			p.rootY = -0.35
		end
	end
	p.snappy = strike or stage == "windup"
end

local function scale(p: PoseOutput, k: number)
	for _, angles in p.joints do
		angles.x *= k
		angles.y *= k
		angles.z *= k
	end
	p.rootY *= k
	p.pitch *= k
end

function Pose.compute(input: PoseInput): PoseOutput
	local p = out()
	local state = input.state
	local t = input.t

	if state == "Defeated" then
		return p
	elseif state == "Ledge" then
		set(p, {
			LeftShoulder = a(170, 0, -10),
			RightShoulder = a(170, 0, 10),
			LeftHip = a(10),
			RightHip = a(-5),
			LeftKnee = a(-20 + math.sin(t * 3) * 10),
			RightKnee = a(-15),
		})
		return p
	elseif state == "HitStun" or state == "Grabbed" then
		local wob = math.sin(t * 18) * 8
		set(p, {
			Waist = a(-25),
			Neck = a(-25),
			LeftShoulder = a(-30 + wob, 0, -70),
			RightShoulder = a(-30 - wob, 0, 70),
			LeftHip = a(25),
			RightHip = a(-15),
			LeftKnee = a(-40),
			RightKnee = a(-20),
		})
		p.pitch = -15
		p.snappy = true
		return p
	elseif state == "ShieldBreak" or state == "Dazed" then
		set(p, {
			Waist = a(30),
			Neck = a(35),
			LeftShoulder = a(5, 0, -10),
			RightShoulder = a(5, 0, 10),
			LeftKnee = a(-35),
			RightKnee = a(-35),
			LeftHip = a(20),
			RightHip = a(20),
		})
		p.rootY = -0.5
		p.roll = math.sin(t * 3) * 12
		return p
	elseif state == "Grab" or state == "Carrying" or state == "Throw" then
		guard(p, t)
		set(p, {
			LeftShoulder = a(90, 0, -5),
			RightShoulder = a(90, 0, 5),
			LeftElbow = a(25),
			RightElbow = a(25),
			Waist = a(15),
		})
		p.snappy = true
		return p
	elseif state == "Charge" then
		guard(p, t)
		set(p, { Waist = a(-5, -45), RightShoulder = a(-65, 0, 20), RightElbow = a(40) })
		p.rootY = -0.45 + math.sin(t * 40) * 0.04 -- trembling with power
		return p
	elseif state == "Dodge" then
		if input.grounded then
			set(p, {
				Waist = a(40),
				Neck = a(20),
				LeftHip = a(80),
				RightHip = a(80),
				LeftKnee = a(-110),
				RightKnee = a(-110),
			})
			p.rootY = -0.9
		else
			air(p, 2)
		end
		return p
	end

	if input.blocking then
		set(p, {
			Waist = a(18),
			LeftShoulder = a(85, 0, 25),
			RightShoulder = a(85, 0, -25),
			LeftElbow = a(110),
			RightElbow = a(110),
			LeftHip = a(45),
			RightHip = a(30),
			LeftKnee = a(-75),
			RightKnee = a(-60),
		})
		p.rootY = -0.6
		return p
	end

	local kind = if input.move ~= "" then Pose.MOVE_KIND[input.move] or "punch" else nil
	if kind and (input.stage == "windup" or input.stage == "active") then
		if input.grounded then
			guard(p, t)
		else
			air(p, input.vy)
		end
		attack(p, kind, input.stage, t)
		return p
	end

	if not input.grounded then
		air(p, input.vy)
	elseif input.speed > 0.6 then
		run(p, input.phase, input.speed)
	else
		guard(p, t)
	end
	if kind and input.stage == "recovery" then
		-- Follow-through: hold half of the strike so the hit doesn't snap back instantly.
		local strike = out()
		attack(strike, kind, "active", t)
		scale(strike, 0.5)
		for name, angles in strike.joints do
			if angles.x ~= 0 or angles.y ~= 0 or angles.z ~= 0 then
				p.joints[name] = angles
			end
		end
	end
	return p
end

return Pose
