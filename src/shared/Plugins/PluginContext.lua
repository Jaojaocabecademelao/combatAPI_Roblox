--!strict

local Types = require(script.Parent.Parent.CombatAPITypes)

type APIContextType = Types.APIContext
type APIErrorType = Types.APIError
type EventBusType = Types.EventBus
type EventSubscriptionType = Types.EventSubscription
type EventType = Types.Event
type PluginType = Types.Plugin
type PluginCapabilityType = Types.PluginCapability
type PluginContextErrorCode = Types.PluginContextErrorCode
type PluginContextType = Types.PluginContext
type PluginRegistryView = Types.PluginRegistryView
type WorldType = Types.World

type ContextWorld = WorldType & {
	APIContext: APIContextType,
	EventBus: EventBusType,
}

type Registry = {
	Get: (self: Registry, id: string) -> PluginType?,
	Has: (self: Registry, id: string) -> boolean,
	List: (self: Registry) -> { PluginType },
	HasCapability: (self: Registry, id: string) -> boolean,
	GetCapability: (self: Registry, id: string) -> PluginCapabilityType?,
	ListCapabilities: (self: Registry) -> { PluginCapabilityType },
}

type Resolver = {
	World: ContextWorld?,
	Registry: Registry,
	_registerCapability: (
		self: Resolver,
		plugin: PluginType,
		id: string,
		implementation: any?,
		version: string?
	) -> (PluginCapabilityType?, PluginContextErrorCode?),
	_unregisterCapability: (self: Resolver, plugin: PluginType, id: string) -> (boolean, string?),
	_failRuntime: (self: Resolver, plugin: PluginType, failure: any) -> (),
}

type Resource =
	{ Kind: "Capability", Id: string }
	| { Kind: "Subscription", Value: EventSubscriptionType }

type ContextFields = {
	_resolver: Resolver?,
	_plugin: PluginType?,
	_valid: boolean,
	_resources: { Resource },
	_registryView: PluginRegistryView?,
}

type Context = ContextFields & PluginContextType & {
	_invalidate: (self: Context) -> boolean,
}

local Context = {}
Context.__index = Context

local function getResolver(self: Context): Resolver?
	if not self._valid then return nil end
	return self._resolver
end

local function getRegistry(self: Context): Registry?
	local resolver = getResolver(self)
	return resolver and resolver.Registry or nil
end

function Context.new(resolver: Resolver, plugin: PluginType): Context
	local self = setmetatable({
		_resolver = resolver,
		_plugin = plugin,
		_valid = true,
		_resources = {},
		_registryView = nil,
	}, Context) :: Context

	local registryView: PluginRegistryView = {
		Get = function(_registry: PluginRegistryView, id: string): PluginType?
			local registry = getRegistry(self)
			return registry and registry:Get(id) or nil
		end,
		Has = function(_registry: PluginRegistryView, id: string): boolean
			local registry = getRegistry(self)
			return registry ~= nil and registry:Has(id)
		end,
		List = function(_registry: PluginRegistryView): { PluginType }
			local registry = getRegistry(self)
			return registry and registry:List() or {}
		end,
		HasCapability = function(_registry: PluginRegistryView, id: string): boolean
			local registry = getRegistry(self)
			return registry ~= nil and registry:HasCapability(id)
		end,
		GetCapability = function(_registry: PluginRegistryView, id: string): PluginCapabilityType?
			local registry = getRegistry(self)
			return registry and registry:GetCapability(id) or nil
		end,
		ListCapabilities = function(_registry: PluginRegistryView): { PluginCapabilityType }
			local registry = getRegistry(self)
			return registry and registry:ListCapabilities() or {}
		end,
	}
	self._registryView = table.freeze(registryView)
	return self
end

function Context.IsValid(self: Context): boolean
	return self._valid and self._resolver ~= nil
end

function Context.GetWorld(self: Context): WorldType?
	local resolver = getResolver(self)
	return resolver and resolver.World or nil
end

function Context.GetAPI(self: Context): APIContextType?
	local world = self:GetWorld()
	return world and world.APIContext or nil
end

function Context.GetEventBus(self: Context): EventBusType?
	local world = self:GetWorld()
	return world and world.EventBus or nil
end

function Context.GetRegistry(self: Context): PluginRegistryView?
	return self:IsValid() and self._registryView or nil
end

function Context.GetCapability(self: Context, id: string): PluginCapabilityType?
	local registry = getRegistry(self)
	return registry and registry:GetCapability(id) or nil
end

function Context.RegisterCapability(
	self: Context,
	id: string,
	implementation: any?,
	version: string?
): (PluginCapabilityType?, PluginContextErrorCode?)
	local resolver = getResolver(self)
	local plugin = self._plugin
	if resolver == nil or plugin == nil then return nil, "InvalidContext" end

	local capability, code = resolver:_registerCapability(plugin, id, implementation, version)
	if capability then table.insert(self._resources, { Kind = "Capability", Id = id }) end
	return capability, code
end

function Context.Subscribe(
	self: Context,
	eventType: string,
	callback: (EventType, APIContextType, PluginContextType) -> (),
	options: Types.EventSubscriptionOptions?
): (EventSubscriptionType?, APIErrorType | PluginContextErrorCode?)
	local resolver = getResolver(self)
	local plugin = self._plugin
	if resolver == nil or plugin == nil then return nil, "InvalidContext" end
	if type(eventType) ~= "string" or eventType == "" or type(callback) ~= "function" then
		return nil, "InvalidArgument"
	end

	local world = resolver.World
	if world == nil then return nil, "InvalidContext" end
	local userCallback = callback
	local subscription, err = world.EventBus:Subscribe(eventType, function(event, api)
		local currentResolver = getResolver(self)
		local currentPlugin = self._plugin
		if currentResolver == nil or currentPlugin == nil then return end

		local apiContext: APIContextType = api
		local ok, failure = pcall(userCallback, event, apiContext, self)
		if not ok then currentResolver:_failRuntime(currentPlugin, failure) end
	end, options)
	if subscription then
		table.insert(self._resources, { Kind = "Subscription", Value = subscription })
	end
	return subscription, err
end

function Context.Register(
	self: Context,
	kind: string,
	id: string,
	implementation: any?,
	version: string?
): (PluginCapabilityType?, PluginContextErrorCode?)
	if kind ~= "Capability" then return nil, "UnsupportedExtensionKind" end
	return self:RegisterCapability(id, implementation, version)
end

function Context._invalidate(self: Context): boolean
	if not self._valid then return false end
	local resolver = self._resolver
	assert(resolver ~= nil, "Valid PluginContext must retain its resolver")
	local plugin = self._plugin
	assert(plugin ~= nil, "Valid PluginContext must retain its plugin")

	self._valid = false
	for index = #self._resources, 1, -1 do
		local resource = self._resources[index]
		if resource.Kind == "Subscription" then
			resource.Value:Disconnect()
		else
			resolver:_unregisterCapability(plugin, resource.Id)
		end
	end
	table.clear(self._resources)
	self._resolver = nil
	self._plugin = nil
	self._registryView = nil
	return true
end

return Context
