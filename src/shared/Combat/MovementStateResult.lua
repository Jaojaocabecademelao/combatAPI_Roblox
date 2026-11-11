local Result = {}
Result.__index = Result
Result.Type = table.freeze({
	Transitioned = "Transitioned",
	Rejected = "Rejected",
	AlreadyInState = "AlreadyInState",
	InvalidState = "InvalidState",
	InvalidEntity = "InvalidEntity",
})
function Result.new(data) return setmetatable(data, Result) end
return Result
