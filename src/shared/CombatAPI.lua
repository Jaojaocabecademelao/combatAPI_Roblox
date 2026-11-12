local World = require(script.Parent.Core.World)
local APIContext = require(script.Parent.Events.APIContext)
local EventTypes = require(script.Parent.Events.EventTypes)
local APIResult = require(script.Parent.Events.APIResult)
local APIError = require(script.Parent.Events.APIError)
local ResolverErrorMap = require(script.Parent.Events.ResolverErrorMap)
local Plugin = require(script.Parent.Plugins.Plugin)
local PluginProfile = require(script.Parent.Plugins.PluginProfile)
local PluginState = require(script.Parent.Plugins.PluginState)
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
local Hitbox = require(script.Parent.Combat.Hitbox)
local Hurtbox = require(script.Parent.Combat.Hurtbox)
local OffensiveProperties = require(script.Parent.Combat.OffensiveProperties)
local CombatStateSchema = require(script.Parent.Combat.CombatStateSchema)

local function wrapPluginResult(result, world)
	local err = nil
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
function CombatAPI.CreateWorld(options) return World.new(options) end
function CombatAPI.GetContext(world)
	if type(world) ~= "table" or type(world.GetCombatAPI) ~= "function" then return nil end
	return world:GetCombatAPI()
end
function CombatAPI.GetAPIContext(world)
	if type(world) ~= "table" or type(world.GetCombatAPI) ~= "function" then return nil end
	return world:GetCombatAPI()
end
function CombatAPI.IsWorld(value) return type(value) == "table" and getmetatable(value) == World end
function CombatAPI.GetPluginResolver(world)
	if type(world) ~= "table" or type(world.GetPluginResolver) ~= "function" then return nil end
	return world:GetPluginResolver()
end
function CombatAPI.RegisterPlugin(world, plugin, implementation)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:RegisterPlugin(plugin,implementation)
	return wrapPluginResult(result, world)
end
function CombatAPI.StartPlugin(world, id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:StartPlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.StopPlugin(world, id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:StopPlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.UnregisterPlugin(world,id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:UnregisterPlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.EnablePlugin(world,id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:EnablePlugin(id)
	return wrapPluginResult(result, world)
end
function CombatAPI.DisablePlugin(world,id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:DisablePlugin(id)
	return wrapPluginResult(result, world)
end
CombatAPI.APIContext = APIContext
CombatAPI.EventTypes = EventTypes
CombatAPI.APIResult = APIResult
CombatAPI.APIError = APIError
CombatAPI.Plugin = Plugin
CombatAPI.PluginProfile = PluginProfile
CombatAPI.PluginState = PluginState
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
CombatAPI.Hitbox = Hitbox
CombatAPI.Hurtbox = Hurtbox
CombatAPI.OffensiveProperties = OffensiveProperties
return table.freeze(CombatAPI)
