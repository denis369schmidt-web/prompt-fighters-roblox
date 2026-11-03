--!strict
-- Cosmetics as data: skins (alternative looks per launch fighter plus material skins for any fighter), KO effects
-- and name plates (title + frame). Every item is bought directly: fixed coin price and, for skins, a fixed Robux
-- price (Products "Skin direkt"). Rarity is only a label for the shop card, never a drop chance: nothing here is
-- random. Cosmetics have zero combat effect: a skin may only change colors and materials (SKIN_FIELDS, checked by
-- tests/Cosmetics.spec.luau), and the server sends equipped cosmetics to clients for display only; the simulation
-- never sees them. Own designs only (no look-alikes of known characters).

local Products = require(script.Parent.Products)
local RewardData = require(script.Parent.Generated.RewardData)
local Seed = require(script.Parent.Parent.Util.Seed)

export type Rarity = "standard" | "selten" | "episch" | "legendär" | "ruhmespfad"

-- Look fields a skin may override (Data/Looks Look). Colors and materials only: no gear, scale, build or face.
export type SkinLook = { [string]: any }

export type Skin = {
	id: string,
	kind: "skin",
	name: string,
	rarity: Rarity,
	fighter: string?, -- nil = material skin, fits every fighter
	coins: number?, -- nil = not for sale (earned elsewhere, see source)
	source: string?, -- where an unsold skin comes from (shown in the shop)
	info: string,
	look: SkinLook,
}

export type KoStyle = "classic" | "confetti" | "pixel" | "nova" | "thunder" | "petals" | "void"

export type KoEffect = {
	id: string,
	kind: "ko",
	name: string,
	rarity: Rarity,
	coins: number?,
	info: string,
	style: KoStyle,
	color: string?, -- fixed main color; nil = the fighter's glow color
	accent: string?,
}

export type Plate = {
	id: string,
	kind: "plate",
	name: string,
	rarity: Rarity,
	coins: number?,
	pass: string?, -- owned with this game pass instead of coins
	info: string,
	title: string, -- text under the player's name
	frame: string, -- frame color
}

export type Item = Skin | KoEffect | Plate

local Cosmetics = {}

Cosmetics.RARITIES = {
	standard = { name = "STANDARD", color = "#A9A6BC" },
	selten = { name = "SELTEN", color = "#3FA9FF" },
	episch = { name = "EPISCH", color = "#B98CFF" },
	["legendär"] = { name = "LEGENDÄR", color = "#FFD24A" },
	ruhmespfad = { name = "RUHMESPFAD", color = "#FF8A3D" },
} :: { [string]: { name: string, color: string } }

-- Fixed coin prices per rarity for the fighter skins.
Cosmetics.SKIN_PRICES = { selten = 400, episch = 700, ["legendär"] = 1100 } :: { [string]: number }

-- Look fields a skin may set (tests check every skin against this list).
Cosmetics.SKIN_FIELDS = {
	"skin",
	"primary",
	"secondary",
	"glow",
	"accent",
	"trim",
	"hair",
	"material",
	"skinMaterial",
	"sleeves",
	"forearms",
	"gloves",
	"boots",
	"belt",
	"neck",
	"materials",
}

