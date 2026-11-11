local APIError = {}
APIError.__index = APIError
APIError.Code = table.freeze({ InvalidArgument = "InvalidArgument", InvalidEntity = "InvalidEntity",
	InvalidOperation = "InvalidOperation", NotFound = "NotFound", AlreadyExists = "AlreadyExists",
	NotInitialized = "NotInitialized", Disabled = "Disabled", PermissionDenied = "PermissionDenied",
	InternalError = "InternalError", Destroyed = "Destroyed" })
function APIError.new(code, message, system, frame, context)
	assert(type(code) == "string" and type(message) == "string", "APIError requires Code and Message")
	return table.freeze(setmetatable({ Code = code, Message = message, System = system,
		Frame = frame, Context = context }, APIError))
end
return APIError
