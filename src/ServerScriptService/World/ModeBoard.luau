--!strict
-- Mode vote and Daily-Challenge board in the lobby's north-east corner, next to the arena vote (kept out of
-- LobbyBuilder so the lobby file stays untouched): three small pads SCHNELLKAMPF / BOSS-RAID / TAGES-CHALLENGE
-- (standing on one votes for the mode, like the arena pads), a sign with the next raid boss and a board with
-- today's challenge. Built as its own model inside the lobby model; the server changes the texts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Visuals = require(ReplicatedStorage.Shared.Data.Visuals)
local Decor = require(script.Parent.Decor)

local ModeBoard = {}

ModeBoard.MODES = { "quick", "raid", "daily" }
ModeBoard.NAMES = { quick = "SCHNELLKAMPF", raid = "BOSS-RAID", daily = "TAGES-CHALLENGE" }
ModeBoard.PAD_RADIUS = 4.6

local ORIGIN = Visuals.LOBBY_ORIGIN
local PAD_Z = -73
local PAD_X = { 50, 62, 74 }
local COLORS = {
	quick = Color3.fromRGB(0, 240, 255),
	raid = Color3.fromRGB(255, 80, 60),
	daily = Color3.fromRGB(255, 210, 60),
}
local INK = Color3.fromRGB(8, 6, 16)
local STEEL = Color3.fromRGB(40, 36, 60)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 210, 60)

type Pad = { part: BasePart, ring: BasePart, votes: TextLabel, mode: string }

local pads: { Pad } = {}
local bossName: TextLabel? = nil
local bossTitle: TextLabel? = nil
local challengeLines: { TextLabel } = {}
local model: Model? = nil

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Unrotated: the Back face looks toward +Z (the spawn side of the plaza), so texts go on Back.
local function south(position: Vector3): CFrame
	return CFrame.new(position)
end

