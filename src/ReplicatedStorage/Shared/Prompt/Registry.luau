--!strict
-- Makes prompt fighters usable everywhere a roster fighter id is: registers the interpreter's result under its
-- id ("prompt_<CODE>") in Data/Fighters, Data/Looks and the generated preset and signature tables that
-- Combat/Moveset and Combat/Simulation read by id. Requiring this module also installs a resolver in
-- Fighters.get, so any id of the form prompt_<CODE> is rebuilt on first use from the code alone. That is how
-- clients get the full definition (look included) of another player's prompt fighter: the server only ever
-- sends the id, and the build is deterministic.

local Interpreter = require(script.Parent.Interpreter)
local Fighters = require(script.Parent.Parent.Data.Fighters)
local Looks = require(script.Parent.Parent.Data.Looks)
local Presets = require(script.Parent.Parent.Data.Generated.FighterPresets)
local SignatureParams = require(script.Parent.Parent.Data.Generated.SignatureParams)

local Registry = {}

local results: { [string]: Interpreter.Result } = {}

function Registry.register(result: Interpreter.Result): Interpreter.Result
	local known = results[result.id]
	if known then
		return known
	end
	results[result.id] = result
	Fighters.byId[result.id] = result.fighter
	Looks.BY_ID[result.id] = result.look;
	(Presets :: any)[result.id] = result.preset;
	(SignatureParams :: any)[result.id] = result.signatureParams
	return result
end

-- Interprets (already filtered) prompt text and registers the fighter.
function Registry.fromText(text: string): Interpreter.Result
	return Registry.register(Interpreter.fromText(text))
end

-- Rebuilds and registers the fighter behind a code, or nil for an invalid code.
function Registry.fromCode(code: string): Interpreter.Result?
	local result = Interpreter.fromCode(code)
	return if result then Registry.register(result) else nil
end

-- The registered result for a prompt fighter id (built on demand), or nil for other ids.
function Registry.get(id: string): Interpreter.Result?
	local known = results[id]
	if known then
		return known
	end
	local code = Interpreter.codeOf(id)
	return if code then Registry.fromCode(code) else nil
end

Registry.isPromptId = Interpreter.isPromptId

Fighters.resolver = function(id: string): Fighters.Fighter?
	local result = Registry.get(id)
	return if result then result.fighter else nil
end

return Registry
