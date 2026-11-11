local Snapshot = {}
Snapshot.__index = Snapshot

local MAX_DEPTH = 32
local MAX_ENTRIES = 10000

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function cloneData(value, seen, budget, depth)
	local valueType = type(value)
	if value == nil or valueType == "boolean" or valueType == "string" then return value end
	if valueType == "number" then
		assert(finite(value), "AuthoritySnapshot contains a non-finite number")
		return value
	end
	assert(valueType == "table" and getmetatable(value) == nil,
		"AuthoritySnapshot contains non-data values")
	assert(depth < MAX_DEPTH, "AuthoritySnapshot nesting limit exceeded")
	assert(not seen[value], "AuthoritySnapshot contains a cycle")
	seen[value] = true
	local copy = {}
	for key, item in pairs(value) do
		budget.Count += 1
		assert(budget.Count <= MAX_ENTRIES, "AuthoritySnapshot entry limit exceeded")
		assert(type(key) == "string" or (type(key) == "number" and finite(key)),
			"AuthoritySnapshot key is not serializable")
		copy[key] = cloneData(item, seen, budget, depth + 1)
	end
	seen[value] = nil
	return copy
end

function Snapshot.new(data)
	assert(type(data) == "table", "AuthoritySnapshot.new() expects a table")
	local frame = data.SimulationFrame
	assert(finite(frame) and frame >= 0 and frame % 1 == 0,
		"AuthoritySnapshot SimulationFrame is invalid")
	assert(type(data.Entities) == "table", "AuthoritySnapshot Entities are required")
	assert(data.Complete == nil or type(data.Complete) == "boolean",
		"AuthoritySnapshot Complete must be boolean")
	local budget = { Count = 0 }
	local entities = cloneData(data.Entities, {}, budget, 0)
	local components = cloneData(data.Components or {}, {}, budget, 0)
	local rngState = cloneData(data.RNGState, {}, budget, 0)
	return setmetatable({
		SimulationFrame = frame,
		Entities = entities,
		Components = components,
		RNGState = rngState,
		NetworkSequence = data.NetworkSequence,
		Complete = data.Complete == true,
	}, Snapshot)
end

return Snapshot
