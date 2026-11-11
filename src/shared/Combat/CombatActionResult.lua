local Result = {}
Result.__index = Result
Result.Type = table.freeze({
	Started = "Started", Cancelled = "Cancelled", Rejected = "Rejected",
	Completed = "Completed", InvalidEntity = "InvalidEntity",
	UnknownAction = "UnknownAction", AlreadyRunning = "AlreadyRunning",
	NotCancelable = "NotCancelable", InvalidFrame = "InvalidFrame",
})
function Result.new(data) return setmetatable(data, Result) end
return Result
