local Result = {}
Result.__index = Result

Result.Type = table.freeze({
	Success = "Success",
	Disabled = "Disabled",
	InvalidEntity = "InvalidEntity",
	InvalidFrame = "InvalidFrame",
	RollbackAlreadyInProgress = "RollbackAlreadyInProgress",
	RollbackTooLarge = "RollbackTooLarge",
	ReplayTooLarge = "ReplayTooLarge",
	MissingSnapshot = "MissingSnapshot",
	MissingInput = "MissingInput",
	RestoreFailed = "RestoreFailed",
	ReplayFailed = "ReplayFailed",
	UnsupportedComponent = "UnsupportedComponent",
	UnsupportedWorld = "UnsupportedWorld",
	InvalidScope = "InvalidScope",
	NoRollbackNeeded = "NoRollbackNeeded",
	AlreadyAtFrame = "AlreadyAtFrame",
	InvalidRequest = "InvalidRequest",
	InvalidSimulation = "InvalidSimulation",
	HistoryFull = "HistoryFull",
	UnconfirmedSnapshot = "UnconfirmedSnapshot",
})

function Result.new(data)
	assert(type(data) == "table", "RollbackResult.new() expects a table")
	return setmetatable({
		Type = data.Type,
		Accepted = data.Type == Result.Type.Success,
		Frame = data.Frame,
		FromFrame = data.FromFrame,
		ToFrame = data.ToFrame,
		EntityId = data.EntityId,
		Reason = data.Reason,
		Detail = data.Detail,
		Request = data.Request,
		ReplayFrames = data.ReplayFrames,
	}, Result)
end

return Result
