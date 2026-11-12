return function()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local World = require(Shared.Core.World)
local CombatAPI = require(Shared.CombatAPI)
local APIError = require(Shared.Events.APIError)
local ResolverErrorMap = require(Shared.Events.ResolverErrorMap)
local Plugin = require(Shared.Plugins.Plugin)
local Profile = require(Shared.Plugins.PluginProfile)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Plugin error mapping assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end
local function make(id, options, implementation)
	options = options or {}
	options.Id = id
	options.Name = options.Name or id
	options.Version = options.Version or "1.0.0"
	return Plugin.new(Profile.new(options), implementation)
end

-- Every mapped value belongs to the public vocabulary; unknown resolver codes keep the old behavior.
for resolverCode, apiCode in pairs(ResolverErrorMap.Codes) do
	check(APIError.isCode(apiCode), "Resolver code " .. resolverCode .. " must map to a recognized APIError.Code")
end
check(table.isfrozen(ResolverErrorMap.Codes), "The mapping table must be immutable")
check(ResolverErrorMap.codeFor("FutureResolverCode") == "InvalidOperation"
	and ResolverErrorMap.codeFor(nil) == "InvalidOperation"
	and ResolverErrorMap.codeFor(42) == "InvalidOperation",
	"Unknown or non-string resolver codes must fall back to InvalidOperation")

local world = World.new()
local api = world:GetAPIContext()

local function expectFailure(result, apiCode, resolverCode, label)
	check(result.Success == false, label .. ": operation must fail")
	local err = result.Error
	check(err ~= nil and err.Code == apiCode,
		label .. ": expected APIError.Code " .. apiCode .. ", got " .. tostring(err and err.Code))
	check(err.Message == resolverCode, label .. ": Message keeps carrying the resolver code")
	check(err.Context ~= nil and err.Context.ResolverCode == resolverCode,
		label .. ": the resolver code must be preserved in Context.ResolverCode")
	check(err.System == "Plugins" and err.Frame == world.CurrentFrame,
		label .. ": System and Frame must be preserved")
	check(table.isfrozen(err), label .. ": the error record must be immutable")
end

-- Facade (CombatAPI.*): each failure class reaches its own APIError.Code.
check(CombatAPI.RegisterPlugin(world, make("Dup")).Success, "Registration succeeds")
local okResult = CombatAPI.StartPlugin(world, "Dup")
check(okResult.Success and okResult.Error == nil, "Successful operations carry no error")
expectFailure(CombatAPI.UnregisterPlugin(world, "absent"), "NotFound", "PluginNotFound", "Unregister unknown")
expectFailure(CombatAPI.StartPlugin(world, "absent"), "NotFound", "PluginNotFound", "Start unknown")
expectFailure(CombatAPI.RegisterPlugin(world, make("Dup")), "AlreadyExists", "DuplicatePlugin", "Duplicate registration")
expectFailure(CombatAPI.RegisterPlugin(world, {}), "InvalidArgument", "InvalidPlugin", "Malformed plugin")

CombatAPI.RegisterPlugin(world, make("Off"))
check(CombatAPI.DisablePlugin(world, "Off").Success, "Disable succeeds")
expectFailure(CombatAPI.StartPlugin(world, "Off"), "Disabled", "PluginDisabled", "Start disabled")

CombatAPI.RegisterPlugin(world, make("NeedsGhost", { Dependencies = { "NoSuchPlugin" } }))
expectFailure(CombatAPI.StartPlugin(world, "NeedsGhost"), "NotFound", "DependencyMissing", "Missing dependency")

CombatAPI.RegisterPlugin(world, make("Base", { Version = "2.1.0" }))
CombatAPI.RegisterPlugin(world, make("Child", { Dependencies = { "Base" } }))
check(CombatAPI.StartPlugin(world, "Child").Success, "Dependent plugin starts with its dependency")
expectFailure(CombatAPI.StopPlugin(world, "Base"), "InvalidOperation", "ActiveDependents", "Stop with active dependents")
CombatAPI.RegisterPlugin(world, make("Incompatible", { Dependencies = { { PluginId = "Base", MinVersion = "3.0.0" } } }))
expectFailure(CombatAPI.StartPlugin(world, "Incompatible"), "InvalidOperation", "DependencyVersionMismatch", "Version mismatch")

CombatAPI.RegisterPlugin(world, make("CycleB", { Dependencies = { "CycleC" } }))
CombatAPI.RegisterPlugin(world, make("CycleC", { Dependencies = { "CycleB" } }))
expectFailure(CombatAPI.StartPlugin(world, "CycleB"), "InvalidOperation", "DependencyCycle", "Dependency cycle")

local broken = make("Broken", nil, { Initialize = function() error("boom") end })
CombatAPI.RegisterPlugin(world, broken)
expectFailure(CombatAPI.StartPlugin(world, "Broken"), "InternalError", "InitializationFailed", "Initialization failure")

-- APIContext methods use the same mapping.
check(api:RegisterPlugin(make("CtxDup")).Success, "Context registration succeeds")
expectFailure(api:RegisterPlugin(make("CtxDup")), "AlreadyExists", "DuplicatePlugin", "Context duplicate")
expectFailure(api:StartPlugin("ctx-absent"), "NotFound", "PluginNotFound", "Context start unknown")
expectFailure(api:UnregisterPlugin("ctx-absent"), "NotFound", "PluginNotFound", "Context unregister unknown")
expectFailure(api:RegisterPlugin({}), "InvalidArgument", "InvalidPlugin", "Context malformed plugin")

world:Destroy()
print("CombatPluginErrorMappingTest: PASS (" .. tostring(assertions) .. " assertions)")

end
