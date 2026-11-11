--!strict

local APIError = require(script.Parent.APIError)

type APIErrorValue = APIError.Error

local APIResult = {}
APIResult.__index = APIResult

export type Result<T> = {
	Success: boolean,
	Value: T?,
	Error: APIErrorValue?,
}

function APIResult.new<T>(success: boolean, value: T?, err: APIErrorValue?): Result<T>
	assert(type(success) == "boolean", "APIResult Success flag must be boolean")
	assert(err == nil or type(err) == "table", "APIResult Error must be a table or nil")
	if success then
		assert(err == nil, "Successful APIResult cannot contain an Error")
	else
		assert(err ~= nil, "Failed APIResult must contain an Error")
	end

	local result = setmetatable({
		Success = success,
		Value = value,
		Error = err,
	}, APIResult)
	return table.freeze(result) :: any
end

function APIResult.is(value: any): boolean
	return type(value) == "table"
		and type(value.Success) == "boolean"
		and (value.Error == nil or type(value.Error) == "table")
		and (value.Success and value.Error == nil or not value.Success and value.Error ~= nil)
end

return table.freeze(APIResult)
