--!strict

local World = require(script.Parent.Core.World)
local APIContext = require(script.Parent.Events.APIContext)
local EventTypes = require(script.Parent.Events.EventTypes)
local APIResult = require(script.Parent.Events.APIResult)
local APIError = require(script.Parent.Events.APIError)
local ResolverErrorMap = require(script.Parent.Events.ResolverErrorMap)
local Plugin = require(script.Parent.Plugins.Plugin)
local PluginCapability = require(script.Parent.Plugins.PluginCapability)
local PluginContext = require(script.Parent.Plugins.PluginContext)
local PluginProfile = require(script.Parent.Plugins.PluginProfile)
local PluginState = require(script.Parent.Plugins.PluginState)
local Simulation = require(script.Parent.Simulation.Simulation)
local CombatActionProfiles = require(script.Parent.Combat.CombatActionProfiles)
local CombatActionCatalog = require(script.Parent.Combat.CombatActionCatalog)
local ReplayRecording = require(script.Parent.Simulation.ReplayRecording)
local NetworkMessage = require(script.Parent.Combat.NetworkMessage)
local CombatActionDefinition = require(script.Parent.Combat.CombatActionDefinition)
local RobloxRemoteEventAdapter = require(script.Parent.Combat.RobloxRemoteEventAdapter)
local Attack = require(script.Parent.Combat.Attack)
local AttackInstance = require(script.Parent.Combat.AttackInstance)
local AttackCatalog = require(script.Parent.Combat.AttackCatalog)
local CollisionWorld = require(script.Parent.Combat.CollisionWorld)
local CollisionTopologyCatalog = require(script.Parent.Combat.CollisionTopologyCatalog)
local Hitbox = require(script.Parent.Combat.Hitbox)
local Hurtbox = require(script.Parent.Combat.Hurtbox)
local OffensiveProperties = require(script.Parent.Combat.OffensiveProperties)
local CombatStateSchema = require(script.Parent.Combat.CombatStateSchema)
local CombatAPITypes = require(script.Parent.CombatAPITypes)
type PublicCombatAPI = CombatAPITypes.CombatAPI
type WorldType = CombatAPITypes.World
type APIResultType<T> = CombatAPITypes.APIResult<T>
type PluginResolverResult = CombatAPITypes.PluginResolverResult

local function wrapPluginResult(result: PluginResolverResult, world: WorldType?): APIResultType<PluginResolverResult>
	local err: CombatAPITypes.APIError? = nil
	if not result.Success then
		err = ResolverErrorMap.toError(result, "Plugins", world and world.CurrentFrame)
	end
	return APIResult.new(result.Success, result, err)
end

local CombatAPI = {
	Name = "CombatAPI",
	-- Version is retained as the numeric API generation for existing consumers.
	Version = 1,
	-- SemVer describes the package/API release independently from serialized contracts.
	SemVer = "0.1.4",
	Contracts = table.freeze({
		NetworkMessage = NetworkMessage.Version,
		CombatActionDefinition = CombatActionDefinition.Version,
		CombatActionCatalog = CombatActionCatalog.Version,
		AttackCatalogManifest = AttackCatalog.ManifestVersion,
		CombatStateSchema = CombatStateSchema.Version,
		ReplayRecording = ReplayRecording.Version,
	}),
}
function CombatAPI.CreateWorld(options: { [string]: any }?): WorldType return World.new(options) end
function CombatAPI.GetContext(world: any): CombatAPITypes.APIContext?
	if type(world) ~= "table" or type(world.GetCombatAPI) ~= "function" then return nil end
	return world:GetCombatAPI()
end
function CombatAPI.GetAPIContext(world: any): CombatAPITypes.APIContext?
	if type(world) ~= "table" or type(world.GetCombatAPI) ~= "function" then return nil end
	return world:GetCombatAPI()
end
function CombatAPI.IsWorld(value: any): boolean return type(value) == "table" and getmetatable(value) == World end
function CombatAPI.GetPluginResolver(world: any): any?
	if type(world) ~= "table" or type(world.GetPluginResolver) ~= "function" then return nil end
	return world:GetPluginResolver()
end
function CombatAPI.RegisterPlugin(
	world: WorldType,
	plugin: CombatAPITypes.Plugin | CombatAPITypes.PluginProfile | CombatAPITypes.PluginProfileOptions,
	implementation: CombatAPITypes.PluginImplementation?
): APIResultType<PluginResolverResult>
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result: PluginResolverResult=resolver:RegisterPlugin(plugin,implementation)
	return wrapPluginResult(result, world)
end
function CombatAPI.StartPlugin(world: WorldType, id: string): APIResultType<PluginResolverResult>
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result: PluginResolverResult=resolver:StartPlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.StopPlugin(world: WorldType, id: string): APIResultType<PluginResolverResult>
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result: PluginResolverResult=resolver:StopPlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.UnregisterPlugin(world: WorldType, id: string): APIResultType<PluginResolverResult>
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result: PluginResolverResult=resolver:UnregisterPlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.EnablePlugin(world: WorldType, id: string): APIResultType<PluginResolverResult>
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result: PluginResolverResult=resolver:EnablePlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.DisablePlugin(world: WorldType, id: string): APIResultType<PluginResolverResult>
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result: PluginResolverResult=resolver:DisablePlugin(id)
	return wrapPluginResult(result, world)
end
CombatAPI.APIContext = APIContext
CombatAPI.EventTypes = EventTypes
CombatAPI.APIResult = APIResult
CombatAPI.APIError = APIError
CombatAPI.Plugin = Plugin
CombatAPI.PluginCapability = PluginCapability
CombatAPI.PluginContext = PluginContext
CombatAPI.PluginProfile = PluginProfile
CombatAPI.PluginState = PluginState
CombatAPI.Simulation = Simulation
CombatAPI.CombatActionProfiles = CombatActionProfiles
CombatAPI.CombatActionCatalog = CombatActionCatalog
CombatAPI.ReplayRecording = ReplayRecording
CombatAPI.RobloxRemoteEventAdapter = RobloxRemoteEventAdapter
-- Public constructors required by consumers that need attack definitions,
-- per-instance overrides, and rollback-capable collision registration.
CombatAPI.Attack = Attack
CombatAPI.AttackInstance = AttackInstance
CombatAPI.AttackCatalog = AttackCatalog
CombatAPI.CollisionWorld = CollisionWorld
CombatAPI.CollisionTopologyCatalog = CollisionTopologyCatalog
CombatAPI.Hitbox = Hitbox
CombatAPI.Hurtbox = Hurtbox
CombatAPI.OffensiveProperties = OffensiveProperties
return table.freeze(CombatAPI) :: PublicCombatAPI
