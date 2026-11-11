local StateSerializer = {}

local DEFAULT_MAX_ENTRIES = 100000
local DEFAULT_MAX_DEPTH = 64

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function keyLess(left, right)
	local leftType, rightType = type(left), type(right)
	if leftType ~= rightType then
		return leftType == "number"
	end
	return left < right
end

local function makeLimits(options)
	options = options or {}
	assert(type(options) == "table", "StateSerializer options must be a table")
	local maxEntries = options.MaxEntries or DEFAULT_MAX_ENTRIES
	local maxDepth = options.MaxDepth or DEFAULT_MAX_DEPTH
	assert(type(maxEntries) == "number" and maxEntries >= 1 and maxEntries % 1 == 0,
		"StateSerializer MaxEntries must be a positive integer")
	assert(type(maxDepth) == "number" and maxDepth >= 1 and maxDepth % 1 == 0,
		"StateSerializer MaxDepth must be a positive integer")
	return { Entries = 0, MaxEntries = maxEntries, MaxDepth = maxDepth }
end

local function countEntry(limits, depth)
	limits.Entries += 1
	assert(limits.Entries <= limits.MaxEntries, "StateSerializer exceeded MaxEntries")
	assert(depth <= limits.MaxDepth, "StateSerializer exceeded MaxDepth")
end

local function cloneValue(value, ancestors, limits, depth)
	countEntry(limits, depth)
	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "string" then
		return value
	end
	if valueType == "number" then
		assert(isFiniteNumber(value), "StateSerializer rejects non-finite numbers")
		return value
	end
	assert(valueType == "table", "StateSerializer accepts only plain serializable values")
	assert(getmetatable(value) == nil, "StateSerializer rejects metatable-backed tables")
	assert(not ancestors[value], "StateSerializer rejects cyclic tables")
	ancestors[value] = true
	local copy = {}
	for key, child in pairs(value) do
		local keyType = type(key)
		assert(keyType == "string" or (keyType == "number" and isFiniteNumber(key)),
			"StateSerializer table keys must be strings or finite numbers")
		copy[key] = cloneValue(child, ancestors, limits, depth + 1)
	end
	ancestors[value] = nil
	return copy
end

local function serializeValue(value, ancestors, limits, depth, output)
	countEntry(limits, depth)
	local valueType = type(value)
	if valueType == "nil" then
		table.insert(output, "n;")
	elseif valueType == "boolean" then
		table.insert(output, value and "b1;" or "b0;")
	elseif valueType == "number" then
		assert(isFiniteNumber(value), "StateSerializer rejects non-finite numbers")
		if value == 0 then value = 0 end
		local numberText = string.format("%.17g", value)
		table.insert(output, "d" .. #numberText .. ":" .. numberText .. ";")
	elseif valueType == "string" then
		table.insert(output, "s" .. #value .. ":" .. value .. ";")
	else
		assert(valueType == "table", "StateSerializer accepts only plain serializable values")
		assert(getmetatable(value) == nil, "StateSerializer rejects metatable-backed tables")
		assert(not ancestors[value], "StateSerializer rejects cyclic tables")
		ancestors[value] = true
		local keys = {}
		for key in pairs(value) do
			local keyType = type(key)
			assert(keyType == "string" or (keyType == "number" and isFiniteNumber(key)),
				"StateSerializer table keys must be strings or finite numbers")
			table.insert(keys, key)
		end
		table.sort(keys, keyLess)
		table.insert(output, "t" .. #keys .. "{")
		for _, key in ipairs(keys) do
			serializeValue(key, ancestors, limits, depth + 1, output)
			serializeValue(value[key], ancestors, limits, depth + 1, output)
		end
		table.insert(output, "}")
		ancestors[value] = nil
	end
end

local function freezeValue(value)
	if type(value) ~= "table" then return value end
	assert(type(table.freeze) == "function", "StateSerializer requires table.freeze() in this runtime")
	for _, child in pairs(value) do freezeValue(child) end
	return table.freeze(value)
end

function StateSerializer.CloneSerializable(value, options)
	return cloneValue(value, {}, makeLimits(options), 0)
end

function StateSerializer.Serialize(value, options)
	local output = {}
	serializeValue(value, {}, makeLimits(options), 0, output)
	return table.concat(output)
end

function StateSerializer.Freeze(value)
	return freezeValue(value)
end

function StateSerializer.IsFiniteNumber(value)
	return isFiniteNumber(value)
end

return table.freeze(StateSerializer)
