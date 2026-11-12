--!strict

local APIError = {}
APIError.__index = APIError

export type Code =
	"InvalidArgument"
	| "InvalidEntity"
	| "InvalidOperation"
	| "NotFound"
	| "AlreadyExists"
	| "NotInitialized"
	| "Disabled"
	| "PermissionDenied"
	| "InternalError"
	| "Destroyed"

export type Error = {
	Code: Code,
	Message: string,
	System: string?,
	Frame: number?,
	Context: { [string]: any }?,
}

type ResolverFailure = {
	Success: false,
	Code: string,
	PluginId: string?,
	Details: any?,
}

local codes: { [string]: Code } = {
	InvalidArgument = "InvalidArgument",
	InvalidEntity = "InvalidEntity",
	InvalidOperation = "InvalidOperation",
	NotFound = "NotFound",
	AlreadyExists = "AlreadyExists",
	NotInitialized = "NotInitialized",
	Disabled = "Disabled",
	PermissionDenied = "PermissionDenied",
	InternalError = "InternalError",
	Destroyed = "Destroyed",
}

local resolverCodeMap: { [string]: Code } = {
	WorldDestroyed = "Destroyed",
	InvalidPlugin = "InvalidArgument",
	InvalidCapabilityId = "InvalidArgument",
	InvalidCapabilityVersion = "InvalidArgument",
	PluginAlreadyOwned = "AlreadyExists",
	DuplicatePlugin = "AlreadyExists",
	CapabilityConflict = "AlreadyExists",
	PluginNotFound = "NotFound",
	CapabilityNotFound = "NotFound",
	DependencyMissing = "NotFound",
	PluginDisabled = "Disabled",
	PermissionDenied = "PermissionDenied",
	CapabilityNotDeclared = "PermissionDenied",
	InitializationFailed = "InternalError",
	PluginRuntimeFailed = "InternalError",
	StopFailed = "InternalError",
	ActiveDependents = "InvalidOperation",
	PluginActive = "InvalidOperation",
	InvalidLifecycleState = "InvalidOperation",
	DependencyVersionMismatch = "InvalidOperation",
	DependencyCycle = "InvalidOperation",
	DependencyFailed = "InvalidOperation",
}

APIError.Code = table.freeze(codes)

function APIError.isCode(value: any): boolean
	return type(value) == "string" and codes[value] ~= nil
end

function APIError.new(
	code: Code,
	message: string,
	system: string?,
	frame: number?,
	context: { [string]: any }?
): Error
	assert(APIError.isCode(code), "APIError requires a recognized Code")
	assert(type(message) == "string", "APIError requires a string Message")
	assert(system == nil or type(system) == "string", "APIError System must be a string or nil")
	assert(frame == nil or (type(frame) == "number" and frame == frame and frame > -math.huge and frame < math.huge),
		"APIError Frame must be a finite number or nil")
	assert(context == nil or type(context) == "table", "APIError Context must be a table or nil")

	local result = setmetatable({
		Code = code,
		Message = message,
		System = system,
		Frame = frame,
		Context = context,
	}, APIError)
	return table.freeze(result) :: any
end

function APIError.fromResolverResult(
	result: ResolverFailure,
	system: string?,
	frame: number?
): Error
	assert(type(result) == "table" and result.Success == false and type(result.Code) == "string",
		"APIError.fromResolverResult requires a failed resolver result")
	local context: { [string]: any } = {}
	if type(result.Details) == "table" then
		for key, value in pairs(result.Details) do
			context[key] = value
		end
	elseif result.Details ~= nil then
		context.ResolverDetails = result.Details
	end
	context.ResolverCode = result.Code
	if result.PluginId ~= nil then
		context.PluginId = result.PluginId
	end
	return APIError.new(
		resolverCodeMap[result.Code] or APIError.Code.InvalidOperation,
		result.Code,
		system,
		frame,
		context
	)
end

return table.freeze(APIError)
