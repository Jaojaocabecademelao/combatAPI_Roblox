local Damage = require(script.Parent.Damage)
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local OffensiveProperties = {}

local function isFiniteNumber(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function freeze(value)
	if not table.isfrozen(value) then
		table.freeze(value)
	end
	return value
end

local CUSTOM_DATA_LIMITS = table.freeze({ MaxEntries = 256, MaxDepth = 8 })

local function normalizeCustomData(value, label)
	if value == nil then return nil end
	assert(type(value) == "table" and getmetatable(value) == nil,
		label .. " must be a plain table or nil")
	local ok, clone = pcall(Serializer.CloneSerializable, value, CUSTOM_DATA_LIMITS)
	assert(ok, label .. " must be plain serializable data: " .. tostring(clone))
	if next(clone) == nil then return nil end
	return Serializer.Freeze(clone)
end

-- Fonte unica dos limites e da normalizacao; AttackInstance, AttackCatalog e CollisionWorld reutilizam.
OffensiveProperties.CustomDataLimits = CUSTOM_DATA_LIMITS
OffensiveProperties.NormalizeCustomData = normalizeCustomData

-- Serializer.Serialize conta chaves e valores, enquanto CloneSerializable conta so valores. Um dado ja
-- validado com N valores tem no maximo N - 1 chaves, ou seja, ate 2N - 1 entradas ao serializar.
local CUSTOM_DATA_CANONICAL_LIMITS = table.freeze({
	MaxEntries = CUSTOM_DATA_LIMITS.MaxEntries * 2,
	MaxDepth = CUSTOM_DATA_LIMITS.MaxDepth,
})

function OffensiveProperties.CanonicalizeCustomData(customData)
	if customData == nil then return nil end
	return Serializer.Serialize(customData, CUSTOM_DATA_CANONICAL_LIMITS)
end

local function normalizeDamage(value)
	if value == nil then
		return nil
	elseif type(value) == "number" then
		return freeze(Damage.new({ Amount = value }))
	end

	assert(type(value) == "table" and isFiniteNumber(value.Amount) and value.Amount >= 0,
		"OffensiveProperties Damage must be a non-negative finite number or Damage value")
	if getmetatable(value) == Damage then
		assert(type(value.Type) == "string" and value.Type ~= "",
			"OffensiveProperties Damage Type must be a non-empty string")
		return freeze(value)
	end
	return freeze(Damage.new({ Amount = value.Amount, Type = value.Type }))
end

function OffensiveProperties.new(options)
	if options == nil then
		options = {}
	end
	assert(type(options) == "table", "OffensiveProperties.new() expects an options table or nil")

	local hitstun = options.Hitstun
	if hitstun == nil then
		hitstun = 0
	end
	assert(isFiniteNumber(hitstun) and hitstun >= 0 and hitstun % 1 == 0,
		"OffensiveProperties Hitstun must be a non-negative finite integer")
	local priority = options.Priority
	if priority == nil then
		priority = 0
	end
	assert(isFiniteNumber(priority), "OffensiveProperties Priority must be finite")
	local canClash = options.CanClash
	if canClash == nil then
		canClash = true
	end
	assert(type(canClash) == "boolean", "OffensiveProperties CanClash must be a boolean")

	local defenseOptions = options.Defense
	if defenseOptions == nil then
		defenseOptions = {}
	end
	assert(type(defenseOptions) == "table", "OffensiveProperties Defense must be a table")
	local canBlock = defenseOptions.CanBlock
	if canBlock == nil then
		canBlock = options.CanBlock
	end
	if canBlock == nil then
		canBlock = true
	end
	local canParry = defenseOptions.CanParry
	if canParry == nil then
		canParry = options.CanParry
	end
	if canParry == nil then
		canParry = true
	end
	assert(type(canBlock) == "boolean", "OffensiveProperties CanBlock must be a boolean")
	assert(type(canParry) == "boolean", "OffensiveProperties CanParry must be a boolean")

	local defense = freeze({ CanBlock = canBlock, CanParry = canParry })
	local hasHitstun = options.HasHitstun
	if hasHitstun == nil then
		hasHitstun = options.Hitstun ~= nil
	end
	assert(type(hasHitstun) == "boolean", "OffensiveProperties HasHitstun must be a boolean")

	return freeze({
		Damage = normalizeDamage(options.Damage),
		CustomData = normalizeCustomData(options.CustomData, "OffensiveProperties CustomData"),
		Hitstun = hitstun,
		HitstunFrames = hitstun,
		HasHitstun = hasHitstun,
		Defense = defense,
		Priority = priority,
		CanClash = canClash,
	})
end

function OffensiveProperties.WithCustomData(properties, customData)
	assert(type(properties) == "table", "WithCustomData expects OffensiveProperties")
	assert(customData == nil or (type(customData) == "table" and table.isfrozen(customData)),
		"WithCustomData expects nil or frozen CustomData table")
	local derived = table.clone(properties)
	derived.CustomData = customData
	return table.freeze(derived)
end

return OffensiveProperties