-- Fighter skins: two per launch fighter. Field order: id, fighter, name, rarity, info, look.
local FIGHTER_SKINS: { { any } } = {
	{
		"ninja_bloodmoon",
		"ninja",
		"BLUTMOND",
		"selten",
		"Rot wie der Mond über den Dächern",
		{
			primary = "#4A1420",
			secondary = "#2A0C14",
			glow = "#FF3B4E",
			accent = "#C8A0A8",
			gloves = "#1A0A10",
			boots = "#1A0A10",
			belt = "#FF3B4E*0.6",
		},
	},
	{
		"ninja_jade",
		"ninja",
		"JADESCHATTEN",
		"episch",
		"Weißer Anzug, Jadeblitze, goldene Schnallen",
		{
			primary = "#E4EAEC",
			secondary = "#2F6F5A",
			glow = "#3BFFB0",
			accent = "#C9A24A",
			gloves = "#2F6F5A",
			boots = "#2F6F5A",
			belt = "#C9A24A",
		},
	},
	{
		"golem_glacier",
		"golem",
		"GLETSCHERKOLOSS",
		"episch",
		"Ein Berg aus Eis statt aus Lava",
		{
			skin = "#9EC8DE",
			primary = "#B8DDEE",
			secondary = "#6E98B4",
			glow = "#7FE3FF",
			material = "Glacier",
			skinMaterial = "Glacier",
			materials = { Slate = "Glacier" },
		},
	},
	{
		"golem_moss",
		"golem",
		"MOOSRIESE",
		"selten",
		"Uralter Fels, von Moos und Leuchtsporen bewachsen",
		{ skin = "#6E7A58", primary = "#7C8C5E", secondary = "#4E5A3A", glow = "#B6FF5A" },
	},
	{
		"valkyrie_night",
		"valkyrie",
		"NACHTSCHWINGE",
		"episch",
		"Dunkle Rüstung, silberne Federn",
		{
			primary = "#2A2438",
			secondary = "#14101E",
			glow = "#B98CFF",
			hair = "#E8E4F4",
			accent = "#A7B4C2",
			gloves = "#3A3448",
		},
	},
	{
		"valkyrie_rose",
		"valkyrie",
		"ROSENSCHILD",
		"selten",
		"Rosé und Bordeaux mit hellem Gold",
		{
			primary = "#F6D6DE",
			secondary = "#8C2E4A",
			glow = "#FF8FB0",
			hair = "#8A4A2A",
			accent = "#E8C27A",
		},
	},
	{
		"kairo_ember",
		"kairo",
		"GLUTMÖNCH",
		"selten",
		"Weste in Glutrot, Zeichen in Orange",
		{ primary = "#8A2A12", secondary = "#F0D8B0", glow = "#FFB23D" },
	},
	{
		"kairo_storm",
		"kairo",
		"STURMAUGE",
		"episch",
		"Gewitterblau mit hellem Wolkenstoff",
		{ primary = "#2E3A6E", secondary = "#C8CEE8", glow = "#A8C8FF" },
	},
	{
		"glaciem_aurora",
		"glaciem",
		"POLARLICHT",
		"episch",
		"Mantel in Nordlichtgrün",
		{
			primary = "#1E5A5A",
			secondary = "#12303A",
			glow = "#7DFFC8",
			hair = "#D8FFF0",
			accent = "#B6FFE4",
			belt = "#7DFFC8*0.5",
		},
	},
	{
		"glaciem_onyx",
		"glaciem",
		"ONYXFROST",
		"selten",
		"Schwarzer Mantel, weißes Eislicht",
		{
			primary = "#1A1A22",
			secondary = "#0E0E14",
			glow = "#E8F4FF",
			hair = "#2A2A34",
			accent = "#8A93A6",
		},
	},
	{
		"jubei_indigo",
		"jubei",
		"INDIGO-WANDERER",
		"selten",
		"Indigo-Haori und goldene Klingen",
		{ primary = "#2A3A7A", secondary = "#E8E2D2", glow = "#FFD24A", accent = "#1C1820" },
	},
	{
		"jubei_blossom",
		"jubei",
		"BLÜTENKLINGE",
		"legendär",
		"Blassrosa Haori, weißes Haar, pinke Klingen",
		{
			primary = "#F2B8C8",
			secondary = "#3A2A3A",
			glow = "#FF6AA8",
			hair = "#F4F4F4",
			accent = "#FFFFFF",
			belt = "#FF6AA8*0.6",
		},
	},
	{
		"zip_turquoise",
		"zip",
		"TÜRKISBLITZ",
		"selten",
		"Türkis und Schwarz, Säuregrün im Schub",
		{ primary = "#18B8A8", secondary = "#1E2230", glow = "#9BFF3A", accent = "#F4F4F4" },
	},
	{
		"zip_retro",
		"zip",
		"RETRO-RENNER",
		"episch",
		"Creme, Rennrot und Marineblau",
		{ primary = "#F4E8C8", secondary = "#B3202A", glow = "#FFF1A8", accent = "#1E3A6E" },
	},
	{
		"lepora_meadow",
		"lepora",
		"WIESENPFEIL",
		"selten",
		"Frühlingsgrün mit Honighaar",
		{ primary = "#9CCB6A", secondary = "#4A6A2A", glow = "#FFF07A", hair = "#C8925A" },
	},
	{
		"lepora_starlit",
		"lepora",
		"STERNENHASE",
		"episch",
		"Nachtblau mit Sternengold",
		{ primary = "#232A5C", secondary = "#12163A", glow = "#FFE9A8", accent = "#FFD24A" },
	},
	{
		"knight_sun",
		"steel_knight",
		"SONNENPALADIN",
		"legendär",
		"Goldene Platten, weißer Federbusch",
		{
			primary = "#E2C066",
			secondary = "#8C6A2A",
			glow = "#FFF1A8",
			accent = "#F4F4F4",
			gloves = "#C8A04A",
			boots = "#C8A04A",
		},
	},
	{
		"knight_forge",
		"steel_knight",
		"SCHMIEDEGLUT",
		"episch",
		"Geschwärzter Stahl, glühende Fugen",
		{
			primary = "#3A3A40",
			secondary = "#22222A",
			glow = "#FF6A1F",
			accent = "#FF6A1F",
			gloves = "#2A2A30",
			boots = "#2A2A30",
		},
	},
	{
		"grimbolt_copper",
		"grimbolt",
		"KUPFERKESSEL",
		"selten",
		"Kupferweste, weißer Bart, blauer Funke",
		{ primary = "#B0603A", secondary = "#3A2A22", glow = "#5AE0FF", hair = "#F2F2F2" },
	},
	{
		"grimbolt_toxic",
		"grimbolt",
		"GIFTWERK",
		"episch",
		"Olivgrüne Werkstatt, giftgrüner Rauch",
		{ primary = "#3E4A2A", secondary = "#222A18", glow = "#9BFF3A", hair = "#6E8A2A" },
	},
	{
		"dragon_jade",
		"dragon",
		"JADEDRACHE",
		"episch",
		"Jadegrüne Schuppen mit Goldkante",
		{ primary = "#CFE8D8", secondary = "#2F5A4A", glow = "#3BFFB0", accent = "#1F7A5A", trim = "#D4A93C" },
	},
	{
		"dragon_abyss",
		"dragon",
		"ABGRUNDSCHUPPE",
		"legendär",
		"Schwarzviolette Rüstung, Seelenfeuer",
		{ primary = "#2A2438", secondary = "#14101E", glow = "#B05AFF", accent = "#5A1A8C", trim = "#A7B4C2" },
	},
	{
		"phoenix_azure",
		"phoenix",
		"BLAUFEUER",
		"episch",
		"Die heißeste Flamme ist blau",
		{ primary = "#1E5AC8", secondary = "#12285C", glow = "#7FD8FF", hair = "#2A8CFF", accent = "#E8F4FF" },
	},
	{
		"phoenix_ash",
		"phoenix",
		"ASCHENFLÜGEL",
		"selten",
		"Graue Asche, darunter noch Glut",
		{ primary = "#4A4A52", secondary = "#24242A", glow = "#FF8A3D", hair = "#2A2A30", accent = "#C8C8D0" },
	},
	{
		"fox_autumn",
		"celestial_fox",
		"HERBSTFUCHS",
		"selten",
		"Rotes Laub und warmes Fuchsfeuer",
		{ primary = "#F4E2C8", secondary = "#8C3A1A", glow = "#FF8A3D", hair = "#E8641F", accent = "#8C3A1A" },
	},
	{
		"fox_moon",
		"celestial_fox",
		"MONDFUCHS",
		"legendär",
		"Mitternachtsblau, silbernes Haar, Mondlicht",
		{
			primary = "#2A2450",
			secondary = "#F4F1FA",
			glow = "#E8E0FF",
			hair = "#C8C0F0",
			accent = "#F4F1FA",
			trim = "#FFD24A",
		},
	},
	{
		"mech_desert",
		"cyborg_mech",
		"WÜSTENLÄUFER",
		"selten",
		"Sandtarnung mit oranger Kernglut",
		{ skin = "#C8B08A", primary = "#C8A87A", secondary = "#6E5A3E", glow = "#FF8A1F", accent = "#2B2D42" },
	},
	{
		"mech_arctic",
		"cyborg_mech",
		"POLARWACHE",
		"episch",
		"Schneeweiße Panzerung, rote Markierungen",
		{ skin = "#E8EEF2", primary = "#F2F4F8", secondary = "#8A96A6", glow = "#3FA9FF", accent = "#FF4D5E" },
	},
	{
		"nekra_bone",
		"nekra",
		"KNOCHENKRONE",
		"selten",
		"Robe aus Knochenweiß, grünes Seelenlicht",
		{ primary = "#E8E4D8", secondary = "#8A8070", glow = "#7DFF9B", hair = "#E8E4D8", accent = "#3A2A5C" },
	},
	{
		"nekra_blood",
		"nekra",
		"BLUTORAKEL",
		"episch",
		"Tiefrote Robe, rote Augen",
		{ primary = "#5C1420", secondary = "#2A0A10", glow = "#FF4D5E", hair = "#2A0A10", accent = "#E8E4D8" },
	},
	{
		"dusty_midnight",
		"dusty",
		"MITTERNACHTSREITER",
		"selten",
		"Schwarzes Leder, silberne Sporen",
		{ primary = "#2A2A38", secondary = "#14141E", glow = "#8FE3FF", hair = "#1C1820", accent = "#A7B4C2" },
	},
	{
		"dusty_cactus",
		"dusty",
		"KAKTUSBLÜTE",
		"episch",
		"Kaktusgrün mit pinker Blüte",
		{ primary = "#8CC86A", secondary = "#4A6A3A", glow = "#FF8FB0", accent = "#F2A0B0" },
	},
}

