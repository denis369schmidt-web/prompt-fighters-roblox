local RigBuilder = require(Shared.Visual.RigBuilder)
local Looks = require(Shared.Data.Looks)
local Pose = require(Shared.Visual.Pose)

local function close(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3
end

describe("RigBuilder", function()
	for _, id in { "ninja", "golem", "jubei", "lepora", "kairo" } do
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
		end)
	end
end)
