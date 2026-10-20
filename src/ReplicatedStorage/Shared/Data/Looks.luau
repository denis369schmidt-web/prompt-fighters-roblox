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
		primary = "#2F4A3A",
		secondary = "#1F2A24",
		glow = "#7DF5B4",
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
