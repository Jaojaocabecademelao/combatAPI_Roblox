local Result = {}
Result.__index = Result

Result.Type = table.freeze({
	Success = "Success",
	AlreadyEnabled = "AlreadyEnabled",
	AlreadyDisabled = "AlreadyDisabled",
	AlreadyStarted = "AlreadyStarted",
	InvalidEntity = "InvalidEntity",
	InvalidProfile = "InvalidProfile",
	InvalidFrame = "InvalidFrame",
	InvalidInput = "InvalidInput",
	InvalidSnapshot = "InvalidSnapshot",
	NotStarted = "NotStarted",
	OutOfOrder = "OutOfOrder",
	MaxPredictionFrames = "MaxPredictionFrames",
	UnknownFrame = "UnknownFrame",
})

function Result.new(data)
	assert(type(data) == "table", "PredictionResult.new() expects data")
	return setmetatable({
		Type = data.Type,
		Accepted = data.Type == Result.Type.Success,
		EntityId = data.EntityId,
		Frame = data.Frame,
		Predicted = data.Predicted == true,
		PredictionIndex = data.PredictionIndex,
		Divergences = data.Divergences,
		Reason = data.Reason,
	}, Result)
end

return Result
