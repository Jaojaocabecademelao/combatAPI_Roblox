--!strict

-- Maps PluginResolver result codes to the stable APIError.Code vocabulary.
-- Resolver codes stay distinct from APIError.Code: the original value is preserved in
-- Error.Context.ResolverCode, and Error.Message keeps carrying it for compatibility.

local APIError = require(script.Parent.APIError)

local ResolverErrorMap = {}

local FALLBACK: APIError.Code = "InvalidOperation"

local codes: { [string]: APIError.Code } = {
	-- A referenced plugin, capability or dependency does not exist.
	PluginNotFound = "NotFound",
	CapabilityNotFound = "NotFound",
	DependencyMissing = "NotFound",

	-- Duplicate registration or ownership conflict.
	DuplicatePlugin = "AlreadyExists",
	PluginAlreadyOwned = "AlreadyExists",
	CapabilityConflict = "AlreadyExists",

	-- Malformed input.
	InvalidPlugin = "InvalidArgument",
	InvalidCapabilityId = "InvalidArgument",
	InvalidCapabilityVersion = "InvalidArgument",

	-- The caller is not allowed to perform the operation.
	PermissionDenied = "PermissionDenied",
	CapabilityNotDeclared = "PermissionDenied",

	-- Target state.
	PluginDisabled = "Disabled",
	WorldDestroyed = "Destroyed",

	-- An exception escaped plugin-owned code while the operation was running.
	InitializationFailed = "InternalError",
	PluginRuntimeFailed = "InternalError",
	StopFailed = "InternalError",

	-- Well-formed request that the current lifecycle or dependency graph does not allow.
	InvalidLifecycleState = "InvalidOperation",
	PluginActive = "InvalidOperation",
	ActiveDependents = "InvalidOperation",
	DependencyCycle = "InvalidOperation",
	DependencyVersionMismatch = "InvalidOperation",
	DependencyFailed = "InvalidOperation",
}

ResolverErrorMap.Codes = table.freeze(codes)

-- Unknown or future resolver codes fall back to InvalidOperation, the previous behavior.
function ResolverErrorMap.codeFor(resolverCode: any): APIError.Code
	if type(resolverCode) == "string" then
		local mapped = codes[resolverCode]
		if mapped ~= nil then return mapped end
	end
	return FALLBACK
end

function ResolverErrorMap.toError(result: { Code: any }, system: string?, frame: number?): APIError.Error
	local resolverCode = tostring(result.Code)
	return APIError.new(
		ResolverErrorMap.codeFor(result.Code),
		resolverCode,
		system,
		frame,
		{ ResolverCode = resolverCode }
	)
end

return table.freeze(ResolverErrorMap)
