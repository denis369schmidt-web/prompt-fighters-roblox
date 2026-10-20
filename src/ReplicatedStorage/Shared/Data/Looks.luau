--!strict
-- How each fighter looks on Roblox: body colors, proportions, material and the gear pieces Visual/RigBuilder builds
-- from plain parts. Own designs only (no catalog or third-party assets). Fighters without an entry get a look
-- from their element color, so every roster fighter is playable before it gets a hand-made look.

local Fighters = require(script.Parent.Fighters)
local Visuals = require(script.Parent.Visuals)

export type Look = {
	skin: string, -- head and hands
	primary: string, -- torso and arms
	secondary: string, -- legs
	glow: string, -- neon accents, trails, hit sparks
	material: string?, -- Enum.Material name for the body
	scale: { height: number, width: number, depth: number, head: number },
	gear: { string },
	glowEyes: boolean?,
	hair: string?, -- hair gear
	accent: string?, -- trims, plumes, straps
}

local Looks = {}

local DEFAULT_SCALE = { height = 1, width = 1, depth = 1, head = 1 }

Looks.BY_ID = {
	ninja = {
		skin = "#4A5070",
		primary = "#3A4068",
		secondary = "#2A2E4A",
		glow = "#3FD0FF",
		material = "Fabric",
		scale = { height = 1, width = 0.92, depth = 0.95, head = 0.95 },
		gear = { "headband", "mask", "blades_back", "scarf" },
		glowEyes = true,
	},
	golem = {
		skin = "#6A5248",
		primary = "#7A5E50",
		secondary = "#4E3C34",
		glow = "#FF6A1F",
		material = "Slate",
		scale = { height = 1.12, width = 1.3, depth = 1.15, head = 0.9 },
		gear = { "rock_shoulders", "magma_cracks", "magma_fists" },
		glowEyes = true,
	},
	jubei = {
		skin = "#E2B08C",
		primary = "#7A1F2B",
		secondary = "#222026",
		glow = "#3BFAC8",
		material = "Fabric",
		scale = { height = 1.02, width = 1, depth = 1, head = 1 },
		gear = { "katana", "sheath", "sash", "topknot" },
	},
	lepora = {
		skin = "#F1D3BE",
		primary = "#E8E4F2",
		secondary = "#6E5A8C",
		glow = "#B9F7FF",
		material = "Fabric",
		scale = { height = 0.95, width = 0.88, depth = 0.9, head = 1.05 },
		gear = { "ears", "bow", "quiver", "scarf" },
	},
	valkyrie = {
		skin = "#F0C8A8",
		primary = "#E9E2CF",
		secondary = "#6C5A3A",
		glow = "#FFE26A",
		material = "Fabric",
		scale = { height = 1.04, width = 1, depth = 1, head = 1 },
		gear = { "winged_helm", "wings_back", "pauldrons", "hair_long" },
		hair = "#F5E6A8",
		accent = "#D4A93C",
	},
	kairo = {
		skin = "#C98E62",
		primary = "#1F7A6E",
		secondary = "#EDE6D6",
		glow = "#7DF5B4",
		material = "Fabric",
		scale = { height = 1, width = 1.05, depth = 1, head = 1 },
		gear = { "prayer_beads", "wrist_wraps", "sash", "forehead_mark" },
	},
	glaciem = {
		skin = "#DCE8F5",
		primary = "#EAF4FF",
		secondary = "#5B6F9A",
		glow = "#8FE3FF",
		material = "Fabric",
		scale = { height = 1, width = 0.92, depth = 0.95, head = 1 },
		gear = { "hair_long", "ice_crown", "ice_shards", "ice_daggers", "coat_tail" },
		hair = "#F4FAFF",
		glowEyes = true,
	},
	zip = {
		skin = "#F2C9A0",
		primary = "#FF7A1A",
		secondary = "#F4F4F4",
		glow = "#FFE44D",
		material = "SmoothPlastic",
		scale = { height = 0.92, width = 0.9, depth = 0.92, head = 1.05 },
		gear = { "helmet_visor", "jet_boots", "backpack_thrusters" },
		accent = "#2B2D42",
	},
	steel_knight = {
		skin = "#E0B896",
		primary = "#A7B4C2",
		secondary = "#5A6472",
		glow = "#9FE7FF",
		material = "Metal",
		scale = { height = 1.05, width = 1.15, depth = 1.1, head = 1 },
		gear = { "knight_helm", "plume", "tower_shield", "tabard", "pauldrons" },
		accent = "#B3202A",
	},
	grimbolt = {
		skin = "#E6B48E",
		primary = "#6B4E2E",
		secondary = "#3D3A35",
		glow = "#FF8A1F",
		material = "Fabric",
		scale = { height = 0.9, width = 1.1, depth = 1.05, head = 1.1 },
		gear = { "goggles", "wild_hair", "bomb_belt", "tinker_pack" },
		hair = "#FF6A1F",
		accent = "#8A8F99",
	},
	dragon = {
		skin = "#E8BE9A",
		primary = "#F2EEE6",
		secondary = "#8A8F99",
		glow = "#FF5A1F",
		material = "Metal",
		scale = { height = 1.08, width = 1.2, depth = 1.1, head = 1 },
		gear = { "great_helm", "cape", "flame_sword", "pauldrons" },
		accent = "#B3202A",
	},
	phoenix = {
		skin = "#F1C7A4",
		primary = "#C8231E",
		secondary = "#5C1A14",
		glow = "#FFB23D",
		material = "Fabric",
		scale = { height = 1, width = 0.95, depth = 0.95, head = 1 },
		gear = { "hair_long", "flame_wings", "glaive" },
		hair = "#E8461F",
		accent = "#FFD24A",
	},
	celestial_fox = {
		skin = "#F6E3D6",
		primary = "#F4F1FA",
		secondary = "#3C2E5C",
		glow = "#38BDF8",
		material = "Fabric",
		scale = { height = 0.97, width = 0.92, depth = 0.95, head = 1.02 },
		gear = { "ears", "fox_tails", "sash", "hair_long" },
		hair = "#FFFFFF",
	},
	cyborg_mech = {
		skin = "#9AA4B1",
		primary = "#5A6270",
		secondary = "#2E333B",
		glow = "#22D3EE",
		material = "Metal",
		scale = { height = 1.1, width = 1.25, depth = 1.15, head = 1 },
		gear = { "mech_visor", "missile_pods", "chest_core" },
		accent = "#FFB000",
		glowEyes = true,
	},
	nekra = {
		skin = "#CFC8D9",
		primary = "#2A2140",
		secondary = "#1A1428",
		glow = "#E7E5E4",
		material = "Fabric",
		scale = { height = 1.02, width = 0.95, depth = 0.95, head = 1 },
		gear = { "hood", "robe", "skull_staff" },
		accent = "#E8E4D8",
		glowEyes = true,
	},
	dusty = {
		skin = "#D9A27A",
		primary = "#A0522D",
		secondary = "#3E5C80",
		glow = "#D6B37A",
		material = "Fabric",
		scale = { height = 1, width = 1.05, depth = 1, head = 1 },
		gear = { "cowboy_hat", "bandana", "lasso_coil", "boots" },
		accent = "#6B4423",
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
	local color = Visuals.elementColor(def.element)
	local heavy = def.weight >= 1.15
	return {
		skin = "#D9B59A",
		primary = shade(color, 0.55),
		secondary = shade(color, 0.3),
		glow = color,
		material = "SmoothPlastic",
		scale = if heavy then { height = 1.08, width = 1.2, depth = 1.1, head = 0.95 } else DEFAULT_SCALE,
		gear = { "scarf" },
	}
end

return Looks
