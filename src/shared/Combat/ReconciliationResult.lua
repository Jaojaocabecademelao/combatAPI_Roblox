local Result = {}
Result.__index = Result

Result.Type = table.freeze({
	Applied = "Applied",
	Matched = "Matched",
	Duplicate = "Duplicate",
	InvalidSnapshot = "InvalidSnapshot",
	MissingAdapter = "MissingAdapter",
	AdapterFailed = "AdapterFailed",
	CompareFailed = "CompareFailed",
})

function Result.new(data)
	assert(type(data) == "table" and type(data.Type) == "string",
		"ReconciliationResult is invalid")
	data.Accepted = data.Type == Result.Type.Applied or data.Type == Result.Type.Matched
	return setmetatable(data, Result)
end

return Result
