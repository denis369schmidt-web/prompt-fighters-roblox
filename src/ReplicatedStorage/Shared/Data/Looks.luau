--!strict
-- How each fighter looks on Roblox: body colors per region, build (proportions), face, material and the gear sets
-- (Visual/GearData) that Visual/RigBuilder builds from plain parts. Own designs only (no catalog or third-party
-- assets, no look-alikes of known characters). Fighters without an entry get a look from their element color, so
-- every roster fighter is playable before it gets a hand-made look.

local Cosmetics = require(script.Parent.Cosmetics)
local Fighters = require(script.Parent.Fighters)
local Visuals = require(script.Parent.Visuals)

-- Face settings. eyes: "sharp" (determined), "round" (big, friendly), "glow" (neon slits), "none".
-- brows: "angry" | "calm" | "raised" | "none". mouth: "smirk" | "grin" | "smile" | "flat" | "frown" | "open" | "none".
export type Face = {
	eyes: string?,
	eyeColor: string?,
	brows: string?,
	browColor: string?,
	mouth: string?,
	lashes: boolean?,
	blush: boolean?,
	nose: boolean?,
}

-- Body proportions in studs at scale 1: chest/waist/hip widths, neck diameter, limb thickness factors, shoulder
-- (arm bone x) and stance (leg bone x).
export type Build = {
	chest: number,
	waist: number,
	hip: number,
	neck: number,
	arm: number,
	leg: number,
	hand: number,
	foot: number,
	shoulder: number,
	stance: number,
}

export type Look = {
	skin: string, -- head, neck and bare skin
	primary: string, -- top (chest, abdomen) and by default the sleeves
	secondary: string, -- pants (pelvis, legs)
	glow: string, -- neon accents, trails, hit sparks
	material: string?, -- Enum.Material name for clothing
	skinMaterial: string?, -- Enum.Material name for skin (default SmoothPlastic)
	scale: { height: number, width: number, depth: number, head: number },
	build: string?, -- "light" | "medium" | "heavy" (Looks.BUILDS)
	gear: { string },
	glowEyes: boolean?,
	face: Face?,
	hair: string?, -- hair color
	accent: string?, -- trims, plumes, straps
	trim: string?, -- second accent (defaults to accent)
	-- Region color slots (look field, fixed tone or "#RRGGBB", optionally "*factor"): upper arms, forearms,
	-- gloves (nil = bare hands), boots, belt ("none" = no belt), neck.
	sleeves: string?,
	forearms: string?,
	gloves: string?,
	boots: string?,
	belt: string?,
	neck: string?,
	headOffset: { number }?, -- head position relative to the neck bone, in head units (default 0, 0.1, 0)
	materials: { [string]: string }?, -- gear material swaps, e.g. { Slate = "Ice" } for an ice golem
}

local Looks = {}

Looks.BUILDS = {
	light = {
		chest = 1.72,
		waist = 1.2,
		hip = 1.45,
		neck = 0.42,
		arm = 0.84,
		leg = 0.9,
		hand = 0.92,
		foot = 0.92,
		shoulder = 1.18,
		stance = 0.46,
	},
	medium = {
		chest = 1.9,
		waist = 1.36,
		hip = 1.55,
		neck = 0.5,
		arm = 1,
		leg = 1,
		hand = 1,
		foot = 1,
		shoulder = 1.32,
		stance = 0.5,
	},
	heavy = {
		chest = 2.05,
		waist = 1.7,
		hip = 1.72,
		neck = 0.68,
		arm = 1.32,
		leg = 1.22,
		hand = 1.28,
		foot = 1.12,
		shoulder = 1.48,
		stance = 0.56,
	},
} :: { [string]: Build }

local DEFAULT_SCALE = { height = 1, width = 1, depth = 1, head = 1 }

