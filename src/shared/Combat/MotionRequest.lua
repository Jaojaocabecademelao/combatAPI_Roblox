local MotionType = require(script.Parent.MotionType)

local MotionRequest = {}
MotionRequest.__index = MotionRequest

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function normalizeDirection(direction)
	if direction == nil then
		return nil
	end
	if typeof and typeof(direction) == "Vector3" then
		return direction
	end
	if type(direction) == "table" then
		if direction.X ~= nil and direction.Y ~= nil and direction.Z ~= nil then
			return Vector3.new(direction.X, direction.Y, direction.Z)
		end
		local x = direction[1]
		local y = direction[2]
		local z = direction[3]
		if x ~= nil and y ~= nil and z ~= nil then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function isSupportedMotionType(value)
	return value == MotionType.Knockback
		or value == MotionType.Impulse
		or value == MotionType.Push
		or value == MotionType.Pull
		or value == MotionType.Launch
end

function MotionRequest.new(options)
	if options == nil then
		options = {}
	end
	assert(type(options) == "table", "MotionRequest.new() expects an options table")

	local source = options.Source
	local target = options.Target
	local requestType = options.Type or MotionType.Knockback
	assert(requestType ~= nil and type(requestType) == "string",
		"MotionRequest Type must be a non-empty string")
	assert(isSupportedMotionType(requestType), "MotionRequest Type is not supported")

	local direction = normalizeDirection(options.Direction)
	assert(direction ~= nil, "MotionRequest Direction must be a Vector3-compatible value")

	local magnitude = options.Magnitude
	assert(isFiniteNumber(magnitude) and magnitude >= 0,
		"MotionRequest Magnitude must be a finite non-negative number")

	local duration = options.Duration or 0
	assert(isFiniteNumber(duration) and duration >= 0 and duration % 1 == 0,
		"MotionRequest Duration must be a finite non-negative integer")

	local priority = options.Priority or 0
	assert(isFiniteNumber(priority), "MotionRequest Priority must be a finite number")

	return setmetatable({
		Source = source,
		Target = target,
		Type = requestType,
		Direction = direction,
		Magnitude = magnitude,
		Duration = duration,
		Priority = priority,
		Frame = options.Frame,
		Time = options.Time,
	}, MotionRequest)
end

return MotionRequest
