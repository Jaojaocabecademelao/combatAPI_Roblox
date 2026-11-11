local JuggleProfile = {}
JuggleProfile.__index = JuggleProfile

function JuggleProfile.new(options)
	options = options or {}
	assert(type(options) == "table", "JuggleProfile.new() expects a table")
	local function integer(name, default, minimum)
		local value = options[name]
		if value == nil then value = default end
		assert(type(value) == "number" and value == value and value < math.huge
			and value >= minimum and value % 1 == 0, name .. " must be a finite integer")
		return value
	end
	return setmetatable({
		MaxJuggleHits = integer("MaxJuggleHits", 5, 1),
		JuggleWindowFrames = integer("JuggleWindowFrames", 60, 0),
		ReJuggleLimit = integer("ReJuggleLimit", 1, 0),
		RecoveryFrames = integer("RecoveryFrames", 20, 0),
	}, JuggleProfile)
end

return JuggleProfile
