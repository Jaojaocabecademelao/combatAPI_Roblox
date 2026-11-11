local StateSerializer = require(script.Parent.StateSerializer)

local StateHasher = {}
local MODULUS = 2147483647
local MULTIPLIER = 65599

function StateHasher.Hash(value, options)
	local canonical = StateSerializer.Serialize(value, options)
	local hash = 7
	for index = 1, #canonical do
		hash = (hash * MULTIPLIER + string.byte(canonical, index)) % MODULUS
	end
	return "state-v1:" .. string.format("%010d", hash)
end

function StateHasher.HashString(canonicalString)
	assert(type(canonicalString) == "string", "StateHasher.HashString() expects a string")
	local hash = 7
	for index = 1, #canonicalString do
		hash = (hash * MULTIPLIER + string.byte(canonicalString, index)) % MODULUS
	end
	return "state-v1:" .. string.format("%010d", hash)
end

return table.freeze(StateHasher)
