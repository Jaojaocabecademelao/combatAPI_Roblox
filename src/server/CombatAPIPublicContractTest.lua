return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = Shared:WaitForChild("Events")

local APIError = require(Events.APIError)
local APIResult = require(Events.APIResult)

local assertions = 0
local function check(condition, message)
	assert(condition, message or ("public contract assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

-- Every documented error code is discoverable and stable.
for _, code in ipairs({
	"InvalidArgument", "InvalidEntity", "InvalidOperation", "NotFound", "AlreadyExists",
	"NotInitialized", "Disabled", "PermissionDenied", "InternalError", "Destroyed",
}) do
	check(APIError.isCode(code), "APIError code must be recognized: " .. code)
	check(APIError.Code[code] == code, "APIError code value must remain stable: " .. code)
end
check(not APIError.isCode("UnknownFailure"), "unknown APIError codes must be rejected")

local errorValue = APIError.new(APIError.Code.InvalidArgument, "Invalid input", "Test", 12, { Field = "Id" })
check(errorValue.Code == "InvalidArgument")
check(errorValue.Message == "Invalid input")
check(errorValue.System == "Test" and errorValue.Frame == 12)
check(errorValue.Context.Field == "Id")
check(table.isfrozen(errorValue), "APIError records must be immutable")
check(table.isfrozen(APIError.Code), "APIError code registry must be immutable")
check(not pcall(function()
	APIError.new("UnknownFailure", "failure")
end), "APIError.new must reject unknown codes")
check(not pcall(function()
	APIError.new(APIError.Code.InvalidArgument, "failure", "Test", math.huge)
end), "APIError must reject non-finite frames")

for _, failure in ipairs({
	{ Code = "WorldDestroyed", Expected = "Destroyed" },
	{ Code = "InvalidPlugin", Expected = "InvalidArgument" },
	{ Code = "InvalidCapabilityId", Expected = "InvalidArgument" },
	{ Code = "InvalidCapabilityVersion", Expected = "InvalidArgument" },
	{ Code = "PluginAlreadyOwned", Expected = "AlreadyExists" },
	{ Code = "DuplicatePlugin", Expected = "AlreadyExists" },
	{ Code = "CapabilityConflict", Expected = "AlreadyExists" },
	{ Code = "PluginNotFound", Expected = "NotFound" },
	{ Code = "CapabilityNotFound", Expected = "NotFound" },
	{ Code = "DependencyMissing", Expected = "NotFound" },
	{ Code = "PluginDisabled", Expected = "Disabled" },
	{ Code = "PermissionDenied", Expected = "PermissionDenied" },
	{ Code = "CapabilityNotDeclared", Expected = "PermissionDenied" },
	{ Code = "InitializationFailed", Expected = "InternalError" },
	{ Code = "PluginRuntimeFailed", Expected = "InternalError" },
	{ Code = "StopFailed", Expected = "InternalError" },
	{ Code = "ActiveDependents", Expected = "InvalidOperation" },
	{ Code = "PluginActive", Expected = "InvalidOperation" },
	{ Code = "InvalidLifecycleState", Expected = "InvalidOperation" },
	{ Code = "DependencyVersionMismatch", Expected = "InvalidOperation" },
	{ Code = "DependencyCycle", Expected = "InvalidOperation" },
	{ Code = "DependencyFailed", Expected = "InvalidOperation" },
	{ Code = "UnmappedResolverFailure", Expected = "InvalidOperation" },
}) do
	local mapped = APIError.fromResolverResult({
		Success = false,
		Code = failure.Code,
		PluginId = "test-plugin",
		Details = { DependencyId = "missing-dependency" },
	}, "Plugins", 8)
	check(mapped.Code == failure.Expected, "resolver failure maps to APIError.Code: " .. failure.Code)
	check(mapped.Context.ResolverCode == failure.Code
		and mapped.Context.PluginId == "test-plugin"
		and mapped.Context.DependencyId == "missing-dependency",
		"resolver failure details remain available in APIError.Context")
end
check(not pcall(function()
	APIError.fromResolverResult({ Success = true, Code = "Started" })
end), "resolver error mapping requires a failed result")

local success = APIResult.new(true, { Value = 5 })
check(success.Success and success.Value.Value == 5 and success.Error == nil)
check(APIResult.is(success), "success result must satisfy the public result contract")
check(table.isfrozen(success), "APIResult records must be immutable")

local failure = APIResult.new(false, nil, errorValue)
check(not failure.Success and failure.Error == errorValue)
check(APIResult.is(failure), "failure result must satisfy the public result contract")
check(not pcall(function()
	APIResult.new(true, "value", errorValue)
end), "success result must not contain an error")
check(not pcall(function()
	APIResult.new(false, nil, nil)
end), "failure result must contain an error")

print(string.format("[CombatAPIPublicContractTest] PASS (%d assertions)", assertions))

end