local function disc(
	parent: Instance,
	name: string,
	radius: number,
	height: number,
	center: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Decor.part(
		parent,
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		Enum.PartType.Cylinder
	)
	return p
end

local function board(parent: Instance, name: string, size: Vector3, center: Vector3, frame: Color3): Part
	local b = Decor.part(parent, name, size, south(center), INK)
	Decor.part(
		parent,
		name .. "Frame",
		size + Vector3.new(0.8, 0.8, -size.Z + 0.2),
		south(center) * CFrame.new(0, 0, -size.Z / 2 - 0.15),
		frame,
		Enum.Material.Neon
	)
	return b
end

function ModeBoard.build(parent: Instance?): Model
	local old = if parent then parent:FindFirstChild("ModeBoard") else nil
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "ModeBoard"
	table.clear(pads)
	table.clear(challengeLines)

	-- Header sign over the pads.
	local header = board(m, "ModeHeader", Vector3.new(34, 5, 0.5), at(62, 15, PAD_Z - 9), GOLD)
	Decor.text(header, Enum.NormalId.Back, "MODUS-WAHL", GOLD, 10, { 0.03, 0.08, 0.94, 0.84 })
	for _, x in { 46, 78 } do
		local pole =
			Decor.part(m, "ModePole", Vector3.new(0.8, 15, 0.8), at(x, 7.5, PAD_Z - 9), STEEL, Enum.Material.Metal)
		pole.CanCollide = true
	end

	for k, mode in ModeBoard.MODES do
		local color = COLORS[mode]
		local center = at(PAD_X[k], 0.3, PAD_Z)
		local pad =
			disc(m, "ModePad" .. k, ModeBoard.PAD_RADIUS, 0.6, center, Color3.fromRGB(40, 34, 70), Enum.Material.Glass)
		pad.CanCollide = true
		local ring = disc(
			m,
			"ModeRing" .. k,
			ModeBoard.PAD_RADIUS + 0.5,
			0.5,
			center - Vector3.new(0, 0.1, 0),
			color,
			Enum.Material.Neon
		)
		Decor.light(ring, color, 14, 1)
		local sign = board(m, "ModeSign" .. k, Vector3.new(10, 4.4, 0.4), center + Vector3.new(0, 7.5, -3.5), color)
		Decor.text(sign, Enum.NormalId.Back, ModeBoard.NAMES[mode], color, 14, { 0.03, 0.06, 0.94, 0.5 })
		local votes = Decor.text(sign, Enum.NormalId.Back, "0 STIMMEN", WHITE, 14, { 0.1, 0.6, 0.8, 0.32 })
		for _, side in { -1, 1 } do
			local pole = Decor.part(
				m,
				"ModeSignPole",
				Vector3.new(0.5, 6, 0.5),
				center + Vector3.new(side * 4.4, 3, -3.7),
				STEEL,
				Enum.Material.Metal
			)
			pole.CanCollide = true
		end
		pads[k] = { part = pad, ring = ring, votes = votes, mode = mode }
	end

	-- Next raid boss, above the raid pad's sign.
	local bossSign = board(m, "RaidBossSign", Vector3.new(12, 3.2, 0.4), at(PAD_X[2], 21.5, PAD_Z - 9), COLORS.raid)
	bossName = Decor.text(bossSign, Enum.NormalId.Back, "", COLORS.raid, 14, { 0.03, 0.04, 0.94, 0.56 })
	bossTitle = Decor.text(bossSign, Enum.NormalId.Back, "", WHITE, 14, { 0.03, 0.62, 0.94, 0.32 })

	-- Daily-Challenge board on the west side of the corner, facing the plaza.
	local daily = board(m, "DailyBoard", Vector3.new(20, 13, 0.5), at(62, 8.5, -86), COLORS.daily)
	Decor.text(daily, Enum.NormalId.Back, "TAGES-CHALLENGE", COLORS.daily, 12, { 0.04, 0.03, 0.92, 0.14 })
	local rows = 6
	for i = 1, rows do
		local y = 0.2 + (i - 1) * 0.13
		local label = Decor.text(daily, Enum.NormalId.Back, "", WHITE, 12, { 0.05, y, 0.9, 0.11 })
		label.TextXAlignment = Enum.TextXAlignment.Left
		challengeLines[i] = label
	end
	for _, x in { 53, 71 } do
		local leg = Decor.part(m, "DailyLeg", Vector3.new(1, 2.2, 1), at(x, 1.1, -86), STEEL, Enum.Material.Metal)
		leg.CanCollide = true
	end

	Decor.finalize(m, {
		solid = function(p)
			return p.CanCollide
		end,
		shadowMin = 2.5,
	})
	m.Parent = parent or workspace
	model = m
	return m
end

-- Which mode pad (1..3) a world position stands on, or nil.
function ModeBoard.padAt(position: Vector3): number?
	for k, pad in pads do
		local center = Decor.where(pad.part)
		local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
		if flat.Magnitude <= ModeBoard.PAD_RADIUS and math.abs(position.Y - center.Y) < 8 then
			return k
		end
	end
	return nil
end

-- Votes per mode (same order as MODES); the leading mode's ring turns gold.
function ModeBoard.setVotes(totals: { number }, leading: number?)
	for k, pad in pads do
		local votes = totals[k] or 0
		pad.votes.Text = if votes == 1 then "1 STIMME" else `{votes} STIMMEN`
		pad.ring.Color = if leading == k then GOLD else COLORS[pad.mode]
	end
end

function ModeBoard.setBoss(name: string, title: string)
	if bossName then
		bossName.Text = `NÄCHSTER BOSS: {name}`
	end
	if bossTitle then
		bossTitle.Text = title
	end
end

-- `info` is DailyChallenge.describe(...).
function ModeBoard.setChallenge(info: { [string]: any })
	local mutators = {}
	for _, m in info.mutators do
		table.insert(mutators, `{m.icon} {m.name}`)
	end
	local lines = {
		`ZIEL: {info.goalText}`,
		`KÄMPFER: {info.fighterName}`,
		`GEGNER: {table.concat(info.opponents, ", ")} (KI {info.botLevel})`,
		`MUTATOREN: {table.concat(mutators, " + ")}`,
		`ARENA: {info.arenaName}`,
		`BELOHNUNG: {info.rewards[1]}–{info.rewards[#info.rewards]} MÜNZEN (SERIE)`,
	}
	for i, label in challengeLines do
		label.Text = lines[i] or ""
	end
end

function ModeBoard.model(): Model?
	return model
end

return ModeBoard