-- Material skins (rewards.gd): the whole fighter in one material. Fit every fighter.
local MATERIAL_LOOKS: { [string]: SkinLook } = {
	gold = { base = "#D4A93C", dark = "#A07A26", glow = "#FFE26A", material = "Foil" },
	silver = { base = "#C8D0DA", dark = "#8A94A0", glow = "#E8F4FF", material = "Metal" },
	marble = { base = "#ECE8E2", dark = "#BEB8B0", glow = "#FFFFFF", material = "Marble" },
	emerald = { base = "#2FB86A", dark = "#1A7A44", glow = "#7DFFB0", material = "Glass" },
	frost = { base = "#BFE6F6", dark = "#7FB8D6", glow = "#E8FAFF", material = "Ice" },
	obsidian = { base = "#22202A", dark = "#121018", glow = "#FF5A1F", material = "Basalt" },
	neon = { base = "#1A1A2E", dark = "#10101E", glow = "#FF28C8", material = "SmoothPlastic", trim = "#00E6FF" },
	shadow = { base = "#2A2240", dark = "#16122A", glow = "#8C6BFF", material = "SmoothPlastic" },
	lava = { base = "#3A1E16", dark = "#24120C", glow = "#FF6A1F", material = "CrackedLava" },
	crystal = { base = "#D8C8FF", dark = "#A08CE0", glow = "#F0E8FF", material = "Glass" },
	ghost = { base = "#DDEBF4", dark = "#A8C0D0", glow = "#B9F7FF", material = "ForceField" },
	galaxy = { base = "#2A1E5C", dark = "#140E34", glow = "#FF8FE8", material = "Foil", trim = "#7FD8FF" },
	celestial = { base = "#FFF4D8", dark = "#E2C066", glow = "#FFF1A8", material = "Foil" },
	infernal = { base = "#5C1A14", dark = "#2A0A08", glow = "#FF3B1F", material = "Basalt", trim = "#FFB23D" },
}

