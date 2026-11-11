local Profile = {}
Profile.__index = Profile

Profile.InputPolicy = table.freeze({
	RepeatLast = "RepeatLast",
	Neutral = "Neutral",
})

local function validInteger(value, minimum)
	return type(value) == "number" and value == value and value >= minimum
		and value < math.huge and value % 1 == 0
end

function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "PredictionProfile.new() expects an options table")

	local maxHistoryFrames = options.MaxHistoryFrames
	if maxHistoryFrames == nil then maxHistoryFrames = 120 end
	local maxPredictionFrames = options.MaxPredictionFrames
	if maxPredictionFrames == nil then maxPredictionFrames = 8 end
	local inputPolicy = options.InputPolicy
	if inputPolicy == nil then inputPolicy = Profile.InputPolicy.RepeatLast end

	assert(validInteger(maxHistoryFrames, 1), "PredictionProfile MaxHistoryFrames must be a positive integer")
	assert(validInteger(maxPredictionFrames, 0), "PredictionProfile MaxPredictionFrames must be a non-negative integer")
	assert(inputPolicy == Profile.InputPolicy.RepeatLast or inputPolicy == Profile.InputPolicy.Neutral,
		"PredictionProfile InputPolicy is invalid")

	return setmetatable({
		MaxHistoryFrames = maxHistoryFrames,
		MaxPredictionFrames = maxPredictionFrames,
		InputPolicy = inputPolicy,
	}, Profile)
end

return Profile
