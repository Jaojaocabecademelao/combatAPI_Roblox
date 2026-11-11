local ArmorCategory = require(script.Parent.ArmorCategory)

local ArmorProfile = {}
ArmorProfile.__index = ArmorProfile

local function finite(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local superArmorDefaults = {
	Damage = true,
	Hitstun = false,
	Knockback = false,
	Launch = false,
	Push = false,
	Pull = false,
}

function ArmorProfile.new(options)
	options = options or {}
	assert(type(options) == "table", "ArmorProfile.new() expects an options table")
	local kind = options.Kind or "Armor"
	assert(kind == "Armor" or kind == "SuperArmor", "ArmorProfile Kind must be Armor or SuperArmor")
	local id = options.Id or options.Name or "ArmorProfile"
	assert(type(id) == "string" or (finite(id) and id % 1 == 0), "ArmorProfile Id must be a string or integer")
	local consequences = options.Consequences or {}
	assert(type(consequences) == "table", "ArmorProfile Consequences must be a table")
	local normalized = {}
	if kind == "SuperArmor" then
		for category, allowed in pairs(superArmorDefaults) do normalized[category] = allowed end
	end
	for category, allowed in pairs(consequences) do
		assert(type(category) == "string" and category ~= "", "Armor category must be a non-empty string")
		assert(type(allowed) == "boolean", "Armor consequences must be true (allowed) or false (blocked)")
		normalized[category] = allowed
	end
	if options.Damage ~= nil then
		assert(type(options.Damage) == "boolean", "Armor Damage must be a boolean")
		normalized[ArmorCategory.Damage] = options.Damage
	end
	for _, allowed in pairs(normalized) do assert(type(allowed) == "boolean") end
	local duration = options.DurationFrames
	if options.Permanent == true then
		duration = nil
	elseif duration ~= nil then
		assert(finite(duration) and duration > 0 and duration % 1 == 0,
			"Armor DurationFrames must be a positive integer or nil for permanent armor")
	end
	local priority = options.Priority
	if priority == nil then priority = 0 end
	assert(finite(priority), "Armor Priority must be finite")
	assert(options.Condition == nil or type(options.Condition) == "function",
		"Armor Condition must be a deterministic predicate or nil")
	return setmetatable({
		Id = id,
		Name = options.Name or tostring(id),
		Kind = kind,
		Consequences = table.freeze(normalized),
		DurationFrames = duration,
		Priority = priority,
		Source = options.Source,
		Condition = options.Condition,
	}, ArmorProfile)
end

function ArmorProfile.SuperArmor(options)
	options = options or {}
	local copy = {}
	for key, value in pairs(options) do copy[key] = value end
	copy.Kind = "SuperArmor"
	return ArmorProfile.new(copy)
end

function ArmorProfile:Allows(category)
	local value = self.Consequences[category]
	return value ~= false
end

return ArmorProfile
