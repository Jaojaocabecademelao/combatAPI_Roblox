local HitPolicy = require(script.Parent.HitPolicy)
local OffensiveProperties = require(script.Parent.OffensiveProperties)

local Attack = {}
Attack.__index = Attack

-- Attack is reusable definition data; each execution gets a separate AttackInstance.

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function Attack.new(options)
	if options == nil then
		options = {}
	end
	assert(type(options) == "table", "Attack.new() expects an options table")
	local id = options.Id
	if id == nil then
		id = "Attack"
	end
	assert((type(id) == "string" and id ~= "")
		or (isFiniteNumber(id) and id % 1 == 0), "Attack.new() requires a stable string or integer Id")

	local priority = options.Priority
	if priority == nil then
		priority = 0
	end
	assert(isFiniteNumber(priority), "Attack Priority must be a finite number")

	local policy = options.HitPolicy or HitPolicy.Once
	HitPolicy.Validate(policy)
	local scope = options.HitScope or HitPolicy.Scope.AttackInstance
	HitPolicy.ValidateScope(scope)
	assert(options.CanHit == nil or type(options.CanHit) == "function",
		"Attack CanHit must be a function or nil")
	local properties = OffensiveProperties.new({
		Damage = options.Damage,
		Hitstun = options.Hitstun,
		HasHitstun = options.Hitstun ~= nil,
		Defense = options.Defense,
		CanBlock = options.CanBlock,
		CanParry = options.CanParry,
		Priority = priority,
		CanClash = options.CanClash,
			CustomData = options.CustomData,
	})
	local attack = setmetatable({
		Id = id,
		HitPolicy = policy,
		HitScope = scope,
		OffensiveProperties = properties,
		Priority = properties.Priority,
		CanClash = properties.CanClash,
		CustomData = properties.CustomData,
		Damage = properties.Damage,
		Hitstun = properties.Hitstun,
		Defense = properties.Defense,
		CanHit = options.CanHit,
	}, Attack)
	return table.freeze(attack)
end

return Attack
