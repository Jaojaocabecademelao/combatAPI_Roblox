local Result = {}
Result.__index = Result

Result.Type = table.freeze({
	Success = "Success",
	Disabled = "Disabled",
	InvalidPeer = "InvalidPeer",
	UnknownPeer = "UnknownPeer",
	InvalidEntity = "InvalidEntity",
	UnauthorizedEntity = "UnauthorizedEntity",
	OwnershipConflict = "OwnershipConflict",
	InvalidInput = "InvalidInput",
	InvalidFrame = "InvalidFrame",
	InvalidSequence = "InvalidSequence",
	DuplicateInput = "DuplicateInput",
	OutOfOrderInput = "OutOfOrderInput",
	InputRateExceeded = "InputRateExceeded",
	FutureInput = "FutureInput",
	PastInput = "PastInput",
	RecoveryRequired = "RecoveryRequired",
	RollbackUnsupported = "RollbackUnsupported",
	ValidationFailed = "ValidationFailed",
	SimulationUnavailable = "SimulationUnavailable",
	SimulationFailed = "SimulationFailed",
	InvalidAdvance = "InvalidAdvance",
	AlreadyProcessing = "AlreadyProcessing",
	SnapshotFailed = "SnapshotFailed",
	PublishingFailed = "PublishingFailed",
})

function Result.new(data)
	assert(type(data) == "table" and type(data.Type) == "string", "AuthorityResult is invalid")
	data.Accepted = data.Type == Result.Type.Success
	return setmetatable(data, Result)
end

return Result
