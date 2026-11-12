--!strict

local Types = require(script.Parent.Parent.CombatAPITypes)
local APIResult = require(script.Parent.APIResult)
local APIError = require(script.Parent.APIError)
local ResolverErrorMap = require(script.Parent.ResolverErrorMap)
local EventBus = require(script.Parent.EventBus)

type World = Types.World
type APIContextType = Types.APIContext
type APIErrorType = Types.APIError
type APIResultType<T> = Types.APIResult<T>
type EventCallback = Types.EventCallback
type EventBusType = Types.EventBus
type EventSubscriptionOptions = Types.EventSubscriptionOptions
type Plugin = Types.Plugin
type PluginProfile = Types.PluginProfile
type PluginProfileOptions = Types.PluginProfileOptions
type PluginImplementation = Types.PluginImplementation
type PluginResolverResult = Types.PluginResolverResult

local APIContext: any = {}
APIContext.__index = APIContext

local function wrapResolverResult(
	result: PluginResolverResult,
	system: string,
	frame: number?
): APIResultType<PluginResolverResult>
	local err: APIErrorType? = nil
	if not result.Success then
		err = ResolverErrorMap.toError(result, system, frame)
	end
	return APIResult.new(result.Success, result, err)
end

local systemMethods: { [string]: string } = {
	Simulation = "GetSimulation",
	Input = "GetInputResolver", Collision = "GetCollisionWorld", Damage = "GetDamageResolver",
	Defense = "GetDefenseResolver", CombatResolution = "GetCombatResolver", Motion = "GetMotionResolver",
	Guard = "GetGuardResolver", Combo = "GetComboResolver", Juggle = "GetJuggleResolver",
	MovementState = "GetMovementStateResolver", Cancel = "GetCancelResolver", Character = "GetCharacterResolver",
	Animation = "GetAnimationResolver", Networking = "GetNetworkResolver", Prediction = "GetPredictionResolver",
	Rollback = "GetRollbackResolver", Authority = "GetAuthorityResolver", Armor = "GetArmorResolver",
	Protection = "GetProtectionResolver", Hitstop = "GetHitstopResolver", Plugins = "GetPluginResolver",
}

function APIContext.new(world: World): APIContextType
	local self = setmetatable({ World = world, Destroyed = false }, APIContext)
	self.Events = EventBus.new(self)
	return self :: APIContextType
end

function APIContext:GetWorld(): World?
	return self.World
end

function APIContext:GetEvents(): EventBusType
	return self.Events
end

function APIContext:Subscribe(eventType: string, callback: EventCallback, options: EventSubscriptionOptions?)
	return self.Events:Subscribe(eventType, callback, options)
end

function APIContext:On(eventType: string, callback: EventCallback, options: EventSubscriptionOptions?)
	return self:Subscribe(eventType, callback, options)
end

function APIContext:_get(method: string): any?
	if self.Destroyed or not self.World then return nil end
	return self.World[method](self.World)
end

function APIContext:GetEntity(id: Types.EntityId): APIResultType<any>
	if self.Destroyed or not self.World then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API"))
	end
	local entity = self.World:GetEntity(id)
	if not entity then
		return APIResult.new(false, nil, APIError.new(APIError.Code.InvalidEntity, "Entity was not found", "Core", self.World.CurrentFrame))
	end
	return APIResult.new(true, entity)
end

function APIContext:CreateEntity(): APIResultType<any>
	if self.Destroyed or not self.World then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API"))
	end
	if self.World.Destroying or self.World.ExecutionContext ~= "Normal" then
		return APIResult.new(false, nil, APIError.new(APIError.Code.InvalidOperation,
			"Entity creation is unavailable during replay", "Core", self.World.CurrentFrame))
	end
	return APIResult.new(true, self.World:CreateEntity())
end

function APIContext:DestroyEntity(entityOrId: any): APIResultType<boolean>
	if self.Destroyed then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API"))
	end
	if self.World.ExecutionContext ~= "Normal" then
		return APIResult.new(false, false, APIError.new(APIError.Code.InvalidOperation,
			"Entity destruction is unavailable during replay", "Core", self.World.CurrentFrame))
	end
	if not self.World:DestroyEntity(entityOrId) then
		return APIResult.new(false, false, APIError.new(APIError.Code.InvalidEntity, "Entity was not found", "Core", self.World.CurrentFrame))
	end
	return APIResult.new(true, true)
end

function APIContext:GetSystem(name: string): APIResultType<any>
	if self.Destroyed or not self.World then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API"))
	end
	if type(name) ~= "string" then
		return APIResult.new(false, nil, APIError.new(APIError.Code.InvalidArgument,
			"System name must be a string", "API", self.World.CurrentFrame))
	end
	local method = systemMethods[name]
	if not method then
		return APIResult.new(false, nil, APIError.new(APIError.Code.NotFound,
			"System is not part of the public surface", "API", self.World.CurrentFrame))
	end
	local value = self.World[method](self.World)
	if not value then
		return APIResult.new(false, nil, APIError.new(APIError.Code.NotInitialized,
			"System is unavailable", name, self.World.CurrentFrame))
	end
	return APIResult.new(true, value)
end

function APIContext:HasSystem(name: string): boolean
	return not self.Destroyed and self.World ~= nil and systemMethods[name] ~= nil
		and self.World[systemMethods[name]](self.World) ~= nil