local RARITY_CODES: { [string]: Rarity } = { S = "selten", E = "episch", L = "legendär", P = "ruhmespfad" }

local function materialLook(spec: SkinLook): SkinLook
	local trim = spec.trim or spec.glow
	return {
		skin = spec.base,
		primary = spec.base,
		secondary = spec.dark,
		glow = spec.glow,
		accent = spec.dark,
		trim = trim,
		hair = spec.dark,
		material = spec.material,
		skinMaterial = spec.material,
		gloves = spec.dark,
		boots = spec.dark,
		belt = trim,
		neck = spec.dark,
	}
end

Cosmetics.SKINS = {} :: { Skin }
for _, row in FIGHTER_SKINS do
	table.insert(Cosmetics.SKINS, {
		id = row[1],
		kind = "skin",
		fighter = row[2],
		name = row[3],
		rarity = row[4],
		coins = Cosmetics.SKIN_PRICES[row[4]],
		info = row[5],
		look = row[6],
	})
end
for _, s in RewardData.skins do
	local spec = MATERIAL_LOOKS[s.material]
	if spec then
		local earned = (s :: any).path
		table.insert(Cosmetics.SKINS, {
			id = s.id,
			kind = "skin",
			name = s.name,
			rarity = RARITY_CODES[s.rarity] or "selten",
			coins = if s.price > 0 then s.price else nil,
			source = if earned then `Ruhmespfad Stufe {earned}` else nil,
			info = "Material-Skin, passt auf jeden Kämpfer",
			look = materialLook(spec),
		})
	end
