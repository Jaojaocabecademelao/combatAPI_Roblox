local Snapshot = {}
Snapshot.__index = Snapshot

local function cloneSerializable(value, ancestors, limits, depth)
	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "string" then
		return value
	end
	if valueType == "number" then
		assert(value == value and value > -math.huge and value < math.huge,
			"Rollback snapshot contains a non-finite number")
		return value
	end
	assert(valueType == "table", "Rollback snapshot only accepts plain serializable data")
	assert(depth <= limits.MaxDepth, "Rollback snapshot exceeds MaxSnapshotDepth")
	assert(getmetatable(value) == nil, "Rollback snapshot rejects metatable-backed data")
	assert(not ancestors[value], "Rollback snapshot rejects cyclic data")
	ancestors[value] = true
	local copy = {}
	for key, child in pairs(value) do
		limits.Entries += 1
		assert(limits.Entries <= limits.MaxEntries, "Rollback snapshot exceeds MaxSnapshotEntries")
		assert(type(key) == "string" or (type(key) == "number"
			and key == key and key > -math.huge and key < math.huge),
			"Rollback snapshot keys must be strings or finite numbers")
		copy[key] = cloneSerializable(child, ancestors, limits, depth + 1)
	end
	ancestors[value] = nil
	return copy
end

local function makeLimits(options)
	options = options or {}
	return {
		Entries = 0,
		MaxEntries = options.MaxSnapshotEntries or 100000,
		MaxDepth = options.MaxSnapshotDepth or 64,
	}
end

function Snapshot.CloneSerializable(value, options)
	return cloneSerializable(value, {}, makeLimits(options), 0)
end

function Snapshot.new(data, options)
	assert(type(data) == "table" and type(data.Frame) == "number"
		and data.Frame >= 0 and data.Frame < math.huge and data.Frame % 1 == 0,
		"RollbackSnapshot frame is invalid")
	assert(type(data.Entities) == "table" and type(data.Simulation) == "table"
		and type(data.InputFrames) == "table", "RollbackSnapshot data is incomplete")
	assert(data.Simulation.Frame == data.Frame and data.Simulation.RNGState ~= nil,
		"RollbackSnapshot Simulation frame or RNG state is invalid")
	assert(data.Simulation.Accumulator == nil
		or (type(data.Simulation.Accumulator) == "number"
			and data.Simulation.Accumulator == data.Simulation.Accumulator
			and data.Simulation.Accumulator >= 0 and data.Simulation.Accumulator < math.huge),
		"RollbackSnapshot accumulator is invalid")
	assert(data.Confirmed == nil or type(data.Confirmed) == "boolean",
		"RollbackSnapshot Confirmed flag must be boolean")
	local copied = cloneSerializable(data, {}, makeLimits(options), 0)
	return setmetatable({
		Frame = copied.Frame,
		Entities = copied.Entities,
		Simulation = copied.Simulation,
		InputFrames = copied.InputFrames,
		Confirmed = copied.Confirmed == true,
		CombatState = copied.CombatState,
	}, Snapshot)
end

return Snapshot
