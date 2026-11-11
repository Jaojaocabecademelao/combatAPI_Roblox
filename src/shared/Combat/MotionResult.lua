local MotionResult = {}
MotionResult.__index = MotionResult

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function MotionResult.new(request, frame)
	assert(request and type(request) == "table", "MotionResult.new() expects a MotionRequest")
	local direction = request.Direction
	assert(direction ~= nil, "MotionResult Direction is required")
	local magnitude = request.Magnitude
	assert(isFiniteNumber(magnitude) and magnitude >= 0,
		"MotionResult Magnitude must be non-negative and finite")

	return setmetatable({
		Source = request.Source,
		Target = request.Target,
		Type = request.Type,
		Direction = direction,
		Magnitude = magnitude,
		Duration = request.Duration or 0,
		Priority = request.Priority or 0,
		Frame = frame or request.Frame or 0,
		Time = request.Time,
		Request = request,
	}, MotionResult)
end

return MotionResult