end

Cosmetics.KO_EFFECTS = {
	{
		id = "ko_classic",
		kind = "ko",
		name = "KLASSIK",
		rarity = "standard",
		info = "Der Lichtstrahl quer über die Arena",
		style = "classic",
	},
	{
		id = "ko_confetti",
		kind = "ko",
		name = "KONFETTI-KANONE",
		rarity = "selten",
		coins = 400,
		info = "Bunte Konfetti-Salve statt Funken",
		style = "confetti",
	},
	{
		id = "ko_pixel",
		kind = "ko",
		name = "PIXELZERFALL",
		rarity = "selten",
		coins = 450,
		info = "Der Strahl zerfällt in leuchtende Würfel",
		style = "pixel",
	},
	{
		id = "ko_nova",
		kind = "ko",
		name = "SUPERNOVA",
		rarity = "episch",
		coins = 600,
		info = "Drei Lichtringe und ein Sternenkern",
		style = "nova",
	},
	{
		id = "ko_thunder",
		kind = "ko",
		name = "DONNERKEIL",
		rarity = "episch",
		coins = 650,
		info = "Zickzack-Blitze schlagen ein",
		style = "thunder",
		color = "#FFE44D",
		accent = "#7FD8FF",
	},
	{
		id = "ko_petals",
		kind = "ko",
		name = "BLÜTENSTURM",
		rarity = "episch",
		coins = 700,
		info = "Ein Wirbel aus Blütenblättern",
		style = "petals",
		color = "#FF8FB0",
		accent = "#FFFFFF",
	},
	{
		id = "ko_void",
		kind = "ko",
		name = "SCHWARZES LOCH",
		rarity = "legendär",
		coins = 1000,
		info = "Alles stürzt nach innen, dann knallt es",
		style = "void",
		color = "#B05AFF",
		accent = "#120A1E",
	},
} :: { KoEffect }

