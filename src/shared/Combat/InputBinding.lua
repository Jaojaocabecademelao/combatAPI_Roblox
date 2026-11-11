local Input = require(script.Parent.Input)
local Binding = {}
Binding.__index = Binding
function Binding.new(externalId, combatInput)
	assert(type(externalId) == "string" and externalId ~= "", "InputBinding ExternalId is required")
	assert(type(combatInput) == "string" and combatInput ~= "", "InputBinding CombatInput is required")
	return setmetatable({ ExternalId = externalId, CombatInput = combatInput }, Binding)
end
return Binding
