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
	local offensiveOptions: CombatAPITypes.OffensivePropertiesOptions = {
		Damage = 8,
		CustomData = { Element = "Fire" },
	}
	local offensiveProperties: CombatAPITypes.OffensiveProperties =
		publicAPI.OffensiveProperties.new(offensiveOptions)
	assert(offensiveProperties.CustomData ~= nil, "typed OffensiveProperties preserve CustomData")
	check(offensiveProperties.Damage ~= nil and offensiveProperties.CustomData.Element == "Fire",
		"typed OffensiveProperties expose damage and custom data")
	local world: CombatAPITypes.World = publicAPI.CreateWorld()
	local simulationOptions: CombatAPITypes.SimulationOptions = {
		FixedDeltaTime = 1 / 60,
		MaxStepsPerUpdate = 5,
		Seed = 42,
		FrameCommandBuffer = { MaxCommandsPerFrame = 32, HistorySize = 12 },
		DeterministicScheduler = { MaxEvents = 64 },
	}
	local simulation: CombatAPITypes.Simulation = publicAPI.Simulation.new(world, simulationOptions)
	check(simulation:GetWorld() == world, "typed Simulation constructor associates with the World")
	local actionEventType = "types.contract.action-effect"
	local actionHandler: (CombatAPITypes.ActionGameplayEvent) -> () = function(event)
		check(event.Type == actionEventType and event.Parameters ~= nil,
			"typed action event handler receives the shared event contract")
	end
	check(simulation:RegisterGameplayActionEventHandler(actionEventType, actionHandler),
		"typed Simulation registers an action event handler")
	local actionParameters = { Amount = 5 }
	local actionDefinition: CombatAPITypes.CombatActionDefinition =
		publicAPI.CombatActionDefinition.new({
			Id = "types.contract.action",
			StartupFrames = 1,
			ActiveFrames = 1,
			GameplayEvents = {
				{
					FrameOffset = 1,
					Type = "types.contract.action-effect",
					Parameters = actionParameters,
				},
			},
		})
	actionParameters.Amount = 99
	check(actionDefinition.GameplayEvents[1].Parameters.Amount == 5,
		"typed action definitions defensively copy gameplay event parameters")
	check(simulation:Update(0) == 0, "typed Simulation exposes its update method")
	check(simulation:GetAlpha() == 0 and simulation:GetPendingStepCount() == 0,
		"typed Simulation exposes interpolation and pending-step state")
	local rng: CombatAPITypes.DeterministicRNG = simulation:GetRNG()
	local randomSample = rng:NextNumber()
	check(randomSample >= 0 and randomSample < 1 and rng:NextInteger(4, 4) == 4,
		"typed Simulation exposes its deterministic RNG contract")
	check(simulation:CanRestoreRollbackFrame(), "new typed Simulation is ready for rollback capture")
	local simulationState = simulation:CaptureState()
	check(simulation:RestoreState(simulationState), "typed Simulation state round-trips")
	check(simulation:GetKernelStateHash() ~= "", "typed Simulation exposes a kernel state hash")
	local topologyCatalog: CombatAPITypes.CollisionTopologyCatalog =
		publicAPI.CollisionTopologyCatalog.new()
	topologyCatalog:Register("types.contract.hitbox", 1, function(saved, owner)
		return publicAPI.Hitbox.new({
			Id = saved.Id,
			Owner = owner,
			Shape = saved.Shape,
			Size = Vector3.new(1, 1, 1),
			TopologyDefinitionId = "types.contract.hitbox",
			TopologyDefinitionVersion = 1,
		})
	end)
	topologyCatalog:Seal()
	local context: CombatAPITypes.APIContext? = publicAPI.GetContext(world)
	assert(context ~= nil, "typed GetContext returns the World-owned APIContext")
	check(context:HasFeature("Events"), "typed APIContext exposes Events")

	local pluginProfile: CombatAPITypes.PluginProfileOptions = {
		Id = "types.contract.plugin",
		Name = "Typed Plugin",
		Version = "1.0.0",
		Capabilities = { "types.contract.capability" },
	}
	local callbackCount = 0
	local plugin: CombatAPITypes.Plugin = publicAPI.Plugin.new(pluginProfile, {
		Initialize = function(
			_pluginContext: CombatAPITypes.PluginContext,
			_registeredPlugin: CombatAPITypes.Plugin
		)
			local subscription, subscribeError = _pluginContext:Subscribe(
				"TypedPluginContract",
				function(
					event: CombatAPITypes.Event,
					_api: CombatAPITypes.APIContext?,
					callbackContext: CombatAPITypes.PluginContext
				)
					if event.Type == "TypedPluginContract" and callbackContext:IsValid() then
						callbackCount += 1
					end
				end
			)
			assert(subscription ~= nil and subscribeError == nil,
				"typed plugin context subscribes with a typed event callback")
			local invalidSubscription, invalidSubscribeError =
				_pluginContext:Subscribe("", function() end)
			assert(invalidSubscription == nil and invalidSubscribeError == "InvalidArgument",
				"typed plugin context reports invalid subscription arguments")
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
	local invalidPluginId = context:GetPlugin("")
	check(not invalidPluginId.Success and invalidPluginId.Error ~= nil
		and invalidPluginId.Error.Code == "InvalidArgument",
		"APIContext rejects an empty plugin ID as invalid input")
	check(publicAPI.StartPlugin(world, plugin.Id).Success, "typed plugin lifecycle operation succeeds")
	context.Events:Dispatch("TypedPluginContract", {}, { ExecutionMode = "Normal" })
	check(callbackCount == 1, "typed plugin event callback receives its event and live context")

	local pluginContext: CombatAPITypes.PluginContext? = plugin.Context
	assert(pluginContext ~= nil, "typed plugin lifecycle exposes a PluginContext")
	local registeredCapability: CombatAPITypes.PluginCapability?, registerCapabilityError: CombatAPITypes.PluginContextErrorCode? =
		pluginContext:RegisterCapability("types.contract.capability", {
		Ping = function() return "pong" end,
	}, "1.0.0")
	assert(registeredCapability ~= nil and registerCapabilityError == nil,
		"typed plugin capability registration succeeds")
	check(registeredCapability ~= nil and registeredCapability.Id == "types.contract.capability",
		"typed plugin capability is registered with the declared identifier")
	local readCapability: CombatAPITypes.PluginCapability? = pluginContext:GetCapability("types.contract.capability")
	check(readCapability ~= nil and readCapability.Version == "1.0.0",
		"typed plugin capability lookup returns the registered capability")
	local registryView: CombatAPITypes.PluginRegistryView? = pluginContext:GetRegistry()
	check(registryView ~= nil and registryView:Has(plugin.Id)
		and registryView:HasCapability("types.contract.capability"),
		"typed plugin registry view exposes plugin and capability membership")
	local pluginEventBus: CombatAPITypes.EventBus? = pluginContext:GetEventBus()
	check(pluginEventBus ~= nil and pluginEventBus == context:GetEvents(),
		"typed plugin context exposes the World's shared EventBus")
	local eventOptions: CombatAPITypes.EventSubscriptionOptions = {
		Priority = 5,
		Filter = {
			EntityId = plugin.Id,
			Predicate = function(event: CombatAPITypes.Event)
				return event.Type == "TypedPluginFiltered"
			end,
		},
	}
	local filteredSubscription, filterError = pluginContext:Subscribe(
		"TypedPluginFiltered",
		function(
			_event: CombatAPITypes.Event,
			_api: CombatAPITypes.APIContext,
			_context: CombatAPITypes.PluginContext
		)
		end,
		eventOptions
	)
	check(filteredSubscription ~= nil and filterError == nil,
		"typed EventBus subscriptions accept the documented filter options")
	local duplicateCapability: CombatAPITypes.PluginCapability?, duplicateCapabilityError: CombatAPITypes.PluginContextErrorCode? =
		pluginContext:RegisterCapability("types.contract.capability", {})
	check(duplicateCapability == nil and duplicateCapabilityError == "CapabilityConflict",
		"duplicate capability registration returns its typed error code")
	local undeclaredCapability: CombatAPITypes.PluginCapability?, undeclaredCapabilityError: CombatAPITypes.PluginContextErrorCode? =
		pluginContext:RegisterCapability("types.contract.undeclared", {})
	check(undeclaredCapability == nil and undeclaredCapabilityError == "CapabilityNotDeclared",
		"undeclared capability registration returns its typed error code")
	local unsupportedExtension: CombatAPITypes.PluginCapability?, unsupportedExtensionError: CombatAPITypes.PluginContextErrorCode? =
		pluginContext:Register("Resolver", "types.contract.resolver", {})
	check(unsupportedExtension == nil and unsupportedExtensionError == "UnsupportedExtensionKind",
		"plugin context reports unsupported extension kinds explicitly")

	local directPlugin: CombatAPITypes.APIResult<CombatAPITypes.PluginResolverResult> =
		publicAPI.RegisterPlugin(world, {
			Id = "types.contract.direct-plugin",
			Name = "Directly Registered Plugin",
			Version = "1.0.0",
		})
	check(directPlugin.Success, "typed facade accepts a plugin profile directly")
	check(publicAPI.StopPlugin(world, plugin.Id).Success, "typed plugin lifecycle operation stops the plugin")
	check(not pluginContext:IsValid(), "stopping a plugin invalidates its PluginContext")
	check(registryView ~= nil and not registryView:Has(plugin.Id)
		and not registryView:HasCapability("types.contract.capability"),
		"retained registry views become safe after their plugin context is invalidated")
	context.Events:Dispatch("TypedPluginContract", {}, { ExecutionMode = "Normal" })
	check(callbackCount == 1, "stopping the plugin disconnects its owned event subscription")
	local lateCapability: CombatAPITypes.PluginCapability?, lateCapabilityError: CombatAPITypes.PluginContextErrorCode? =
		pluginContext:RegisterCapability("types.contract.capability", {})
	check(lateCapability == nil and lateCapabilityError == "InvalidContext",
		"invalidated PluginContext rejects capability registration with a typed error")
	local lateSubscription, lateSubscribeError =
		pluginContext:Subscribe("TypedPluginContract", function() end)
	check(lateSubscription == nil and lateSubscribeError == "InvalidContext",
		"invalidated PluginContext rejects subscriptions with a typed error")

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
	local destroyedContextLookup = context:GetPlugin(plugin.Id)
	check(not destroyedContextLookup.Success and destroyedContextLookup.Error ~= nil
		and destroyedContextLookup.Error.Code == "Destroyed",
		"destroyed APIContext returns a Destroyed error instead of NotFound")
	print("[CombatAPITypesTest] PASS")
end
