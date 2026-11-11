local Result = {}
Result.__index = Result
function Result.new(success, value, error)
	assert(type(success) == "boolean", "APIResult success flag must be boolean")
	return table.freeze(setmetatable({ Success = success, Value = value, Error = error }, Result))
end
return Result
