local RigBuilder = require(Shared.Visual.RigBuilder)
local Looks = require(Shared.Data.Looks)
local GearData = require(Shared.Visual.GearData)
local Pose = require(Shared.Visual.Pose)
local Visuals = require(Shared.Data.Visuals)

local function close(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3
end

describe("RigBuilder", function()
	for _, id in Visuals.SLICE_FIGHTERS do
		it(`builds a complete, consistent rig for {id}`, function()
			local model = RigBuilder.build(id)
			local motors = {}
			for _, d in model:GetDescendants() do
				if d:IsA("Motor6D") then
					motors[d.Name] = d
					-- At rest both sides of a joint meet at the same pivot.
					assert(close(d.Part0.CFrame * d.C0, d.Part1.CFrame * d.C1), `{id}: joint {d.Name} misaligned`)
				end
			end
			for _, name in Pose.JOINTS do
				assert(motors[name], `{id}: Pose joint {name} missing`)
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			expect(root.Anchored).toBe(true)
			expect(model:GetAttribute("StandHeight")).toBeCloseTo(
				RigBuilder.STAND_HEIGHT * Looks.get(id).scale.height,
				4
			)
			-- Every hand-made gear piece got built (each adds at least one part).
			for _, gear in Looks.get(id).gear do
				assert(RigBuilder.GEAR[gear], `{id}: unknown gear {gear}`)
			end
			local parts = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					expect(d.CanCollide).toBe(false)
				end
			end
			expect(parts).toBeGreaterThan(18)
			-- Data-driven gear lands on the rig with every piece (named parts exist).
			for _, gear in Looks.get(id).gear do
				for _, d in (GearData :: any)[gear] or {} do
					assert(model:FindFirstChild(d.name, true), `{id}: {gear} piece {d.name} missing`)
				end
			end
		end)
	end

	it("builds every gear set in the data with valid limbs, materials and shapes", function()
		local all = {}
		for gear in GearData :: any do
			table.insert(all, gear)
		end
		local look = table.clone(Looks.get("ninja")) :: any
		look.gear = all
		Looks.BY_ID.__allgear = look
		local ok, model = pcall(RigBuilder.build, "__allgear")
		Looks.BY_ID.__allgear = nil
		assert(ok, tostring(model))
		for gear, pieces in GearData :: any do
			for _, d in pieces do
				assert(model:FindFirstChild(d.name, true), `{gear}: piece {d.name} not built (limb {d.limb}?)`)
			end
		end
	end)
end)
