--!strict
-- Prompt fighters on the server. A player sends a description (SubmitPrompt) or a share code (LoadPromptCode).
-- Text: Guard (types, 120 characters, rate limit) -> TextService filter (FilterStringAsync +
-- GetNonChatStringForBroadcastAsync, pcall; failure = polite refusal) -> a filtered text with "#" (the filter
-- hid something) is refused -> only the FILTERED text goes to Prompt/Interpreter. The raw text is never stored,
-- shown or logged. The fighter is registered under "prompt_<CODE>"; the player may pick it (MatchService asks
-- PromptService.allows) and its code joins the last three in the saved profile. Clients rebuild the fighter from
-- the id alone (Prompt/Registry), so nothing but the id ever crosses the network to other players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Interpreter = require(ReplicatedStorage.Shared.Prompt.Interpreter)
local Registry = require(ReplicatedStorage.Shared.Prompt.Registry)
local Profile = require(ReplicatedStorage.Shared.Meta.Profile)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)
local RemoteHub = require(script.Parent.Parent.Net.RemoteHub)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)

local PromptService = {}
-- Name of the ProximityPrompt on the lobby's terminal anchor; the client opens the terminal UI when it fires.
PromptService.PROXIMITY_NAME = "OpenPromptTerminal"

-- Prompt fighter ids each player made or loaded this session (the saved list covers earlier sessions).
local allowed: { [number]: { [string]: boolean } } = {}

local TOO_FAST = { ok = false, message = "Kurz warten, dann nochmal" }

local function remember(player: Player, result: Interpreter.Result)
	local set = allowed[player.UserId]
	if set == nil then
		set = {}
		allowed[player.UserId] = set
	end
	set[result.id] = true
	PlayerData.update(player, function(profile)
		Profile.addPromptFighter(profile, result.code)
	end)
end

-- May this player play this prompt fighter? (Made or loaded it this session, or it is in their saved list.)
function PromptService.allows(player: Player, fighterId: string): boolean
	local code = Interpreter.codeOf(fighterId)
	if code == nil then
		return false
	end
	local set = allowed[player.UserId]
	if set and set[fighterId] then
		return true
	end
	local profile = PlayerData.get(player)
	if profile and table.find(profile.promptFighters, code :: string) and Registry.get(fighterId) then
		return true
	end
	return false
end

-- Filters text the player typed for display to everyone. Returns nil when the filter could not run.
local function filter(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	warn(`[PromptService] text filter failed for {player.UserId}`)
	return nil
end

local function submit(player: Player, raw: string): { [string]: any }
	local text = Interpreter.clean(raw)
	if text == "" then
		return { ok = false, message = "Beschreibe zuerst deinen Kämpfer" }
	end
	if (utf8.len(text) or math.huge) > Interpreter.MAX_CHARS then
		return { ok = false, message = `Höchstens {Interpreter.MAX_CHARS} Zeichen` }
	end
	-- Only printable text: no control characters (newlines, escape codes).
	if string.find(text, "[%c]") then
		return { ok = false, message = "Text nicht erlaubt" }
	end
	local filtered = filter(player, text)
	if filtered == nil then
		return { ok = false, message = "Der Textfilter ist gerade nicht erreichbar. Versuch es gleich nochmal." }
	end
	local safe = filtered :: string
	if string.find(safe, "#", 1, true) then
		return { ok = false, message = "Text nicht erlaubt" }
	end
	local result = Registry.fromText(safe)
	remember(player, result)
	-- The newest creation stands on the lobby showcase for everyone (only its id is used, never the text).
	pcall(LobbyBuilder.setFeatured, result.id)
	return { ok = true, fighter = result.summary, prompt = safe }
end

local function loadCode(player: Player, input: string): { [string]: any }
	local found = Registry.fromCode(input)
	if found == nil then
		return { ok = false, message = "Code ungültig" }
	end
	local result = found :: Interpreter.Result
	remember(player, result)
	return { ok = true, fighter = result.summary }
end

-- A ProximityPrompt on the lobby terminal (LobbyBuilder's "PromptTerminal" anchor) that opens the prompt UI.
local function addProximityPrompt()
	local found = LobbyBuilder.terminal()
	if found == nil then
		return
	end
	local anchor = found :: BasePart
	local parent: Instance = anchor:FindFirstChild("PromptAttachment") or anchor
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PromptService.PROXIMITY_NAME
	prompt.ActionText = "Kämpfer erschaffen"
	prompt.ObjectText = "Prompt-Terminal"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
end

function PromptService.start()
	addProximityPrompt()
	RemoteHub.handle("SubmitPrompt", submit, TOO_FAST)
	RemoteHub.handle("LoadPromptCode", loadCode, TOO_FAST)
	Players.PlayerRemoving:Connect(function(player)
		allowed[player.UserId] = nil
	end)
end

return PromptService
