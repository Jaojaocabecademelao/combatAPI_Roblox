local Result = {}
Result.__index = Result
Result.Type = table.freeze({
	Allowed = "Allowed", Rejected = "Rejected", InvalidEntity = "InvalidEntity",
	InvalidAction = "InvalidAction", InvalidRule = "InvalidRule", OutsideWindow = "OutsideWindow",
	WrongSourceAction = "WrongSourceAction", AlreadyCancelled = "AlreadyCancelled",
	ConditionFailed = "ConditionFailed",
})
function Result.new(data) return setmetatable(data, Result) end
return Result
