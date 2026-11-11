local Damage = {}
Damage.__index = Damage

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function Damage.new(options)
	assert(type(options) == "table", "Damage.new() expects an options table")
	assert(isFiniteNumber(options.Amount) and options.Amount >= 0,
		"Damage Amount must be a finite non-negative number")
	local damageType = options.Type
	if damageType == nil then
		damageType = "Normal"
	end
	assert(type(damageType) == "string" and damageType ~= "",
		"Damage Type must be a non-empty string")

	local damage = {
		Amount = options.Amount,
		Type = damageType,
	}
	return setmetatable(damage, Damage)
end

return Damage
