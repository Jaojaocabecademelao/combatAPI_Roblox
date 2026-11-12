--!strict
-- Compile-time and runtime contract test for the consumer-facing Luau types.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)
local CombatAPITypes = require(ReplicatedStorage.Shared.CombatAPITypes)

local function check(condition: boolean, message: string)
	assert(condition, "CombatAPITypesTest: " .. message)
end

return function()
	local publicAPI: CombatAPITypes.CombatAPI = CombatAPI
	local world: CombatAPITypes.World = publicAPI.CreateWorld()
	local context: CombatAPITypes.APIContext? = publicAPI.GetContext(world)
	assert(context ~= nil, "typed GetContext returns the World-owned APIContext")
	check(context:HasFeature("Events"), "typed APIContext exposes Events")

	local pluginProfile: CombatAPITypes.PluginProfileOptions = {
		Id = "types.contract.plugin",
		Name = "Typed Plugin",
		Version = "1.0.0",
		Capabilities = { "types.contract.capability" },
	}
	local plugin: CombatAPITypes.Plugin = publicAPI.Plugin.new(pluginProfile, {
		Initialize = function(_pluginContext, _registeredPlugin)
			return true
		end,
	})
	local registration: CombatAPITypes.APIResult<CombatAPITypes.PluginResolverResult> =
		publicAPI.RegisterPlugin(world, plugin)
	assert(registration.Success, "typed plugin registration succeeds")
	local pluginResult: CombatAPITypes.PluginResolverResult? = registration.Value
	assert(pluginResult ~= nil, "typed plugin registration returns a resolver result")
	check(pluginResult.Value ~= nil and pluginResult.Value.Id == plugin.Id,
		"typed plugin result exposes the registered plugin")
	local typedPlugin: CombatAPITypes.APIResult<CombatAPITypes.Plugin> = context:GetPlugin(plugin.Id)
	check(typedPlugin.Success and typedPlugin.Value == plugin,
		"typed APIContext lookup returns the registered plugin")
	check(publicAPI.StartPlugin(world, plugin.Id).Success, "typed plugin lifecycle operation succeeds")

	local pluginContext: CombatAPITypes.PluginContext? = plugin.Context
	assert(pluginContext ~= nil, "typed plugin lifecycle exposes a PluginContext")
	local capabilityResult = pluginContext:RegisterCapability("types.contract.capability", {
		Ping = function() return "pong" end,
	}, "1.0.0")
	assert(capabilityResult[1] ~= nil, "typed plugin capability registration succeeds")
	local registeredCapability: CombatAPITypes.PluginCapability? = capabilityResult[1]
	check(registeredCapability ~= nil and registeredCapability.Id == "types.contract.capability",
		"typed plugin capability is registered with the declared identifier")
	local readCapability: CombatAPITypes.PluginCapability? = pluginContext:GetCapability("types.contract.capability")
	check(readCapability ~= nil and readCapability.Version == "1.0.0",
		"typed plugin capability lookup returns the registered capability")

	local directPlugin: CombatAPITypes.APIResult<CombatAPITypes.PluginResolverResult> =
		publicAPI.RegisterPlugin(world, {
			Id = "types.contract.direct-plugin",
			Name = "Directly Registered Plugin",
			Version = "1.0.0",
		})
	check(directPlugin.Success, "typed facade accepts a plugin profile directly")

	local attackOptions: CombatAPITypes.AttackOptions = {
		Id = "types.contract.attack",
		Damage = 10,
		CustomData = { Radius = 3, Element = "Arcane" },
	}
	local attack: CombatAPITypes.Attack = publicAPI.Attack.new(attackOptions)
	local instanceOptions: CombatAPITypes.AttackInstanceOptions = {
		Id = "types.contract.instance",
		CustomDataOverrides = { Radius = 5 },
	}
	local instance: CombatAPITypes.AttackInstance = publicAPI.AttackInstance.new(
		attack,
		nil,
		nil,
		instanceOptions
	)

	local effectiveData = instance.OffensiveProperties.CustomData
	assert(effectiveData ~= nil, "typed instance retains effective CustomData")
	check(effectiveData.Radius == 5, "typed override replaces the base value")
	check(effectiveData.Element == "Arcane", "typed override inherits the base value")

	world:Destroy()
	print("[CombatAPITypesTest] PASS")
end
