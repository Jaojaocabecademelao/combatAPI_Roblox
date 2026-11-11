local Result = {}
Result.__index = Result
Result.Type = table.freeze({
	Success = "Success", InvalidEntity = "InvalidEntity", EntityDead = "EntityDead",
	AlreadyAttached = "AlreadyAttached", NotAttached = "NotAttached",
	InvalidCharacter = "InvalidCharacter", InvalidProfile = "InvalidProfile",
	InvalidAdapter = "InvalidAdapter", InvalidRepresentation = "InvalidRepresentation",
	AdapterRejected = "AdapterRejected", AttachFailed = "AttachFailed",
	DetachFailed = "DetachFailed", InvalidOperation = "InvalidOperation",
})
function Result.new(data) return setmetatable(data, Result) end
return Result