Looks.BY_ID = {
	-- Lightning ninja: slim navy suit, hood and mask, glowing eyes, electric scarf, twin blades on the back.
	ninja = {
		skin = "#C99A78",
		primary = "#262B4A",
		secondary = "#1C2038",
		glow = "#3FD0FF",
		material = "Fabric",
		build = "light",
		scale = { height = 1, width = 1, depth = 1, head = 1 },
		gear = { "ninja_hood", "ninja_mask", "ninja_suit", "scarf_tails", "blades_back", "arm_wraps", "shin_wraps" },
		glowEyes = true,
		accent = "#8A93B8",
		forearms = "primary*0.8",
		gloves = "#15182A",
		boots = "#15182A",
		belt = "#3FD0FF*0.6",
	},
	-- Magma golem: a hulking body of craggy rock with glowing cracks, boulder shoulders and molten fists.
	golem = {
		skin = "#7A665C",
		primary = "#8A7262",
		secondary = "#5E4C42",
		glow = "#FF6A1F",
		material = "Slate",
		skinMaterial = "Slate",
		build = "heavy",
		scale = { height = 1.12, width = 1.25, depth = 1.15, head = 0.85 },
		gear = { "rock_head", "rock_body", "rock_shoulders", "magma_cracks", "magma_fists", "rock_legs" },
		glowEyes = true,
		face = { eyes = "glow", brows = "none", mouth = "none", nose = false },
		boots = "primary*0.8",
		belt = "none",
		headOffset = { 0, -0.05, -0.25 },
	},
	-- Light warrior: winged golden helm, braids, white-and-gold armor, feather wings and a lance.
	valkyrie = {
		skin = "#F0C8A8",
		primary = "#ECE6D6",
		secondary = "#4E5E86",
		glow = "#FFE26A",
		material = "Fabric",
		build = "medium",
		scale = { height = 1.04, width = 0.98, depth = 1, head = 1 },
		gear = { "winged_helm", "braids", "valkyrie_armor", "skirt_plates", "feather_wings", "lance", "greaves" },
		face = { eyes = "round", eyeColor = "#3C7AD6", brows = "calm", mouth = "smirk", lashes = true },
		hair = "#F5DC8A",
		accent = "#D4A93C",
		sleeves = "secondary",
		forearms = "accent",
		gloves = "#8C6A2A",
		boots = "accent*0.85",
		belt = "accent*0.7",
	},
	-- Wind monk: shaved head with a glowing mark, big prayer beads, crossed teal vest over bare arms, wide pants.
	kairo = {
		skin = "#C98E62",
		primary = "#1F7A6E",
		secondary = "#EDE6D6",
		glow = "#7DF5B4",
		material = "Fabric",
		build = "medium",
		scale = { height = 1, width = 1.05, depth = 1, head = 1 },
		gear = { "monk_vest", "prayer_beads", "forehead_mark", "wrist_wraps", "monk_sash", "wide_pants" },
		face = { eyes = "sharp", eyeColor = "#2B6E52", brows = "angry", browColor = "#3A2418", mouth = "grin" },
		sleeves = "skin",
		boots = "#5A4632",
		belt = "none",
	},
	-- Frost assassin: long white hair, crystal crown, high-collared ice coat, shards and twin ice daggers.
	glaciem = {
		skin = "#AFC6DE",
		primary = "#2E4878",
		secondary = "#1E2C4C",
		glow = "#8FE3FF",
		material = "Fabric",
		build = "light",
		scale = { height = 1.02, width = 0.95, depth = 0.95, head = 1 },
		gear = { "frost_hair", "ice_crown", "frost_coat", "ice_shards", "ice_daggers" },
		glowEyes = true,
		face = { eyes = "glow", brows = "angry", mouth = "flat" },
		hair = "#F4FAFF",
		accent = "#DDEBFA",
		gloves = "#1A2440",
		boots = "#DDEBFA*0.8",
		belt = "#8FE3FF*0.5",
	},
	-- Ronin with three blades: crimson haori over dark kimono, topknot, straw hat on the back, katana in hand.
	jubei = {
		skin = "#E2B08C",
		primary = "#8A1F2B",
		secondary = "#2E2C34",
		glow = "#3BFAC8",
		material = "Fabric",
		build = "medium",
		scale = { height = 1.02, width = 1, depth = 1, head = 1 },
		gear = { "topknot", "haori", "hakama", "katana", "hip_swords", "straw_hat", "wrist_wraps" },
		face = { eyes = "sharp", eyeColor = "#4A2A1A", brows = "angry", mouth = "smirk" },
		hair = "#1C1820",
		accent = "#F2EEE6",
		forearms = "primary*0.85",
		boots = "#2A2228",
		belt = "#3BFAC8*0.45",
	},
	-- Jet speedster: open racing helmet with a tinted visor, aero armor, thruster pack and jet boots.
	zip = {
		skin = "#F2C9A0",
		primary = "#FF7A1A",
		secondary = "#F4F4F4",
		glow = "#FFE44D",
		material = "SmoothPlastic",
		build = "light",
		scale = { height = 0.94, width = 0.95, depth = 0.95, head = 1.05 },
		gear = { "racer_helmet", "racer_suit", "backpack_thrusters", "jet_boots" },
		face = { eyes = "round", eyeColor = "#2D6CD6", brows = "raised", mouth = "grin" },
		hair = "#5A3A22",
		accent = "#2B2D42",
		forearms = "secondary",
		gloves = "#2B2D42",
		boots = "#2B2D42",
		belt = "accent",
	},
	-- Bunny archer: long ears, silver bob, short cape, bracer, bow in hand and a quiver of glowing arrows.
	lepora = {
		skin = "#F1D3BE",
		primary = "#B9A6E0",
		secondary = "#4B3A6E",
		glow = "#B9F7FF",
		material = "Fabric",
		build = "light",
		scale = { height = 0.95, width = 0.95, depth = 0.95, head = 1.05 },
		gear = { "bunny_ears", "hair_bob", "archer_cape", "bow", "quiver", "bunny_tail", "fur_boots" },
		face = { eyes = "round", eyeColor = "#7A4FD0", brows = "calm", mouth = "smile", lashes = true, blush = true },
		hair = "#E8E0F4",
		accent = "#F4F1FA",
		forearms = "skin",
		gloves = "#6E5A8C",
		boots = "#F4F1FA",
		belt = "#6E5A8C",
	},
	-- Ice-blue plated knight: great helm with a crimson plume, tabard, layered pauldrons and a kite shield.
	steel_knight = {
		skin = "#E0B896",
		primary = "#A7B4C2",
		secondary = "#6A7684",
		glow = "#9FE7FF",
		material = "Metal",
		build = "heavy",
		scale = { height = 1.05, width = 1.08, depth = 1.05, head = 0.95 },
		gear = { "knight_helm", "plume", "plate_armor", "tabard", "pauldrons", "kite_shield", "knight_sword" },
		accent = "#B3202A",
		gloves = "#8A96A6",
		boots = "#8A96A6",
		belt = "#4A4F58",
		neck = "#6A7684",
	},
	-- Stocky tinkerer: brass goggles, wild orange hair and beard, leather apron, bomb belt and a smoking backpack.
	grimbolt = {
		skin = "#E6B48E",
		primary = "#5A6E7E",
		secondary = "#3D3A35",
		glow = "#FF8A1F",
		material = "Fabric",
		build = "heavy",
		scale = { height = 0.9, width = 1.0, depth = 1.0, head = 1.12 },
		gear = { "wild_hair", "beard", "goggles", "apron", "bomb_belt", "tinker_pack", "wrench" },
		face = { eyes = "round", eyeColor = "#3A6E9A", brows = "raised", mouth = "none" },
		hair = "#E8641F",
		accent = "#8A8F99",
		sleeves = "primary",
		forearms = "skin",
		gloves = "#6B4423",
		boots = "#4A3420",
		belt = "#4A3420",
	},
	-- Dragon templar: horned dragon helm, scaled armor, leathery wings, armored tail and a flame sword.
	dragon = {
		skin = "#E8BE9A",
		primary = "#E8E2D6",
		secondary = "#5A5E68",
		glow = "#FF5A1F",
		material = "Metal",
		build = "heavy",
		scale = { height = 1.06, width = 1.1, depth = 1.05, head = 1 },
		gear = { "dragon_helm", "dragon_armor", "dragon_wings", "dragon_tail", "flame_sword", "dragon_pauldrons" },
		accent = "#9E1C24",
		trim = "#D4A93C",
		gloves = "#4A4F58",
		boots = "#4A4F58",
		belt = "#9E1C24*0.7",
		neck = "#4A4F58",
	},
	-- Fire phoenix: flame-feather crest, neon gradient wings and tail feathers, gold armlets and a glaive.
	phoenix = {
		skin = "#F1C7A4",
		primary = "#C8231E",
		secondary = "#5C1A14",
		glow = "#FFB23D",
		material = "Fabric",
		build = "light",
		scale = { height = 1.02, width = 1, depth = 1, head = 1 },
		gear = { "flame_crest", "phoenix_wings", "phoenix_garb", "tail_feathers", "glaive" },
		face = { eyes = "round", eyeColor = "#E0861A", brows = "angry", mouth = "smirk", lashes = true },
		hair = "#D62A1A",
		accent = "#FFD24A",
		forearms = "skin",
		gloves = "#FFD24A*0.8",
		boots = "#5C1A14*0.7",
		belt = "accent",
	},
	-- Celestial fox spirit: fox ears, long white hair, five glowing tails, star charms and fox-fire orbs.
	celestial_fox = {
		skin = "#F6E3D6",
		primary = "#F4F1FA",
		secondary = "#3C2E5C",
		glow = "#38BDF8",
		material = "Fabric",
		build = "light",
		scale = { height = 0.98, width = 0.96, depth = 0.96, head = 1.04 },
		gear = { "fox_ears", "fox_hair", "fox_robe", "fox_tails", "star_charms", "foxfire" },
		face = { eyes = "round", eyeColor = "#38BDF8", brows = "calm", mouth = "smile", lashes = true, blush = true },
		hair = "#FFFFFF",
		accent = "#3C2E5C",
		trim = "#38BDF8",
		sleeves = "primary",
		forearms = "primary",
		boots = "#3C2E5C*0.7",
		belt = "#38BDF8*0.7",
	},
	-- Artillery mech: boxy armored head with a visor, missile pods, pistons, glowing reactor core and big fists.
	cyborg_mech = {
		skin = "#A8B2BE",
		primary = "#8E98A6",
		secondary = "#5A616C",
		glow = "#22D3EE",
		material = "Metal",
		skinMaterial = "Metal",
		build = "heavy",
		scale = { height = 1.08, width = 1.18, depth = 1.12, head = 0.95 },
		gear = { "mech_head", "mech_armor", "missile_pods", "mech_limbs", "chest_core" },
		glowEyes = true,
		accent = "#FFB000",
		gloves = "#3A404A",
		boots = "#3A404A",
		belt = "#FFB000*0.8",
		neck = "#2E333B",
	},
	-- Necromancer: deep hood, layered robe, bone collar and pauldrons, soul-lit eyes and a skull staff.
	nekra = {
		skin = "#C8BCD8",
		primary = "#3A2A5C",
		secondary = "#241A3C",
		glow = "#B98CFF",
		material = "Fabric",
		build = "light",
		scale = { height = 1.03, width = 0.96, depth = 0.96, head = 1 },
		gear = { "hood", "robe", "bone_armor", "skull_staff", "soul_orbs" },
		glowEyes = true,
		face = { eyes = "glow", brows = "angry", mouth = "smirk", lashes = true },
		hair = "#4A2E6E",
		accent = "#E8E4D8",
		forearms = "primary*0.8",
		gloves = "#E8E4D8*0.75",
		boots = "#1A1428",
		belt = "#B98CFF*0.5",
	},
	-- Desert rodeo grappler: wide-brim hat, red bandana, leather vest and chaps, big buckle, lasso and spurs.
	dusty = {
		skin = "#D9A27A",
		primary = "#E8D8B8",
		secondary = "#3E5C80",
		glow = "#FFC86A",
		material = "Fabric",
		build = "medium",
		scale = { height = 1, width = 1.05, depth = 1, head = 1 },
		gear = { "cowboy_hat", "bandana", "cowboy_vest", "chaps", "lasso_coil", "spurs" },
		face = { eyes = "sharp", eyeColor = "#4A6A3A", brows = "angry" },
		hair = "#6B4423",
		accent = "#7A4A26",
		sleeves = "primary",
		forearms = "primary",
		gloves = "#7A4A26",
		boots = "#5A3A20",
		belt = "#3A2414",
	},
} :: { [string]: Look }

