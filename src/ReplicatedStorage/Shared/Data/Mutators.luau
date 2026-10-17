--!strict
-- Mutators (imported from Godot) with the Roblox-specific changes:
--  * "vampire" is shown as ENERGIEDURST (no blood wording, keeps the Mild maturity label).
--  * RIESEN and WINZLINGE never run together.

local MutatorData = require(script.Parent.Generated.MutatorData)

local Mutators = {}
Mutators.byId = table.clone(MutatorData) :: { [string]: any }

local vampire = table.clone(Mutators.byId.vampire)
vampire.name = "ENERGIEDURST"
vampire.icon = "⚡"
vampire.text = "Wer trifft, lädt 40 % des ausgeteilten Schadens als Energie zurück."
Mutators.byId.vampire = vampire

Mutators.EXCLUSIVE = { { "giants", "tiny" } }

function Mutators.compatible(ids: { string }): boolean
	local set = {}
	for _, id in ids do
		if not Mutators.byId[id] then
			return false
		end
		set[id] = true
	end
	for _, pair in Mutators.EXCLUSIVE do
		if set[pair[1]] and set[pair[2]] then
			return false
		end
	end
	return true
end

return Mutators
