local World = require(script.Parent.Core.World)
local APIContext = require(script.Parent.Events.APIContext)
local EventTypes = require(script.Parent.Events.EventTypes)
local APIResult = require(script.Parent.Events.APIResult)
local APIError = require(script.Parent.Events.APIError)
local Plugin = require(script.Parent.Plugins.Plugin)
local PluginProfile = require(script.Parent.Plugins.PluginProfile)
local PluginState = require(script.Parent.Plugins.PluginState)
local CombatActionProfiles = require(script.Parent.Combat.CombatActionProfiles)
local CombatActionCatalog = require(script.Parent.Combat.CombatActionCatalog)
local ReplayRecording = require(script.Parent.Simulation.ReplayRecording)
local NetworkMessage = require(script.Parent.Combat.NetworkMessage)
local CombatActionDefinition = require(script.Parent.Combat.CombatActionDefinition)
local RobloxRemoteEventAdapter = require(script.Parent.Combat.RobloxRemoteEventAdapter)

local CombatAPI = {
	Name = "CombatAPI",
	Version = 1,
	Contracts = table.freeze({
		NetworkMessage = NetworkMessage.Version,
		CombatActionDefinition = CombatActionDefinition.Version,
		CombatActionCatalog = CombatActionCatalog.Version,
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
	return APIResult.new(result.Success,result,result.Success and nil or APIError.new(APIError.Code.InvalidOperation,result.Code,"Plugins",world.CurrentFrame))
end
function CombatAPI.StartPlugin(world, id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:StartPlugin(id)
	return APIResult.new(result.Success,result,result.Success and nil or APIError.new(APIError.Code.InvalidOperation,result.Code,"Plugins",world.CurrentFrame))
end
function CombatAPI.StopPlugin(world, id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:StopPlugin(id)
	return APIResult.new(result.Success,result,result.Success and nil or APIError.new(APIError.Code.InvalidOperation,result.Code,"Plugins",world.CurrentFrame))
end
function CombatAPI.UnregisterPlugin(world,id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:UnregisterPlugin(id)
	return APIResult.new(result.Success,result,result.Success and nil or APIError.new(APIError.Code.InvalidOperation,result.Code,"Plugins",world.CurrentFrame))
end
function CombatAPI.EnablePlugin(world,id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:EnablePlugin(id)
	return APIResult.new(result.Success,result,result.Success and nil or APIError.new(APIError.Code.InvalidOperation,result.Code,"Plugins",world.CurrentFrame))
end
function CombatAPI.DisablePlugin(world,id)
	local resolver=CombatAPI.GetPluginResolver(world)
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.InvalidArgument,"A valid World is required","Plugins")) end
	local result=resolver:DisablePlugin(id)
	return APIResult.new(result.Success,result,result.Success and nil or APIError.new(APIError.Code.InvalidOperation,result.Code,"Plugins",world.CurrentFrame))
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
return table.freeze(CombatAPI)
