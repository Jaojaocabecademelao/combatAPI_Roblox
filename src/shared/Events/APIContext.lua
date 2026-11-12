local APIResult = require(script.Parent.APIResult)
local APIError = require(script.Parent.APIError)
local ResolverErrorMap = require(script.Parent.ResolverErrorMap)
local EventBus = require(script.Parent.EventBus)

local APIContext = {}
APIContext.__index = APIContext

local function wrapResolverResult(result, system, frame)
	local err = nil
	if not result.Success then
		err = ResolverErrorMap.toError(result, system, frame)
	end
	return APIResult.new(result.Success, result, err)
end
local systemMethods = {
	Simulation = "GetSimulation",
	Input = "GetInputResolver", Collision = "GetCollisionWorld", Damage = "GetDamageResolver",
	Defense = "GetDefenseResolver", CombatResolution = "GetCombatResolver", Motion = "GetMotionResolver",
	Guard = "GetGuardResolver", Combo = "GetComboResolver", Juggle = "GetJuggleResolver",
	MovementState = "GetMovementStateResolver", Cancel = "GetCancelResolver", Character = "GetCharacterResolver",
	Animation = "GetAnimationResolver", Networking = "GetNetworkResolver", Prediction = "GetPredictionResolver",
	Rollback = "GetRollbackResolver", Authority = "GetAuthorityResolver", Armor = "GetArmorResolver",
	Protection = "GetProtectionResolver", Hitstop = "GetHitstopResolver",
	Plugins = "GetPluginResolver",
}
function APIContext.new(world)
	local self = setmetatable({ World = world, Destroyed = false }, APIContext)
	self.Events = EventBus.new(self)
	return self
end
function APIContext:GetWorld() return self.World end
function APIContext:GetEvents() return self.Events end
function APIContext:Subscribe(eventType, callback, options) return self.Events:Subscribe(eventType, callback, options) end
function APIContext:On(eventType, callback, options) return self:Subscribe(eventType, callback, options) end
function APIContext:_get(method)
	if self.Destroyed or not self.World then return nil end
	return self.World[method](self.World)
end
function APIContext:GetEntity(id)
	if self.Destroyed or not self.World then return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API")) end
	local entity = self.World:GetEntity(id)
	if not entity then return APIResult.new(false, nil, APIError.new(APIError.Code.InvalidEntity, "Entity was not found", "Core", self.World.CurrentFrame)) end
	return APIResult.new(true, entity)
end
function APIContext:CreateEntity()
	if self.Destroyed or not self.World then
		return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API"))
	end
	if self.World.Destroying or self.World.ExecutionContext ~= "Normal" then
		return APIResult.new(false, nil, APIError.new(APIError.Code.InvalidOperation,
			"Entity creation is unavailable during replay", "Core", self.World.CurrentFrame))
	end
	return APIResult.new(true, self.World:CreateEntity())
end
function APIContext:DestroyEntity(entityOrId)
	if self.Destroyed then return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API")) end
	if self.World.ExecutionContext ~= "Normal" then
		return APIResult.new(false, false, APIError.new(APIError.Code.InvalidOperation,
			"Entity destruction is unavailable during replay", "Core", self.World.CurrentFrame))
	end
	if not self.World:DestroyEntity(entityOrId) then return APIResult.new(false, false, APIError.new(APIError.Code.InvalidEntity, "Entity was not found", "Core", self.World.CurrentFrame)) end
	return APIResult.new(true, true)
end
function APIContext:GetSystem(name)
	if self.Destroyed or not self.World then return APIResult.new(false, nil, APIError.new(APIError.Code.Destroyed, "API context is destroyed", "API")) end
	if type(name) ~= "string" then return APIResult.new(false, nil, APIError.new(APIError.Code.InvalidArgument,
		"System name must be a string", "API", self.World.CurrentFrame)) end
	local method = systemMethods[name]
	if not method then return APIResult.new(false, nil, APIError.new(APIError.Code.NotFound, "System is not part of the public surface", "API", self.World.CurrentFrame)) end
	local value = self.World[method](self.World)
	if not value then return APIResult.new(false, nil, APIError.new(APIError.Code.NotInitialized, "System is unavailable", name, self.World.CurrentFrame)) end
	return APIResult.new(true, value)
end
function APIContext:HasSystem(name)
	return not self.Destroyed and self.World ~= nil and systemMethods[name] ~= nil
		and self.World[systemMethods[name]](self.World) ~= nil
