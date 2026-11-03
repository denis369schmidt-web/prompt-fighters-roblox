local Cosmetics = require(Shared.Data.Cosmetics)
local Products = require(Shared.Data.Products)
local Looks = require(Shared.Data.Looks)
local Visuals = require(Shared.Data.Visuals)
local RigBuilder = require(Shared.Visual.RigBuilder)

-- Roblox material names a skin may use (Enum.Material is not available to specs).
local MATERIALS = {}
for _, name in
	{
		"SmoothPlastic",
		"Plastic",
		"Fabric",
		"Metal",
		"Foil",
		"Marble",
		"Glass",
		"Ice",
		"Glacier",
		"Basalt",
		"CrackedLava",
		"ForceField",
		"Neon",
		"Slate",
		"Granite",
		"DiamondPlate",
		"Leather",
		"Wood",
	}
do
	MATERIALS[name] = true
end

local function walk(value, path, visit)
	if type(value) == "table" then
		for k, v in value do
			visit(tostring(k), `{path}.{k}`)
			walk(v, `{path}.{k}`, visit)
		end
	end
end

-- Sizes and names of every part, so two rigs can be compared for anything but color and material.
local function shape(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(
				out,
				`{d.Name}:{math.floor(d.Size.X * 1000)}x{math.floor(d.Size.Y * 1000)}x{math.floor(d.Size.Z * 1000)}`
			)
		end
	end
	table.sort(out)
	return out
end

describe("Cosmetics (zero combat effect, nothing random)", function()
	it("has at least two own skins for every launch fighter", function()
		for _, id in Visuals.SLICE_FIGHTERS do
			local own = 0
			for _, skin in Cosmetics.SKINS do
				if skin.fighter == id then
					own += 1
				end
			end
			assert(own >= 2, `{id} has only {own} skins`)
		end
	end)

	it("gives every item an id, a name, a known rarity label and a fixed price or source", function()
		local seen = {}
		for _, list in { Cosmetics.SKINS, Cosmetics.KO_EFFECTS, Cosmetics.PLATES } do
			for _, item in list do
				assert(not seen[item.id], `duplicate {item.id}`)
				seen[item.id] = true
				assert(type(item.name) == "string" and #item.name > 0, `{item.id} has no name`)
				assert(Cosmetics.RARITIES[item.rarity], `{item.id} has unknown rarity {item.rarity}`)
				assert(type(item.info) == "string", `{item.id} has no info`)
				if item.coins ~= nil then
					expect(item.coins).toBeGreaterThan(0)
					expect(item.coins % 50).toBe(0)
				else
					assert(
						item.source or item.pass or item.id == Cosmetics.DEFAULT_KO,
						`{item.id} is neither sold nor earned`
					)
				end
			end
		end
	end)

	it("lets skins change colors and materials only", function()
		local allowed = {}
		for _, field in Cosmetics.SKIN_FIELDS do
			allowed[field] = true
		end
		for _, skin in Cosmetics.SKINS do
			for field, value in skin.look do
				assert(allowed[field], `{skin.id} changes {field}`)
				if field == "materials" then
					for from, to in value do
						assert(MATERIALS[from] and MATERIALS[to], `{skin.id}: bad material swap {from}`)
					end
				elseif field == "material" or field == "skinMaterial" then
					assert(MATERIALS[value], `{skin.id}: unknown material {value}`)
				else
					assert(string.match(value, "^#%x%x%x%x%x%x") or string.match(value, "^%a+"), `{skin.id}.{field}`)
				end
			end
		end
	end)

	it("never mentions a combat stat anywhere in the cosmetics data", function()
		for _, list in { Cosmetics.SKINS, Cosmetics.KO_EFFECTS, Cosmetics.PLATES } do
			walk(list, "cosmetics", function(key, path)
				for _, forbidden in Products.FORBIDDEN_PERKS do
					assert(not key:lower():find(forbidden:lower(), 1, true), `{path} looks like a combat field`)
				end
			end)
		end
	end)

	it("builds skinned rigs with exactly the same parts and sizes", function()
		for _, id in Visuals.SLICE_FIGHTERS do
			local base = RigBuilder.build(id)
			local baseShape = shape(base)
			for _, skin in Cosmetics.skinsFor(id) do
				local rig = RigBuilder.build(id, skin.id)
				expect(rig:GetAttribute("Skin")).toBe(skin.id)
				expect(rig:GetAttribute("StandHeight")).toBe(base:GetAttribute("StandHeight"))
				local skinShape = shape(rig)
				expect(#skinShape).toBe(#baseShape)
				for k, entry in baseShape do
					assert(skinShape[k] == entry, `{id}/{skin.id}: part {entry} changed`)
				end
			end
		end
	end)

	it("applies a skin's colors and ignores skins of other fighters", function()
		local look = Looks.resolve("ninja", "ninja_jade")
		expect(look.glow).toBe("#3BFFB0")
		expect(look.build).toBe(Looks.get("ninja").build)
		expect(Looks.resolve("ninja", "golem_moss")).toBe(Looks.get("ninja"))
		expect(Looks.resolve("ninja", "nope")).toBe(Looks.get("ninja"))
		expect(Looks.resolve("golem", "gold").material).toBe("Foil")
		expect(RigBuilder.build("ninja", "golem_moss"):GetAttribute("Skin")).toBe(nil)
	end)

	it("sells every sold skin for Robux through an existing Skin-direkt product", function()
		for _, skin in Cosmetics.SKINS do
			if skin.coins then
				local robux, productId = Cosmetics.robux(skin)
				local product = Products.byId[productId] :: any
				assert(product, `{skin.id}: no product {productId}`)
				expect(product.robux).toBe(robux)
				local grant = product.grants[1]
				expect(grant.kind).toBe("skinChoice")
				assert(skin.coins >= grant.minPrice and skin.coins <= grant.maxPrice, `{skin.id} outside its step`)
			end
		end
	end)

	it("knows every KO style the client can draw", function()
		local styles =
			{ classic = true, confetti = true, pixel = true, nova = true, thunder = true, petals = true, void = true }
		for _, ko in Cosmetics.KO_EFFECTS do
			assert(styles[ko.style], `{ko.id}: unknown style {ko.style}`)
		end
		expect(Cosmetics.get(Cosmetics.DEFAULT_KO).style).toBe("classic")
	end)

	it("features the same items all day and different ones on other days, never unsold ones", function()
		local day = Cosmetics.dayOf(1793664000) -- 2026-11-02
		local a, b = Cosmetics.featured(day), Cosmetics.featured(day)
		expect(#a).toBe(4)
		for k = 1, 4 do
			expect(a[k].id).toBe(b[k].id)
			assert(a[k].coins, `{a[k].id} is featured but not sold`)
		end
		local changed = false
		for offset = 1, 7 do
			if Cosmetics.featured(day + offset)[1].id ~= a[1].id then
				changed = true
			end
		end
		expect(changed).toBe(true)
	end)
end)
