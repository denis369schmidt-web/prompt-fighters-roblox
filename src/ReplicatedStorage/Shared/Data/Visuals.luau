--!strict
-- Look-only values shared by server (arena build) and client (renderer, HUD). No gameplay numbers here.

local Constants = require(script.Parent.Constants)

local Visuals = {}

-- Simulation meters -> Roblox studs.
Visuals.STUDS_PER_METER = Constants.METER
-- Height of the stage surface in the world, so the blast zone below stays above the default baseplate height.
Visuals.STAGE_Y = 60
Visuals.BODY_HEIGHT_M = 1.6
Visuals.BODY_WIDTH_M = 0.75

-- Element -> main color (hex). Matched by prefix, so "fire", "nine_fire" and "sun_flame" share a family.
local ELEMENT_COLORS: { { string } } = {
	{ "fire", "#FF6A2B" },
	{ "nine_fire", "#FF8A1F" },
	{ "sun", "#FFC23D" },
	{ "ice", "#7FD8FF" },
	{ "water", "#2F8CFF" },
	{ "wind", "#7DF5B4" },
	{ "electric", "#FFE44D" },
	{ "plasma", "#C46BFF" },
	{ "ki_gold", "#FFD24A" },
	{ "ki_purple", "#A15BFF" },
	{ "metal", "#B8C3CF" },
	{ "shadow", "#6B4BFF" },
	{ "soul", "#5B3A8C" },
	{ "dark", "#7A2FD6" },
	{ "void", "#3C1F6E" },
	{ "blood", "#D6334A" },
	{ "holy", "#FFF1A8" },
	{ "acid", "#9BFF3A" },
	{ "nature", "#4CC75A" },
	{ "wood", "#5FA33C" },
	{ "gravity", "#8C7BFF" },
	{ "rubber", "#FF5FA2" },
	{ "impact", "#FF8F5A" },
	{ "claw", "#E0E0E0" },
	{ "death", "#4A4F5C" },
}
Visuals.DEFAULT_COLOR = "#E6E6F0"

function Visuals.elementColor(element: string): string
	local best, bestLen = Visuals.DEFAULT_COLOR, 0
	for _, pair in ELEMENT_COLORS do
		local prefix = pair[1]
		if string.sub(element, 1, #prefix) == prefix and #prefix > bestLen then
			best, bestLen = pair[2], #prefix
		end
	end
	return best
end

-- Player slot colors for HUD cards and name tags (P1 red, P2 blue, P3 yellow, P4 green).
Visuals.SLOT_COLORS = { "#FF4D5E", "#3FA9FF", "#FFD23F", "#4CE08A" }

-- The Phase 1 vertical slice plays these four fighters on NEON-GASSE.
Visuals.SLICE_FIGHTERS = { "ninja", "golem", "jubei", "lepora" }
Visuals.SLICE_ARENA = "neon_alley"

return Visuals
