local HitstopRequest = {}
HitstopRequest.__index = HitstopRequest

local function finite(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function HitstopRequest.new(options)
	assert(type(options) == "table", "HitstopRequest.new() expects an options table")
	local target = options.Target
	assert(type(target) == "table" and target.Id ~= nil,
		"HitstopRequest requires a Target entity with an Id")
	local frames = options.Frames
	assert(finite(frames) and frames >= 0 and frames % 1 == 0,
		"HitstopRequest Frames must be a non-negative finite integer")
	local priority = options.Priority
	if priority == nil then
		priority = 0
	end
	assert(finite(priority), "HitstopRequest Priority must be finite")
	return setmetatable({
		Source = options.Source,
		Target = target,
		Frames = frames,
		Priority = priority,
	}, HitstopRequest)
end

return HitstopRequest
