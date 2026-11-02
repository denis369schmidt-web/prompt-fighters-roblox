--!strict
-- Cheap ambient motion for arena and lobby decoration (turning signs, swaying flags, passing ships, pulsing neon).
-- The server only tags parts with attributes (DecorMotion.tag); the client (DecorAnimator.client) moves them locally
-- with BulkMoveTo, so nothing replicates per frame and the Simulation never sees it. Only ever used on anchored,
-- non-colliding decoration: gameplay geometry never carries an Anim attribute.
--
-- Attributes on a part:
--   Anim        "spin" | "sway" | "bob" | "pass" | "pulse"
--   AnimSpeed   spin: radians per second; pass: studs per second
--   AnimAmp     sway: radians; bob: studs; pass: loop length in studs; pulse: transparency swing (0..1)
--   AnimPeriod  seconds per cycle (sway, bob, pulse)
--   AnimAxis    Vector3 (world): spin/sway rotation axis (default Y / Z), bob/pass direction (default Y / X)
--   AnimPivot   Vector3 (world): rotation center for spin/sway (default: the part's own position)
--   AnimPhase   seconds of offset, so neighbours do not move in lockstep (parts of one group share it)

local DecorMotion = {}

export type Spec = {
	speed: number?,
	amp: number?,
	period: number?,
	axis: Vector3?,
	pivot: Vector3?,
	phase: number?,
}

export type Motion = {
	kind: string,
	speed: number,
	amp: number,
	period: number,
	axis: Vector3,
	pivot: Vector3?,
	phase: number,
}

DecorMotion.KINDS = { spin = true, sway = true, bob = true, pass = true, pulse = true }

-- Tags a part for the client animator. Returns the part, so builders can chain it.
function DecorMotion.tag<T>(part: T & Instance, kind: string, spec: Spec?): T
	assert(DecorMotion.KINDS[kind], `unknown decor motion {kind}`)
	local s: Spec = spec or {}
	part:SetAttribute("Anim", kind)
	if s.speed then
		part:SetAttribute("AnimSpeed", s.speed)
	end
	if s.amp then
		part:SetAttribute("AnimAmp", s.amp)
	end
	if s.period then
		part:SetAttribute("AnimPeriod", s.period)
	end
	if s.axis then
		part:SetAttribute("AnimAxis", s.axis)
	end
	if s.pivot then
		part:SetAttribute("AnimPivot", s.pivot)
	end
	if s.phase then
		part:SetAttribute("AnimPhase", s.phase)
	end
	return part
end

-- Reads a tagged part's motion back (nil when it has none).
function DecorMotion.read(part: Instance): Motion?
	local kind = part:GetAttribute("Anim")
	if type(kind) ~= "string" or not DecorMotion.KINDS[kind] then
		return nil
	end
	local axis = part:GetAttribute("AnimAxis")
	local pivot = part:GetAttribute("AnimPivot")
	local defaultAxis = if kind == "pass" then Vector3.new(1, 0, 0) elseif kind == "sway" then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	return {
		kind = kind,
		speed = (part:GetAttribute("AnimSpeed") :: number?) or 1,
		amp = (part:GetAttribute("AnimAmp") :: number?) or 1,
		period = math.max((part:GetAttribute("AnimPeriod") :: number?) or 4, 0.05),
		axis = if typeof(axis) == "Vector3" then (axis :: Vector3).Unit else defaultAxis,
		pivot = if typeof(pivot) == "Vector3" then pivot :: Vector3 else nil,
		phase = (part:GetAttribute("AnimPhase") :: number?) or 0,
	}
end

local function wave(m: Motion, t: number): number
	return math.sin((t + m.phase) / m.period * 2 * math.pi)
end

-- Where a part with rest CFrame `base` is at time `t` (seconds).
function DecorMotion.cframe(m: Motion, base: CFrame, t: number): CFrame
	if m.kind == "bob" then
		return base + m.axis * (m.amp * wave(m, t))
	elseif m.kind == "pass" then
		-- Loops along the axis from -amp/2 to +amp/2 around the rest position.
		local travel = ((t + m.phase) * m.speed) % m.amp
		return base + m.axis * (travel - m.amp / 2)
	elseif m.kind == "spin" or m.kind == "sway" then
		local angle = if m.kind == "spin" then (t + m.phase) * m.speed else m.amp * wave(m, t)
		local pivot = CFrame.new(m.pivot or base.Position)
		return pivot * CFrame.fromAxisAngle(m.axis, angle) * pivot:Inverse() * base
	end
	return base
end

-- Transparency of a pulsing part with rest transparency `base` at time `t`.
function DecorMotion.transparency(m: Motion, base: number, t: number): number
	if m.kind ~= "pulse" then
		return base
	end
	return math.clamp(base + m.amp * (0.5 + 0.5 * wave(m, t)), 0, 1)
end

return DecorMotion