local function shade(hex: string, factor: number): string
	local r = tonumber(string.sub(hex, 2, 3), 16) :: number
	local g = tonumber(string.sub(hex, 4, 5), 16) :: number
	local b = tonumber(string.sub(hex, 6, 7), 16) :: number
	local function c(v: number): number
		return math.clamp(math.floor(v * factor + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", c(r), c(g), c(b))
end
Looks.shade = shade

function Looks.get(fighterId: string): Look
	local look = Looks.BY_ID[fighterId]
	if look then
		return look
	end
	local def = Fighters.get(fighterId)
	-- Runtime fighters (prompt fighters) register their look while Fighters.get resolves them.
	local registered = Looks.BY_ID[fighterId]
	if registered then
		return registered
	end
	local color = Visuals.elementColor(def.element)
	local heavy = def.weight >= 1.15
	return {
		skin = "#D9B59A",
		primary = shade(color, 0.55),
		secondary = shade(color, 0.3),
		glow = color,
		material = "Fabric",
		build = if heavy then "heavy" else "medium",
		scale = if heavy then { height = 1.06, width = 1.1, depth = 1.05, head = 0.95 } else DEFAULT_SCALE,
		gear = { "hair_short", "scarf" },
		hair = "#2A2226",
		face = { eyes = "sharp", brows = "angry", mouth = "smirk" },
		gloves = shade(color, 0.35),
	}
end

-- A fighter's look with a skin (Data/Cosmetics) applied: only colors and materials change, so the silhouette and
-- every size stay the same. Unknown skins, or skins for another fighter, give the normal look. Cached per pair.
local skinned: { [string]: Look } = {}
function Looks.resolve(fighterId: string, skinId: string?): Look
	local base = Looks.get(fighterId)
	if skinId == nil or skinId == "" then
		return base
	end
	local found = Cosmetics.skin(skinId :: string)
	if found == nil or not Cosmetics.fits(found :: Cosmetics.Skin, fighterId) then
		return base
	end
	local skin = found :: Cosmetics.Skin
	local cacheKey = `{fighterId}|{skinId}`
	local cached = skinned[cacheKey]
	if cached then
		return cached
	end
	local look = table.clone(base)
	for _, field in Cosmetics.SKIN_FIELDS do
		local value = skin.look[field]
		-- Gloves and belts add parts: a skin may recolor them but never add or remove them.
		local adds = (field == "gloves" and base.gloves == nil) or (field == "belt" and base.belt == "none")
		if value ~= nil and not adds then
			(look :: any)[field] = value
		end
	end
	skinned[cacheKey] = look
	return look
end

return Looks
