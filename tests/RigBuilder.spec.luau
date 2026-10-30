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
			-- Sculpted, but cheap: every visible piece is a massless decoration welded to an invisible R15 bone,
			-- the rig stays inside the part budget and stands on the floor (feet at y = 0).
			local visible, lowest = 0, math.huge
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					visible += 1
					expect(d.Massless).toBe(true)
					assert(d:FindFirstChildOfClass("WeldConstraint"), `{id}: {d.Name} not welded`)
					local s = d.Size
					for _, corner in
						{
							Vector3.new(-1, -1, -1),
							Vector3.new(1, -1, -1),
							Vector3.new(-1, -1, 1),
							Vector3.new(1, -1, 1),
							Vector3.new(-1, 1, -1),
							Vector3.new(1, 1, -1),
							Vector3.new(-1, 1, 1),
							Vector3.new(1, 1, 1),
						}
					do
						local p = d.CFrame * (corner * s / 2)
						lowest = math.min(lowest, p.Y)
					end
				end
			end
			assert(visible <= RigBuilder.PART_BUDGET, `{id}: {visible} parts (budget {RigBuilder.PART_BUDGET})`)
			assert(math.abs(lowest) < 0.06, `{id}: lowest point at y = {lowest}`)
			for _, bone in { "Head", "UpperTorso", "LowerTorso", "RightHand", "LeftFoot" } do
				expect(model:FindFirstChild(bone).Transparency).toBe(1)
			end
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