Cosmetics.PLATES = {
	{
		id = "plate_neon",
		kind = "plate",
		name = "NEONLÄUFER",
		rarity = "selten",
		coins = 300,
		info = "Pinker Neonrahmen",
		title = "Neonläufer",
		frame = "#FF28C8",
	},
	{
		id = "plate_prompt",
		kind = "plate",
		name = "PROMPT-POET",
		rarity = "selten",
		coins = 500,
		info = "Für Wortkünstler am Terminal",
		title = "Prompt-Poet",
		frame = "#00E6FF",
	},
	{
		id = "plate_combo",
		kind = "plate",
		name = "COMBO-KÜNSTLER",
		rarity = "episch",
		coins = 650,
		info = "Mintgrüner Rahmen",
		title = "Combo-Künstler",
		frame = "#7DF5B4",
	},
	{
		id = "plate_gold",
		kind = "plate",
		name = "GOLDENE FAUST",
		rarity = "legendär",
		coins = 900,
		info = "Goldrahmen für die Lobby",
		title = "Goldene Faust",
		frame = "#FFD24A",
	},
} :: { Plate }

-- Owned by everyone, equipped when nothing else is.
Cosmetics.DEFAULT_KO = "ko_classic"

Cosmetics.byId = {} :: { [string]: Item }
for _, list in { Cosmetics.SKINS, Cosmetics.KO_EFFECTS, Cosmetics.PLATES } :: { any } do
	for _, item in list do
		assert(Cosmetics.byId[item.id] == nil, `duplicate cosmetic id {item.id}`)
		Cosmetics.byId[item.id] = item
	end
end

function Cosmetics.get(id: string): Item?
	return Cosmetics.byId[id]
end

function Cosmetics.skin(id: string): Skin?
	local item = Cosmetics.byId[id]
	return if item and item.kind == "skin" then item :: Skin else nil
end

-- True if the skin can be worn by this fighter (its own skin, or a material skin).
function Cosmetics.fits(skin: Skin, fighterId: string): boolean
	return skin.fighter == nil or skin.fighter == fighterId
end

-- Skins for one fighter: its own first, then the material skins.
function Cosmetics.skinsFor(fighterId: string): { Skin }
	local own, shared = {}, {}
	for _, s in Cosmetics.SKINS do
		if s.fighter == fighterId then
			table.insert(own, s)
		elseif s.fighter == nil then
			table.insert(shared, s)
		end
	end
	for _, s in shared do
		table.insert(own, s)
	end
	return own
end

-- Robux price and product of a skin's direct purchase (nil if the skin is not sold).
function Cosmetics.robux(item: Item): (number?, string?)
	if item.kind ~= "skin" or item.coins == nil then
		return nil, nil
	end
	local coins = item.coins :: number
	return Products.skinRobux(coins), Products.skinProductId(coins)
end

-- Day number (days since 1970, UTC) for the rotation.
function Cosmetics.dayOf(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- The daily "Heute im Fokus" items: a fixed order per day from a hash of the date, the same for every player and
-- server. It only decides which sold items are shown on top; prices and contents never change.
function Cosmetics.featured(day: number, count: number?): { Item }
	local pool: { { item: Item, key: number } } = {}
	for _, list in { Cosmetics.SKINS, Cosmetics.KO_EFFECTS } :: { any } do
		for _, item in list do
			if item.coins then
				table.insert(pool, { item = item, key = Seed.fromText(`{item.id}#{day}`) })
			end
		end
	end
	table.sort(pool, function(a, b)
		if a.key ~= b.key then
			return a.key < b.key
		end
		return a.item.id < b.item.id
	end)
	local out: { Item } = {}
	local want = count or 4
	-- At most one KO effect, so the strip shows mostly skins.
	local ko = 0
	for _, entry in pool do
		if #out >= want then
			break
		end
		if entry.item.kind ~= "ko" or ko == 0 then
			if entry.item.kind == "ko" then
				ko += 1
			end
			table.insert(out, entry.item)
		end
	end
	return out
end

return Cosmetics