end

function APIContext:HasFeature(name: string): boolean
	if self.Destroyed then return false end
	local features: { [string]: boolean } = {
		Events = true, Simulation = true, Prediction = true, Rollback = true, Authority = true,
		Damage = true, Defense = true, Collision = true, Motion = true, Guard = true, Combo = true,
		Juggle = true, MovementState = true, Cancel = true, Input = true, Character = true,
		Animation = true, Networking = true, Armor = true, Protection = true, Hitstop = true, Plugins = true,
	}
	return features[name] == true and (name == "Events" or name == "Simulation" or self:HasSystem(name))
end

function APIContext:GetInputResolver(): any? return self:_get("GetInputResolver") end
function APIContext:GetSimulation(): any? return self:_get("GetSimulation") end
function APIContext:GetCollisionWorld(): any? return self:_get("GetCollisionWorld") end
function APIContext:GetDamageResolver(): any? return self:_get("GetDamageResolver") end
function APIContext:GetDefenseResolver(): any? return self:_get("GetDefenseResolver") end
function APIContext:GetCombatResolver(): any? return self:_get("GetCombatResolver") end
function APIContext:GetProtectionResolver(): any? return self:_get("GetProtectionResolver") end
function APIContext:GetArmorResolver(): any? return self:_get("GetArmorResolver") end
function APIContext:GetHitstopResolver(): any? return self:_get("GetHitstopResolver") end
function APIContext:GetMotionResolver(): any? return self:_get("GetMotionResolver") end
function APIContext:GetGuardResolver(): any? return self:_get("GetGuardResolver") end
function APIContext:GetComboResolver(): any? return self:_get("GetComboResolver") end
function APIContext:GetJuggleResolver(): any? return self:_get("GetJuggleResolver") end
function APIContext:GetMovementStateResolver(): any? return self:_get("GetMovementStateResolver") end
function APIContext:GetCancelResolver(): any? return self:_get("GetCancelResolver") end
function APIContext:GetCharacterResolver(): any? return self:_get("GetCharacterResolver") end
function APIContext:GetAnimationResolver(): any? return self:_get("GetAnimationResolver") end
function APIContext:GetNetworkResolver(): any? return self:_get("GetNetworkResolver") end
function APIContext:GetPredictionResolver(): any? return self:_get("GetPredictionResolver") end
function APIContext:GetRollbackResolver(): any? return self:_get("GetRollbackResolver") end
function APIContext:GetAuthorityResolver(): any? return self:_get("GetAuthorityResolver") end
function APIContext:GetPluginResolver(): any? return self:_get("GetPluginResolver") end

function APIContext:RegisterPlugin(
	plugin: Plugin | PluginProfile | PluginProfileOptions,
	implementation: PluginImplementation?
): APIResultType<PluginResolverResult>
	local resolver = self:GetPluginResolver()
	if not resolver then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "Plugin resolver is unavailable", "Plugins"))
	end
	local result: PluginResolverResult = resolver:RegisterPlugin(plugin, implementation)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end

function APIContext:GetPlugin(id: string): APIResultType<Plugin>
	if self.Destroyed or not self.World then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API"))
	end
	if type(id) ~= "string" or id == "" then
		return APIResult.new(false, nil, APIError.new(
			APIError.Code.InvalidArgument,
			"Plugin ID must be a non-empty string",
			"Plugins",
			self.World.CurrentFrame
		))
	end
	local resolver = self:GetPluginResolver()
	if not resolver then
		return APIResult.new(false, nil, APIError.new(
			APIError.Code.NotInitialized,
			"Plugin resolver is unavailable",
			"Plugins",
			self.World.CurrentFrame
		))
	end
	local plugin: Plugin? = resolver:GetPlugin(id)
	if not plugin then
		return APIResult.new(false, nil, APIError.new(
			APIError.Code.NotFound,
			"Plugin was not found",
			"Plugins",
			self.World.CurrentFrame
		))
	end
	return APIResult.new(true, plugin)
end

local function invokePluginLifecycle(
	self: any,
	method: string,
	id: string
): APIResultType<PluginResolverResult>
	local resolver = self:GetPluginResolver()
	if not resolver then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "Plugin resolver is unavailable", "Plugins"))
	end
	local result: PluginResolverResult = resolver[method](resolver, id)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end

function APIContext:StartPlugin(id: string): APIResultType<PluginResolverResult> return invokePluginLifecycle(self, "StartPlugin", id) end
function APIContext:StopPlugin(id: string): APIResultType<PluginResolverResult> return invokePluginLifecycle(self, "StopPlugin", id) end
function APIContext:UnregisterPlugin(id: string): APIResultType<PluginResolverResult> return invokePluginLifecycle(self, "UnregisterPlugin", id) end
function APIContext:EnablePlugin(id: string): APIResultType<PluginResolverResult> return invokePluginLifecycle(self, "EnablePlugin", id) end
function APIContext:DisablePlugin(id: string): APIResultType<PluginResolverResult> return invokePluginLifecycle(self, "DisablePlugin", id) end

function APIContext:Destroy(): boolean
	if self.Destroyed then return false end
	self.Destroyed = true
	if self.Events then self.Events:Destroy() end
	self.World = nil
	return true
end

return APIContext