end
function APIContext:HasFeature(name)
	if self.Destroyed then return false end
	local features = { Events = true, Simulation = true, Prediction = true, Rollback = true, Authority = true,
		Damage = true, Defense = true, Collision = true, Motion = true, Guard = true, Combo = true,
		Juggle = true, MovementState = true, Cancel = true, Input = true, Character = true, Animation = true,
		Networking = true, Armor = true, Protection = true, Hitstop = true, Plugins = true }
	return features[name] == true and (name == "Events" or name == "Simulation" or self:HasSystem(name))
end
function APIContext:GetInputResolver() return self:_get("GetInputResolver") end
function APIContext:GetSimulation() return self:_get("GetSimulation") end
function APIContext:GetCollisionWorld() return self:_get("GetCollisionWorld") end
function APIContext:GetDamageResolver() return self:_get("GetDamageResolver") end
function APIContext:GetDefenseResolver() return self:_get("GetDefenseResolver") end
function APIContext:GetCombatResolver() return self:_get("GetCombatResolver") end
function APIContext:GetProtectionResolver() return self:_get("GetProtectionResolver") end
function APIContext:GetArmorResolver() return self:_get("GetArmorResolver") end
function APIContext:GetHitstopResolver() return self:_get("GetHitstopResolver") end
function APIContext:GetMotionResolver() return self:_get("GetMotionResolver") end
function APIContext:GetGuardResolver() return self:_get("GetGuardResolver") end
function APIContext:GetComboResolver() return self:_get("GetComboResolver") end
function APIContext:GetJuggleResolver() return self:_get("GetJuggleResolver") end
function APIContext:GetMovementStateResolver() return self:_get("GetMovementStateResolver") end
function APIContext:GetCancelResolver() return self:_get("GetCancelResolver") end
function APIContext:GetCharacterResolver() return self:_get("GetCharacterResolver") end
function APIContext:GetAnimationResolver() return self:_get("GetAnimationResolver") end
function APIContext:GetNetworkResolver() return self:_get("GetNetworkResolver") end
function APIContext:GetPredictionResolver() return self:_get("GetPredictionResolver") end
function APIContext:GetRollbackResolver() return self:_get("GetRollbackResolver") end
function APIContext:GetAuthorityResolver() return self:_get("GetAuthorityResolver") end
function APIContext:GetPluginResolver() return self:_get("GetPluginResolver") end
function APIContext:RegisterPlugin(plugin, implementation)
	local resolver=self:GetPluginResolver()
	if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.Destroyed,"Plugin resolver is unavailable","Plugins")) end
	local result=resolver:RegisterPlugin(plugin,implementation)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end
function APIContext:GetPlugin(id)
	local resolver=self:GetPluginResolver(); local plugin=resolver and resolver:GetPlugin(id)
	if not plugin then return APIResult.new(false,nil,APIError.new(APIError.Code.NotFound,"Plugin was not found","Plugins",self.World and self.World.CurrentFrame)) end
	return APIResult.new(true,plugin)
end
function APIContext:StartPlugin(id)
	local resolver=self:GetPluginResolver(); if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.Destroyed,"Plugin resolver is unavailable","Plugins")) end
	local result=resolver:StartPlugin(id)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end
function APIContext:StopPlugin(id)
	local resolver=self:GetPluginResolver(); if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.Destroyed,"Plugin resolver is unavailable","Plugins")) end
	local result=resolver:StopPlugin(id)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end
function APIContext:UnregisterPlugin(id)
	local resolver=self:GetPluginResolver(); if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.Destroyed,"Plugin resolver is unavailable","Plugins")) end
	local result=resolver:UnregisterPlugin(id)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end
function APIContext:EnablePlugin(id)
	local resolver=self:GetPluginResolver(); if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.Destroyed,"Plugin resolver is unavailable","Plugins")) end
	local result=resolver:EnablePlugin(id)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end
function APIContext:DisablePlugin(id)
	local resolver=self:GetPluginResolver(); if not resolver then return APIResult.new(false,nil,APIError.new(APIError.Code.Destroyed,"Plugin resolver is unavailable","Plugins")) end
	local result=resolver:DisablePlugin(id)
	return wrapResolverResult(result, "Plugins", self.World and self.World.CurrentFrame)
end
function APIContext:Destroy()
	if self.Destroyed then return false end
	self.Destroyed = true
	if self.Events then self.Events:Destroy() end
	self.World = nil
	return true
end
return APIContext
