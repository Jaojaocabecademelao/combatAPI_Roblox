local DamageRequest = {}
DamageRequest.__index = DamageRequest

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function DamageRequest.new(options)
	assert(type(options) == "table", "DamageRequest.new() expects an options table")
	assert(isFiniteNumber(options.Amount) and options.Amount >= 0,
		"DamageRequest Amount must be a finite non-negative number")
	assert(options.Target ~= nil, "DamageRequest.new() requires a Target")
	local damageType = options.Type or "Physical"
	assert(type(damageType) == "string" and damageType ~= "",
		"DamageRequest Type must be a non-empty string")

	local source = options.Source
	if source == nil then
		source = options.SourceEntity
	end
	local hitstunFrames = options.HitstunFrames
	assert(hitstunFrames == nil or (isFiniteNumber(hitstunFrames) and hitstunFrames >= 0
		and hitstunFrames % 1 == 0),
		"DamageRequest HitstunFrames must be a non-negative finite integer or nil")
	return setmetatable({
		Amount = options.Amount,
		Type = damageType,
		Source = source,
		SourceEntity = source,
		Target = options.Target,
		AttackInstance = options.AttackInstance,
		HitEvent = options.HitEvent,
		OffensiveProperties = options.OffensiveProperties,
		Frame = options.Frame,
		Time = options.Time,
		HitstunFrames = hitstunFrames,
	}, DamageRequest)
end

function DamageRequest.FromHitEvent(hitEvent)
	assert(type(hitEvent) == "table", "DamageRequest.FromHitEvent() expects a HitEvent")
	local offensiveProperties = hitEvent.OffensiveProperties
	local damage = offensiveProperties and offensiveProperties.Damage or hitEvent.Damage
	if damage == nil then
		return nil
	end

	local amount = damage
	local damageType = "Physical"
	if type(damage) == "table" then
		amount = damage.Amount
		damageType = damage.Type or "Physical"
	end

	return DamageRequest.new({
		Amount = amount,
		Type = damageType,
		Source = hitEvent.Attacker,
		Target = hitEvent.Target,
		AttackInstance = hitEvent.AttackInstance,
		HitEvent = hitEvent,
		OffensiveProperties = offensiveProperties,
		HitstunFrames = offensiveProperties and offensiveProperties.Hitstun or hitEvent.Hitstun,
		Frame = hitEvent.Frame,
		Time = hitEvent.Time,
	})
end

return DamageRequest
